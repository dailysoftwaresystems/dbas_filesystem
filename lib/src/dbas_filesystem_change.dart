import 'package:dbas_filesystem/src/dbas_filesystem_entry.dart';

/// The type of change that occurred to a file system entry.
enum FileChangeType { created, modified, deleted }

/// Describes a change to a single file system entry.
///
/// At least one of [oldEntry] or [newEntry] must be non-null:
/// - [oldEntry] `null` + [newEntry] set → file/directory was created
/// - [oldEntry] set + [newEntry] `null` → file/directory was deleted
/// - Both set → file/directory was modified (overwritten)
///
/// Use the named factories [FileChange.created], [FileChange.deleted], and
/// [FileChange.modified] for clarity and safety.
final class FileChange {
  /// The entry before the change, or `null` if it was created.
  final FileSystemEntry? oldEntry;

  /// The entry after the change, or `null` if it was deleted.
  final FileSystemEntry? newEntry;

  const FileChange({this.oldEntry, this.newEntry})
      : assert(oldEntry != null || newEntry != null,
            'At least one of oldEntry or newEntry must be non-null');

  /// Creates a [FileChange] representing a newly created entry.
  const FileChange.created(FileSystemEntry entry)
      : oldEntry = null,
        newEntry = entry;

  /// Creates a [FileChange] representing a deleted entry.
  const FileChange.deleted(FileSystemEntry entry)
      : oldEntry = entry,
        newEntry = null;

  /// Creates a [FileChange] representing a modified (overwritten) entry.
  const FileChange.modified({required this.oldEntry, required this.newEntry});

  /// The path of the affected entry. Always non-null.
  String get path => (newEntry ?? oldEntry)!.path;

  /// The type of change.
  FileChangeType get type {
    if (oldEntry == null) return FileChangeType.created;
    if (newEntry == null) return FileChangeType.deleted;
    return FileChangeType.modified;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileChange &&
          oldEntry == other.oldEntry &&
          newEntry == other.newEntry;

  @override
  int get hashCode => Object.hash(oldEntry, newEntry);

  @override
  String toString() => 'FileChange($type, $path)';
}

/// Callback invoked after a file system operation completes.
///
/// The map keys are file paths, and the values describe what changed at each
/// path. Directory operations fire a single notification containing all
/// affected entries.
typedef FileChangeCallback = void Function(Map<String, FileChange> changes);
