import 'dart:io';

import 'package:dbas_filesystem/dbas_filesystem.dart';
import 'package:dbas_filesystem/src/helpers/dbas_filesystem_path_helper_io.dart' as io_paths;
import 'package:dbas_filesystem/src/helpers/dbas_filesystem_path_helper_web.dart' as web_paths;
import 'package:dbas_filesystem/src/helpers/dbas_filesystem_platform_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Staging-root contract that can be asserted against the CURRENT public
/// surface — no new API required.
///
/// `flutter test` runs each test FILE in its own operating-system process,
/// and runs several of those processes concurrently. Every one of them
/// resolves the `FLUTTER_TEST` storage root through
/// [io_paths.getAppDirImpl], so if that root has no per-process component
/// the processes share one directory: one suite's recursive cleanup
/// deletes another suite's staged bytes, and one suite's leftovers are
/// visible to another suite's `listDirectory`.
///
/// The companion file `dbas_filesystem_staging_root_isolation_test.dart`
/// pins the isolation properties that need a new seam to express.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The single directory every `FLUTTER_TEST` process stages under today.
  /// Written out literally rather than read back from the helper, so these
  /// tests describe the contract instead of restating the implementation.
  final sharedTestParent =
      p.join(Directory.current.path, 'test', 'files').replaceAll('\\', '/');

  /// Stand-in for the platform's application-support directory, so the
  /// production (non-test) branch is exercised without a real plugin.
  const fakeSupportDir = '/fake/app-support';
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      pathProviderChannel,
      (call) async =>
          call.method == 'getApplicationSupportDirectory' ? fakeSupportDir : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  // ── Sanity: we really are on the FLUTTER_TEST branch ──────────────────

  test('the test suite resolves paths through the FLUTTER_TEST branch', () {
    expect(DbasFileSystemPlatformUtil.isTest(), isTrue,
        reason: 'Every assertion below is about the FLUTTER_TEST staging '
            'root; if this is false the rest of the file proves nothing.');
  });

  // ── Per-process staging root ──────────────────────────────────────────

  test('the FLUTTER_TEST staging root is NOT the shared test/files directory', () async {
    final root = await io_paths.getAppDirImpl(true);

    expect(
      root,
      isNot(equals(sharedTestParent)),
      reason: 'Every concurrently running test process resolves this same '
          'directory, so a suite that recursively cleans its own staging '
          'root destroys the bytes another suite staged there.',
    );
  });

  test('the FLUTTER_TEST staging root is strictly inside test/files', () async {
    final root = await io_paths.getAppDirImpl(true);

    expect(
      p.isWithin(sharedTestParent, root),
      isTrue,
      reason: 'Per-process roots must stay confined to one well-known '
          'parent so abandoned roots from crashed runs are sweepable in '
          'one place instead of scattered across the tree.',
    );
  });

  // ── Within-process stability ──────────────────────────────────────────
  //
  // A suite writes bytes and then reads them back. If the root moved
  // between those two calls the suite would read from a directory it never
  // wrote to. This is exactly the property a naive per-CALL random
  // component would break, so it is pinned BEFORE the per-process
  // component exists.

  test('repeated resolutions in one process return the identical root', () async {
    final first = await io_paths.getAppDirImpl(true);
    final second = await io_paths.getAppDirImpl(true);
    final third = await io_paths.getAppDirImpl(true);

    expect(second, equals(first));
    expect(third, equals(first));
  });

  test('getAppFilePath resolves the same root on every call', () async {
    final fs = await DbasFileSystem.getInstance();

    final first = await fs.getAppFilePath('stability/probe.bin');
    final second = await fs.getAppFilePath('stability/probe.bin');

    expect(second, equals(first));
  });

  test('the staging root is per PROCESS, not per DbasFileSystem instance', () async {
    // The suite disposes and re-creates the singleton (see the disposal
    // lifecycle tests); the root must not move underneath it when it does.
    final first = await DbasFileSystem.getInstance();
    final before = await first.getAppFilePath('stability/probe.bin');
    await first.dispose();

    final second = await DbasFileSystem.getInstance();
    final after = await second.getAppFilePath('stability/probe.bin');

    expect(identical(first, second), isFalse,
        reason: 'Guard: this must be a genuinely fresh instance, otherwise '
            'the assertion below is trivially satisfied by the cache.');
    expect(after, equals(before));
  });

  // ── Production rooting is unaffected ──────────────────────────────────
  //
  // This is a published package. Outside FLUTTER_TEST the resolved paths
  // must stay byte-identical to today.

  test('outside FLUTTER_TEST the root is <application-support>/dbas_files', () async {
    final root = await io_paths.getAppDirImpl(false);

    expect(root, equals('$fakeSupportDir/dbas_files'));
  });

  test('outside FLUTTER_TEST the root carries no per-process component', () async {
    final first = await io_paths.getAppDirImpl(false);
    final second = await io_paths.getAppDirImpl(false);

    expect(second, equals(first));
    expect(first, isNot(contains('$pid')),
        reason: 'A per-process component in production would scatter real '
            'user data across a new directory on every app launch.');
  });

  test('outside FLUTTER_TEST getAppFilePath is unchanged', () async {
    final resolved = await io_paths.getAppFilePathImpl('uploads/photo.jpg', false);

    expect(resolved, equals('$fakeSupportDir/dbas_files/uploads/photo.jpg'));
  });

  // ── Web (OPFS) rooting is unaffected ──────────────────────────────────
  //
  // The web helper takes `isTest` and ignores it — and
  // `DbasFileSystemPlatformUtil.isTest()` short-circuits to false on web
  // anyway, so the FLUTTER_TEST staging branch is unreachable there. OPFS
  // is also per-origin with a single page per run, so there is no
  // shared-root hazard to fix. These assertions fail if the fix reaches
  // across into the web helper.

  test('the web (OPFS) root is unconditional in both modes', () async {
    expect(await web_paths.getAppDirImpl(true), equals('/dbas_files'));
    expect(await web_paths.getAppDirImpl(false), equals('/dbas_files'));
  });

  test('the web (OPFS) file path is unconditional in both modes', () async {
    expect(await web_paths.getAppFilePathImpl('uploads/photo.jpg', true),
        equals('/dbas_files/uploads/photo.jpg'));
    expect(await web_paths.getAppFilePathImpl('uploads/photo.jpg', false),
        equals('/dbas_files/uploads/photo.jpg'));
  });
}
