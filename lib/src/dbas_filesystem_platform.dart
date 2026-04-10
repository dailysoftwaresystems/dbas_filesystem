import 'dart:async';
import 'dart:typed_data';

import 'package:dbas_filesystem/src/dbas_filesystem_exceptions.dart';
import 'package:dbas_filesystem/src/helpers/dbas_cancellation_token.dart';
import 'package:dbas_filesystem/src/helpers/dbas_concurrency_pool.dart';
import 'package:dbas_filesystem/src/helpers/dbas_path_lock.dart';
import 'package:dbas_filesystem/src/helpers/dbas_path_validator.dart';
import 'package:dbas_filesystem/src/native/dbas_filesystem_native_interface.dart';

final class DbasFileSystemPlatform {
  final DbasFileSystemNativeInterface _delegate;
  final PathLock _lock = PathLock();

  DbasFileSystemPlatform._(this._delegate);

  static Future<DbasFileSystemPlatform> create({int workerPoolSize = 4}) async {
    final delegate = DbasFileSystemNativeInterface.getInstance();
    await delegate.initialize(workerPoolSize: workerPoolSize);
    return DbasFileSystemPlatform._(delegate);
  }

  bool get isPersistentStorage => _delegate.isPersistentStorage;

  Future<void> dispose() async {
    await _lock.dispose();
    await _delegate.dispose();
    DbasFileSystemNativeInterface.resetInstance();
  }

  // ── Single file operations ────────────────────────────────────────────

  Future<void> writeFile(String path, Uint8List bytes, {bool overwrite = true}) {
    DbasPathValidator.validate(path);
    return _lock.synchronized(path, () => _delegate.writeFile(path, bytes, overwrite: overwrite));
  }

  Future<void> writeFileStream(String path, Stream<List<int>> stream, {bool overwrite = true}) {
    DbasPathValidator.validate(path);
    return _lock.synchronized(path, () => _delegate.writeFileStream(path, stream, overwrite: overwrite));
  }

  Future<Uint8List> readFile(String path) {
    DbasPathValidator.validate(path);
    return _lock.synchronized(path, () => _delegate.readFile(path));
  }

  Stream<Uint8List> readFileStream(String path, {int chunkSize = 65536}) {
    DbasPathValidator.validate(path);
    late StreamController<Uint8List> controller;
    final lockCompleter = Completer<void>();
    bool cancelled = false;

    controller = StreamController<Uint8List>(
      onListen: () {
        _lock.synchronized(path, () async {
          await for (final chunk in _delegate.readFileStream(path, chunkSize: chunkSize)) {
            if (cancelled || controller.isClosed) break;
            controller.add(chunk);
          }
        }).catchError((Object e) {
          if (!cancelled && !controller.isClosed) controller.addError(e);
        }).whenComplete(() {
          if (!controller.isClosed) controller.close();
          if (!lockCompleter.isCompleted) lockCompleter.complete();
        });
      },
      onCancel: () {
        cancelled = true;
        return lockCompleter.future;
      },
    );
    return controller.stream;
  }

  Future<void> deleteFile(String path) {
    DbasPathValidator.validate(path);
    return _lock.synchronized(path, () => _delegate.deleteFile(path));
  }

  Future<bool> fileExists(String path) {
    DbasPathValidator.validate(path);
    return _lock.synchronized(path, () => _delegate.fileExists(path));
  }

  Future<void> copyFile(String sourcePath, String destPath) {
    DbasPathValidator.validateAll([sourcePath, destPath]);
    return _lock.synchronizedMulti([sourcePath, destPath], () => _delegate.copyFile(sourcePath, destPath));
  }

  Future<void> moveFile(String sourcePath, String destPath) {
    DbasPathValidator.validateAll([sourcePath, destPath]);
    return _lock.synchronizedMulti([sourcePath, destPath], () => _delegate.moveFile(sourcePath, destPath));
  }

  Future<void> renameFile(String oldPath, String newPath) {
    DbasPathValidator.validateAll([oldPath, newPath]);
    return _lock.synchronizedMulti([oldPath, newPath], () => _delegate.renameFile(oldPath, newPath));
  }

  // ── File metadata ─────────────────────────────────────────────────────

  Future<int> getFileSize(String path) {
    DbasPathValidator.validate(path);
    return _lock.synchronized(path, () => _delegate.getFileSize(path));
  }

  Future<DateTime> getLastModified(String path) {
    DbasPathValidator.validate(path);
    return _lock.synchronized(path, () => _delegate.getLastModified(path));
  }

  // ── Bulk operations ───────────────────────────────────────────────────

  Future<void> writeFiles(
    Map<String, Uint8List> files, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
    void Function(String path, Object error)? onError,
  }) {
    if (onError == null) {
      return ConcurrencyPool.runAll(
        files.entries.map((e) => () => writeFile(e.key, e.value)),
        maxConcurrency: maxConcurrency,
        cancellationToken: cancellationToken,
      );
    }
    return ConcurrencyPool.runAll(
      files.entries.map((e) => () async {
        try {
          await writeFile(e.key, e.value);
        } catch (err) {
          if (err is OperationCancelledException) rethrow;
          onError(e.key, err);
        }
      }),
      maxConcurrency: maxConcurrency,
      cancellationToken: cancellationToken,
    );
  }

  Future<void> writeFilesStream(
    Map<String, Stream<List<int>>> files, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
    void Function(String path, Object error)? onError,
  }) {
    if (onError == null) {
      return ConcurrencyPool.runAll(
        files.entries.map((e) => () => writeFileStream(e.key, e.value)),
        maxConcurrency: maxConcurrency,
        cancellationToken: cancellationToken,
      );
    }
    return ConcurrencyPool.runAll(
      files.entries.map((e) => () async {
        try {
          await writeFileStream(e.key, e.value);
        } catch (err) {
          if (err is OperationCancelledException) rethrow;
          onError(e.key, err);
        }
      }),
      maxConcurrency: maxConcurrency,
      cancellationToken: cancellationToken,
    );
  }

  Future<Map<String, Uint8List>> readFiles(
    List<String> paths, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
    void Function(String path, Object error)? onError,
  }) async {
    if (onError == null) {
      final entries = await ConcurrencyPool.runAll(
        paths.map((p) => () async => MapEntry(p, await readFile(p))),
        maxConcurrency: maxConcurrency,
        cancellationToken: cancellationToken,
      );
      return Map.fromEntries(entries);
    }

    final entries = await ConcurrencyPool.runAll(
      paths.map((p) => () async {
        try {
          return MapEntry<String, Uint8List?>(p, await readFile(p));
        } catch (e) {
          if (e is OperationCancelledException) rethrow;
          onError(p, e);
          return MapEntry<String, Uint8List?>(p, null);
        }
      }),
      maxConcurrency: maxConcurrency,
      cancellationToken: cancellationToken,
    );
    final result = <String, Uint8List>{};
    for (final e in entries) {
      if (e.value != null) result[e.key] = e.value!;
    }
    return result;
  }

  // ── Directory operations ──────────────────────────────────────────────

  Future<void> createDirectory(String path, {bool recursive = true}) {
    DbasPathValidator.validate(path);
    return _lock.synchronized(path, () => _delegate.createDirectory(path, recursive: recursive));
  }

  Future<bool> directoryExists(String path) {
    DbasPathValidator.validate(path);
    return _lock.synchronized(path, () => _delegate.directoryExists(path));
  }

  Future<List<String>> listDirectory(String path) {
    DbasPathValidator.validate(path);
    return _lock.synchronized(path, () => _delegate.listDirectory(path));
  }

  Future<void> deleteDirectory(String path, {bool recursive = false}) {
    DbasPathValidator.validate(path);
    return _lock.synchronized(path, () => _delegate.deleteDirectory(path, recursive: recursive));
  }

  Future<void> renameDirectory(String oldPath, String newPath) {
    DbasPathValidator.validateAll([oldPath, newPath]);
    return _lock.synchronizedMulti([oldPath, newPath], () => _delegate.renameDirectory(oldPath, newPath));
  }
}
