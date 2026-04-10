import 'dart:async';
import 'dart:js_interop';
import 'package:dbas_filesystem/src/dbas_filesystem_exceptions.dart';
import 'package:dbas_filesystem/src/helpers/dbas_concurrency_pool.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;
import 'dbas_filesystem_native_interface.dart';

class _WorkerHandle {
  final web.Worker worker;
  int _nextRequestId = 0;
  bool _crashed = false;
  final Map<int, Completer<dynamic>> _pendingRequests = {};

  int get pendingCount => _pendingRequests.length;

  _WorkerHandle(this.worker) {
    worker.onmessage = ((web.MessageEvent e) => _onMessage(e)).toJS;
    worker.onerror = ((web.Event e) => _onError(e)).toJS;
  }

  Future<dynamic> send(String method, [Map<String, dynamic>? args]) {
    if (_crashed) {
      return Future.error(DbasFileSystemException('Worker has crashed.'));
    }
    final id = _nextRequestId++;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;
    worker.postMessage(<String, dynamic>{
      'id': id, 'method': method, 'args': args ?? {},
    }.jsify());
    return completer.future;
  }

  void _onMessage(web.MessageEvent event) {
    final data = (event.data as JSObject).dartify();
    if (data is! Map) return;

    final id = data['id'];
    if (id == null) return;

    final completer = _pendingRequests.remove(id);
    if (completer == null) return;

    if (data.containsKey('error') && data['error'] != null) {
      completer.completeError(_mapWorkerError(data['error'].toString()));
    } else {
      completer.complete(data['result']);
    }
  }

  void _onError(web.Event event) {
    _crashed = true;
    final error = DbasFileSystemException('Worker crashed unexpectedly.');
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingRequests.clear();
    worker.terminate();
  }

  /// Maps worker error message prefixes to typed exceptions.
  /// Prefixes must match the Error strings thrown in dbas_filesystem_worker.js.
  static DbasFileSystemException _mapWorkerError(String msg) {
    if (msg.startsWith('File not found:')) {
      return FileNotFoundException(msg.substring('File not found: '.length));
    }
    if (msg.startsWith('File already exists:')) {
      return FileAlreadyExistsException(msg.substring('File already exists: '.length));
    }
    if (msg.startsWith('Directory not found:')) {
      return DirectoryNotFoundException(msg.substring('Directory not found: '.length));
    }
    if (msg.startsWith('Directory is not empty:')) {
      return DirectoryNotEmptyException(msg.substring('Directory is not empty: '.length));
    }
    return DbasFileSystemException(msg);
  }
}

class DbasFileSystemNativeWeb extends DbasFileSystemNativeInterface {
  final List<_WorkerHandle> _workers = [];
  bool _initialized = false;
  int _nextStreamId = 0;

  DbasFileSystemNativeWeb();

  static void registerWith(Registrar registrar) {}

  // ── Worker pool ───────────────────────────────────────────────────────

  _WorkerHandle _pickWorker() {
    final alive = _workers.where((w) => !w._crashed).toList();
    if (alive.isEmpty) {
      throw DbasFileSystemException('All workers have crashed. Re-initialize required.');
    }
    return alive.reduce((a, b) => a.pendingCount <= b.pendingCount ? a : b);
  }

  Future<dynamic> _send(String method, [Map<String, dynamic>? args]) {
    return _pickWorker().send(method, args);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  Future<void> initialize({int workerPoolSize = 4}) async {
    if (_initialized && _workers.isNotEmpty) return;

    try {
      const workerUrl = 'assets/packages/dbas_filesystem/web/libs/dbas_filesystem_worker.js';
      final initFutures = <Future<void>>[];
      for (var i = 0; i < workerPoolSize; i++) {
        final worker = web.Worker(workerUrl.toJS);
        final handle = _WorkerHandle(worker);
        _workers.add(handle);
        initFutures.add(handle.send('initialize'));
      }
      await Future.wait(initFutures);
      _initialized = true;
    } catch (e) {
      for (final w in _workers) {
        w.worker.terminate();
      }
      _workers.clear();
      _initialized = false;
      throw DbasFileSystemException('Failed to initialize DbasFileSystemNativeWeb: $e');
    }
  }

  // ── Single file operations ────────────────────────────────────────────

  @override
  Future<void> writeFile(String path, List<int> bytes, {bool overwrite = true}) async {
    await _send('writeFile', {'path': path, 'bytes': bytes, 'overwrite': overwrite});
  }

  @override
  Future<void> writeFileStream(String path, Stream<List<int>> stream) async {
    final worker = _pickWorker(); // pin for entire stream
    final streamId = _nextStreamId++;
    await worker.send('beginStreamWrite', {'path': path, 'streamId': streamId});
    try {
      await for (final chunk in stream) {
        await worker.send('streamWriteChunk', {'streamId': streamId, 'bytes': chunk});
      }
      await worker.send('endStreamWrite', {'streamId': streamId});
    } catch (e) {
      try { await worker.send('abortStreamWrite', {'streamId': streamId}); } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<List<int>> readFile(String path) async {
    final result = await _send('readFile', {'path': path});
    if (result is Map && result['bytes'] is List) {
      return (result['bytes'] as List).cast<num>().map((e) => e.toInt()).toList();
    }
    throw DbasFileSystemException('Unexpected response from worker for readFile', path: path);
  }

  @override
  Stream<List<int>> readFileStream(String path, {int chunkSize = 65536}) {
    late StreamController<List<int>> controller;
    bool cancelled = false;
    final worker = _pickWorker(); // pin for entire stream

    controller = StreamController<List<int>>(
      onCancel: () { cancelled = true; },
      onListen: () async {
        try {
          int offset = 0;
          while (!cancelled) {
            final result = await worker.send('readFileChunk', {
              'path': path,
              'offset': offset,
              'length': chunkSize,
            });
            if (cancelled) break;
            if (result is! Map || result['bytes'] is! List || result['totalSize'] is! num) {
              throw DbasFileSystemException('Unexpected response from worker for readFileChunk', path: path);
            }
            final bytes = (result['bytes'] as List).cast<num>().map((e) => e.toInt()).toList();
            if (bytes.isEmpty) break;
            controller.add(bytes);
            offset += bytes.length;
            if (offset >= (result['totalSize'] as num).toInt()) break;
          }
        } catch (e) {
          if (!cancelled) controller.addError(e);
        } finally {
          if (!controller.isClosed) await controller.close();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> deleteFile(String path) async {
    await _send('deleteFile', {'path': path});
  }

  @override
  Future<bool> fileExists(String path) async {
    final result = await _send('fileExists', {'path': path});
    return result == true;
  }

  @override
  Future<void> copyFile(String sourcePath, String destPath) async {
    await _send('copyFile', {'sourcePath': sourcePath, 'destPath': destPath});
  }

  @override
  Future<void> moveFile(String sourcePath, String destPath) async {
    await _send('moveFile', {'sourcePath': sourcePath, 'destPath': destPath});
  }

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    await _send('renameFile', {'oldPath': oldPath, 'newPath': newPath});
  }

  // ── File metadata ─────────────────────────────────────────────────────

  @override
  Future<int> getFileSize(String path) async {
    final result = await _send('getFileSize', {'path': path});
    if (result is num) return result.toInt();
    throw DbasFileSystemException('Unexpected response from worker for getFileSize', path: path);
  }

  @override
  Future<DateTime> getLastModified(String path) async {
    final result = await _send('getLastModified', {'path': path});
    if (result is num) {
      return DateTime.fromMillisecondsSinceEpoch(result.toInt(), isUtc: true);
    }
    throw DbasFileSystemException('Unexpected response from worker for getLastModified', path: path);
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
    await _send('createDirectory', {'path': path, 'recursive': recursive});
  }

  @override
  Future<bool> directoryExists(String path) async {
    final result = await _send('directoryExists', {'path': path});
    return result == true;
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    final result = await _send('listDirectory', {'path': path});
    if (result is List) {
      return result.map((e) => e.toString()).toList();
    }
    throw DbasFileSystemException('Unexpected response from worker for listDirectory', path: path);
  }

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) async {
    await _send('deleteDirectory', {'path': path, 'recursive': recursive});
  }

  @override
  Future<void> renameDirectory(String oldPath, String newPath) async {
    await _send('renameDirectory', {'oldPath': oldPath, 'newPath': newPath});
  }
}
