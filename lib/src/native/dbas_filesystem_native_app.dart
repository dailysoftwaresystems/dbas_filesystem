import 'dart:io';
import 'package:dbas_filesystem/src/dbas_filesystem_exceptions.dart';
import 'package:dbas_filesystem/src/helpers/dbas_concurrency_pool.dart';
import 'dbas_filesystem_native_interface.dart';

class DbasFileSystemNativeApp extends DbasFileSystemNativeInterface {
  @override
  Future<void> initialize({int workerPoolSize = 4}) async {
    // No initialization needed for dart:io
  }

  // ── Single file operations ────────────────────────────────────────────

  @override
  Future<void> writeFile(String path, List<int> bytes, {bool overwrite = true}) async {
    final file = File(path);
    if (!overwrite && await file.exists()) {
      throw FileAlreadyExistsException(path);
    }
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> writeFileStream(String path, Stream<List<int>> stream) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    try {
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  @override
  Future<List<int>> readFile(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      _throwIfNotFound(e, path);
      rethrow;
    }
  }

  @override
  Stream<List<int>> readFileStream(String path, {int chunkSize = 65536}) {
    return File(path).openRead().handleError((e) {
      if (e is FileSystemException) _throwIfNotFound(e, path);
      throw e;
    });
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> fileExists(String path) async {
    return await File(path).exists();
  }

  @override
  Future<void> copyFile(String sourcePath, String destPath) async {
    try {
      final destFile = File(destPath);
      await destFile.parent.create(recursive: true);
      await File(sourcePath).openRead().pipe(destFile.openWrite());
    } on FileSystemException catch (e) {
      _throwIfNotFound(e, sourcePath);
      rethrow;
    }
  }

  @override
  Future<void> moveFile(String sourcePath, String destPath) async {
    final source = File(sourcePath);
    final dest = File(destPath);
    await dest.parent.create(recursive: true);
    try {
      await source.rename(destPath);
    } on FileSystemException catch (e) {
      // Cross-device rename fails — fallback to copy+delete.
      // EXDEV = 18 (Linux/macOS), ERROR_NOT_SAME_DEVICE = 17 (Windows)
      final code = e.osError?.errorCode;
      if (code == 18 || code == 17) {
        await copyFile(sourcePath, destPath);
        await source.delete();
      } else {
        _throwIfNotFound(e, sourcePath);
        rethrow;
      }
    }
  }

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    try {
      final dest = File(newPath);
      await dest.parent.create(recursive: true);
      await File(oldPath).rename(newPath);
    } on FileSystemException catch (e) {
      _throwIfNotFound(e, oldPath);
      rethrow;
    }
  }

  // ── File metadata ─────────────────────────────────────────────────────

  @override
  Future<int> getFileSize(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException catch (e) {
      _throwIfNotFound(e, path);
      rethrow;
    }
  }

  @override
  Future<DateTime> getLastModified(String path) async {
    try {
      return (await File(path).lastModified()).toUtc();
    } on FileSystemException catch (e) {
      _throwIfNotFound(e, path);
      rethrow;
    }
  }

  // ── Bulk operations ───────────────────────────────────────────────────

  @override
  Future<void> writeFiles(Map<String, List<int>> files, {int maxConcurrency = 10}) async {
    await ConcurrencyPool.runAll(
      files.entries.map((e) => () => writeFile(e.key, e.value)),
      maxConcurrency: maxConcurrency,
    );
  }

  @override
  Future<void> writeFilesStream(Map<String, Stream<List<int>>> files, {int maxConcurrency = 10}) async {
    await ConcurrencyPool.runAll(
      files.entries.map((e) => () => writeFileStream(e.key, e.value)),
      maxConcurrency: maxConcurrency,
    );
  }

  @override
  Future<Map<String, List<int>>> readFiles(List<String> paths, {int maxConcurrency = 10}) async {
    final result = <String, List<int>>{};
    final entries = await ConcurrencyPool.runAll(
      paths.map((p) => () async => MapEntry(p, await readFile(p))),
      maxConcurrency: maxConcurrency,
    );
    for (final entry in entries) {
      result[entry.key] = entry.value;
    }
    return result;
  }

  // ── Directory operations ──────────────────────────────────────────────

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    await Directory(path).create(recursive: recursive);
  }

  @override
  Future<bool> directoryExists(String path) async {
    return await Directory(path).exists();
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    try {
      final entities = await Directory(path).list().toList();
      return entities.map((e) => e.path).toList();
    } on FileSystemException catch (e) {
      _throwIfDirNotFound(e, path);
      rethrow;
    }
  }

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: recursive);
      } on FileSystemException catch (e) {
        final code = e.osError?.errorCode;
        // ENOTEMPTY = 39 (Linux/macOS), ERROR_DIR_NOT_EMPTY = 145 (Windows)
        if (code == 39 || code == 145) {
          throw DirectoryNotEmptyException(path);
        }
        rethrow;
      }
    }
  }

  @override
  Future<void> renameDirectory(String oldPath, String newPath) async {
    try {
      await Directory(oldPath).rename(newPath);
    } on FileSystemException catch (e) {
      _throwIfDirNotFound(e, oldPath);
      rethrow;
    }
  }

  // ── Error mapping ─────────────────────────────────────────────────────

  static void _throwIfNotFound(FileSystemException e, String path) {
    final code = e.osError?.errorCode;
    // ENOENT = 2 (Linux/macOS/Windows)
    if (code == 2) throw FileNotFoundException(path);
  }

  static void _throwIfDirNotFound(FileSystemException e, String path) {
    final code = e.osError?.errorCode;
    if (code == 2) throw DirectoryNotFoundException(path);
  }
}
