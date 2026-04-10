import 'dart:async';
import 'dart:js_interop';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;
import 'dbas_filesystem_native_interface.dart';

class DbasFileSystemNativeWeb extends DbasFileSystemNativeInterface {
  web.Worker? _worker;
  bool _initialized = false;

  int _nextRequestId = 0;
  int _nextStreamId = 0;
  final Map<int, Completer<dynamic>> _pendingRequests = {};

  DbasFileSystemNativeWeb();

  static void registerWith(Registrar registrar) {}

  // ── Worker communication ──────────────────────────────────────────────

  Future<dynamic> _send(String method, [Map<String, dynamic>? args]) async {
    final id = _nextRequestId++;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;
    _worker!.postMessage(<String, dynamic>{
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
      completer.completeError(Exception(data['error'].toString()));
    } else {
      completer.complete(data['result']);
    }
  }

  void _onError(web.Event event) {
    final error = Exception('Worker crashed unexpectedly.');
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingRequests.clear();
    _initialized = false;
    _worker = null;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    if (_initialized && _worker != null) return;

    try {
      // Flutter serves plugin assets at assets/packages/<package_name>/<asset_path>
      _worker = web.Worker('assets/packages/dbas_filesystem/web/libs/dbas_filesystem_worker.js'.toJS);
      _worker!.onmessage = ((web.MessageEvent e) => _onMessage(e)).toJS;
      _worker!.onerror = ((web.Event e) => _onError(e)).toJS;
      await _send('initialize');
      _initialized = true;
    } catch (e) {
      _pendingRequests.clear();
      _initialized = false;
      _worker = null;
      throw Exception('Failed to initialize DbasFileSystemNativeWeb: $e');
    }
  }

  // ── Single file operations ────────────────────────────────────────────

  @override
  Future<void> writeFile(String path, List<int> bytes) async {
    await _send('writeFile', {'path': path, 'bytes': bytes});
  }

  @override
  Future<void> writeFileStream(String path, Stream<List<int>> stream) async {
    final streamId = _nextStreamId++;
    await _send('beginStreamWrite', {'path': path, 'streamId': streamId});
    try {
      await for (final chunk in stream) {
        await _send('streamWriteChunk', {'streamId': streamId, 'bytes': chunk});
      }
      await _send('endStreamWrite', {'streamId': streamId});
    } catch (e) {
      try { await _send('abortStreamWrite', {'streamId': streamId}); } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<List<int>> readFile(String path) async {
    final result = await _send('readFile', {'path': path});
    if (result is Map && result['bytes'] is List) {
      return (result['bytes'] as List).cast<num>().map((e) => e.toInt()).toList();
    }
    throw Exception('Unexpected response from worker for readFile: $path');
  }

  @override
  Stream<List<int>> readFileStream(String path, {int chunkSize = 65536}) {
    late StreamController<List<int>> controller;
    bool cancelled = false;

    controller = StreamController<List<int>>(
      onCancel: () { cancelled = true; },
      onListen: () async {
        try {
          int offset = 0;
          while (!cancelled) {
            final result = await _send('readFileChunk', {
              'path': path,
              'offset': offset,
              'length': chunkSize,
            });
            if (cancelled) break;
            if (result is! Map || result['bytes'] is! List || result['totalSize'] is! num) {
              throw Exception('Unexpected response from worker for readFileChunk: $path');
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

  // ── Bulk operations ───────────────────────────────────────────────────

  @override
  Future<void> writeFiles(Map<String, List<int>> files) async {
    for (final entry in files.entries) {
      await writeFile(entry.key, entry.value);
    }
  }

  @override
  Future<void> writeFilesStream(Map<String, Stream<List<int>>> files) async {
    for (final entry in files.entries) {
      await writeFileStream(entry.key, entry.value);
    }
  }

  @override
  Future<Map<String, List<int>>> readFiles(List<String> paths) async {
    final result = <String, List<int>>{};
    for (final path in paths) {
      result[path] = await readFile(path);
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
    throw Exception('Unexpected response from worker for listDirectory: $path');
  }

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) async {
    await _send('deleteDirectory', {'path': path, 'recursive': recursive});
  }
}
