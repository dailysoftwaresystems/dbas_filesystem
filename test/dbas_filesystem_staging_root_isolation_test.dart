import 'dart:io';
import 'dart:typed_data';

import 'package:dbas_filesystem/dbas_filesystem.dart';
import 'package:dbas_filesystem/src/helpers/dbas_filesystem_path_helper_io.dart' as io_paths;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Cross-process isolation of the `FLUTTER_TEST` staging root.
///
/// A single test runs in a single process, so "two processes get different
/// roots" cannot be observed directly — and asserting it by racing real
/// processes would be a flaky test of a timing window rather than of the
/// contract. Instead these tests go through the seam the fix introduces,
/// which splits the resolution into an impure part and a pure part:
///
/// * `io_paths.testProcessTag()` — the per-process component. Impure
///   (reads the OS process id, draws entropy) but CACHED, so its only
///   in-process observable property is that it never changes.
/// * `io_paths.testStagingRootFor(tag)` — pure. Cross-process isolation
///   reduces to this function being injective, which IS deterministically
///   observable from one process.
///
/// `getAppDirImpl(true)` must equal `testStagingRootFor(testProcessTag())`,
/// which is what ties the provable property to the real resolution.
///
/// Neither symbol is exported from `lib/dbas_filesystem.dart`; they are
/// internal to `src/helpers/`, reachable the same way the existing suite
/// reaches `src/helpers/dbas_path_lock.dart`.
void main() {
  /// The shared parent every per-process root must live under.
  final sharedTestParent =
      p.join(Directory.current.path, 'test', 'files').replaceAll('\\', '/');

  /// Two tags standing in for two concurrently running test processes.
  /// Both are namespaced under this process's real tag so the directories
  /// created below cannot collide with a genuine run's staging root.
  String tagOfSuiteA() => '${io_paths.testProcessTag()}-suite-a';
  String tagOfSuiteB() => '${io_paths.testProcessTag()}-suite-b';

  void deleteIfPresent(String dirPath) {
    final dir = Directory(dirPath);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  // ── Cross-process isolation ───────────────────────────────────────────

  test('two processes resolve DIFFERENT staging roots', () {
    final rootA = io_paths.testStagingRootFor('process-a');
    final rootB = io_paths.testStagingRootFor('process-b');

    expect(rootA, isNot(equals(rootB)),
        reason: 'Parallel `flutter test` suites are separate processes. '
            'Sharing one staging root is what lets them delete and list '
            "each other's files.");
  });

  test('distinct staging roots are disjoint — neither contains the other', () {
    final rootA = io_paths.testStagingRootFor('process-a');
    final rootB = io_paths.testStagingRootFor('process-b');

    expect(p.isWithin(rootA, rootB), isFalse);
    expect(p.isWithin(rootB, rootA), isFalse);
  });

  test('this process resolves the root its own tag maps to', () async {
    // Ties the pure, provable function to the real resolution: without
    // this, `testStagingRootFor` could be injective and yet unused.
    expect(
      await io_paths.getAppDirImpl(true),
      equals(io_paths.testStagingRootFor(io_paths.testProcessTag())),
    );
  });

  // ── The user-visible bug ──────────────────────────────────────────────

  test("a suite's recursive cleanup of its OWN root leaves another suite's staged bytes intact", () async {
    final rootA = io_paths.testStagingRootFor(tagOfSuiteA());
    final rootB = io_paths.testStagingRootFor(tagOfSuiteB());
    addTearDown(() {
      deleteIfPresent(rootA);
      deleteIfPresent(rootB);
    });

    Directory(rootA).createSync(recursive: true);
    Directory(rootB).createSync(recursive: true);

    // Suite B stages bytes it will read back later in its run.
    final staged = File('$rootB/staged.bin');
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    staged.writeAsBytesSync(bytes);

    // Suite A finishes and runs its tearDownAll: delete MY staging root,
    // recursively. This is the exact call that destroys other suites today.
    Directory(rootA).deleteSync(recursive: true);

    expect(staged.existsSync(), isTrue,
        reason: "Suite A's cleanup deleted the directory suite B is still "
            'staging into.');
    expect(staged.readAsBytesSync(), equals(bytes));
  });

  test("a suite's staging root does not see files another suite staged", () async {
    final rootA = io_paths.testStagingRootFor(tagOfSuiteA());
    final rootB = io_paths.testStagingRootFor(tagOfSuiteB());
    addTearDown(() {
      deleteIfPresent(rootA);
      deleteIfPresent(rootB);
    });

    Directory(rootA).createSync(recursive: true);
    Directory(rootB).createSync(recursive: true);
    File('$rootB/foreign.bin').writeAsBytesSync(Uint8List.fromList([9]));

    expect(Directory(rootA).listSync(), isEmpty,
        reason: 'A foreign suite\'s files inflate listDirectory counts and '
            'make `existsSync` true for paths this suite never wrote.');
  });

  // ── Within-process stability ──────────────────────────────────────────

  test('the process tag never changes within a process', () {
    final first = io_paths.testProcessTag();
    final second = io_paths.testProcessTag();

    expect(first, isNotEmpty);
    expect(second, equals(first));
  });

  test('getAppDirectory is stable across dispose and re-creation', () async {
    final first = await DbasFileSystem.getInstance();
    final before = await first.getAppDirectory();
    await first.dispose();

    final second = await DbasFileSystem.getInstance();
    final after = await second.getAppDirectory();

    expect(identical(first, second), isFalse);
    expect(after, equals(before),
        reason: 'The per-process component must not be drawn per instance — '
            'the suite disposes and re-creates the singleton mid-run, and '
            'bytes written before that must still be readable after.');
    expect(after, equals(await io_paths.getAppDirImpl(true)));
  });

  test('getAppDirectory is the directory getAppFilePath resolves under', () async {
    final fs = await DbasFileSystem.getInstance();

    final dir = await fs.getAppDirectory();
    final filePath = await fs.getAppFilePath('uploads/photo.jpg');

    expect(filePath, equals('$dir/uploads/photo.jpg'));
  });

  test('getAppDirectory throws StateError after dispose', () async {
    final disposed = await DbasFileSystem.getInstance();
    await disposed.dispose();
    addTearDown(DbasFileSystem.getInstance);

    expect(() => disposed.getAppDirectory(), throwsA(isA<StateError>()));
  });

  // ── Cleanup contract ──────────────────────────────────────────────────
  //
  // Isolation without cleanup turns collisions into unbounded growth. The
  // contract pinned here is CONFINEMENT: every root a process can ever
  // resolve is a direct child of one known parent, so (a) a suite can
  // delete its own root without reaching another's, and (b) everything a
  // crashed run abandoned is collectable from one place.
  //
  // Confinement is what the library can guarantee. RECLAMATION of roots
  // abandoned by a crashed run cannot be expressed as a test from inside
  // one process — there is no in-process observable for "another process
  // died" — so no sweep is assumed here. See the phase report.

  test('every staging root is a direct child of the shared parent', () {
    final tags = ['a', 'b', 'process-1234', io_paths.testProcessTag()];

    for (final tag in tags) {
      final root = io_paths.testStagingRootFor(tag);
      expect(p.isWithin(sharedTestParent, root), isTrue, reason: 'tag: $tag');
      expect(root, isNot(equals(sharedTestParent)), reason: 'tag: $tag');
      expect(p.dirname(root), equals(sharedTestParent), reason: 'tag: $tag');
    }
  });

  test('deleting the shared parent collects every process root', () {
    final rootA = io_paths.testStagingRootFor(tagOfSuiteA());
    addTearDown(() => deleteIfPresent(rootA));

    Directory(rootA).createSync(recursive: true);

    expect(p.isWithin(sharedTestParent, rootA), isTrue,
        reason: 'A between-runs sweep of test/files must reclaim roots '
            'abandoned by crashed runs; that only works while every root '
            'is confined to that one parent.');
  });

  // ── Derivation of the per-process tag ─────────────────────────────────
  //
  // The two assertions below are the only ones coupled to the SHAPE of the
  // tag rather than to an observable behaviour — they are separated so
  // they can be dropped independently if the derivation changes. Each pins
  // a property that cannot otherwise be observed from inside one process.

  test('the process tag is derived from the OS process id', () {
    // Entropy alone makes cross-process distinctness probabilistic;
    // including the pid makes it GUARANTEED for processes that are alive
    // at the same time, which is precisely the failure mode.
    expect(io_paths.testProcessTag(), contains('$pid'));
  });

  test('the process tag is more than the OS process id alone', () {
    // Process ids are recycled. A tag of exactly the pid means a later run
    // can land on the staging root a crashed run abandoned and read its
    // stale bytes as if it had written them.
    expect(io_paths.testProcessTag(), isNot(equals('$pid')));
  });
}
