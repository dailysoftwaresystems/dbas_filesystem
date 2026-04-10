import 'dart:async';
import 'dart:collection';

/// A per-path read-write lock with hierarchical parent protection.
///
/// **Shared locks** allow multiple holders on the same path simultaneously
/// but block exclusive locks. **Exclusive locks** block all other locks on
/// the same path.
///
/// Writer-priority: when both readers and a writer are waiting, the writer
/// is woken first to prevent writer starvation.
///
/// The [withLocks] method acquires multiple shared and exclusive locks in
/// sorted path order to prevent deadlock.
class PathLock {
  final Map<String, _RWLock> _locks = {};
  bool _disposed = false;

  _RWLock _lockFor(String path) =>
      _locks.putIfAbsent(path, () => _RWLock());

  void _maybeClean(String path) {
    final lock = _locks[path];
    if (lock != null && lock.isIdle) _locks.remove(path);
  }

  /// Acquires a shared (read) lock on [path], runs [action], and releases.
  ///
  /// Multiple shared locks on the same path can be held simultaneously.
  /// Blocks while an exclusive lock is held or waiting on [path].
  Future<T> shared<T>(String path, Future<T> Function() action) async {
    if (_disposed) throw StateError('DbasFileSystem has been disposed.');
    final lock = _lockFor(path);
    await lock.acquireShared();
    if (_disposed) {
      lock.releaseShared();
      _maybeClean(path);
      throw StateError('DbasFileSystem has been disposed.');
    }
    try {
      return await action();
    } finally {
      lock.releaseShared();
      _maybeClean(path);
    }
  }

  /// Acquires an exclusive (write) lock on [path], runs [action], and releases.
  ///
  /// Only one exclusive lock can be held per path. Blocks while any shared
  /// or exclusive lock is held on [path].
  Future<T> exclusive<T>(String path, Future<T> Function() action) async {
    if (_disposed) throw StateError('DbasFileSystem has been disposed.');
    final lock = _lockFor(path);
    await lock.acquireExclusive();
    if (_disposed) {
      lock.releaseExclusive();
      _maybeClean(path);
      throw StateError('DbasFileSystem has been disposed.');
    }
    try {
      return await action();
    } finally {
      lock.releaseExclusive();
      _maybeClean(path);
    }
  }

  /// Acquires multiple locks atomically in sorted path order.
  ///
  /// [sharedPaths] are acquired as shared (read) locks and [exclusivePaths]
  /// as exclusive (write) locks. If a path appears in both lists, exclusive
  /// wins. Paths are sorted before acquisition to prevent deadlock.
  Future<T> withLocks<T>({
    List<String> sharedPaths = const [],
    List<String> exclusivePaths = const [],
    required Future<T> Function() action,
  }) {
    final lockPlan = <String, bool>{}; // path → isExclusive
    for (final p in sharedPaths) {
      lockPlan.putIfAbsent(p, () => false);
    }
    for (final p in exclusivePaths) {
      lockPlan[p] = true; // exclusive overrides shared
    }
    final sorted = lockPlan.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return _acquireChain(sorted, 0, action);
  }

  Future<T> _acquireChain<T>(
    List<MapEntry<String, bool>> locks,
    int index,
    Future<T> Function() action,
  ) {
    if (index >= locks.length) return action();
    final entry = locks[index];
    Future<T> next() => _acquireChain(locks, index + 1, action);
    return entry.value ? exclusive(entry.key, next) : shared(entry.key, next);
  }

  /// Waits for all in-flight operations and marks the lock as disposed.
  ///
  /// New lock acquisitions after [dispose] throw [StateError].
  Future<void> dispose({Duration timeout = const Duration(seconds: 30)}) async {
    _disposed = true;
    final idleFutures = _locks.values
        .where((l) => !l.isIdle)
        .map((l) => l.idleFuture)
        .toList();
    if (idleFutures.isNotEmpty) {
      try {
        await Future.wait(idleFutures).timeout(timeout);
      } on TimeoutException {
        // In-flight operations did not complete within the grace period.
        // Error all pending waiters so they don't hang forever.
        for (final lock in _locks.values) {
          lock.errorAllWaiters(StateError('DbasFileSystem has been disposed.'));
        }
      }
    }
    _locks.clear();
  }

  /// Extracts the parent directory path from a file or directory path.
  ///
  /// Returns `null` for root-level paths (no parent).
  static String? parentOf(String path) {
    final normalized = path.replaceAll('\\', '/');
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash <= 0) return null;
    return normalized.substring(0, lastSlash);
  }
}

// ── Per-path read-write lock ──────────────────────────────────────────────

class _RWLock {
  int _readers = 0;
  bool _writing = false;
  final Queue<Completer<void>> _readQueue = Queue();
  final Queue<Completer<void>> _writeQueue = Queue();
  Completer<void>? _idleCompleter;

  bool get isIdle =>
      _readers == 0 &&
      !_writing &&
      _readQueue.isEmpty &&
      _writeQueue.isEmpty;

  /// Resolves when the lock becomes idle (no holders, no waiters).
  Future<void> get idleFuture {
    if (isIdle) return Future.value();
    _idleCompleter ??= Completer<void>();
    return _idleCompleter!.future;
  }

  /// Acquires a shared (read) lock.
  ///
  /// Waits if a writer is active or writers are waiting (writer-priority).
  Future<void> acquireShared() async {
    if (_writing || _writeQueue.isNotEmpty) {
      final c = Completer<void>();
      _readQueue.add(c);
      await c.future;
      // _readers was already incremented by _wakeNext
      return;
    }
    _readers++;
  }

  void releaseShared() {
    assert(_readers > 0, 'releaseShared called without matching acquireShared');
    _readers--;
    if (_readers == 0) _wakeNext();
  }

  /// Acquires an exclusive (write) lock.
  ///
  /// Waits if any reader or writer is active.
  Future<void> acquireExclusive() async {
    if (_writing || _readers > 0) {
      final c = Completer<void>();
      _writeQueue.add(c);
      await c.future;
      // _writing was already set by _wakeNext
      return;
    }
    _writing = true;
  }

  void releaseExclusive() {
    assert(_writing, 'releaseExclusive called without matching acquireExclusive');
    _writing = false;
    _wakeNext();
  }

  /// Errors all pending waiters. Called during forced disposal.
  void errorAllWaiters(Object error) {
    for (final c in _readQueue) {
      if (!c.isCompleted) c.completeError(error);
    }
    _readQueue.clear();
    for (final c in _writeQueue) {
      if (!c.isCompleted) c.completeError(error);
    }
    _writeQueue.clear();
  }

  /// Wakes the next waiter(s) when the lock becomes free.
  ///
  /// State is set **before** completing the waiter's completer to prevent
  /// race conditions between the completer resolution and new lock callers
  /// checking state.
  void _wakeNext() {
    if (_writing || _readers > 0) return;
    if (_writeQueue.isNotEmpty) {
      _writing = true;
      _writeQueue.removeFirst().complete();
    } else if (_readQueue.isNotEmpty) {
      _readers = _readQueue.length;
      while (_readQueue.isNotEmpty) {
        _readQueue.removeFirst().complete();
      }
    } else {
      // Truly idle — notify dispose waiters.
      _idleCompleter?.complete();
      _idleCompleter = null;
    }
  }
}
