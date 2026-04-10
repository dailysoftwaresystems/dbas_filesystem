import 'dart:async';
import 'dart:typed_data';

import 'package:dbas_filesystem/src/helpers/dbas_concurrency_pool.dart';
import 'package:dbas_filesystem/src/helpers/dbas_path_lock.dart';
import 'package:dbas_filesystem/src/native/dbas_filesystem_native_interface.dart';

final class DbasFileSystemPlatform {
  final DbasFileSystemNativeInterface _delegate;
  final PathLock _lock = PathLock();
  bool _disposed = false;

  DbasFileSystemPlatform._(this._delegate);

  static Future<DbasFileSystemPlatform> create({int workerPoolSize = 4}) async {
    final delegate = DbasFileSystemNativeInterface.getInstance();
    await delegate.initialize(workerPoolSize: workerPoolSize);
    return DbasFileSystemPlatform._(delegate);
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('DbasFileSystem has been disposed.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _delegate.dispose();
    DbasFileSystemNativeInterface.resetInstance();
  }

  // ── Single file operations ────────────────────────────────────────────

  Future<void> writeFile(String path, Uint8List bytes, {bool overwrite = true}) {
    _checkNotDisposed();
    return _lock.synchronized(path, () => _delegate.writeFile(path, bytes, overwrite: overwrite));
  }

  Future<void> writeFileStream(String path, Stream<List<int>> stream, {bool overwrite = true}) {
    _checkNotDisposed();
    return _lock.synchronized(path, () => _delegate.writeFileStream(path, stream, overwrite: overwrite));
  }

  Future<Uint8List> readFile(String path) {
    _checkNotDisposed();
    return _lock.synchronized(path, () => _delegate.readFile(path));
  }

  Stream<Uint8List> readFileStream(String path, {int chunkSize = 65536}) {
    _checkNotDisposed();
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
          lockCompleter.complete();
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
    _checkNotDisposed();
    return _lock.synchronized(path, () => _delegate.deleteFile(path));
  }

  Future<bool> fileExists(String path) {
    _checkNotDisposed();
    return _lock.synchronized(path, () => _delegate.fileExists(path));
  }

  Future<void> copyFile(String sourcePath, String destPath) {
    _checkNotDisposed();
    return _lock.synchronizedMulti([sourcePath, destPath], () => _delegate.copyFile(sourcePath, destPath));
  }

  Future<void> moveFile(String sourcePath, String destPath) {
    _checkNotDisposed();
    return _lock.synchronizedMulti([sourcePath, destPath], () => _delegate.moveFile(sourcePath, destPath));
  }

  Future<void> renameFile(String oldPath, String newPath) {
    _checkNotDisposed();
    return _lock.synchronizedMulti([oldPath, newPath], () => _delegate.renameFile(oldPath, newPath));
  }

  // ── File metadata ─────────────────────────────────────────────────────

  Future<int> getFileSize(String path) {
    _checkNotDisposed();
    return _lock.synchronized(path, () => _delegate.getFileSize(path));
  }

  Future<DateTime> getLastModified(String path) {
    _checkNotDisposed();
    return _lock.synchronized(path, () => _delegate.getLastModified(path));
  }

  // ── Bulk operations ───────────────────────────────────────────────────

  Future<void> writeFiles(Map<String, Uint8List> files, {int maxConcurrency = 10}) {
    _checkNotDisposed();
    return ConcurrencyPool.runAll(
      files.entries.map((e) => () => writeFile(e.key, e.value)),
      maxConcurrency: maxConcurrency,
    );
  }

  Future<void> writeFilesStream(Map<String, Stream<List<int>>> files, {int maxConcurrency = 10}) {
    _checkNotDisposed();
    return ConcurrencyPool.runAll(
      files.entries.map((e) => () => writeFileStream(e.key, e.value)),
      maxConcurrency: maxConcurrency,
    );
  }

  Future<Map<String, Uint8List>> readFiles(List<String> paths, {int maxConcurrency = 10}) async {
    _checkNotDisposed();
    final entries = await ConcurrencyPool.runAll(
      paths.map((p) => () async => MapEntry(p, await readFile(p))),
      maxConcurrency: maxConcurrency,
    );
    return Map.fromEntries(entries);
  }

  // ── Directory operations ──────────────────────────────────────────────

  Future<void> createDirectory(String path, {bool recursive = true}) {
    _checkNotDisposed();
    return _lock.synchronized(path, () => _delegate.createDirectory(path, recursive: recursive));
  }

  Future<bool> directoryExists(String path) {
    _checkNotDisposed();
    return _lock.synchronized(path, () => _delegate.directoryExists(path));
  }

  Future<List<String>> listDirectory(String path) {
    _checkNotDisposed();
    return _lock.synchronized(path, () => _delegate.listDirectory(path));
  }

  Future<void> deleteDirectory(String path, {bool recursive = false}) {
    _checkNotDisposed();
    return _lock.synchronized(path, () => _delegate.deleteDirectory(path, recursive: recursive));
  }

  Future<void> renameDirectory(String oldPath, String newPath) {
    _checkNotDisposed();
    return _lock.synchronizedMulti([oldPath, newPath], () => _delegate.renameDirectory(oldPath, newPath));
  }
}
