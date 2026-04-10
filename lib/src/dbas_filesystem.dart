import 'dart:async';

import 'package:dbas_filesystem/src/dbas_filesystem_platform.dart';
import 'package:dbas_filesystem/src/helpers/dbas_cancellation_token.dart';
import 'package:dbas_filesystem/src/helpers/dbas_filesystem_platform_util.dart';
import 'package:dbas_filesystem/src/helpers/dbas_filesystem_path_helper_io.dart'
  if (dart.library.js_interop) 'package:dbas_filesystem/src/helpers/dbas_filesystem_path_helper_web.dart';
import 'package:flutter/foundation.dart';

/// Cross-platform file system abstraction for Flutter.
///
/// Provides a unified API for file and directory operations across
/// Android, iOS, macOS, Linux, Windows, and Web (OPFS).
/// Operations on the same path are automatically serialized via per-path locks.
class DbasFileSystem {
  static DbasFileSystem? _instance;
  static Completer<DbasFileSystem>? _initCompleter;
  final DbasFileSystemPlatform _platform;

  DbasFileSystem._(this._platform);

  /// Returns the singleton instance, creating it if needed.
  ///
  /// On web, [workerPoolSize] controls the number of OPFS worker threads
  /// (default 4). Concurrent calls during initialization are coalesced.
  ///
  /// Throws [DbasFileSystemException] if initialization fails (e.g. OPFS
  /// not supported on web).
  static Future<DbasFileSystem> getInstance({int workerPoolSize = 4}) async {
    if (_instance != null) return _instance!;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<DbasFileSystem>();
    try {
      final platform = await DbasFileSystemPlatform.create(workerPoolSize: workerPoolSize);
      _instance = DbasFileSystem._(platform);
      _initCompleter!.complete(_instance!);
      return _instance!;
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  /// Disposes the singleton and releases all resources (e.g. web workers).
  ///
  /// After calling dispose, [getInstance] will create a fresh instance.
  /// Callers holding old references will get [StateError] on subsequent calls.
  Future<void> dispose() async {
    // Null out singleton first so concurrent getInstance() calls don't
    // return the being-disposed instance.
    _instance = null;
    _initCompleter = null;
    await _platform.dispose();
  }

  /// Whether the underlying storage is persistent (survives browser eviction).
  ///
  /// Always `true` on native platforms (Android, iOS, macOS, Linux, Windows).
  /// On web, reflects whether the browser granted persistent OPFS storage.
  /// If `false`, data may be evicted under storage pressure.
  bool get isPersistentStorage => _platform.isPersistentStorage;

  // ── Path helpers ──────────────────────────────────────────────────────

  /// Returns a platform-appropriate file path for [fileName] under the
  /// application's data directory.
  ///
  /// On native platforms, uses the application support directory.
  /// On web, returns a path relative to the OPFS root.
  /// Paths are always normalized to forward slashes.
  Future<String> getAppFilePath(String fileName) =>
      getAppFilePathImpl(fileName, DbasFileSystemPlatformUtil.isTest());

  // ── Single file operations ────────────────────────────────────────────

  /// Writes [bytes] to [filePath], creating parent directories as needed.
  ///
  /// If [overwrite] is `false` and the file already exists, throws
  /// [FileAlreadyExistsException]. Defaults to overwriting.
  Future<void> writeFile(String filePath, Uint8List bytes, {bool overwrite = true}) =>
      _platform.writeFile(filePath, bytes, overwrite: overwrite);

  /// Writes bytes from [stream] to [filePath], creating parent directories
  /// as needed.
  ///
  /// If [overwrite] is `false` and the file already exists, throws
  /// [FileAlreadyExistsException]. Defaults to overwriting.
  Future<void> writeFileStream(String filePath, Stream<List<int>> stream, {bool overwrite = true}) =>
      _platform.writeFileStream(filePath, stream, overwrite: overwrite);

  /// Reads the entire file at [filePath] into memory.
  ///
  /// Throws [FileNotFoundException] if the file does not exist.
  Future<Uint8List> readFile(String filePath) =>
      _platform.readFile(filePath);

  /// Reads the file at [filePath] as a stream of byte chunks.
  ///
  /// On web, each chunk is at most [chunkSize] bytes (default 64 KB).
  /// On native platforms, chunk sizes are determined by the underlying I/O
  /// system and [chunkSize] is not used.
  /// Throws [FileNotFoundException] if the file does not exist.
  Stream<Uint8List> readFileStream(String filePath, {int chunkSize = 65536}) =>
      _platform.readFileStream(filePath, chunkSize: chunkSize);

  /// Deletes the file at [filePath]. No-op if the file does not exist.
  Future<void> deleteFile(String filePath) =>
      _platform.deleteFile(filePath);

  /// Returns `true` if a file exists at [filePath].
  Future<bool> fileExists(String filePath) =>
      _platform.fileExists(filePath);

  /// Copies the file at [sourcePath] to [destPath], creating parent
  /// directories as needed.
  ///
  /// Throws [FileNotFoundException] if the source file does not exist.
  Future<void> copyFile(String sourcePath, String destPath) =>
      _platform.copyFile(sourcePath, destPath);

  /// Moves the file at [sourcePath] to [destPath], creating parent
  /// directories as needed.
  ///
  /// Falls back to copy-then-delete when moving across filesystems.
  /// Throws [FileNotFoundException] if the source file does not exist.
  Future<void> moveFile(String sourcePath, String destPath) =>
      _platform.moveFile(sourcePath, destPath);

  /// Renames the file at [oldPath] to [newPath], creating parent
  /// directories as needed.
  ///
  /// Throws [FileNotFoundException] if the source file does not exist.
  Future<void> renameFile(String oldPath, String newPath) =>
      _platform.renameFile(oldPath, newPath);

  // ── File metadata ─────────────────────────────────────────────────────

  /// Returns the size of the file at [filePath] in bytes.
  ///
  /// Throws [FileNotFoundException] if the file does not exist.
  Future<int> getFileSize(String filePath) =>
      _platform.getFileSize(filePath);

  /// Returns the last-modified timestamp (UTC) of the file at [filePath].
  ///
  /// Throws [FileNotFoundException] if the file does not exist.
  Future<DateTime> getLastModified(String filePath) =>
      _platform.getLastModified(filePath);

  // ── Bulk operations ───────────────────────────────────────────────────

  /// Writes multiple files concurrently, bounded by [maxConcurrency].
  ///
  /// Each entry in [files] maps a file path to its byte content.
  /// Per-path locking still applies — same-path operations serialize.
  ///
  /// If [cancellationToken] is provided and cancelled, tasks that have not
  /// yet started will throw [OperationCancelledException]. Tasks already in
  /// flight will run to completion.
  ///
  /// **Not atomic**: if one write fails, others may have already completed
  /// or still be in flight. No rollback is performed on partial failure.
  Future<void> writeFiles(
    Map<String, Uint8List> files, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
  }) =>
      _platform.writeFiles(files, maxConcurrency: maxConcurrency, cancellationToken: cancellationToken);

  /// Writes multiple files from streams concurrently, bounded by
  /// [maxConcurrency].
  ///
  /// If [cancellationToken] is provided and cancelled, tasks that have not
  /// yet started will throw [OperationCancelledException]. Tasks already in
  /// flight will run to completion.
  ///
  /// **Not atomic**: if one write fails, others may have already completed
  /// or still be in flight. No rollback is performed on partial failure.
  Future<void> writeFilesStream(
    Map<String, Stream<List<int>>> files, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
  }) =>
      _platform.writeFilesStream(files, maxConcurrency: maxConcurrency, cancellationToken: cancellationToken);

  /// Reads multiple files concurrently, bounded by [maxConcurrency].
  ///
  /// Returns a map from file path to byte content.
  /// Throws [FileNotFoundException] if any file does not exist.
  ///
  /// If [cancellationToken] is provided and cancelled, tasks that have not
  /// yet started will throw [OperationCancelledException]. Tasks already in
  /// flight will run to completion.
  ///
  /// **Not atomic**: if one read fails, others may have already completed
  /// or still be in flight.
  Future<Map<String, Uint8List>> readFiles(
    List<String> paths, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
  }) =>
      _platform.readFiles(paths, maxConcurrency: maxConcurrency, cancellationToken: cancellationToken);

  // ── Directory operations ──────────────────────────────────────────────

  /// Creates a directory at [dirPath].
  ///
  /// If [recursive] is `true` (default), creates all missing parent
  /// directories. If `false`, throws [DirectoryNotFoundException] when
  /// the parent does not exist.
  Future<void> createDirectory(String dirPath, {bool recursive = true}) =>
      _platform.createDirectory(dirPath, recursive: recursive);

  /// Returns `true` if a directory exists at [dirPath].
  Future<bool> directoryExists(String dirPath) =>
      _platform.directoryExists(dirPath);

  /// Lists the entries in the directory at [dirPath].
  ///
  /// Returns full paths normalized to forward slashes.
  /// Throws [DirectoryNotFoundException] if the directory does not exist.
  Future<List<String>> listDirectory(String dirPath) =>
      _platform.listDirectory(dirPath);

  /// Deletes the directory at [dirPath]. No-op if it does not exist.
  ///
  /// If [recursive] is `false` (default) and the directory is not empty,
  /// throws [DirectoryNotEmptyException].
  Future<void> deleteDirectory(String dirPath, {bool recursive = false}) =>
      _platform.deleteDirectory(dirPath, recursive: recursive);

  /// Renames the directory at [oldPath] to [newPath].
  ///
  /// Throws [DirectoryNotFoundException] if the source does not exist.
  Future<void> renameDirectory(String oldPath, String newPath) =>
      _platform.renameDirectory(oldPath, newPath);
}
