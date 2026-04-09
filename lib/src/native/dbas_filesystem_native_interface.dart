import 'package:dbas_filesystem/src/native/dbas_filesystem_native_app_selector.dart';
import 'package:dbas_filesystem/src/native/stub/dbas_filesystem_native_web_stub.dart'
  if (dart.library.js_interop) 'package:dbas_filesystem/src/native/dbas_filesystem_native_web.dart';

import 'package:flutter/foundation.dart';

abstract class DbasFileSystemNativeInterface {
  static DbasFileSystemNativeInterface? _instance;

  static DbasFileSystemNativeInterface getInstance() {
    _instance ??= _getPlatform();
    return _instance!;
  }

  static DbasFileSystemNativeInterface _getPlatform() {
    if (kIsWeb) {
      return DbasFileSystemNativeWeb();
    }
    return DbasFileSystemNativeApp();
  }

  Future<void> initialize();

  Future<void> writeFile(String path, List<int> bytes);
  Future<void> writeFileStream(String path, Stream<List<int>> stream);
  Future<List<int>> readFile(String path);
  Stream<List<int>> readFileStream(String path, {int chunkSize = 65536});
  Future<void> deleteFile(String path);
  Future<bool> fileExists(String path);
  Future<void> copyFile(String sourcePath, String destPath);
  Future<void> moveFile(String sourcePath, String destPath);

  Future<void> writeFiles(Map<String, List<int>> files);
  Future<void> writeFilesStream(Map<String, Stream<List<int>>> files);
  Future<Map<String, List<int>>> readFiles(List<String> paths);

  Future<void> createDirectory(String path, {bool recursive = true});
  Future<bool> directoryExists(String path);
  Future<List<String>> listDirectory(String path);
  Future<void> deleteDirectory(String path, {bool recursive = false});
}
