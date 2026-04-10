import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbas_filesystem/src/dbas_filesystem_entry.dart';
import 'package:dbas_filesystem/src/dbas_filesystem_exceptions.dart';
import 'package:dbas_filesystem/src/dbas_filesystem_progress.dart';
import 'dbas_filesystem_native_interface.dart';

class DbasFileSystemNativeApp extends DbasFileSystemNativeInterface {
  @override
  bool get isPersistentStorage => true;

  @override
  Future<void> initialize({int workerPoolSize = 4}) async {}

  @override
  Future<void> dispose() async {}

  // ── Single file operations ────────────────────────────────────────────

  @override
  Future<void> writeFile(String path, Uint8List bytes, {bool overwrite = false}) async {
    final file = File(path);
    if (!overwrite && await file.exists()) {
      throw FileAlreadyExistsException(path);
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    } on FileSystemException catch (e) {
      _throwMapped(e, path);
      rethrow;
    }
  }

  @override
  Future<void> writeFileStream(String path, Stream<List<int>> stream, {bool overwrite = false}) async {
    final file = File(path);
    if (!overwrite && await file.exists()) {
      throw FileAlreadyExistsException(path);
    }
    try {
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
    } on FileSystemException catch (e) {
      _throwMapped(e, path);
      rethrow;
    }
  }

  @override
  Future<void> appendFile(String path, Uint8List bytes) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      final sink = file.openWrite(mode: FileMode.append);
      try {
        sink.add(bytes);
        await sink.flush();
      } finally {
        await sink.close();
      }
    } on FileSystemException catch (e) {
      _throwMapped(e, path);
      rethrow;
    }
  }

  @override
  Future<void> appendFileStream(String path, Stream<List<int>> stream) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      final sink = file.openWrite(mode: FileMode.append);
      try {
        await for (final chunk in stream) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } on FileSystemException catch (e) {
      _throwMapped(e, path);
      rethrow;
    }
  }

  @override
  Future<Uint8List> readFile(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      _throwMapped(e, path);
      rethrow;
    }
  }

  @override
  Stream<Uint8List> readFileStream(String path, {int chunkSize = 65536}) {
    late StreamController<Uint8List> controller;
    bool cancelled = false;
    Completer<void>? pauseCompleter;

    controller = StreamController<Uint8List>(
      onPause: () { pauseCompleter = Completer<void>(); },
      onResume: () {
        pauseCompleter?.complete();
        pauseCompleter = null;
      },
      onCancel: () {
        cancelled = true;
        pauseCompleter?.complete();
        pauseCompleter = null;
      },
      onListen: () async {
        RandomAccessFile? raf;
        try {
          try {
            raf = await File(path).open();
          } on FileSystemException catch (e) {
            _throwMapped(e, path);
            rethrow;
          }
          while (!cancelled) {
            final pc = pauseCompleter;
            if (pc != null) await pc.future;
            if (cancelled) break;
            final chunk = await raf.read(chunkSize);
            if (chunk.isEmpty || cancelled) break;
            controller.add(chunk);
            if (chunk.length < chunkSize) break;
          }
        } catch (e) {
          if (!cancelled && !controller.isClosed) controller.addError(e);
        } finally {
          try { await raf?.close(); } catch (_) {}
          if (!controller.isClosed) controller.close();
        }
      },
    );
    return controller.stream;
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
  Future<void> copyFile(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) async {
    final sourceFile = File(sourcePath);
    final destFile = File(destPath);
    final destExisted = await destFile.exists();
    if (!overwrite && destExisted) {
      throw FileAlreadyExistsException(destPath);
    }
    int totalSize;
    try {
      totalSize = await sourceFile.length();
    } on FileSystemException catch (e) {
      _throwMapped(e, sourcePath);
      rethrow;
    }
    var succeeded = false;
    await destFile.parent.create(recursive: true);
    int transferred = 0;
    final writer = destFile.openWrite();
    try {
      await for (final chunk in sourceFile.openRead()) {
        writer.add(chunk);
        transferred += chunk.length;
        if (onProgress != null && totalSize > 0) {
          onProgress(OperationProgress(
            current: CurrentEntryProgress(
              entry: FileSystemEntry(path: destPath, type: FileSystemEntityType.file),
              progress: (transferred / totalSize).clamp(0.0, 1.0),
            ),
            overall: (transferred / totalSize).clamp(0.0, 1.0),
          ));
        }
      }
      await writer.flush();
      succeeded = true;
    } on FileSystemException catch (e) {
      _throwMapped(e, sourcePath);
      rethrow;
    } finally {
      try { await writer.close(); } catch (_) {}
      if (!succeeded && !destExisted) {
        try { await destFile.delete(); } catch (_) {}
      }
    }
  }

  @override
  Future<void> moveFile(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) async {
    final source = File(sourcePath);
    final dest = File(destPath);
    if (!overwrite && await dest.exists()) {
      throw FileAlreadyExistsException(destPath);
    }
    await dest.parent.create(recursive: true);
    try {
      await source.rename(destPath);
    } on FileSystemException catch (e) {
      // Cross-device rename fails — fallback to copy+delete.
      // EXDEV = 18 (Linux/macOS), ERROR_NOT_SAME_DEVICE = 17 (Windows)
      final code = e.osError?.errorCode;
      if (code == 18 || code == 17) {
        try {
          await copyFile(sourcePath, destPath, overwrite: true, onProgress: onProgress);
        } catch (_) {
          // Clean up partial destination on copy failure
          if (await dest.exists()) {
            try { await dest.delete(); } catch (_) {}
          }
          rethrow;
        }
        try {
          await source.delete();
        } catch (_) {
          // Source delete failed — keep the destination (copy succeeded,
          // data is intact) and propagate the error. Matches web behaviour.
          rethrow;
        }
      } else {
        _throwMapped(e, sourcePath);
        rethrow;
      }
    }
  }

  @override
  Future<void> renameFile(String oldPath, String newPath, {bool overwrite = false}) async {
    if (!overwrite && await File(newPath).exists()) {
      throw FileAlreadyExistsException(newPath);
    }
    try {
      final dest = File(newPath);
      await dest.parent.create(recursive: true);
      await File(oldPath).rename(newPath);
    } on FileSystemException catch (e) {
      _throwMapped(e, oldPath);
      rethrow;
    }
  }

  // ── File metadata ─────────────────────────────────────────────────────

  @override
  Future<int> getFileSize(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException catch (e) {
      _throwMapped(e, path);
      rethrow;
    }
  }

  @override
  Future<DateTime> getLastModified(String path) async {
    try {
      return (await File(path).lastModified()).toUtc();
    } on FileSystemException catch (e) {
      _throwMapped(e, path);
      rethrow;
    }
  }

  // ── Directory operations ──────────────────────────────────────────────

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    try {
      await Directory(path).create(recursive: recursive);
    } on FileSystemException catch (e) {
      _throwMapped(e, path, isDirectory: true);
      rethrow;
    }
  }

  @override
  Future<bool> directoryExists(String path) async {
    return await Directory(path).exists();
  }

  @override
  Future<List<FileSystemEntry>> listDirectory(String path, {bool recursive = false}) async {
    try {
      final entities = await Directory(path).list(recursive: recursive).toList();
      final entries = <FileSystemEntry>[];
      for (final e in entities) {
        final normalized = e.path.replaceAll('\\', '/');
        FileSystemEntityType type;
        if (e is File) {
          type = FileSystemEntityType.file;
        } else if (e is Directory) {
          type = FileSystemEntityType.directory;
        } else {
          // Symlink — resolve target type.
          type = await FileSystemEntity.isDirectory(e.path)
              ? FileSystemEntityType.directory
              : FileSystemEntityType.file;
        }
        entries.add(FileSystemEntry(path: normalized, type: type));
      }
      return entries;
    } on FileSystemException catch (e) {
      _throwMapped(e, path, isDirectory: true);
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
      _throwMapped(e, oldPath, isDirectory: true);
      rethrow;
    }
  }

  @override
  Future<void> copyDirectory(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) async {
    final source = Directory(sourcePath);
    if (!await source.exists()) {
      throw DirectoryNotFoundException(sourcePath);
    }
    await Directory(destPath).create(recursive: true);
    var sourcePrefix = sourcePath.replaceAll('\\', '/');
    if (!sourcePrefix.endsWith('/')) sourcePrefix = '$sourcePrefix/';

    // Collect all entities for progress tracking.
    final entities = await source.list(recursive: true).toList();
    final total = entities.whereType<File>().length;
    int completed = 0;

    for (final entity in entities) {
      final normalizedEntity = entity.path.replaceAll('\\', '/');
      final relative = normalizedEntity.substring(sourcePrefix.length);
      final normalizedDest = destPath.replaceAll('\\', '/');
      final targetPath = normalizedDest.endsWith('/') ? '$normalizedDest$relative' : '$normalizedDest/$relative';
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        final targetFile = File(targetPath);
        if (!overwrite && await targetFile.exists()) {
          throw FileAlreadyExistsException(targetPath);
        }
        await targetFile.parent.create(recursive: true);
        await entity.copy(targetPath);
        completed++;
        if (onProgress != null && total > 0) {
          onProgress(OperationProgress(
            current: CurrentEntryProgress(
              entry: FileSystemEntry(path: targetPath, type: FileSystemEntityType.file),
              progress: 1.0,
            ),
            overall: (completed / total).clamp(0.0, 1.0),
          ));
        }
      }
    }
  }

  @override
  Future<void> moveDirectory(String sourcePath, String destPath, {ProgressCallback? onProgress}) async {
    final source = Directory(sourcePath);
    if (!await source.exists()) {
      throw DirectoryNotFoundException(sourcePath);
    }
    try {
      await source.rename(destPath);
    } on FileSystemException catch (e) {
      // Cross-device rename fails — fallback to copy+delete.
      // EXDEV = 18 (Linux/macOS), ERROR_NOT_SAME_DEVICE = 17 (Windows)
      final code = e.osError?.errorCode;
      if (code == 18 || code == 17) {
        try {
          await copyDirectory(sourcePath, destPath, overwrite: true, onProgress: onProgress);
        } catch (_) {
          // Clean up partial destination on copy failure
          final dest = Directory(destPath);
          if (await dest.exists()) {
            try { await dest.delete(recursive: true); } catch (_) {}
          }
          rethrow;
        }
        await source.delete(recursive: true);
      } else {
        _throwMapped(e, sourcePath, isDirectory: true);
        rethrow;
      }
    }
  }

  // ── Error mapping ─────────────────────────────────────────────────────

  /// Maps a [FileSystemException] to a typed [DbasFileSystemException] if a
  /// known OS error code is present. Returns `null` for unrecognised codes.
  ///
  /// When [isDirectory] is `true`, missing-path codes map to
  /// [DirectoryNotFoundException]; when `false`, to [FileNotFoundException].
  static DbasFileSystemException? handleError(
    FileSystemException e,
    String path, {
    bool isDirectory = false,
  }) {
    final code = e.osError?.errorCode;
    switch (code) {
      // ENOENT = 2 (Linux/macOS/Windows)
      case 2:
        return isDirectory ? DirectoryNotFoundException(path) : FileNotFoundException(path);
      // ERROR_PATH_NOT_FOUND = 3 (Windows) — always a missing directory component
      case 3:
        return DirectoryNotFoundException(path);
      // ENOTDIR = 20 (Linux/macOS) — a path component is not a directory
      case 20:
      // EISDIR = 21 (Linux/macOS) — expected file, got directory (or vice versa)
      case 21:
        return isDirectory ? DirectoryNotFoundException(path) : FileNotFoundException(path);
      // EPERM = 1 (Linux/macOS)
      case 1:
      // ERROR_ACCESS_DENIED = 5 (Windows)
      case 5:
      // EACCES = 13 (Linux/macOS)
      case 13:
        return PermissionDeniedException(path);
      default:
        return null;
    }
  }

  static void _throwMapped(FileSystemException e, String path, {bool isDirectory = false}) {
    final mapped = handleError(e, path, isDirectory: isDirectory);
    if (mapped != null) throw mapped;
  }
}
