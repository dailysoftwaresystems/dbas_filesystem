import 'dart:io';
import 'dbas_filesystem_native_interface.dart';

class DbasFileSystemNativeApp extends DbasFileSystemNativeInterface {
  @override
  Future<void> initialize() async {
    // No initialization needed for dart:io
  }

  @override
  Future<void> writeFile(String path, List<int> bytes) async {
    final file = File(path);
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
    return await File(path).readAsBytes();
  }

  @override
  Stream<List<int>> readFileStream(String path, {int chunkSize = 65536}) {
    return File(path).openRead();
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
    final destFile = File(destPath);
    await destFile.parent.create(recursive: true);
    await File(sourcePath).openRead().pipe(destFile.openWrite());
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
        rethrow;
      }
    }
  }

  @override
  Future<void> writeFiles(Map<String, List<int>> files) async {
    for (final entry in files.entries) {
      await writeFile(entry.key, entry.value);
    }
  }

  @override
  Future<void> writeFilesStream(Map<String, Stream<List<int>>> files) async {
    for (final entry in files.entries) {
      await writeFileStream(entry.key, entry.value);
    }
  }

  @override
  Future<Map<String, List<int>>> readFiles(List<String> paths) async {
    final result = <String, List<int>>{};
    for (final path in paths) {
      result[path] = await readFile(path);
    }
    return result;
  }

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
    final entities = await Directory(path).list().toList();
    return entities.map((e) => e.path).toList();
  }

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: recursive);
    }
  }
}
