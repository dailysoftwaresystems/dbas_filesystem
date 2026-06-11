import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// The app's file-storage ROOT directory. All relative paths handed to
/// the file system resolve under here, so a bucket path like
/// `uploads/x` always lands in the app's own storage area, never the
/// process working directory.
///
/// - Under test (`FLUTTER_TEST`): `<cwd>/test/files`.
/// - Otherwise: `<application-support>/dbas_files`.
Future<String> getAppDirImpl(bool isTest) async {
  if (isTest) {
    return path.join(Directory.current.path, 'test', 'files').replaceAll('\\', '/');
  }

  final directory = await getApplicationSupportDirectory();
  return path.join(directory.path, 'dbas_files').replaceAll('\\', '/');
}

Future<String> getAppFilePathImpl(String fileName, bool isTest) async {
  final dirPath = await getAppDirImpl(isTest);
  return path.join(dirPath, fileName).replaceAll('\\', '/');
}
