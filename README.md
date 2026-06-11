# dbas_filesystem

A Flutter plugin for cross-platform file system operations with streaming, byte array, and directory support across **Android, iOS, macOS, Linux, Windows, and Web**.

## Features

- **File operations** &mdash; read, write, append, copy, move, rename, delete, and existence check.
- **File metadata** &mdash; get file size and last modified timestamp.
- **Overwrite protection** &mdash; `writeFile`, `writeFileStream`, `copyFile`, `moveFile`, `renameFile`, and `copyDirectory` default to `overwrite: false`, preventing accidental data loss.
- **Append support** &mdash; `appendFile` and `appendFileStream` append bytes to existing files (or create them if missing).
- **Stream support** &mdash; stream-based read and write for memory-efficient large file handling.
- **Atomic bulk operations** &mdash; `writeFiles` and `writeFilesStream` default to atomic mode: snapshot existing files, write all, rollback on failure. Set `atomic: false` for independent writes with per-file `onError`.
- **Directory operations** &mdash; create, list (with typed entries), copy, move, delete, rename, and existence check.
- **Cross-device move** &mdash; automatic copy+delete fallback when source and destination are on different devices.
- **File change notifications** &mdash; optional `onFileChanged` callback fires after every mutation with a map of affected entries and their before/after state.
- **Progress callbacks** &mdash; optional `onProgress` on all operations, with per-entry and overall progress reporting.
- **Hierarchical thread safety** &mdash; mutating file operations acquire a shared lock on the parent directory + exclusive lock on the file. Read-only queries (`fileExists`, `getFileSize`, `getLastModified`) use shared locks for minimal contention. Directory-destructive operations acquire exclusive locks that block concurrent child file ops. Different paths proceed in parallel.
- **Typed exceptions** &mdash; `FileNotFoundException`, `FileAlreadyExistsException`, `DirectoryNotFoundException`, `DirectoryNotEmptyException`, `PermissionDeniedException`, `MultiException`, `AtomicOperationException`.
- **Web worker pool** &mdash; configurable pool of OPFS Web Workers for true parallel I/O on web, with automatic restart on crash (exponential backoff).
- **Configurable chunking** &mdash; streamed reads use a configurable chunk size (default 64 KB).
- **Path normalization** &mdash; `listDirectory` and `getAppFilePath` return forward-slash paths on all platforms.
- **Side-effect free path resolution** &mdash; `getAppFilePath` resolves a platform path without creating directories or accessing the file system.
- **App-directory rooting** &mdash; a **relative** path passed to any file operation is automatically rooted under the application storage directory (`<application-support>/dbas_files/` on native, `/dbas_files/` on web, `<cwd>/test/files/` under test), so it never resolves against the process working directory. An **absolute** path passes through unchanged. See [Path rooting](#path-rooting).
- **Lifecycle management** &mdash; `dispose({timeout})` gives in-flight operations a configurable grace period, then forces teardown. `isDisposed` reflects whether an instance has been disposed.
- **Cancellation** &mdash; `CancellationToken` with `addListener` / `removeListener` for reactive cancellation in long-running operations.

## Platform Support

| Platform | Implementation |
|----------|---------------|
| Android  | `dart:io`     |
| iOS      | `dart:io`     |
| macOS    | `dart:io`     |
| Linux    | `dart:io`     |
| Windows  | `dart:io`     |
| Web      | OPFS via Web Worker pool |

Web storage uses the [Origin Private File System (OPFS)](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API/Origin_private_file_system)
exclusively. There is no fallback to IndexedDB, LocalStorage, or Cache API.
OPFS is the modern browser standard for persistent, origin-scoped binary file
storage with byte-level random access and true background-thread I/O.
Applications targeting older browsers should catch the `DbasFileSystemException`
thrown by `getInstance()` and display an appropriate upgrade notice.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dbas_filesystem: ^3.1.4
```

Or install with the Dart CLI:

```bash
flutter pub add dbas_filesystem
```

## Usage

```dart
import 'dart:typed_data';
import 'package:dbas_filesystem/dbas_filesystem.dart';

final fs = await DbasFileSystem.getInstance();
```

### Write and read a file

```dart
final path = await fs.getAppFilePath('example.txt');

// Write (throws FileAlreadyExistsException if file exists)
await fs.writeFile(path, Uint8List.fromList(utf8.encode('Hello, world!')));

// Write with explicit overwrite
await fs.writeFile(path, Uint8List.fromList(utf8.encode('updated')), overwrite: true);

// Read (returns Uint8List)
final bytes = await fs.readFile(path);
print(utf8.decode(bytes));
```

> **Note**: `getAppFilePath` only resolves a path — it does not create
> directories. Parent directories are created automatically when you call
> `writeFile`, `writeFileStream`, or `appendFile`.

### Path rooting

Every file operation roots a **relative** path under the application
storage directory, so you can pass a bucket-style path directly without
pre-resolving it through `getAppFilePath`:

```dart
// Relative — rooted under the app directory automatically.
await fs.writeFileStream('uploads/photo.jpg', byteStream);
final bytes = await fs.readFile('uploads/photo.jpg'); // same physical file

// Equivalent, resolving the path explicitly first.
final path = await fs.getAppFilePath('uploads/photo.jpg');
await fs.writeFileStream(path, byteStream);
```

The storage root is:

| Context | Root |
| --- | --- |
| Native (Android, iOS, macOS, Linux, Windows) | `<application-support>/dbas_files/` |
| Web | `/dbas_files/` (OPFS) |
| Test (`FLUTTER_TEST`) | `<cwd>/test/files/` |

An **absolute** path (POSIX/OPFS `/…`, a Windows drive `C:…`, or a UNC
`\\…` path — including any path returned by `getAppFilePath`) passes
through unchanged, so callers that resolve up front are unaffected and
nothing is double-rooted.

### Append to a file

```dart
// Append bytes (creates file if it doesn't exist)
await fs.appendFile(path, Uint8List.fromList(utf8.encode('more data')));

// Append from a stream
await fs.appendFileStream(path, myStream);
```

### File metadata

```dart
final size = await fs.getFileSize(path);       // bytes
final modified = await fs.getLastModified(path); // DateTime (UTC)
```

### Stream a large file

```dart
// Write from stream
Stream<List<int>> chunks() async* {
  for (int i = 0; i < 100; i++) {
    yield Uint8List(65536); // 64 KB chunks
  }
}
await fs.writeFileStream(path, chunks());

// Read as stream (returns Stream<Uint8List>)
await for (final chunk in fs.readFileStream(path)) {
  // process chunk
}
```

### Bulk operations

```dart
// Atomic write (default) — all-or-nothing with rollback
await fs.writeFiles(fileMap, maxConcurrency: 10);

// Non-atomic write — skip failures, continue
final errors = <String, Object>{};
await fs.writeFiles(fileMap, atomic: false, onError: (path, e) => errors[path] = e);

// Read multiple files concurrently
final results = await fs.readFiles(paths, maxConcurrency: 10);

// Read with partial results on failure
final results = await fs.readFiles(
  paths,
  onError: (path, error) => errors[path] = error,
);
// results contains only successful reads; errors contains the failures
```

> **Memory note**: `readFiles` and `writeFiles` hold all file contents in
> memory simultaneously, bounded by `maxConcurrency`. For large files, prefer
> `readFileStream` / `writeFileStream` individually to control memory usage.

### Rename, copy, and move

```dart
await fs.renameFile(oldPath, newPath);               // atomic on native
await fs.renameDirectory(oldDirPath, newDirPath);     // atomic on native
await fs.copyFile(sourcePath, destPath);
await fs.moveFile(sourcePath, destPath);              // cross-device safe
await fs.moveDirectory(sourceDirPath, destDirPath);   // cross-device safe

// Overwrite explicitly (default is overwrite: false)
await fs.copyFile(sourcePath, destPath, overwrite: true);
await fs.moveFile(sourcePath, destPath, overwrite: true);
await fs.renameFile(oldPath, newPath, overwrite: true);
```

### Directory operations

```dart
await fs.createDirectory(dirPath);

// List returns typed entries with path and type (file or directory)
final entries = await fs.listDirectory(dirPath);
for (final entry in entries) {
  print('${entry.path} is a ${entry.type}'); // FileSystemEntityType.file or .directory
}

final allEntries = await fs.listDirectory(dirPath, recursive: true); // entire tree

// Copy a directory (merge — overwrites conflicting files with overwrite: true)
await fs.copyDirectory(sourceDirPath, destDirPath, overwrite: true);

// Move a directory (atomic rename on native, copy+delete fallback across devices)
await fs.moveDirectory(sourceDirPath, destDirPath);

await fs.deleteDirectory(dirPath, recursive: true);
```

### File change notifications

```dart
final fs = await DbasFileSystem.getInstance(
  onFileChanged: (changes) {
    for (final entry in changes.entries) {
      final change = entry.value;
      print('${change.type}: ${change.path}');
      // FileChangeType.created, .modified, or .deleted
    }
  },
);

// Or set/update the callback later:
fs.onFileChanged = (changes) { /* ... */ };

// Notifications include before/after state:
// change.oldEntry — null if created, set if modified/deleted
// change.newEntry — null if deleted, set if created/modified
```

### Progress callbacks

```dart
await fs.copyFile(source, dest, overwrite: true, onProgress: (progress) {
  print('File: ${progress.current.entry.path}');
  print('Current: ${(progress.current.progress * 100).toInt()}%');
  print('Overall: ${(progress.overall * 100).toInt()}%');
});

await fs.writeFiles(fileMap, onProgress: (progress) {
  print('Writing ${progress.current.entry.path} — overall ${(progress.overall * 100).toInt()}%');
});
```

### Lifecycle management

```dart
// Release all resources (terminates web workers, resets singleton)
await fs.dispose();

// With custom timeout (default 30 seconds)
await fs.dispose(timeout: const Duration(seconds: 10));

// After dispose, getInstance() creates a fresh instance
final freshFs = await DbasFileSystem.getInstance();

// Calling methods on a disposed instance throws StateError
```

### Cancellation

```dart
final token = CancellationToken();

// Start a bulk write in the background
final future = fs.writeFiles(largeFileMap, cancellationToken: token);

// Cancel later — tasks not yet started are skipped, in-flight tasks complete
token.cancel();

try {
  await future;
} on OperationCancelledException {
  print('Write was cancelled');
}
```

### Error handling

```dart
try {
  await fs.readFile('/nonexistent');
} on FileNotFoundException catch (e) {
  print(e.path); // '/nonexistent'
} on PermissionDeniedException catch (e) {
  print('Access denied: ${e.path}');
} on OperationCancelledException {
  print('Operation was cancelled');
} on DbasFileSystemException catch (e) {
  print(e.message);
}

// Atomic bulk writes roll back on failure
try {
  await fs.writeFiles({
    'path/a.bin': bytesA,
    'path/b.bin': bytesB, // if this fails, a.bin is rolled back
  });
} on AtomicOperationException catch (e) {
  print('Primary error: ${e.error}');
  if (e.secondaryError != null) {
    print('Rollback also failed: ${e.secondaryError}');
    // Some files may not have been rolled back — verify state manually.
  }
}

// Non-atomic bulk writes with error handling
await fs.writeFiles(fileMap, atomic: false, onError: (path, error) {
  print('Failed to write $path: $error');
});
```

### Storage persistence (web)

```dart
final fs = await DbasFileSystem.getInstance();

// Check if the browser granted persistent storage
if (!fs.isPersistentStorage) {
  print('Warning: data may be evicted under storage pressure');
}
```

## API Reference

| Method | Description |
|--------|-------------|
| `getInstance({workerPoolSize, onFileChanged})` | Returns the singleton `DbasFileSystem` instance. |
| `dispose({timeout})` | Releases all resources. Gives in-flight operations up to `timeout` (default 30s) to finish, then forces teardown. |
| `isDisposed` | `true` after `dispose()` has been called. Subsequent operations throw `StateError`. |
| `isPersistentStorage` | Whether storage is persistent (always `true` on native; reflects browser grant on web). |
| `onFileChanged` | Getter/setter for the file change notification callback. |
| `getAppFilePath(fileName)` | Resolves a platform-specific path (forward-slash normalized). Does not create directories. |
| `writeFile(path, bytes, {overwrite, onProgress})` | Writes a `Uint8List` to a file. |
| `writeFileStream(path, stream, {overwrite, onProgress})` | Writes a stream of byte chunks to a file. |
| `appendFile(path, bytes, {onProgress})` | Appends bytes to a file (creates it if missing). |
| `appendFileStream(path, stream, {onProgress})` | Appends a stream of byte chunks to a file (creates it if missing). |
| `readFile(path, {onProgress})` | Reads a file as a `Uint8List`. |
| `readFileStream(path, {chunkSize})` | Reads a file as a `Stream<Uint8List>`. Lock is held for the stream's lifetime. |
| `deleteFile(path, {onProgress})` | Deletes a file (no-op if missing). |
| `fileExists(path)` | Checks whether a file exists. |
| `copyFile(source, dest, {overwrite, onProgress})` | Copies a file with byte-level progress on native. |
| `moveFile(source, dest, {overwrite, onProgress})` | Moves a file with cross-device fallback. |
| `renameFile(oldPath, newPath, {overwrite, onProgress})` | Renames a file (atomic on native, copy+delete on web). |
| `getFileSize(path)` | Returns the file size in bytes. |
| `getLastModified(path)` | Returns the last modified timestamp (UTC). |
| `writeFiles(files, {maxConcurrency, cancellationToken, onProgress, atomic, onError})` | Writes multiple files. Atomic by default (rollback on failure). Set `atomic: false` + `onError` for independent writes. |
| `writeFilesStream(files, {maxConcurrency, cancellationToken, onProgress, atomic, onError})` | Writes multiple files from streams. Same atomic/non-atomic semantics as `writeFiles`. |
| `readFiles(paths, {maxConcurrency, cancellationToken, onProgress, onError})` | Reads multiple files. Without `onError`, throws `MultiException` on any failure. With `onError`, returns partial results. |
| `createDirectory(path, {recursive, onProgress})` | Creates a directory. |
| `directoryExists(path)` | Checks whether a directory exists. |
| `listDirectory(path, {recursive})` | Lists typed entries (`FileSystemEntry` with `path` and `type`). |
| `deleteDirectory(path, {recursive, onProgress})` | Deletes a directory. |
| `renameDirectory(oldPath, newPath, {onProgress})` | Renames a directory (atomic on native, recursive copy+delete on web). |
| `copyDirectory(source, dest, {overwrite, onProgress})` | Copies a directory (merge semantics). |
| `moveDirectory(source, dest, {onProgress})` | Moves a directory with cross-device fallback. |

## Thread Safety

All operations are routed through a hierarchical per-path read-write lock (`PathLock`).

- **Mutating file operations** acquire a **shared** lock on the parent directory and an **exclusive** lock on the file path. Two writes to different files in the same directory proceed in parallel. A directory delete blocks until child file operations complete.
- **Read-only file queries** (`fileExists`, `getFileSize`, `getLastModified`) acquire a **shared** lock on the file path only, allowing multiple concurrent reads without blocking each other or contending with sibling paths.
- **Non-destructive directory operations** (`listDirectory`, `directoryExists`, `createDirectory`) acquire a **shared** lock on the directory path, allowing concurrent access.
- **Destructive directory operations** (`deleteDirectory`, `renameDirectory`, `moveDirectory`) acquire an **exclusive** lock that blocks all concurrent file and directory operations within that path.
- **Multi-path operations** (`copyFile`, `moveFile`, `renameFile`, `renameDirectory`, `copyDirectory`, `moveDirectory`) lock all involved paths in sorted order to prevent deadlocks. Exclusive overrides shared when the same path appears in both lock sets.
- **Bulk operations** (`writeFiles`, `readFiles`) run through the locked single-file methods with a configurable concurrency limit (`maxConcurrency`, default 10).
- **Web worker pool** distributes work across N workers (default 4) for true parallel I/O via OPFS.
- **Writer-priority**: When both readers and writers are waiting for a lock, writers are woken first to prevent starvation.

```
Different paths       -> parallel (shared parent locks coexist)
Same path (writes)    -> serialized (exclusive file lock queues)
Same path (reads)     -> parallel (shared file lock allows concurrent queries)
Dir delete + child op -> serialized (exclusive dir lock blocks shared parent)
Bulk operations       -> bounded parallelism (ConcurrencyPool) + per-path locking
```

> **Stream lock behavior**: `readFileStream` holds the file path lock for the
> entire stream lifetime. A slow consumer will block other operations on that
> path until the stream completes or is cancelled.

## Bulk Operation Semantics

### Atomic mode (default)

`writeFiles` and `writeFilesStream` with `atomic: true` (default):

1. **Snapshot**: Existing file contents are saved for rollback.
2. **Write**: All files are written concurrently.
3. **On failure**: All successfully written files are rolled back (restored or deleted). Throws `AtomicOperationException` with the primary `error` and optional `secondaryError` if rollback itself partially failed.

The `onError` callback is ignored in atomic mode.

### Non-atomic mode

`writeFiles` and `writeFilesStream` with `atomic: false`:

- If `onError` is provided, individual failures invoke the callback and the operation continues.
- If `onError` is `null`, throws on the first error.
- **No rollback** is performed on partial failure.

### Read operations

`readFiles` without `onError` collects all errors and throws `MultiException`. With `onError`, failed files are omitted from the result map.

## Performance Tuning

| Parameter | Default | When to adjust |
|-----------|---------|---------------|
| `workerPoolSize` | 4 | Increase for web apps doing heavy parallel I/O. Each worker is a Web Worker thread. On native, this is ignored. |
| `maxConcurrency` | 10 | Lower if bulk operations cause memory pressure (many large files). Raise if I/O is the bottleneck and files are small. |
| `chunkSize` | 64 KB | Increase for large file streaming (e.g. 256 KB or 1 MB). Decrease for memory-constrained environments. Affects `readFileStream` on all platforms. |

## Building

### JS Worker minification

The OPFS Web Worker source is at `web/libs/src/dbas_filesystem_worker.js`. CI automatically minifies it via esbuild and commits the output to `web/libs/`. To build locally:

```bash
# Linux / macOS / Git Bash
bash scripts/build/minify-js-worker.sh

# Windows PowerShell
.\scripts\build\minify-js-worker.ps1
```

Both scripts install `esbuild` automatically if not found.

## Migrating from v3.x to v4.x

### Breaking changes

1. **`overwrite` defaults to `false`**: All write, copy, move, and rename operations now throw `FileAlreadyExistsException` if the destination exists. Add `overwrite: true` where you intentionally replace files.

   ```dart
   // v3.x — silently overwrites
   await fs.writeFile(path, bytes);

   // v4.x — throws if file exists
   await fs.writeFile(path, bytes);              // throws FileAlreadyExistsException
   await fs.writeFile(path, bytes, overwrite: true); // explicit overwrite
   ```

2. **`writeFiles` / `writeFilesStream` are atomic by default**: Set `atomic: false` to restore the previous behavior with `onError`.

   ```dart
   // v3.x
   await fs.writeFiles(files, onError: (p, e) => log(e));

   // v4.x — atomic by default
   await fs.writeFiles(files);                                    // atomic, throws AtomicOperationException
   await fs.writeFiles(files, atomic: false, onError: (p, e) => log(e)); // non-atomic with onError
   ```

3. **`readFiles` without `onError` throws `MultiException`**: Previously threw the first error. Now collects all errors.

   ```dart
   // v4.x — collect partial results
   final results = await fs.readFiles(paths, onError: (p, e) => log(e));
   ```

## Migrating from v1.x to v2.x

### Breaking changes

1. **`Uint8List` API**: All byte parameters and return types changed from `List<int>` to `Uint8List`.

   ```dart
   // v1.x
   await fs.writeFile(path, [1, 2, 3]);
   final List<int> bytes = await fs.readFile(path);

   // v2.x
   await fs.writeFile(path, Uint8List.fromList([1, 2, 3]));
   final Uint8List bytes = await fs.readFile(path);
   ```

2. **`dispose()` added**: Instances must be disposed when no longer needed. Using a disposed instance throws `StateError`.

3. **Bulk operations removed from native interface**: Now handled exclusively by the platform layer. If you extended the native interface, remove bulk method overrides.

## Troubleshooting

### Web: "OPFS is not supported in this browser"

OPFS requires a modern browser (Chrome 102+, Firefox 111+, Safari 15.2+). Ensure your users are on a supported browser. OPFS is **not available** in:
- Older browsers
- Some privacy-focused browsers
- Web views that don't support the Storage Foundation API

### Web: `isPersistentStorage` is `false`

The browser denied the persistent storage request. This means data may be evicted under storage pressure (e.g. low disk space). Common causes:
- The site isn't bookmarked or frequently visited (Chrome heuristic)
- The user denied the permission prompt
- Private/incognito browsing mode

Your app should handle this gracefully — check `isPersistentStorage` after initialization and warn the user if needed.

### Web: Worker crashes

Workers automatically restart on crash with exponential backoff (first 3 retries are immediate, then 1s, 2s, 4s... up to 60s, max 5 retries per worker slot). If all workers permanently fail, operations throw `DbasFileSystemException`. Call `dispose()` and re-initialize with `getInstance()`. Common causes:
- Browser memory pressure killing Web Workers
- OPFS quota exceeded

### Web: No IndexedDB or LocalStorage fallback

`dbas_filesystem` intentionally does not fall back to IndexedDB or LocalStorage when OPFS is unavailable. OPFS is the only storage API that supports the binary, streaming, and parallel I/O semantics this library provides. If OPFS is unavailable, `getInstance()` throws `DbasFileSystemException` — catch it and guide the user to a supported browser.

### Native: Cross-device move fails

`moveFile` and `moveDirectory` automatically fall back to copy+delete when source and destination are on different filesystems. If the fallback also fails, the partial destination is cleaned up. Check disk space and permissions.

## Minimum Platform Versions

| Platform | Minimum Version |
|----------|----------------|
| Android  | API 35         |
| iOS      | 16.0           |
| macOS    | 13.0 (Ventura) |
| Linux    | x86_64         |
| Windows  | x86_64         |
| Web      | Modern browsers with OPFS support |

## License

Copyright 2025-2026 Daily Software Systems LTDA. Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
