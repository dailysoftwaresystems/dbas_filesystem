import 'dart:async';

import 'package:dbas_filesystem/src/dbas_filesystem_platform.dart';
import 'package:dbas_filesystem/src/helpers/dbas_filesystem_platform_util.dart';
import 'package:dbas_filesystem/src/helpers/dbas_filesystem_path_helper_io.dart'
  if (dart.library.js_interop) 'package:dbas_filesystem/src/helpers/dbas_filesystem_path_helper_web.dart';

class DbasFileSystem {
  static DbasFileSystem? _instance;
  static Completer<DbasFileSystem>? _initCompleter;
  final DbasFileSystemPlatform _platform;

  DbasFileSystem._(this._platform);

  static Future<DbasFileSystem> getInstance() async {
    if (_instance != null) return _instance!;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<DbasFileSystem>();
    try {
      final platform = await DbasFileSystemPlatform.getInstance();
      _instance = DbasFileSystem._(platform);
      _initCompleter!.complete(_instance!);
      return _instance!;
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  // ── Path helpers ──────────────────────────────────────────────────────

  Future<String> getAppFilePath(String fileName) =>
      getAppFilePathImpl(fileName, DbasFileSystemPlatformUtil.isTest());

  // ── Single file operations ────────────────────────────────────────────

  Future<void> writeFile(String filePath, List<int> bytes) =>
      _platform.writeFile(filePath, bytes);

  Future<void> writeFileStream(String filePath, Stream<List<int>> stream) =>
      _platform.writeFileStream(filePath, stream);

  Future<List<int>> readFile(String filePath) =>
      _platform.readFile(filePath);

  Stream<List<int>> readFileStream(String filePath, {int chunkSize = 65536}) =>
      _platform.readFileStream(filePath, chunkSize: chunkSize);

  Future<void> deleteFile(String filePath) =>
      _platform.deleteFile(filePath);

  Future<bool> fileExists(String filePath) =>
      _platform.fileExists(filePath);

  Future<void> copyFile(String sourcePath, String destPath) =>
      _platform.copyFile(sourcePath, destPath);

  Future<void> moveFile(String sourcePath, String destPath) =>
      _platform.moveFile(sourcePath, destPath);

  // ── Bulk operations ───────────────────────────────────────────────────

  Future<void> writeFiles(Map<String, List<int>> files) =>
      _platform.writeFiles(files);

  Future<void> writeFilesStream(Map<String, Stream<List<int>>> files) =>
      _platform.writeFilesStream(files);

  Future<Map<String, List<int>>> readFiles(List<String> paths) =>
      _platform.readFiles(paths);

  // ── Directory operations ──────────────────────────────────────────────

  Future<void> createDirectory(String dirPath, {bool recursive = true}) =>
      _platform.createDirectory(dirPath, recursive: recursive);

  Future<bool> directoryExists(String dirPath) =>
      _platform.directoryExists(dirPath);

  Future<List<String>> listDirectory(String dirPath) =>
      _platform.listDirectory(dirPath);

  Future<void> deleteDirectory(String dirPath, {bool recursive = false}) =>
      _platform.deleteDirectory(dirPath, recursive: recursive);
}
