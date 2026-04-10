import 'package:dbas_filesystem/src/dbas_filesystem_exceptions.dart';

/// Token for cooperative cancellation of long-running operations.
///
/// Pass to bulk operations (`writeFiles`, `readFiles`, `writeFilesStream`)
/// to enable cancellation. Operations already in flight will complete, but
/// no new operations will start after cancellation.
///
/// ```dart
/// final token = CancellationToken();
/// final future = fs.writeFiles(files, cancellationToken: token);
/// // Later:
/// token.cancel();
/// ```
class CancellationToken {
  bool _cancelled = false;

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Signals cancellation. Idempotent — subsequent calls are no-ops.
  void cancel() => _cancelled = true;

  /// Throws [OperationCancelledException] if [cancel] has been called.
  void throwIfCancelled() {
    if (_cancelled) throw const OperationCancelledException();
  }
}
