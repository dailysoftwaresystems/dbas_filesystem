import 'dart:async';
import 'package:dbas_filesystem/src/helpers/dbas_concurrency_pool.dart';
import 'package:dbas_filesystem/src/helpers/dbas_path_lock.dart';
import 'package:dbas_filesystem/src/native/dbas_filesystem_native_interface.dart';

final class DbasFileSystemPlatform {
  static DbasFileSystemPlatform? _instance;
  static Completer<DbasFileSystemPlatform>? _initCompleter;
  final DbasFileSystemNativeInterface _delegate;
  final PathLock _lock = PathLock();

  DbasFileSystemPlatform._(this._delegate);

  static Future<DbasFileSystemPlatform> getInstance({int workerPoolSize = 4}) async {
    if (_instance != null) return _instance!;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<DbasFileSystemPlatform>();
    try {
      final delegate = DbasFileSystemNativeInterface.getInstance();
      await delegate.initialize(workerPoolSize: workerPoolSize);
      _instance = DbasFileSystemPlatform._(delegate);
      _initCompleter!.complete(_instance!);
      return _instance!;
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  // ── Single file operations ────────────────────────────────────────────

  Future<void> writeFile(String path, List<int> bytes, {bool overwrite = true}) =>
      _lock.synchronized(path, () => _delegate.writeFile(path, bytes, overwrite: overwrite));

  Future<void> writeFileStream(String path, Stream<List<int>> stream) =>
      _lock.synchronized(path, () => _delegate.writeFileStream(path, stream));

  Future<List<int>> readFile(String path) =>
      _lock.synchronized(path, () => _delegate.readFile(path));

  Stream<List<int>> readFileStream(String path, {int chunkSize = 65536}) {
    late StreamController<List<int>> controller;
    Future<void>? lockFuture;
    bool cancelled = false;

    controller = StreamController<List<int>>(
      onListen: () {
        lockFuture = _lock.synchronized(path, () async {
          await for (final chunk in _delegate.readFileStream(path, chunkSize: chunkSize)) {
            if (cancelled || controller.isClosed) break;
            controller.add(chunk);
          }
        }).catchError((Object e) {
          if (!cancelled && !controller.isClosed) controller.addError(e);
        }).whenComplete(() {
          if (!controller.isClosed) controller.close();
        });
      },
      onCancel: () {
        cancelled = true;
        return lockFuture;
      },
    );
    return controller.stream;
  }

  Future<void> deleteFile(String path) =>
      _lock.synchronized(path, () => _delegate.deleteFile(path));

  Future<bool> fileExists(String path) =>
      _lock.synchronized(path, () => _delegate.fileExists(path));

  Future<void> copyFile(String sourcePath, String destPath) =>
      _lock.synchronizedMulti([sourcePath, destPath], () => _delegate.copyFile(sourcePath, destPath));

  Future<void> moveFile(String sourcePath, String destPath) =>
      _lock.synchronizedMulti([sourcePath, destPath], () => _delegate.moveFile(sourcePath, destPath));

  Future<void> renameFile(String oldPath, String newPath) =>
      _lock.synchronizedMulti([oldPath, newPath], () => _delegate.renameFile(oldPath, newPath));

  // ── File metadata ─────────────────────────────────────────────────────

  Future<int> getFileSize(String path) =>
      _lock.synchronized(path, () => _delegate.getFileSize(path));

  Future<DateTime> getLastModified(String path) =>
      _lock.synchronized(path, () => _delegate.getLastModified(path));

  // ── Bulk operations ───────────────────────────────────────────────────
  // Bulk methods are orchestrated here to route through the locked
  // single-file methods above, ensuring per-file PathLock is acquired.

  Future<void> writeFiles(Map<String, List<int>> files, {int maxConcurrency = 10}) =>
      ConcurrencyPool.runAll(
        files.entries.map((e) => () => writeFile(e.key, e.value)),
        maxConcurrency: maxConcurrency,
      );

  Future<void> writeFilesStream(Map<String, Stream<List<int>>> files, {int maxConcurrency = 10}) =>
      ConcurrencyPool.runAll(
        files.entries.map((e) => () => writeFileStream(e.key, e.value)),
        maxConcurrency: maxConcurrency,
      );

  Future<Map<String, List<int>>> readFiles(List<String> paths, {int maxConcurrency = 10}) async {
    final entries = await ConcurrencyPool.runAll(
      paths.map((p) => () async => MapEntry(p, await readFile(p))),
      maxConcurrency: maxConcurrency,
    );
    return Map.fromEntries(entries);
  }

  // ── Directory operations ──────────────────────────────────────────────

  Future<void> createDirectory(String path, {bool recursive = true}) =>
      _delegate.createDirectory(path, recursive: recursive);

  Future<bool> directoryExists(String path) =>
      _delegate.directoryExists(path);

  Future<List<String>> listDirectory(String path) =>
      _delegate.listDirectory(path);

  Future<void> deleteDirectory(String path, {bool recursive = false}) =>
      _delegate.deleteDirectory(path, recursive: recursive);

  Future<void> renameDirectory(String oldPath, String newPath) =>
      _delegate.renameDirectory(oldPath, newPath);
}
