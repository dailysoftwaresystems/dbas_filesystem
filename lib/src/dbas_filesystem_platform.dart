import 'dart:async';
import 'dart:typed_data';

import 'package:dbas_filesystem/src/dbas_filesystem_entry.dart';
import 'package:dbas_filesystem/src/dbas_filesystem_exceptions.dart';
import 'package:dbas_filesystem/src/dbas_filesystem_progress.dart';
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

  Future<void> dispose({Duration timeout = const Duration(seconds: 30)}) async {
    await _lock.dispose(timeout: timeout);
    await _delegate.dispose();
    DbasFileSystemNativeInterface.resetInstance();
  }

  // ── Lock helpers ─────────────────────────────────────────────────────

  /// File operations: shared lock on parent directory + exclusive lock on file.
  Future<T> _fileLock<T>(String path, Future<T> Function() action) {
    final parent = PathLock.parentOf(path);
    return _lock.withLocks(
      sharedPaths: [?parent],
      exclusivePaths: [path],
      action: action,
    );
  }

  /// Two-file operations: shared locks on both parents + exclusive on both files.
  Future<T> _twoFileLock<T>(String pathA, String pathB, Future<T> Function() action) {
    final parentA = PathLock.parentOf(pathA);
    final parentB = PathLock.parentOf(pathB);
    return _lock.withLocks(
      sharedPaths: [?parentA, ?parentB],
      exclusivePaths: [pathA, pathB],
      action: action,
    );
  }

  // ── Single file operations ────────────────────────────────────────────

  Future<void> writeFile(String path, Uint8List bytes, {bool overwrite = false}) {
    DbasPathValidator.validate(path);
    return _fileLock(path, () => _delegate.writeFile(path, bytes, overwrite: overwrite));
  }

  Future<void> writeFileStream(String path, Stream<List<int>> stream, {bool overwrite = false}) {
    DbasPathValidator.validate(path);
    return _fileLock(path, () => _delegate.writeFileStream(path, stream, overwrite: overwrite));
  }

  Future<void> appendFile(String path, Uint8List bytes) {
    DbasPathValidator.validate(path);
    return _fileLock(path, () => _delegate.appendFile(path, bytes));
  }

  Future<void> appendFileStream(String path, Stream<List<int>> stream) {
    DbasPathValidator.validate(path);
    return _fileLock(path, () => _delegate.appendFileStream(path, stream));
  }

  Future<Uint8List> readFile(String path) {
    DbasPathValidator.validate(path);
    return _fileLock(path, () => _delegate.readFile(path));
  }

  /// Reads a file as a stream of chunks.
  ///
  /// **Lock behaviour**: a shared lock on the parent directory and an
  /// exclusive lock on the file path are held for the entire lifetime of
  /// the stream. If the consumer reads slowly or pauses, other operations
  /// on the same path will block until the stream completes or is cancelled.
  Stream<Uint8List> readFileStream(String path, {int chunkSize = 65536}) {
    DbasPathValidator.validate(path);
    late StreamController<Uint8List> controller;
    final lockCompleter = Completer<void>();
    bool cancelled = false;

    controller = StreamController<Uint8List>(
      onListen: () {
        final parent = PathLock.parentOf(path);
        _lock.withLocks(
          sharedPaths: [?parent],
          exclusivePaths: [path],
          action: () async {
            await for (final chunk in _delegate.readFileStream(path, chunkSize: chunkSize)) {
              if (cancelled || controller.isClosed) break;
              controller.add(chunk);
            }
          },
        ).catchError((Object e) {
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
    return _fileLock(path, () => _delegate.deleteFile(path));
  }

  Future<bool> fileExists(String path) {
    DbasPathValidator.validate(path);
    return _fileLock(path, () => _delegate.fileExists(path));
  }

  Future<void> copyFile(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) {
    DbasPathValidator.validateAll([sourcePath, destPath]);
    return _twoFileLock(sourcePath, destPath,
        () => _delegate.copyFile(sourcePath, destPath, overwrite: overwrite, onProgress: onProgress));
  }

  Future<void> moveFile(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) {
    DbasPathValidator.validateAll([sourcePath, destPath]);
    return _twoFileLock(sourcePath, destPath,
        () => _delegate.moveFile(sourcePath, destPath, overwrite: overwrite, onProgress: onProgress));
  }

  Future<void> renameFile(String oldPath, String newPath, {bool overwrite = false}) {
    DbasPathValidator.validateAll([oldPath, newPath]);
    return _twoFileLock(oldPath, newPath,
        () => _delegate.renameFile(oldPath, newPath, overwrite: overwrite));
  }

  // ── File metadata ─────────────────────────────────────────────────────

  Future<int> getFileSize(String path) {
    DbasPathValidator.validate(path);
    return _fileLock(path, () => _delegate.getFileSize(path));
  }

  Future<DateTime> getLastModified(String path) {
    DbasPathValidator.validate(path);
    return _fileLock(path, () => _delegate.getLastModified(path));
  }

  // ── Bulk operations ───────────────────────────────────────────────────

  void _reportBulkProgress(String path, int completed, int total, ProgressCallback? onProgress) {
    try { onProgress?.call(OperationProgress(
      current: CurrentEntryProgress(
        entry: FileSystemEntry(path: path, type: FileSystemEntityType.file),
        progress: 1.0,
      ),
      overall: (completed / total).clamp(0.0, 1.0),
    )); } catch (_) {}
  }

  /// Writes multiple files concurrently. Returns a map indicating which
  /// paths existed before the operation (for notification use).
  ///
  /// When [atomic] is `true` (default), snapshots existing files, writes
  /// all, and rolls back on failure via [AtomicOperationException].
  /// The [onError] callback is ignored in atomic mode.
  ///
  /// When [atomic] is `false`, writes proceed independently. If [onError]
  /// is provided, individual failures invoke the callback and continue.
  /// If [onError] is `null`, throws on the first error.
  Future<Map<String, bool>> writeFiles(
    Map<String, Uint8List> files, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
    ProgressCallback? onProgress,
    bool atomic = true,
    void Function(String path, Object error)? onError,
  }) async {
    if (files.isEmpty) return {};
    cancellationToken?.throwIfCancelled();
    final paths = files.keys.toList();
    final total = paths.length;

    if (!atomic) {
      return _writeFilesNonAtomic(files, paths, total,
          maxConcurrency: maxConcurrency, cancellationToken: cancellationToken,
          onProgress: onProgress, onError: onError);
    }

    // ── Atomic mode ──

    // Phase 1: Snapshot existing state for rollback.
    final snapshots = <String, Uint8List?>{};
    await ConcurrencyPool.runAll(
      paths.map((p) => () async {
        snapshots[p] = await fileExists(p) ? await readFile(p) : null;
      }),
      maxConcurrency: maxConcurrency,
      cancellationToken: cancellationToken,
    );

    // Phase 2: Write all files concurrently (overwrite: true since we have
    // snapshots for rollback and the user explicitly provides new content).
    int completed = 0;
    final succeeded = <String>{};
    final errors = <(String, Object)>[];
    final pool = ConcurrencyPool(maxConcurrency);

    await Future.wait(
      paths.map((path) async {
        try {
          await pool.run(() async {
            cancellationToken?.throwIfCancelled();
            await writeFile(path, files[path]!, overwrite: true);
            succeeded.add(path);
            completed++;
            _reportBulkProgress(path, completed, total, onProgress);
          });
        } catch (e) {
          errors.add((path, e));
        }
      }),
    );

    if (errors.isEmpty) {
      return snapshots.map((k, v) => MapEntry(k, v != null));
    }

    // Phase 3: Rollback.
    return _rollback(errors, succeeded, snapshots);
  }

  /// Non-atomic write: independent writes with optional per-file error handling.
  Future<Map<String, bool>> _writeFilesNonAtomic(
    Map<String, Uint8List> files,
    List<String> paths,
    int total, {
    required int maxConcurrency,
    CancellationToken? cancellationToken,
    ProgressCallback? onProgress,
    void Function(String path, Object error)? onError,
  }) async {
    final existed = <String, bool>{};
    int completed = 0;

    await ConcurrencyPool.runAll(
      paths.map((path) => _wrapOnError<void>(path, () async {
        existed[path] = await fileExists(path);
        cancellationToken?.throwIfCancelled();
        await writeFile(path, files[path]!, overwrite: true);
        completed++;
        _reportBulkProgress(path, completed, total, onProgress);
      }, onError)),
      maxConcurrency: maxConcurrency,
      cancellationToken: cancellationToken,
    );

    return existed;
  }

  /// Writes multiple files from streams concurrently. Returns a map
  /// indicating which paths existed before the operation.
  ///
  /// See [writeFiles] for [atomic] and [onError] semantics.
  Future<Map<String, bool>> writeFilesStream(
    Map<String, Stream<List<int>>> files, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
    ProgressCallback? onProgress,
    bool atomic = true,
    void Function(String path, Object error)? onError,
  }) async {
    if (files.isEmpty) return {};
    cancellationToken?.throwIfCancelled();
    final paths = files.keys.toList();
    final total = paths.length;

    if (!atomic) {
      final existed = <String, bool>{};
      int completed = 0;

      await ConcurrencyPool.runAll(
        paths.map((path) => _wrapOnError<void>(path, () async {
          existed[path] = await fileExists(path);
          cancellationToken?.throwIfCancelled();
          await writeFileStream(path, files[path]!, overwrite: true);
          completed++;
          _reportBulkProgress(path, completed, total, onProgress);
        }, onError)),
        maxConcurrency: maxConcurrency,
        cancellationToken: cancellationToken,
      );

      return existed;
    }

    // ── Atomic mode ──

    // Phase 1: Snapshot existing state for rollback.
    final snapshots = <String, Uint8List?>{};
    await ConcurrencyPool.runAll(
      paths.map((p) => () async {
        snapshots[p] = await fileExists(p) ? await readFile(p) : null;
      }),
      maxConcurrency: maxConcurrency,
      cancellationToken: cancellationToken,
    );

    // Phase 2: Write all files concurrently (overwrite: true — see writeFiles).
    int completed = 0;
    final succeeded = <String>{};
    final errors = <(String, Object)>[];
    final pool = ConcurrencyPool(maxConcurrency);

    await Future.wait(
      paths.map((path) async {
        try {
          await pool.run(() async {
            cancellationToken?.throwIfCancelled();
            await writeFileStream(path, files[path]!, overwrite: true);
            succeeded.add(path);
            completed++;
            _reportBulkProgress(path, completed, total, onProgress);
          });
        } catch (e) {
          errors.add((path, e));
        }
      }),
    );

    if (errors.isEmpty) {
      return snapshots.map((k, v) => MapEntry(k, v != null));
    }

    // Phase 3: Rollback.
    return _rollback(errors, succeeded, snapshots);
  }

  /// Reads multiple files concurrently.
  ///
  /// If [onError] is provided, individual read failures invoke the callback
  /// and the failed path is omitted from the result. If [onError] is `null`,
  /// throws [MultiException] on any failure — no partial results returned.
  Future<Map<String, Uint8List>> readFiles(
    List<String> paths, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
    ProgressCallback? onProgress,
    void Function(String path, Object error)? onError,
  }) async {
    if (paths.isEmpty) return {};
    cancellationToken?.throwIfCancelled();
    final total = paths.length;
    int completed = 0;

    final entries = await ConcurrencyPool.runAll(
      paths.map((p) => _wrapOnError<MapEntry<String, Uint8List?>>(
        p,
        () async {
          cancellationToken?.throwIfCancelled();
          final data = await readFile(p);
          completed++;
          _reportBulkProgress(p, completed, total, onProgress);
          return MapEntry<String, Uint8List?>(p, data);
        },
        onError,
        MapEntry<String, Uint8List?>(p, null),
      )),
      maxConcurrency: maxConcurrency,
      cancellationToken: cancellationToken,
    );

    final result = <String, Uint8List>{};
    for (final e in entries) {
      if (e.value != null) result[e.key] = e.value!;
    }
    return result;
  }

  /// Wraps a task with an optional [onError] handler.
  ///
  /// If [onError] is `null`, the task runs as-is (errors propagate normally
  /// and are collected by [ConcurrencyPool.runAll]).
  /// If [onError] is provided, errors (except [OperationCancelledException])
  /// are caught, the callback is invoked, and [fallback] is returned.
  static Future<T> Function() _wrapOnError<T>(
    String path,
    Future<T> Function() task,
    void Function(String path, Object error)? onError, [
    T? fallback,
  ]) {
    if (onError == null) return task;
    return () async {
      try {
        return await task();
      } catch (e) {
        if (e is OperationCancelledException) rethrow;
        onError(path, e);
        return fallback as T;
      }
    };
  }

  /// Rolls back [succeeded] writes using [snapshots] and throws
  /// [AtomicOperationException] containing the primary [errors] and any
  /// rollback errors as [secondaryError].
  Future<Never> _rollback(
    List<(String, Object)> errors,
    Set<String> succeeded,
    Map<String, Uint8List?> snapshots,
  ) async {
    final rollbackErrors = <(String, Object)>[];
    for (final path in succeeded) {
      try {
        final original = snapshots[path];
        if (original == null) {
          await deleteFile(path);
        } else {
          await writeFile(path, original, overwrite: true);
        }
      } catch (e) {
        rollbackErrors.add((path, e));
      }
    }

    final primary = errors.length == 1 ? errors.first.$2 : MultiException(errors);
    final secondary = rollbackErrors.isEmpty
        ? null
        : rollbackErrors.length == 1
            ? rollbackErrors.first.$2
            : MultiException(rollbackErrors);

    throw AtomicOperationException(primary, secondaryError: secondary);
  }

  // ── Directory operations ──────────────────────────────────────────────

  Future<void> createDirectory(String path, {bool recursive = true}) {
    DbasPathValidator.validate(path);
    return _lock.shared(path, () => _delegate.createDirectory(path, recursive: recursive));
  }

  Future<bool> directoryExists(String path) {
    DbasPathValidator.validate(path);
    return _lock.shared(path, () => _delegate.directoryExists(path));
  }

  Future<List<FileSystemEntry>> listDirectory(String path, {bool recursive = false}) {
    DbasPathValidator.validate(path);
    return _lock.shared(path, () => _delegate.listDirectory(path, recursive: recursive));
  }

  Future<void> deleteDirectory(String path, {bool recursive = false}) {
    DbasPathValidator.validate(path);
    return _lock.exclusive(path, () => _delegate.deleteDirectory(path, recursive: recursive));
  }

  Future<void> renameDirectory(String oldPath, String newPath) {
    DbasPathValidator.validateAll([oldPath, newPath]);
    return _lock.withLocks(
      exclusivePaths: [oldPath, newPath],
      action: () => _delegate.renameDirectory(oldPath, newPath),
    );
  }

  Future<void> copyDirectory(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) {
    DbasPathValidator.validateAll([sourcePath, destPath]);
    return _lock.withLocks(
      sharedPaths: [sourcePath],
      exclusivePaths: [destPath],
      action: () => _delegate.copyDirectory(sourcePath, destPath, overwrite: overwrite, onProgress: onProgress),
    );
  }

  Future<void> moveDirectory(String sourcePath, String destPath, {ProgressCallback? onProgress}) {
    DbasPathValidator.validateAll([sourcePath, destPath]);
    return _lock.withLocks(
      exclusivePaths: [sourcePath, destPath],
      action: () => _delegate.moveDirectory(sourcePath, destPath, onProgress: onProgress),
    );
  }
}
