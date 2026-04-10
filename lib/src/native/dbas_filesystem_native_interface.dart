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

  static void resetInstance() {
    _instance = null;
  }

  static DbasFileSystemNativeInterface _getPlatform() {
    if (kIsWeb) {
      return DbasFileSystemNativeWeb();
    }
    return DbasFileSystemNativeApp();
  }

  Future<void> initialize({int workerPoolSize = 4});
  Future<void> dispose();

  // ── Single file operations ────────────────────────────────────────────

  Future<void> writeFile(String path, Uint8List bytes, {bool overwrite = true});
  Future<void> writeFileStream(String path, Stream<List<int>> stream, {bool overwrite = true});
  Future<Uint8List> readFile(String path);
  Stream<Uint8List> readFileStream(String path, {int chunkSize = 65536});
  Future<void> deleteFile(String path);
  Future<bool> fileExists(String path);
  Future<void> copyFile(String sourcePath, String destPath);
  Future<void> moveFile(String sourcePath, String destPath);
  Future<void> renameFile(String oldPath, String newPath);

  // ── File metadata ─────────────────────────────────────────────────────

  Future<int> getFileSize(String path);
  Future<DateTime> getLastModified(String path);

  // ── Directory operations ──────────────────────────────────────────────

  Future<void> createDirectory(String path, {bool recursive = true});
  Future<bool> directoryExists(String path);
  Future<List<String>> listDirectory(String path);
  Future<void> deleteDirectory(String path, {bool recursive = false});
  Future<void> renameDirectory(String oldPath, String newPath);
}
