import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dbas_filesystem/src/dbas_filesystem_entry.dart';
import 'package:dbas_filesystem/src/dbas_filesystem_exceptions.dart';
import 'package:dbas_filesystem/src/dbas_filesystem_progress.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;
import 'dbas_filesystem_native_interface.dart';

// ── Worker handle ───────────────────────────────────────────────────────

class _WorkerHandle {
  final web.Worker worker;
  final void Function() onCrash;
  int _nextRequestId = 0;
  bool _crashed = false;
  final Map<int, Completer<dynamic>> _pendingRequests = {};

  int get pendingCount => _pendingRequests.length;

  _WorkerHandle(this.worker, {required this.onCrash}) {
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
    final safeArgs = args != null ? _sanitizeArgs(args) : <String, dynamic>{};
    worker.postMessage(<String, dynamic>{
      'id': id, 'method': method, 'args': safeArgs,
    }.jsify());
    return completer.future;
  }

  /// Converts `Uint8List` values to plain `List<int>` for reliable JS interop.
  ///
  /// **Known overhead**: this creates an extra copy of byte data. Dart's
  /// `jsify()` doesn't reliably transfer `Uint8List` as `Uint8Array` across
  /// all runtimes, and `postMessage` with `Transferable` is not supported
  /// by the current `dart:js_interop` API. The JS worker also converts
  /// `Uint8Array` results back to `Array` for the same reason.
  static Map<String, dynamic> _sanitizeArgs(Map<String, dynamic> args) {
    final result = <String, dynamic>{};
    for (final entry in args.entries) {
      final value = entry.value;
      if (value is Uint8List) {
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
    final error = DbasFileSystemException(
      'Worker crashed unexpectedly. Restarting...',
    );
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingRequests.clear();
    worker.terminate();
    onCrash();
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
      case 'PERMISSION_DENIED':
        return PermissionDeniedException(path);
      default:
        final msg = err['message']?.toString() ?? code;
        return DbasFileSystemException(msg, path: path.isNotEmpty ? path : null);
    }
  }
}

// ── Worker slot (supervises one worker with auto-restart) ───────────────

class _WorkerSlot {
  final String workerUrl;
  final int maxRetries;
  _WorkerHandle? currentHandle;
  int _attemptCount = 0;
  bool _gaveUp = false;
  bool _disposed = false;
  bool _restarting = false;

  _WorkerSlot({required this.workerUrl, this.maxRetries = 5}); // ignore: unused_element_parameter — maxRetries is configurable but uses a sensible default

  bool get isAvailable => currentHandle != null && !currentHandle!._crashed && !_gaveUp && !_disposed;
  int get pendingCount => currentHandle?.pendingCount ?? 0;

  /// Computes delay for a given attempt number.
  /// Attempts 1-3: no delay. Attempt 4+: exponential backoff capped at 60s.
  Duration _delayFor(int attempt) {
    if (attempt <= 3) return Duration.zero;
    final seconds = math.min(math.pow(2, attempt - 4).toInt(), 60);
    return Duration(seconds: seconds);
  }

  /// Spawns the initial worker. Called during pool initialization.
  Future<dynamic> start() async {
    final worker = web.Worker(workerUrl.toJS);
    final handle = _WorkerHandle(worker, onCrash: _onCrash);
    currentHandle = handle;
    return handle.send('initialize');
  }

  void _onCrash() {
    if (_disposed || _restarting) return;
    currentHandle = null;
    _restart();
  }

  Future<void> _restart() async {
    _restarting = true;
    _attemptCount++;
    if (_attemptCount > maxRetries) {
      _gaveUp = true;
      _restarting = false;
      return;
    }
    final delay = _delayFor(_attemptCount);
    if (delay > Duration.zero) await Future.delayed(delay);
    if (_disposed) { _restarting = false; return; }

    final worker = web.Worker(workerUrl.toJS);
    final handle = _WorkerHandle(worker, onCrash: _onCrash);
    try {
      await handle.send('initialize');
      if (_disposed) {
        handle.terminate();
        _restarting = false;
        return;
      }
      currentHandle = handle;
      _attemptCount = 0; // reset on success
      _restarting = false;
    } catch (_) {
      worker.terminate();
      if (!_disposed) {
        _restarting = false;
        _restart(); // counts as another attempt
      } else {
        _restarting = false;
      }
    }
  }

  void dispose() {
    _disposed = true;
    _restarting = false;
    currentHandle?.terminate();
    currentHandle = null;
  }
}

// ── Byte extraction helper ──────────────────────────────────────────────

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

// ── Web platform implementation ─────────────────────────────────────────

class DbasFileSystemNativeWeb extends DbasFileSystemNativeInterface {
  static const String _workerUrl = 'assets/packages/dbas_filesystem/web/libs/dbas_filesystem_worker.js';

  final List<_WorkerSlot> _slots = [];
  bool _initialized = false;
  bool _isPersistentStorage = false;
  int _nextStreamId = 0;

  DbasFileSystemNativeWeb();

  static void registerWith(Registrar registrar) {}

  @override
  bool get isPersistentStorage => _isPersistentStorage;

  // ── Worker pool ───────────────────────────────────────────────────────

  _WorkerHandle _pickWorker() {
    final available = _slots.where((s) => s.isAvailable).toList();
    if (available.isEmpty) {
      if (_slots.every((s) => s._gaveUp)) {
        throw DbasFileSystemException('All workers have permanently failed. Re-initialize required.');
      }
      throw DbasFileSystemException('No workers available (all restarting). Try again shortly.');
    }
    final slot = available.reduce((a, b) => a.pendingCount <= b.pendingCount ? a : b);
    return slot.currentHandle!;
  }

  Future<dynamic> _send(String method, [Map<String, dynamic>? args]) {
    return _pickWorker().send(method, args);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  Future<void> initialize({int workerPoolSize = 4}) async {
    if (_initialized && _slots.isNotEmpty) return;

    try {
      final initFutures = <Future<dynamic>>[];
      for (var i = 0; i < workerPoolSize; i++) {
        final slot = _WorkerSlot(workerUrl: _workerUrl);
        _slots.add(slot);
        initFutures.add(slot.start());
      }
      final results = await Future.wait(initFutures);
      if (results.isNotEmpty && results.first is Map) {
        _isPersistentStorage = (results.first as Map)['persistentStorage'] == true;
      }
      _initialized = true;
    } catch (e) {
      for (final s in _slots) {
        s.dispose();
      }
      _slots.clear();
      _initialized = false;
      throw DbasFileSystemException('Failed to initialize DbasFileSystemNativeWeb: $e');
    }
  }

  @override
  Future<void> dispose() async {
    for (final s in _slots) {
      s.dispose();
    }
    _slots.clear();
    _initialized = false;
    _isPersistentStorage = false;
  }

  // ── Single file operations ────────────────────────────────────────────

  @override
  Future<void> writeFile(String path, Uint8List bytes, {bool overwrite = false}) async {
    await _send('writeFile', {'path': path, 'bytes': bytes, 'overwrite': overwrite});
  }

  @override
  Future<void> writeFileStream(String path, Stream<List<int>> stream, {bool overwrite = false}) async {
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
  Future<void> appendFile(String path, Uint8List bytes) async {
    await _send('appendFile', {'path': path, 'bytes': bytes});
  }

  @override
  Future<void> appendFileStream(String path, Stream<List<int>> stream) async {
    final worker = _pickWorker(); // pin for entire stream
    final streamId = _nextStreamId++;
    await worker.send('beginStreamAppend', {'path': path, 'streamId': streamId});
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
    Completer<void>? pauseCompleter;
    final worker = _pickWorker(); // pin for entire stream

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
        try {
          int offset = 0;
          while (!cancelled) {
            final pc = pauseCompleter;
            if (pc != null) await pc.future;
            if (cancelled) break;
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
            if (bytes.isEmpty || cancelled) break;
            controller.add(bytes);
            offset += bytes.length;
            if (offset >= (result['totalSize'] as num).toInt()) break;
          }
        } catch (e) {
          if (!cancelled && !controller.isClosed) controller.addError(e);
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
  Future<void> copyFile(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) async {
    await _send('copyFile', {'sourcePath': sourcePath, 'destPath': destPath, 'overwrite': overwrite});
    // Web copy is a single worker message — report completion.
    onProgress?.call(OperationProgress(
      current: CurrentEntryProgress(
        entry: FileSystemEntry(path: destPath, type: FileSystemEntityType.file),
        progress: 1.0,
      ),
      overall: 1.0,
    ));
  }

  @override
  Future<void> moveFile(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) async {
    await _send('moveFile', {'sourcePath': sourcePath, 'destPath': destPath, 'overwrite': overwrite});
    onProgress?.call(OperationProgress(
      current: CurrentEntryProgress(
        entry: FileSystemEntry(path: destPath, type: FileSystemEntityType.file),
        progress: 1.0,
      ),
      overall: 1.0,
    ));
  }

  @override
  Future<void> renameFile(String oldPath, String newPath, {bool overwrite = false}) async {
    await _send('renameFile', {'oldPath': oldPath, 'newPath': newPath, 'overwrite': overwrite});
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
  Future<List<FileSystemEntry>> listDirectory(String path, {bool recursive = false}) async {
    final result = await _send('listDirectory', {'path': path, 'recursive': recursive});
    if (result is List) {
      return result.map((e) {
        if (e is! Map) throw DbasFileSystemException('Unexpected entry format from worker for listDirectory', path: path);
        final entryPath = e['path']?.toString() ?? '';
        final kind = e['type']?.toString() ?? '';
        final type = kind == 'directory' ? FileSystemEntityType.directory : FileSystemEntityType.file;
        return FileSystemEntry(path: entryPath, type: type);
      }).toList();
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

  @override
  Future<void> copyDirectory(String sourcePath, String destPath, {bool overwrite = false, ProgressCallback? onProgress}) async {
    await _send('copyDirectory', {'sourcePath': sourcePath, 'destPath': destPath, 'overwrite': overwrite});
    onProgress?.call(OperationProgress(
      current: CurrentEntryProgress(
        entry: FileSystemEntry(path: destPath, type: FileSystemEntityType.directory),
        progress: 1.0,
      ),
      overall: 1.0,
    ));
  }

  @override
  Future<void> moveDirectory(String sourcePath, String destPath, {ProgressCallback? onProgress}) async {
    await _send('moveDirectory', {'sourcePath': sourcePath, 'destPath': destPath});
    onProgress?.call(OperationProgress(
      current: CurrentEntryProgress(
        entry: FileSystemEntry(path: destPath, type: FileSystemEntityType.directory),
        progress: 1.0,
      ),
      overall: 1.0,
    ));
  }
}
