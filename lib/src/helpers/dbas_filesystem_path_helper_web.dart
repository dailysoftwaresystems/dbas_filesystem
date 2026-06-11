/// The app's file-storage ROOT directory under OPFS. All relative paths
/// resolve under here so a bucket path like `uploads/x` always lands in
/// the app's own OPFS storage area.
Future<String> getAppDirImpl(bool isTest) async {
  return '/dbas_files';
}

Future<String> getAppFilePathImpl(String fileName, bool isTest) async {
  return '/dbas_files/$fileName';
}
