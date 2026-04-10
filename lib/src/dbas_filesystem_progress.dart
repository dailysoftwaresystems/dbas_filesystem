import 'package:dbas_filesystem/src/dbas_filesystem_entry.dart';

/// Progress of the entry currently being processed.
final class CurrentEntryProgress {
  /// The entry being processed.
  final FileSystemEntry entry;

  /// Progress of this entry (0.0–1.0).
  final double progress;

  const CurrentEntryProgress({required this.entry, required this.progress})
      : assert(progress >= 0.0 && progress <= 1.0, 'progress must be 0.0–1.0');

  @override
  String toString() =>
      'CurrentEntryProgress(${entry.path}, ${(progress * 100).toStringAsFixed(1)}%)';
}

/// Progress information for an ongoing operation.
///
/// Contains two progress indicators:
/// - [current]: the entry being processed and its individual progress
/// - [overall]: the progress across all entries in the operation (0.0–1.0)
///
/// For single-file operations, [overall] mirrors [current.progress].
/// For bulk or directory operations, [overall] reflects the fraction of
/// entries completed.
final class OperationProgress {
  /// Progress of the current entry being processed.
  final CurrentEntryProgress current;

  /// Overall progress across all entries (0.0–1.0).
  final double overall;

  const OperationProgress({required this.current, required this.overall})
      : assert(overall >= 0.0 && overall <= 1.0, 'overall must be 0.0–1.0');

  @override
  String toString() =>
      'OperationProgress(current: $current, overall: ${(overall * 100).toStringAsFixed(1)}%)';
}

/// Callback invoked to report operation progress.
typedef ProgressCallback = void Function(OperationProgress progress);
