import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbas_filesystem/src/dbas_filesystem_exceptions.dart';
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
  Future<void> writeFile(String path, Uint8List bytes, {bool overwrite = true}) async {
    final file = File(path);
    if (!overwrite && await file.exists()) {
      throw FileAlreadyExistsException(path);
    }
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> writeFileStream(String path, Stream<List<int>> stream, {bool overwrite = true}) async {
    final file = File(path);
    if (!overwrite && await file.exists()) {
      throw FileAlreadyExistsException(path);
    }
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
  Future<Uint8List> readFile(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      _throwIfNotFound(e, path);
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
            _throwIfNotFound(e, path);
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
  Future<void> copyFile(String sourcePath, String destPath) async {
    final destFile = File(destPath);
    final destExisted = await destFile.exists();
    var succeeded = false;
    await destFile.parent.create(recursive: true);
    final writer = destFile.openWrite();
    try {
      await for (final chunk in File(sourcePath).openRead()) {
        writer.add(chunk);
      }
      await writer.flush();
      succeeded = true;
    } on FileSystemException catch (e) {
      _throwIfNotFound(e, sourcePath);
      rethrow;
    } finally {
      try { await writer.close(); } catch (_) {}
      if (!succeeded && !destExisted) {
        try { await destFile.delete(); } catch (_) {}
      }
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
        try {
          await copyFile(sourcePath, destPath);
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
          // Source delete failed — roll back destination to avoid duplicates
          if (await dest.exists()) {
            try { await dest.delete(); } catch (_) {}
          }
          rethrow;
        }
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
      return entities.map((e) => e.path.replaceAll('\\', '/')).toList();
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
    // EACCES = 13 (Linux/macOS), ERROR_ACCESS_DENIED = 5 (Windows)
    if (code == 13 || code == 5) throw PermissionDeniedException(path);
  }

  static void _throwIfDirNotFound(FileSystemException e, String path) {
    final code = e.osError?.errorCode;
    if (code == 2) throw DirectoryNotFoundException(path);
    // EACCES = 13 (Linux/macOS), ERROR_ACCESS_DENIED = 5 (Windows)
    if (code == 13 || code == 5) throw PermissionDeniedException(path);
  }
}
