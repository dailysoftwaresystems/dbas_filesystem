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
