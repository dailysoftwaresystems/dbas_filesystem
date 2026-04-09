import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

Future<String> getAppFilePathImpl(String fileName, bool isTest) async {
  if (isTest) {
    String filePath = path.join(Directory.current.path, 'test', 'files');
    Directory dir = Directory(filePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path.join(filePath, fileName);
  }

  final directory = await getApplicationSupportDirectory();
  final dirPath = path.join(directory.path, 'dbas_files').replaceAll('\\', '/');
  final dir = Directory(dirPath);

  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return path.join(dirPath, fileName);
}
