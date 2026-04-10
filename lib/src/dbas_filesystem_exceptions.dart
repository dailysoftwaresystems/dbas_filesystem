class DbasFileSystemException implements Exception {
  final String message;
  final String? path;

  const DbasFileSystemException(this.message, {this.path});

  @override
  String toString() {
    final loc = path != null ? ' [path: $path]' : '';
    return '$runtimeType: $message$loc';
  }
}

final class FileNotFoundException extends DbasFileSystemException {
  const FileNotFoundException(String path)
      : super('File not found', path: path);
}

final class DirectoryNotFoundException extends DbasFileSystemException {
  const DirectoryNotFoundException(String path)
      : super('Directory not found', path: path);
}

final class FileAlreadyExistsException extends DbasFileSystemException {
  const FileAlreadyExistsException(String path)
      : super('File already exists', path: path);
}

final class DirectoryNotEmptyException extends DbasFileSystemException {
  const DirectoryNotEmptyException(String path)
      : super('Directory is not empty', path: path);
}

final class OperationCancelledException extends DbasFileSystemException {
  const OperationCancelledException()
      : super('Operation was cancelled');
}

final class PermissionDeniedException extends DbasFileSystemException {
  const PermissionDeniedException(String path)
      : super('Permission denied', path: path);
}

/// Thrown when multiple concurrent operations fail.
///
/// Each entry contains the path that failed and the error that occurred.
final class MultiException extends DbasFileSystemException {
  /// The individual errors, each associated with the path that failed.
  final List<(String path, Object error)> errors;

  MultiException(List<(String path, Object error)> errors)
      : assert(errors.isNotEmpty, 'MultiException requires at least one error'),
        errors = List.unmodifiable(errors),
        super('${errors.length} operation(s) failed');

  @override
  String toString() {
    final details = errors.map((e) => '  ${e.$1}: ${e.$2}').join('\n');
    return 'MultiException: ${errors.length} operation(s) failed\n$details';
  }
}

/// Thrown when an atomic bulk operation fails.
///
/// Contains the primary [error] that caused the failure and an optional
/// [secondaryError] from the rollback attempt. If rollback succeeded,
/// [secondaryError] is `null`.
final class AtomicOperationException extends DbasFileSystemException {
  /// The primary error (or [MultiException] if multiple operations failed).
  final Object error;

  /// Error from rollback, or `null` if rollback succeeded.
  final Object? secondaryError;

  AtomicOperationException(this.error, {this.secondaryError})
      : super('Atomic operation failed');

  @override
  String toString() {
    final buf = StringBuffer('AtomicOperationException: $error');
    if (secondaryError != null) {
      buf.write('\n  Rollback error: $secondaryError');
    }
    return buf.toString();
  }
}
