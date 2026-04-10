import 'dart:async';
import 'dart:collection';

import 'package:dbas_filesystem/src/helpers/dbas_cancellation_token.dart';

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

  /// Runs all [tasks] with bounded concurrency.
  ///
  /// If a [cancellationToken] is provided, tasks that have not yet started
  /// will throw [OperationCancelledException] once the token is cancelled.
  /// Tasks already in flight will run to completion.
  ///
  /// Note: this uses [Future.wait] internally. If any task fails, the
  /// returned future completes with that error. Other in-flight tasks
  /// continue to completion but their results are discarded.
  static Future<List<T>> runAll<T>(
    Iterable<Future<T> Function()> tasks, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
  }) {
    final pool = ConcurrencyPool(maxConcurrency);
    return Future.wait(tasks.map((t) => pool.run(() {
      cancellationToken?.throwIfCancelled();
      return t();
    })));
  }
}
