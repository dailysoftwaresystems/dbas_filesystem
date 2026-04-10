/// The type of an entry returned by [DbasFileSystem.listDirectory].
enum FileSystemEntityType { file, directory }

/// A typed entry returned by [DbasFileSystem.listDirectory].
final class FileSystemEntry {
  /// The full path of the entry, normalized to forward slashes.
  final String path;

  /// Whether this entry is a file or a directory.
  final FileSystemEntityType type;

  const FileSystemEntry({required this.path, required this.type});

  @override
  bool operator ==(Object other) =>
      other is FileSystemEntry && other.path == path && other.type == type;

  @override
  int get hashCode => Object.hash(path, type);

  @override
  String toString() => 'FileSystemEntry(path: $path, type: $type)';
}
