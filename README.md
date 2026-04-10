# dbas_filesystem

A Flutter plugin for cross-platform file system operations with streaming, byte array, and directory support across **Android, iOS, macOS, Linux, Windows, and Web**.

## Features

- **File operations** &mdash; read, write, append, copy, move, rename, delete, and existence check.
- **File metadata** &mdash; get file size and last modified timestamp.
- **Overwrite protection** &mdash; `writeFile`, `writeFileStream`, `copyFile`, `moveFile`, and `renameFile` accept an `overwrite` parameter to prevent accidental overwrites.
- **Append support** &mdash; `appendFile` and `appendFileStream` append bytes to existing files (or create them if missing).
- **Stream support** &mdash; stream-based read and write for memory-efficient large file handling.
- **Parallel bulk operations** &mdash; read or write multiple files concurrently with configurable `maxConcurrency`.
- **Directory operations** &mdash; create, list (with typed entries), copy, delete, rename, and existence check.
- **Cross-device move** &mdash; automatic copy+delete fallback when source and destination are on different devices. Partial destination is cleaned up on failure.
- **Thread safety** &mdash; per-path locking for both files and directories. Concurrent operations on the same path are serialized; different paths proceed in parallel.
- **Typed exceptions** &mdash; `FileNotFoundException`, `FileAlreadyExistsException`, `DirectoryNotFoundException`, `DirectoryNotEmptyException`, `PermissionDeniedException`.
- **Web worker pool** &mdash; configurable pool of OPFS Web Workers for true parallel I/O on web, with automatic restart on crash (exponential backoff).
- **Configurable chunking** &mdash; streamed reads use a configurable chunk size (default 64 KB).
- **Path normalization** &mdash; `listDirectory` and `getAppFilePath` return forward-slash paths on all platforms.
- **Side-effect free path resolution** &mdash; `getAppFilePath` resolves a platform path without creating directories or accessing the file system. This asymmetry is intentional: path resolution is a pure computation, while directory creation is a side effect reserved for operations that actually write data.
- **Lifecycle management** &mdash; `dispose()` gives in-flight operations up to 30 seconds to finish, then forces teardown. `isDisposed` reflects whether an instance has been disposed.
- **Cancellation listeners** &mdash; `CancellationToken` supports `addListener` / `removeListener` for reactive cancellation in long-running operations.

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

## Getting Started

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  dbas_filesystem:
    git:
      url: git@github.com:dailysoftwaresystems/DBAS.FileSystem.Dart.git
      ref: main
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

// Write
await fs.writeFile(path, Uint8List.fromList(utf8.encode('Hello, world!')));

// Write with overwrite protection
await fs.writeFile(path, Uint8List.fromList(utf8.encode('data')), overwrite: false);
// throws FileAlreadyExistsException if file exists

// Read (returns Uint8List)
final bytes = await fs.readFile(path);
print(utf8.decode(bytes));
```

> **Note**: `getAppFilePath` only resolves a path — it does not create
> directories. Parent directories are created automatically when you call
> `writeFile`, `writeFileStream`, or `appendFile`.

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
// Write from stream (with overwrite protection)
Stream<List<int>> chunks() async* {
  for (int i = 0; i < 100; i++) {
    yield Uint8List(65536); // 64 KB chunks
  }
}
await fs.writeFileStream(path, chunks());
await fs.writeFileStream(path, chunks(), overwrite: false); // throws if exists

// Read as stream (returns Stream<Uint8List>)
await for (final chunk in fs.readFileStream(path)) {
  // process chunk
}
```

### Bulk operations (parallel)

```dart
// Write 100 files with up to 10 concurrent writes
await fs.writeFiles(fileMap, maxConcurrency: 10);

// Read multiple files concurrently (returns Map<String, Uint8List>)
final results = await fs.readFiles(paths, maxConcurrency: 10);

// Handle individual failures without losing successful results
final errors = <String, Object>{};
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
await fs.renameFile(oldPath, newPath);           // atomic on native
await fs.renameDirectory(oldDirPath, newDirPath); // atomic on native
await fs.copyFile(sourcePath, destPath);
await fs.moveFile(sourcePath, destPath);          // cross-device safe

// With overwrite protection (throws FileAlreadyExistsException if dest exists)
await fs.copyFile(sourcePath, destPath, overwrite: false);
await fs.moveFile(sourcePath, destPath, overwrite: false);
await fs.renameFile(oldPath, newPath, overwrite: false);
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

// Copy a directory (merge — overwrites conflicting files, keeps non-conflicting ones)
await fs.copyDirectory(sourceDirPath, destDirPath);
await fs.copyDirectory(sourceDirPath, destDirPath, overwrite: false); // throws on conflict

await fs.deleteDirectory(dirPath, recursive: true);
```

### Lifecycle management

```dart
// Release all resources (terminates web workers, resets singleton)
await fs.dispose();

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

// Bulk operations are NOT atomic — if one fails, others may have
// already completed. No rollback is performed on partial failure.
try {
  await fs.writeFiles({
    'path/a.bin': bytesA,
    'path/b.bin': bytesB, // if this fails, a.bin may already exist
  });
} on DbasFileSystemException catch (e) {
  print('Partial failure: ${e.message}');
}
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
| `getInstance({workerPoolSize})` | Returns the singleton `DbasFileSystem` instance. |
| `dispose()` | Releases all resources. Gives in-flight operations up to 30 seconds to finish, then forces teardown. |
| `isDisposed` | `true` after `dispose()` has been called. Subsequent operations throw `StateError`. |
| `isPersistentStorage` | Whether storage is persistent (always `true` on native; reflects browser grant on web). |
| `getAppFilePath(fileName)` | Resolves a platform-specific path (forward-slash normalized). Does not create directories. |
| `writeFile(path, bytes, {overwrite})` | Writes a `Uint8List` to a file. |
| `writeFileStream(path, stream, {overwrite})` | Writes a stream of byte chunks to a file. |
| `appendFile(path, bytes)` | Appends bytes to a file (creates it if missing). |
| `appendFileStream(path, stream)` | Appends a stream of byte chunks to a file (creates it if missing). |
| `readFile(path)` | Reads a file as a `Uint8List`. |
| `readFileStream(path, {chunkSize})` | Reads a file as a `Stream<Uint8List>`. |
| `deleteFile(path)` | Deletes a file (no-op if missing). |
| `fileExists(path)` | Checks whether a file exists. |
| `copyFile(source, dest, {overwrite})` | Copies a file. |
| `moveFile(source, dest, {overwrite})` | Moves a file with cross-device fallback. |
| `renameFile(oldPath, newPath, {overwrite})` | Renames a file (atomic on native, copy+delete on web). |
| `getFileSize(path)` | Returns the file size in bytes. |
| `getLastModified(path)` | Returns the last modified timestamp (UTC). |
| `writeFiles(files, {maxConcurrency, cancellationToken, onError})` | Writes multiple files concurrently (not atomic). |
| `writeFilesStream(files, {maxConcurrency, cancellationToken, onError})` | Writes multiple files from streams concurrently (not atomic). |
| `readFiles(paths, {maxConcurrency, cancellationToken, onError})` | Reads multiple files concurrently (not atomic). With `onError`, failed files are omitted from the result. |
| `createDirectory(path, {recursive})` | Creates a directory. |
| `directoryExists(path)` | Checks whether a directory exists. |
| `listDirectory(path, {recursive})` | Lists typed entries (`FileSystemEntry` with `path` and `type`). With `recursive: true`, includes all nested entries. |
| `deleteDirectory(path, {recursive})` | Deletes a directory. |
| `renameDirectory(oldPath, newPath)` | Renames a directory (atomic on native, recursive copy+delete on web). |
| `copyDirectory(source, dest, {overwrite})` | Copies a directory (merge: overwrites conflicting files, leaves non-conflicting ones). |

## Thread Safety

All operations are routed through a per-path lock (`PathLock`). Concurrent operations on the **same path** are automatically serialized, while operations on **different paths** proceed in parallel. Both file and directory operations are locked.

- **Single-path operations** (`writeFile`, `readFile`, `createDirectory`, etc.) acquire the lock for their path.
- **Multi-path operations** (`copyFile`, `moveFile`, `renameFile`, `renameDirectory`) lock both paths in sorted order to prevent deadlocks.
- **Bulk operations** (`writeFiles`, `readFiles`) run through the locked single-file methods with a configurable concurrency limit (`maxConcurrency`, default 10).
- **Web worker pool** distributes work across N workers (default 4) for true parallel I/O via OPFS.

```
Different paths  -> parallel (worker pool + PathLock allows both through)
Same path        -> serialized (PathLock queues second operation until first completes)
Bulk operations  -> bounded parallelism (ConcurrencyPool) + per-path serialization (PathLock)
```

## Bulk Operation Semantics

Bulk operations (`writeFiles`, `readFiles`, `writeFilesStream`) are **not atomic**. If one operation fails mid-batch:

- Operations already completed are **not rolled back**.
- Operations currently in flight will **run to completion**.
- Operations not yet started will be **skipped** (if a `CancellationToken` is used) or **attempted** (if not).

If you need atomic semantics, perform writes individually and implement your own rollback logic.

## Performance Tuning

| Parameter | Default | When to adjust |
|-----------|---------|---------------|
| `workerPoolSize` | 4 | Increase for web apps doing heavy parallel I/O. Each worker is a Web Worker thread. On native, this is ignored. |
| `maxConcurrency` | 10 | Lower if bulk operations cause memory pressure (many large files). Raise if I/O is the bottleneck and files are small. |
| `chunkSize` | 64 KB | Increase for large file streaming (e.g. 256 KB or 1 MB). Decrease for memory-constrained environments. Affects `readFileStream` on all platforms. |

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

`moveFile` automatically falls back to copy+delete when source and destination are on different filesystems. If the fallback also fails, the partial destination is cleaned up. Check disk space and permissions.

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

Copyright (c) 2025-2026 Daily Software Systems LTDA. All rights reserved. See [LICENSE](LICENSE) for details.
