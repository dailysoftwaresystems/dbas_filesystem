import 'dart:async';
import 'dart:collection';

class ConcurrencyPool {
  final int maxConcurrency;
  int _active = 0;
  final Queue<Completer<void>> _waiting = Queue();

  ConcurrencyPool(this.maxConcurrency) {
    if (maxConcurrency <= 0) {
      throw ArgumentError.value(maxConcurrency, 'maxConcurrency', 'Must be > 0');
    }
  }

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= maxConcurrency) {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      }
    }
  }

  static Future<List<T>> runAll<T>(
    Iterable<Future<T> Function()> tasks, {
    int maxConcurrency = 10,
  }) {
    final pool = ConcurrencyPool(maxConcurrency);
    return Future.wait(tasks.map((t) => pool.run(t)));
  }
}
