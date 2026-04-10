import 'package:dbas_filesystem/src/dbas_filesystem_exceptions.dart';

/// Token for cooperative cancellation of long-running operations.
///
/// Pass to bulk operations (`writeFiles`, `readFiles`, `writeFilesStream`)
/// to enable cancellation. Operations already in flight will complete, but
/// no new operations will start after cancellation.
///
/// Listeners registered via [addListener] are called synchronously when
/// [cancel] is called. If [cancel] has already been called, [addListener]
/// invokes the listener immediately.
///
/// ```dart
/// final token = CancellationToken();
/// final future = fs.writeFiles(files, cancellationToken: token);
/// // Later:
/// token.cancel();
/// ```
class CancellationToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Signals cancellation. Idempotent — subsequent calls are no-ops.
  ///
  /// All listeners registered via [addListener] are invoked synchronously
  /// before this method returns. Listeners are called exactly once.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final snapshot = List<void Function()>.from(_listeners);
    for (final listener in snapshot) {
      listener();
    }
  }

  /// Throws [OperationCancelledException] if [cancel] has been called.
  void throwIfCancelled() {
    if (_cancelled) throw const OperationCancelledException();
  }

  /// Registers [listener] to be called when [cancel] is invoked.
  ///
  /// If this token is already cancelled, [listener] is called immediately.
  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// Removes the first occurrence of [listener] from the listener list.
  ///
  /// No-op if [listener] was not registered.
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}
