import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dbas_filesystem/src/dbas_filesystem_exceptions.dart';
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
      return Future.error(DbasFileSystemException(
        'Worker has crashed. Call dispose() and re-initialize.',
      ));
    }
    final id = _nextRequestId++;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;
    // Convert any Uint8List/List<int> bytes to a plain List<int> for reliable
    // jsify() conversion. jsify() handles List<int> correctly as a JS Array.
    final safeArgs = args != null ? _sanitizeArgs(args) : <String, dynamic>{};
    worker.postMessage(<String, dynamic>{
      'id': id, 'method': method, 'args': safeArgs,
    }.jsify());
    return completer.future;
  }

  static Map<String, dynamic> _sanitizeArgs(Map<String, dynamic> args) {
    final result = <String, dynamic>{};
    for (final entry in args.entries) {
      final value = entry.value;
      if (value is Uint8List) {
        // Convert typed byte buffer to plain growable list for jsify()
        result[entry.key] = value.toList();
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  void _onMessage(web.MessageEvent event) {
    final data = (event.data as JSObject).dartify();
    if (data is! Map) return;

    final id = data['id'];
    if (id == null) return;

    final completer = _pendingRequests.remove(id);
    if (completer == null) return;

    if (data.containsKey('error') && data['error'] != null) {
      final err = data['error'];
      completer.completeError(
        err is Map ? _mapWorkerError(err) : DbasFileSystemException(err.toString()),
      );
    } else {
      completer.complete(data['result']);
    }
  }

  void _onError(web.Event event) {
    _crashed = true;
    // All pending and future requests will receive this error, including
    // pinned workers mid-stream (readFileStream / writeFileStream).
    final error = DbasFileSystemException(
      'Worker crashed unexpectedly. Call dispose() and re-initialize.',
    );
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingRequests.clear();
    worker.terminate();
  }

  void terminate() {
    _crashed = true;
    final error = DbasFileSystemException('Worker terminated.');
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingRequests.clear();
    worker.terminate();
  }

  /// Maps structured worker error objects to typed exceptions.
  /// Error codes must match the fsError() codes in dbas_filesystem_worker.js.
  static DbasFileSystemException _mapWorkerError(Map<Object?, Object?> err) {
    final code = err['code']?.toString() ?? 'UNKNOWN';
    final path = err['path']?.toString() ?? '';
    switch (code) {
      case 'FILE_NOT_FOUND':
        return FileNotFoundException(path);
      case 'FILE_ALREADY_EXISTS':
        return FileAlreadyExistsException(path);
      case 'DIRECTORY_NOT_FOUND':
        return DirectoryNotFoundException(path);
      case 'DIRECTORY_NOT_EMPTY':
        return DirectoryNotEmptyException(path);
      default:
        final msg = err['message']?.toString() ?? code;
        return DbasFileSystemException(msg, path: path.isNotEmpty ? path : null);
    }
  }
}

/// Extracts a Uint8List from a worker result's `bytes` field.
/// The worker converts Uint8Array to Array before postMessage, so dartify()
/// produces a List of num. We convert that to Uint8List.
Uint8List _extractBytes(dynamic result) {
  if (result is Map && result['bytes'] != null) {
    final bytes = result['bytes'];
    if (bytes is Uint8List) return bytes;
    if (bytes is List) {
      return Uint8List.fromList(
        bytes.map<int>((e) => (e as num).toInt()).toList(),
      );
    }
  }
  throw DbasFileSystemException('Unexpected response from worker: missing bytes');
}

class DbasFileSystemNativeWeb extends DbasFileSystemNativeInterface {
  final List<_WorkerHandle> _workers = [];
  bool _initialized = false;
  bool _isPersistentStorage = false;
  int _nextStreamId = 0;

  DbasFileSystemNativeWeb();

  static void registerWith(Registrar registrar) {}

  @override
  bool get isPersistentStorage => _isPersistentStorage;

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
      final initFutures = <Future<dynamic>>[];
      for (var i = 0; i < workerPoolSize; i++) {
        final worker = web.Worker(workerUrl.toJS);
        final handle = _WorkerHandle(worker);
        _workers.add(handle);
        initFutures.add(handle.send('initialize'));
      }
      final results = await Future.wait(initFutures);
      // All workers share the same storage context; check persistence from the first.
      if (results.isNotEmpty && results.first is Map) {
        _isPersistentStorage = (results.first as Map)['persistentStorage'] == true;
      }
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

  @override
  Future<void> dispose() async {
    for (final w in _workers) {
      w.terminate();
    }
    _workers.clear();
    _initialized = false;
    _isPersistentStorage = false;
  }

  // ── Single file operations ────────────────────────────────────────────

  @override
  Future<void> writeFile(String path, Uint8List bytes, {bool overwrite = true}) async {
    await _send('writeFile', {'path': path, 'bytes': bytes, 'overwrite': overwrite});
  }

  @override
  Future<void> writeFileStream(String path, Stream<List<int>> stream, {bool overwrite = true}) async {
    final worker = _pickWorker(); // pin for entire stream
    final streamId = _nextStreamId++;
    await worker.send('beginStreamWrite', {'path': path, 'streamId': streamId, 'overwrite': overwrite});
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
  Future<Uint8List> readFile(String path) async {
    final result = await _send('readFile', {'path': path});
    return _extractBytes(result);
  }

  @override
  Stream<Uint8List> readFileStream(String path, {int chunkSize = 65536}) {
    late StreamController<Uint8List> controller;
    bool cancelled = false;
    final worker = _pickWorker(); // pin for entire stream

    controller = StreamController<Uint8List>(
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
            if (result is! Map || result['totalSize'] is! num) {
              throw DbasFileSystemException('Unexpected response from worker for readFileChunk', path: path);
            }
            final bytes = _extractBytes(result);
            if (bytes.isEmpty) break;
            controller.add(bytes);
            offset += bytes.length;
            if (offset >= (result['totalSize'] as num).toInt()) break;
          }
        } catch (e) {
          if (!cancelled) controller.addError(e);
        } finally {
          if (!controller.isClosed) controller.close();
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
