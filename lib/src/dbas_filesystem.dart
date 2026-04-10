import 'dart:async';

import 'package:dbas_filesystem/src/dbas_filesystem_change.dart';
import 'package:dbas_filesystem/src/dbas_filesystem_entry.dart';
import 'package:dbas_filesystem/src/dbas_filesystem_platform.dart';
import 'package:dbas_filesystem/src/dbas_filesystem_progress.dart';
import 'package:dbas_filesystem/src/helpers/dbas_cancellation_token.dart';
import 'package:dbas_filesystem/src/helpers/dbas_filesystem_platform_util.dart';
import 'package:dbas_filesystem/src/helpers/dbas_filesystem_path_helper_io.dart'
  if (dart.library.js_interop) 'package:dbas_filesystem/src/helpers/dbas_filesystem_path_helper_web.dart';
import 'package:flutter/foundation.dart';

/// Cross-platform file system abstraction for Flutter.
///
/// Provides a unified API for file and directory operations across
/// Android, iOS, macOS, Linux, Windows, and Web.
///
/// **Singleton**: This class uses a singleton pattern by design. A single
/// instance coordinates per-path locking, worker pools (web), and change
/// notifications across the entire application. Call [getInstance] to obtain
/// the shared instance and [dispose] to release it. After [dispose],
/// [getInstance] creates a fresh instance.
///
/// **Web storage**: On web, all storage is backed exclusively by the
/// [Origin Private File System (OPFS)](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API/Origin_private_file_system)
/// via a pool of Web Workers. There is no fallback to IndexedDB or
/// LocalStorage. OPFS is required for the binary streaming and parallel I/O
/// semantics this library guarantees. If the browser does not support OPFS,
/// [getInstance] throws [DbasFileSystemException].
///
/// **Thread safety**: Operations on the same path are automatically
/// serialized via per-path locks. Operations on different paths proceed
/// in parallel. Directory-destructive operations (delete, rename, move)
/// acquire an exclusive lock that blocks concurrent file operations within
/// that directory.
///
/// **Default overwrite behaviour**: write, copy, move, and rename operations
/// default to `overwrite: false` — they throw [FileAlreadyExistsException]
/// if the destination already exists. Pass `overwrite: true` explicitly to
/// replace existing files.
class DbasFileSystem {
  static DbasFileSystem? _instance;
  static Completer<DbasFileSystem>? _initCompleter;
  static Future<void>? _lifecycleMutex;
  final DbasFileSystemPlatform _platform;
  bool _isDisposed = false;

  /// Optional callback invoked after every successful file-system mutation.
  ///
  /// The map keys are affected paths. Each [FileChange] describes the
  /// before/after state. Set via [getInstance] or updated at any time.
  FileChangeCallback? onFileChanged;

  DbasFileSystem._(this._platform);

  // ── Lifecycle mutex ───────────────────────────────────────────────────

  static Future<T> _withMutex<T>(Future<T> Function() action) async {
    final prev = _lifecycleMutex;
    final completer = Completer<void>();
    _lifecycleMutex = completer.future;
    if (prev != null) await prev;
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_lifecycleMutex, completer.future)) {
        _lifecycleMutex = null;
      }
    }
  }

  /// Returns the singleton instance, creating it if needed.
  ///
  /// On web, [workerPoolSize] controls the number of OPFS worker threads
  /// (default 4). Concurrent calls during initialization are coalesced.
  ///
  /// If [onFileChanged] is provided, it is registered as the change
  /// notification callback. You can also set or update
  /// [DbasFileSystem.onFileChanged] on the returned instance at any time.
  ///
  /// Throws [DbasFileSystemException] if initialization fails (e.g. OPFS
  /// not supported on web).
  static Future<DbasFileSystem> getInstance({
    int workerPoolSize = 4,
    FileChangeCallback? onFileChanged,
  }) async {
    if (_instance != null) return _instance!;
    final existing = _initCompleter;
    if (existing != null) return existing.future;

    return _withMutex(() async {
      // Re-check after acquiring mutex — another caller may have completed init.
      if (_instance != null) return _instance!;
      final existing = _initCompleter;
      if (existing != null) return existing.future;

      final completer = Completer<DbasFileSystem>();
      _initCompleter = completer;
      try {
        final platform = await DbasFileSystemPlatform.create(workerPoolSize: workerPoolSize);
        _instance = DbasFileSystem._(platform);
        _instance!.onFileChanged = onFileChanged;
        completer.complete(_instance!);
        return _instance!;
      } catch (e) {
        completer.completeError(e);
        if (identical(_initCompleter, completer)) _initCompleter = null;
        rethrow;
      }
    });
  }

  /// Whether [dispose] has been called on this instance.
  ///
  /// Once `true`, all operations on this instance throw [StateError].
  /// Call [getInstance] to obtain a fresh instance.
  bool get isDisposed => _isDisposed;

  /// Disposes the singleton and releases all resources (e.g. web workers).
  ///
  /// Gives in-flight operations up to [timeout] to complete before forcing
  /// teardown. After calling dispose, [getInstance] will create a fresh
  /// instance. Callers holding old references will get [StateError] on
  /// subsequent calls.
  Future<void> dispose({Duration timeout = const Duration(seconds: 30)}) {
    return _withMutex(() async {
      _isDisposed = true;
      _instance = null;
      _initCompleter = null;
      await _platform.dispose(timeout: timeout);
    });
  }

  void _assertNotDisposed() {
    if (_isDisposed) throw StateError('DbasFileSystem has been disposed.');
  }

  /// Whether the underlying storage is persistent (survives browser eviction).
  ///
  /// Always `true` on native platforms (Android, iOS, macOS, Linux, Windows).
  /// On web, reflects whether the browser granted persistent OPFS storage.
  /// If `false`, data may be evicted under storage pressure.
  bool get isPersistentStorage {
    _assertNotDisposed();
    return _platform.isPersistentStorage;
  }

  // ── Path helpers ──────────────────────────────────────────────────────

  /// Returns a platform-appropriate file path for [fileName] under the
  /// application's data directory.
  ///
  /// On native platforms, uses the application support directory.
  /// On web, returns a path relative to the OPFS root.
  /// Paths are always normalized to forward slashes.
  ///
  /// **This method only resolves a path — it does not create directories.**
  /// Parent directories are created automatically by write operations such
  /// as [writeFile] and [writeFileStream]. If you need the directory to
  /// exist before writing, call [createDirectory] explicitly.
  Future<String> getAppFilePath(String fileName) {
    _assertNotDisposed();
    return getAppFilePathImpl(fileName, DbasFileSystemPlatformUtil.isTest());
  }

  // ── Notification helpers ──────────────────────────────────────────────

  /// Fires the change notification callback. Swallows callback exceptions
  /// so a bug in user code never masks a successful filesystem operation.
  void _notify(Map<String, FileChange> changes) {
    if (changes.isEmpty || onFileChanged == null) return;
    try {
      onFileChanged!.call(changes);
    } catch (_) {
      // Notification failure must never crash the calling operation.
    }
  }

  FileSystemEntry _fileEntry(String path) =>
      FileSystemEntry(path: path, type: FileSystemEntityType.file);

  FileSystemEntry _dirEntry(String path) =>
      FileSystemEntry(path: path, type: FileSystemEntityType.directory);

  // ── Progress helpers ──────────────────────────────────────────────────

  /// Reports completion progress. Swallows callback exceptions so a bug
  /// in user code never masks a successful filesystem operation.
  void _reportDone(String path, FileSystemEntityType type, ProgressCallback? onProgress) {
    if (onProgress == null) return;
    try {
      onProgress(OperationProgress(
        current: CurrentEntryProgress(
          entry: FileSystemEntry(path: path, type: type),
          progress: 1.0,
        ),
        overall: 1.0,
      ));
    } catch (_) {
      // Progress callback failure must never crash the calling operation.
    }
  }

  // ── Single file operations ────────────────────────────────────────────

  /// Writes [bytes] to [filePath], creating parent directories as needed.
  ///
  /// If [overwrite] is `false` (default) and the file already exists, throws
  /// [FileAlreadyExistsException]. Pass `overwrite: true` to replace.
  Future<void> writeFile(String filePath, Uint8List bytes, {bool overwrite = false, ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    final existed = onFileChanged != null ? await _platform.fileExists(filePath) : null;
    await _platform.writeFile(filePath, bytes, overwrite: overwrite);
    _reportDone(filePath, FileSystemEntityType.file, onProgress);
    if (existed != null) {
      final entry = _fileEntry(filePath);
      _notify({filePath: FileChange(oldEntry: existed ? entry : null, newEntry: entry)});
    }
  }

  /// Writes bytes from [stream] to [filePath], creating parent directories
  /// as needed.
  ///
  /// If [overwrite] is `false` (default) and the file already exists, throws
  /// [FileAlreadyExistsException]. Pass `overwrite: true` to replace.
  Future<void> writeFileStream(String filePath, Stream<List<int>> stream, {bool overwrite = false, ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    final existed = onFileChanged != null ? await _platform.fileExists(filePath) : null;
    await _platform.writeFileStream(filePath, stream, overwrite: overwrite);
    _reportDone(filePath, FileSystemEntityType.file, onProgress);
    if (existed != null) {
      final entry = _fileEntry(filePath);
      _notify({filePath: FileChange(oldEntry: existed ? entry : null, newEntry: entry)});
    }
  }

  /// Appends [bytes] to the file at [filePath], creating the file and any
  /// parent directories if they do not exist.
  Future<void> appendFile(String filePath, Uint8List bytes, {ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    final existed = onFileChanged != null ? await _platform.fileExists(filePath) : null;
    await _platform.appendFile(filePath, bytes);
    _reportDone(filePath, FileSystemEntityType.file, onProgress);
    if (existed != null) {
      final entry = _fileEntry(filePath);
      _notify({filePath: FileChange(oldEntry: existed ? entry : null, newEntry: entry)});
    }
  }

  /// Appends bytes from [stream] to the file at [filePath], creating the
  /// file and any parent directories if they do not exist.
  Future<void> appendFileStream(String filePath, Stream<List<int>> stream, {ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    final existed = onFileChanged != null ? await _platform.fileExists(filePath) : null;
    await _platform.appendFileStream(filePath, stream);
    _reportDone(filePath, FileSystemEntityType.file, onProgress);
    if (existed != null) {
      final entry = _fileEntry(filePath);
      _notify({filePath: FileChange(oldEntry: existed ? entry : null, newEntry: entry)});
    }
  }

  /// Reads the entire file at [filePath] into memory.
  ///
  /// Throws [FileNotFoundException] if the file does not exist.
  Future<Uint8List> readFile(String filePath, {ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    final result = await _platform.readFile(filePath);
    _reportDone(filePath, FileSystemEntityType.file, onProgress);
    return result;
  }

  /// Reads the file at [filePath] as a stream of byte chunks.
  ///
  /// Each chunk is at most [chunkSize] bytes (default 64 KB). The last chunk
  /// may be smaller if the remaining file content is less than [chunkSize].
  /// Throws [FileNotFoundException] if the file does not exist.
  ///
  /// **Lock behaviour**: the file path lock is held for the entire stream
  /// lifetime. A slow consumer will block other operations on the same path
  /// until the stream completes or is cancelled.
  Stream<Uint8List> readFileStream(String filePath, {int chunkSize = 65536}) {
    _assertNotDisposed();
    return _platform.readFileStream(filePath, chunkSize: chunkSize);
  }

  /// Deletes the file at [filePath]. No-op if the file does not exist.
  Future<void> deleteFile(String filePath, {ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    final existed = onFileChanged != null ? await _platform.fileExists(filePath) : null;
    await _platform.deleteFile(filePath);
    _reportDone(filePath, FileSystemEntityType.file, onProgress);
    if (existed == true) {
      _notify({filePath: FileChange(oldEntry: _fileEntry(filePath))});
    }
  }

  /// Returns `true` if a file exists at [filePath].
  Future<bool> fileExists(String filePath) {
    _assertNotDisposed();
    return _platform.fileExists(filePath);
  }

  /// Copies the file at [sourcePath] to [destPath], creating parent
  /// directories as needed.
  ///
  /// If [overwrite] is `false` (default) and the destination already exists,
  /// throws [FileAlreadyExistsException]. Pass `overwrite: true` to replace.
  /// Throws [FileNotFoundException] if the source file does not exist.
  Future<void> copyFile(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    final destExisted = onFileChanged != null ? await _platform.fileExists(destPath) : null;
    await _platform.copyFile(sourcePath, destPath, overwrite: overwrite, onProgress: onProgress);
    if (onProgress != null) _reportDone(destPath, FileSystemEntityType.file, onProgress);
    if (destExisted != null) {
      final entry = _fileEntry(destPath);
      _notify({destPath: FileChange(oldEntry: destExisted ? entry : null, newEntry: entry)});
    }
  }

  /// Moves the file at [sourcePath] to [destPath], creating parent
  /// directories as needed.
  ///
  /// Falls back to copy-then-delete when moving across filesystems.
  /// If [overwrite] is `false` (default) and the destination already exists,
  /// throws [FileAlreadyExistsException]. Pass `overwrite: true` to replace.
  /// Throws [FileNotFoundException] if the source file does not exist.
  Future<void> moveFile(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    final destExisted = onFileChanged != null ? await _platform.fileExists(destPath) : null;
    await _platform.moveFile(sourcePath, destPath, overwrite: overwrite, onProgress: onProgress);
    if (onProgress != null) _reportDone(destPath, FileSystemEntityType.file, onProgress);
    if (destExisted != null) {
      final srcEntry = _fileEntry(sourcePath);
      final destEntry = _fileEntry(destPath);
      _notify({
        sourcePath: FileChange(oldEntry: srcEntry),
        destPath: FileChange(oldEntry: destExisted ? destEntry : null, newEntry: destEntry),
      });
    }
  }

  /// Renames the file at [oldPath] to [newPath], creating parent
  /// directories as needed.
  ///
  /// If [overwrite] is `false` (default) and the destination already exists,
  /// throws [FileAlreadyExistsException]. Pass `overwrite: true` to replace.
  /// Throws [FileNotFoundException] if the source file does not exist.
  Future<void> renameFile(String oldPath, String newPath, {bool overwrite = false, ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    final destExisted = onFileChanged != null ? await _platform.fileExists(newPath) : null;
    await _platform.renameFile(oldPath, newPath, overwrite: overwrite);
    _reportDone(newPath, FileSystemEntityType.file, onProgress);
    if (destExisted != null) {
      final oldEntry = _fileEntry(oldPath);
      final newEntry = _fileEntry(newPath);
      _notify({
        oldPath: FileChange(oldEntry: oldEntry),
        newPath: FileChange(oldEntry: destExisted ? newEntry : null, newEntry: newEntry),
      });
    }
  }

  // ── File metadata ─────────────────────────────────────────────────────

  /// Returns the size of the file at [filePath] in bytes.
  ///
  /// Throws [FileNotFoundException] if the file does not exist.
  Future<int> getFileSize(String filePath) {
    _assertNotDisposed();
    return _platform.getFileSize(filePath);
  }

  /// Returns the last-modified timestamp (UTC) of the file at [filePath].
  ///
  /// Throws [FileNotFoundException] if the file does not exist.
  Future<DateTime> getLastModified(String filePath) {
    _assertNotDisposed();
    return _platform.getLastModified(filePath);
  }

  // ── Bulk operations ───────────────────────────────────────────────────

  /// Writes multiple files concurrently, bounded by [maxConcurrency].
  ///
  /// **Atomic mode** ([atomic] = `true`, default): snapshots existing files,
  /// writes all, and rolls back on failure. Throws
  /// [AtomicOperationException] containing the primary error and an
  /// optional [AtomicOperationException.secondaryError] if rollback fails.
  /// When [secondaryError] is non-null, some files may not have been
  /// rolled back — callers should verify state with [fileExists] for
  /// affected paths. The [onError] callback is ignored in atomic mode.
  /// No [onFileChanged] notification fires on failure.
  ///
  /// **Non-atomic mode** ([atomic] = `false`): writes proceed independently.
  /// If [onError] is provided, individual failures invoke the callback and
  /// the operation continues. If [onError] is `null`, throws on the first
  /// error.
  ///
  /// Per-path locking still applies — same-path operations serialize.
  ///
  /// If [cancellationToken] is provided and cancelled, tasks that have not
  /// yet started will throw [OperationCancelledException]. Tasks already in
  /// flight will run to completion.
  ///
  /// **Not atomic when `atomic: false`**: if one write fails, others may
  /// have already completed. No rollback is performed.
  ///
  /// **Memory**: all [files] byte content must fit in memory simultaneously.
  /// For large files, prefer [writeFileStream] individually.
  Future<void> writeFiles(
    Map<String, Uint8List> files, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
    ProgressCallback? onProgress,
    bool atomic = true,
    void Function(String path, Object error)? onError,
  }) async {
    _assertNotDisposed();
    final existedMap = await _platform.writeFiles(files,
        maxConcurrency: maxConcurrency, cancellationToken: cancellationToken,
        onProgress: onProgress, atomic: atomic, onError: onError);
    if (onFileChanged != null) {
      final changes = <String, FileChange>{};
      for (final path in files.keys) {
        if (!existedMap.containsKey(path)) continue; // skipped by onError
        final entry = _fileEntry(path);
        changes[path] = FileChange(
          oldEntry: (existedMap[path] ?? false) ? entry : null,
          newEntry: entry,
        );
      }
      _notify(changes);
    }
  }

  /// Writes multiple files from streams concurrently, bounded by
  /// [maxConcurrency].
  ///
  /// See [writeFiles] for [atomic] and [onError] semantics.
  Future<void> writeFilesStream(
    Map<String, Stream<List<int>>> files, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
    ProgressCallback? onProgress,
    bool atomic = true,
    void Function(String path, Object error)? onError,
  }) async {
    _assertNotDisposed();
    final existedMap = await _platform.writeFilesStream(files,
        maxConcurrency: maxConcurrency, cancellationToken: cancellationToken,
        onProgress: onProgress, atomic: atomic, onError: onError);
    if (onFileChanged != null) {
      final changes = <String, FileChange>{};
      for (final path in files.keys) {
        if (!existedMap.containsKey(path)) continue;
        final entry = _fileEntry(path);
        changes[path] = FileChange(
          oldEntry: (existedMap[path] ?? false) ? entry : null,
          newEntry: entry,
        );
      }
      _notify(changes);
    }
  }

  /// Reads multiple files concurrently, bounded by [maxConcurrency].
  ///
  /// Returns a map from file path to byte content.
  ///
  /// If [onError] is provided, individual read failures invoke the callback
  /// and the failed path is omitted from the result. If [onError] is `null`,
  /// throws [MultiException] on any failure — no partial results returned.
  ///
  /// If [cancellationToken] is provided and cancelled, tasks that have not
  /// yet started will throw [OperationCancelledException]. Tasks already in
  /// flight will run to completion.
  ///
  /// **Memory**: all file contents are held in memory simultaneously, bounded
  /// only by [maxConcurrency]. For large files, prefer [readFileStream]
  /// individually to control memory usage.
  Future<Map<String, Uint8List>> readFiles(
    List<String> paths, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
    ProgressCallback? onProgress,
    void Function(String path, Object error)? onError,
  }) {
    _assertNotDisposed();
    return _platform.readFiles(paths,
        maxConcurrency: maxConcurrency, cancellationToken: cancellationToken,
        onProgress: onProgress, onError: onError);
  }

  // ── Directory operations ──────────────────────────────────────────────

  /// Creates a directory at [dirPath].
  ///
  /// If [recursive] is `true` (default), creates all missing parent
  /// directories. If `false`, throws [DirectoryNotFoundException] when
  /// the parent does not exist.
  Future<void> createDirectory(String dirPath, {bool recursive = true, ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    final existed = onFileChanged != null ? await _platform.directoryExists(dirPath) : null;
    await _platform.createDirectory(dirPath, recursive: recursive);
    _reportDone(dirPath, FileSystemEntityType.directory, onProgress);
    if (existed == false) {
      _notify({dirPath: FileChange(newEntry: _dirEntry(dirPath))});
    }
  }

  /// Returns `true` if a directory exists at [dirPath].
  Future<bool> directoryExists(String dirPath) {
    _assertNotDisposed();
    return _platform.directoryExists(dirPath);
  }

  /// Lists the entries in the directory at [dirPath].
  ///
  /// If [recursive] is `true`, lists all entries in subdirectories as well.
  /// Each entry includes a normalized forward-slash path and its type
  /// ([FileSystemEntityType.file] or [FileSystemEntityType.directory]).
  /// Throws [DirectoryNotFoundException] if the directory does not exist.
  Future<List<FileSystemEntry>> listDirectory(String dirPath, {bool recursive = false}) {
    _assertNotDisposed();
    return _platform.listDirectory(dirPath, recursive: recursive);
  }

  /// Deletes the directory at [dirPath]. No-op if it does not exist.
  ///
  /// If [recursive] is `false` (default) and the directory is not empty,
  /// throws [DirectoryNotEmptyException].
  Future<void> deleteDirectory(String dirPath, {bool recursive = false, ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    List<FileSystemEntry>? entries;
    if (onFileChanged != null && await _platform.directoryExists(dirPath)) {
      try {
        entries = await _platform.listDirectory(dirPath, recursive: true);
      } catch (_) {
        entries = null;
      }
    }
    await _platform.deleteDirectory(dirPath, recursive: recursive);
    _reportDone(dirPath, FileSystemEntityType.directory, onProgress);
    if (entries != null) {
      final changes = <String, FileChange>{};
      changes[dirPath] = FileChange(oldEntry: _dirEntry(dirPath));
      for (final e in entries) {
        changes[e.path] = FileChange(oldEntry: e);
      }
      _notify(changes);
    }
  }

  /// Renames the directory at [oldPath] to [newPath].
  ///
  /// Throws [DirectoryNotFoundException] if the source does not exist.
  Future<void> renameDirectory(String oldPath, String newPath, {ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    List<FileSystemEntry>? oldEntries;
    if (onFileChanged != null && await _platform.directoryExists(oldPath)) {
      try {
        oldEntries = await _platform.listDirectory(oldPath, recursive: true);
      } catch (_) {
        oldEntries = null;
      }
    }
    await _platform.renameDirectory(oldPath, newPath);
    _reportDone(newPath, FileSystemEntityType.directory, onProgress);
    if (oldEntries != null) {
      final changes = <String, FileChange>{};
      changes[oldPath] = FileChange(oldEntry: _dirEntry(oldPath));
      changes[newPath] = FileChange(newEntry: _dirEntry(newPath));
      for (final e in oldEntries) {
        changes[e.path] = FileChange(oldEntry: e);
        final relative = e.path.substring(oldPath.length);
        final newEntryPath = '$newPath$relative';
        changes[newEntryPath] = FileChange(
          newEntry: FileSystemEntry(path: newEntryPath, type: e.type),
        );
      }
      _notify(changes);
    }
  }

  /// Copies the directory at [sourcePath] to [destPath], creating the
  /// destination and any missing parent directories as needed.
  ///
  /// This is a merge operation: files in [destPath] that have no counterpart
  /// in [sourcePath] are left untouched. If [overwrite] is `false` (default)
  /// and any file at a matching path already exists in the destination,
  /// throws [FileAlreadyExistsException]. Pass `overwrite: true` to replace
  /// conflicting files.
  ///
  /// Throws [DirectoryNotFoundException] if [sourcePath] does not exist.
  Future<void> copyDirectory(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    await _platform.copyDirectory(sourcePath, destPath, overwrite: overwrite, onProgress: onProgress);
    if (onProgress != null) _reportDone(destPath, FileSystemEntityType.directory, onProgress);
    if (onFileChanged != null) {
      try {
        final destEntries = await _platform.listDirectory(destPath, recursive: true);
        final changes = <String, FileChange>{};
        changes[destPath] = FileChange(newEntry: _dirEntry(destPath));
        for (final e in destEntries) {
          changes[e.path] = FileChange(newEntry: e);
        }
        _notify(changes);
      } catch (_) {
        // Best-effort notification.
      }
    }
  }

  /// Moves the directory at [sourcePath] to [destPath].
  ///
  /// On native, attempts an atomic rename first. Falls back to copy+delete
  /// when moving across filesystems. On web, always performs copy+delete.
  ///
  /// Throws [DirectoryNotFoundException] if [sourcePath] does not exist.
  Future<void> moveDirectory(String sourcePath, String destPath, {ProgressCallback? onProgress}) async {
    _assertNotDisposed();
    List<FileSystemEntry>? srcEntries;
    if (onFileChanged != null) {
      try {
        srcEntries = await _platform.listDirectory(sourcePath, recursive: true);
      } catch (_) {
        srcEntries = null;
      }
    }
    await _platform.moveDirectory(sourcePath, destPath, onProgress: onProgress);
    if (onProgress != null) _reportDone(destPath, FileSystemEntityType.directory, onProgress);
    if (srcEntries != null) {
      final changes = <String, FileChange>{};
      changes[sourcePath] = FileChange(oldEntry: _dirEntry(sourcePath));
      changes[destPath] = FileChange(newEntry: _dirEntry(destPath));
      for (final e in srcEntries) {
        changes[e.path] = FileChange(oldEntry: e);
        final relative = e.path.substring(sourcePath.length);
        final newPath = '$destPath$relative';
        changes[newPath] = FileChange(
          newEntry: FileSystemEntry(path: newPath, type: e.type),
        );
      }
      _notify(changes);
    }
  }
}
