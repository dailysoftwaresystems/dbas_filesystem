import 'dart:async';

class PathLock {
  final Map<String, Future<void>> _locks = {};

  Future<T> synchronized<T>(String path, Future<T> Function() action) async {
    final previous = _locks[path];
    final completer = Completer<void>();
    _locks[path] = completer.future;

    if (previous != null) await previous;

    try {
      return await action();
    } finally {
      completer.complete();
      if (_locks[path] == completer.future) {
        _locks.remove(path);
      }
    }
  }

  Future<T> synchronizedMulti<T>(
    List<String> paths,
    Future<T> Function() action,
  ) async {
    final sorted = (List<String>.from(paths)..sort()).toSet().toList();
    return _lockChain(sorted, 0, action);
  }

  Future<T> _lockChain<T>(
    List<String> paths,
    int index,
    Future<T> Function() action,
  ) {
    if (index >= paths.length) return action();
    return synchronized(paths[index], () => _lockChain(paths, index + 1, action));
  }
}
