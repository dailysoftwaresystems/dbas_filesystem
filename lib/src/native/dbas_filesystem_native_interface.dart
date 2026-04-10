import 'package:dbas_filesystem/src/dbas_filesystem_entry.dart';
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

  /// Whether the underlying storage is persistent (survives browser eviction).
  /// Always `true` on native platforms. On web, reflects whether the browser
  /// granted persistent OPFS storage.
  bool get isPersistentStorage;

  Future<void> initialize({int workerPoolSize = 4});
  Future<void> dispose();

  // ── Single file operations ────────────────────────────────────────────

  Future<void> writeFile(String path, Uint8List bytes, {bool overwrite = true});
  Future<void> writeFileStream(String path, Stream<List<int>> stream, {bool overwrite = true});
  Future<void> appendFile(String path, Uint8List bytes);
  Future<void> appendFileStream(String path, Stream<List<int>> stream);
  Future<Uint8List> readFile(String path);
  Stream<Uint8List> readFileStream(String path, {int chunkSize = 65536});
  Future<void> deleteFile(String path);
  Future<bool> fileExists(String path);
  Future<void> copyFile(String sourcePath, String destPath, {bool overwrite = true});
  Future<void> moveFile(String sourcePath, String destPath, {bool overwrite = true});
  Future<void> renameFile(String oldPath, String newPath, {bool overwrite = true});

  // ── File metadata ─────────────────────────────────────────────────────

  Future<int> getFileSize(String path);
  Future<DateTime> getLastModified(String path);

  // ── Directory operations ──────────────────────────────────────────────

  Future<void> createDirectory(String path, {bool recursive = true});
  Future<bool> directoryExists(String path);
  Future<List<FileSystemEntry>> listDirectory(String path, {bool recursive = false});
  Future<void> deleteDirectory(String path, {bool recursive = false});
  Future<void> renameDirectory(String oldPath, String newPath);
  Future<void> copyDirectory(String sourcePath, String destPath, {bool overwrite = true});
}
