import 'dart:typed_data';

import 'package:dbas_filesystem/src/dbas_filesystem_entry.dart';
import 'package:dbas_filesystem/src/dbas_filesystem_progress.dart';
import 'package:dbas_filesystem/src/native/dbas_filesystem_native_interface.dart';

/// Shared stub base for platforms where the real implementation is not
/// available (e.g. dart:io classes on web, or web classes on native).
/// Every method throws [UnsupportedError].
class DbasFileSystemNativeStub extends DbasFileSystemNativeInterface {
  final String _platform;
  DbasFileSystemNativeStub(this._platform);

  Never _unsupported() => throw UnsupportedError('Not supported on $_platform.');

  @override
  bool get isPersistentStorage => _unsupported();
  @override
  Future<void> initialize({int workerPoolSize = 4}) => _unsupported();
  @override
  Future<void> dispose() => _unsupported();
  @override
  Future<void> writeFile(String path, Uint8List bytes, {bool overwrite = false}) => _unsupported();
  @override
  Future<void> writeFileStream(String path, Stream<List<int>> stream, {bool overwrite = false}) => _unsupported();
  @override
  Future<void> appendFile(String path, Uint8List bytes) => _unsupported();
  @override
  Future<void> appendFileStream(String path, Stream<List<int>> stream) => _unsupported();
  @override
  Future<Uint8List> readFile(String path) => _unsupported();
  @override
  Stream<Uint8List> readFileStream(String path, {int chunkSize = 65536}) => _unsupported();
  @override
  Future<void> deleteFile(String path) => _unsupported();
  @override
  Future<bool> fileExists(String path) => _unsupported();
  @override
  Future<void> copyFile(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) => _unsupported();
  @override
  Future<void> moveFile(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) => _unsupported();
  @override
  Future<void> renameFile(String oldPath, String newPath, {bool overwrite = false}) => _unsupported();
  @override
  Future<int> getFileSize(String path) => _unsupported();
  @override
  Future<DateTime> getLastModified(String path) => _unsupported();
  @override
  Future<void> createDirectory(String path, {bool recursive = true}) => _unsupported();
  @override
  Future<bool> directoryExists(String path) => _unsupported();
  @override
  Future<List<FileSystemEntry>> listDirectory(String path, {bool recursive = false}) => _unsupported();
  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) => _unsupported();
  @override
  Future<void> renameDirectory(String oldPath, String newPath) => _unsupported();
  @override
  Future<void> copyDirectory(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) => _unsupported();
  @override
  Future<void> moveDirectory(String sourcePath, String destPath, {ProgressCallback? onProgress}) => _unsupported();
}
