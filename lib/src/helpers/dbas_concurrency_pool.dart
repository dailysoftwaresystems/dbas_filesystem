import 'dart:async';
import 'dart:collection';

import 'package:dbas_filesystem/src/dbas_filesystem_exceptions.dart';
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

  /// Runs all [tasks] with bounded concurrency, collecting **all** errors.
  ///
  /// Every task runs to completion regardless of whether others fail.
  /// If a [cancellationToken] is provided, tasks that have not yet started
  /// will throw [OperationCancelledException] once the token is cancelled.
  /// Tasks already in flight will run to completion.
  ///
  /// If any tasks fail, throws [MultiException] containing all errors.
  static Future<List<T>> runAll<T>(
    Iterable<Future<T> Function()> tasks, {
    int maxConcurrency = 10,
    CancellationToken? cancellationToken,
  }) async {
    final pool = ConcurrencyPool(maxConcurrency);
    final taskList = tasks.toList();
    final results = List<T?>.filled(taskList.length, null);
    final errors = <(String, Object)>[];

    // Launch all tasks — the pool limits concurrency internally.
    // Wrap each in a try-catch so Future.wait never sees errors.
    await Future.wait(
      List.generate(taskList.length, (i) async {
        try {
          results[i] = await pool.run(() {
            cancellationToken?.throwIfCancelled();
            return taskList[i]();
          });
        } catch (e) {
          errors.add(('task[$i]', e));
        }
      }),
    );

    if (errors.isNotEmpty) throw MultiException(errors);
    return results.cast<T>();
  }
}
