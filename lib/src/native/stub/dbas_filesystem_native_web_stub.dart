import 'package:dbas_filesystem/src/native/dbas_filesystem_native_interface.dart';

class DbasFileSystemNativeWeb extends DbasFileSystemNativeInterface {
  @override
  Future<void> initialize({int workerPoolSize = 4}) async =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> writeFile(String path, List<int> bytes, {bool overwrite = true}) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> writeFileStream(String path, Stream<List<int>> stream) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<List<int>> readFile(String path) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Stream<List<int>> readFileStream(String path, {int chunkSize = 65536}) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> deleteFile(String path) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<bool> fileExists(String path) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> copyFile(String sourcePath, String destPath) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> moveFile(String sourcePath, String destPath) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> renameFile(String oldPath, String newPath) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<int> getFileSize(String path) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<DateTime> getLastModified(String path) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> writeFiles(Map<String, List<int>> files, {int maxConcurrency = 10}) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> writeFilesStream(Map<String, Stream<List<int>>> files, {int maxConcurrency = 10}) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<Map<String, List<int>>> readFiles(List<String> paths, {int maxConcurrency = 10}) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<bool> directoryExists(String path) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<List<String>> listDirectory(String path) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> renameDirectory(String oldPath, String newPath) =>
      throw UnsupportedError('Not supported in web.');
}
