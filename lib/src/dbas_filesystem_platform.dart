import 'dart:async';
import 'package:dbas_filesystem/src/native/dbas_filesystem_native_interface.dart';

final class DbasFileSystemPlatform {
  static DbasFileSystemPlatform? _instance;
  static Completer<DbasFileSystemPlatform>? _initCompleter;
  final DbasFileSystemNativeInterface _delegate;

  DbasFileSystemPlatform._(this._delegate);

  static Future<DbasFileSystemPlatform> getInstance() async {
    if (_instance != null) return _instance!;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<DbasFileSystemPlatform>();
    try {
      final delegate = DbasFileSystemNativeInterface.getInstance();
      await delegate.initialize();
      _instance = DbasFileSystemPlatform._(delegate);
      _initCompleter!.complete(_instance!);
      return _instance!;
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<void> writeFile(String path, List<int> bytes) =>
      _delegate.writeFile(path, bytes);

  Future<void> writeFileStream(String path, Stream<List<int>> stream) =>
      _delegate.writeFileStream(path, stream);

  Future<List<int>> readFile(String path) =>
      _delegate.readFile(path);

  Stream<List<int>> readFileStream(String path, {int chunkSize = 65536}) =>
      _delegate.readFileStream(path, chunkSize: chunkSize);

  Future<void> deleteFile(String path) =>
      _delegate.deleteFile(path);

  Future<bool> fileExists(String path) =>
      _delegate.fileExists(path);

  Future<void> copyFile(String sourcePath, String destPath) =>
      _delegate.copyFile(sourcePath, destPath);

  Future<void> moveFile(String sourcePath, String destPath) =>
      _delegate.moveFile(sourcePath, destPath);

  Future<void> writeFiles(Map<String, List<int>> files) =>
      _delegate.writeFiles(files);

  Future<void> writeFilesStream(Map<String, Stream<List<int>>> files) =>
      _delegate.writeFilesStream(files);

  Future<Map<String, List<int>>> readFiles(List<String> paths) =>
      _delegate.readFiles(paths);

  Future<void> createDirectory(String path, {bool recursive = true}) =>
      _delegate.createDirectory(path, recursive: recursive);

  Future<bool> directoryExists(String path) =>
      _delegate.directoryExists(path);

  Future<List<String>> listDirectory(String path) =>
      _delegate.listDirectory(path);

  Future<void> deleteDirectory(String path, {bool recursive = false}) =>
      _delegate.deleteDirectory(path, recursive: recursive);
}
