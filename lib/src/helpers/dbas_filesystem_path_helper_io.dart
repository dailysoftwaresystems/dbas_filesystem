import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

Future<String> getAppFilePathImpl(String fileName, bool isTest) async {
  if (isTest) {
    final filePath = path.join(Directory.current.path, 'test', 'files');
    return path.join(filePath, fileName).replaceAll('\\', '/');
  }

  final directory = await getApplicationSupportDirectory();
  final dirPath = path.join(directory.path, 'dbas_files').replaceAll('\\', '/');
  return path.join(dirPath, fileName).replaceAll('\\', '/');
}
