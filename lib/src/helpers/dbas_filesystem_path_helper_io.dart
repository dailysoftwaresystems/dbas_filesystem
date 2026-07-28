import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// The single parent directory that every `FLUTTER_TEST` staging root is a
/// direct child of. Keeping every root confined here means a whole test
/// tree's leftovers are collectable from one well-known place.
String _testStagingParent() =>
    path.join(Directory.current.path, 'test', 'files').replaceAll('\\', '/');

/// Cached at LIBRARY scope on purpose.
///
/// [DbasFileSystem] caches the resolved root per INSTANCE, and a test suite
/// may dispose and re-create the singleton many times in one run. Drawing
/// the per-process component inside the instance would move the storage
/// root underneath the suite at every re-creation, so bytes written before
/// a dispose would no longer be readable after it.
String? _testProcessTag;

/// A component that is unique to this operating-system process, stable for
/// the process's whole lifetime.
///
/// `flutter test` runs each test file in its own process and runs several
/// of those processes concurrently. Without this component every one of
/// them stages into the same directory, so one suite's recursive cleanup
/// deletes another suite's staged bytes and one suite's leftovers show up
/// in another suite's directory listings.
///
/// The tag combines the process id with entropy, and needs both:
/// * the **pid** guarantees distinctness between processes that are alive
///   at the same time — which is exactly the failure mode — where entropy
///   alone would only make it probable;
/// * the **entropy** stops a later run from adopting the root a crashed
///   run abandoned, because process ids get recycled.
String testProcessTag() => _testProcessTag ??= _deriveTestProcessTag();

String _deriveTestProcessTag() {
  final entropy = Random.secure().nextInt(1 << 32);
  return '$pid-${entropy.toRadixString(16).padLeft(8, '0')}';
}

/// The staging root a process whose tag is [processTag] resolves to.
///
/// Pure: same tag in, same path out. Cross-process isolation is exactly
/// this function being injective, which — unlike "two processes differ" —
/// is observable from inside a single process.
String testStagingRootFor(String processTag) =>
    path.join(_testStagingParent(), processTag).replaceAll('\\', '/');

/// The app's file-storage ROOT directory. All relative paths handed to
/// the file system resolve under here, so a bucket path like
/// `uploads/x` always lands in the app's own storage area, never the
/// process working directory.
///
/// - Under test (`FLUTTER_TEST`): `<cwd>/test/files/<pid>-<entropy>`, a
///   per-process directory — see [testProcessTag].
/// - Otherwise: `<application-support>/dbas_files`.
Future<String> getAppDirImpl(bool isTest) async {
  if (isTest) {
    return testStagingRootFor(testProcessTag());
  }

  final directory = await getApplicationSupportDirectory();
  return path.join(directory.path, 'dbas_files').replaceAll('\\', '/');
}

Future<String> getAppFilePathImpl(String fileName, bool isTest) async {
  final dirPath = await getAppDirImpl(isTest);
  return path.join(dirPath, fileName).replaceAll('\\', '/');
}
