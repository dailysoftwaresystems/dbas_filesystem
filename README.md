# dbas_filesystem

A Flutter plugin for cross-platform file system operations with streaming, byte array, and directory support across **Android, iOS, macOS, Linux, Windows, and Web**.

## Features

- **File operations** &mdash; read, write, copy, move, rename, delete, and existence check.
- **File metadata** &mdash; get file size and last modified timestamp.
- **Overwrite protection** &mdash; `writeFile` and `writeFileStream` accept an `overwrite` parameter to prevent accidental overwrites.
- **Stream support** &mdash; stream-based read and write for memory-efficient large file handling.
- **Parallel bulk operations** &mdash; read or write multiple files concurrently with configurable `maxConcurrency`.
- **Directory operations** &mdash; create, list, delete, rename, and existence check.
- **Cross-device move** &mdash; automatic copy+delete fallback when source and destination are on different devices. Partial destination is cleaned up on failure.
- **Thread safety** &mdash; per-path locking for both files and directories. Concurrent operations on the same path are serialized; different paths proceed in parallel.
- **Typed exceptions** &mdash; `FileNotFoundException`, `FileAlreadyExistsException`, `DirectoryNotFoundException`, `DirectoryNotEmptyException`.
- **Web worker pool** &mdash; configurable pool of OPFS Web Workers for true parallel I/O on web.
- **Configurable chunking** &mdash; streamed reads use a configurable chunk size (default 64 KB).
- **Path normalization** &mdash; `listDirectory` and `getAppFilePath` return forward-slash paths on all platforms.
- **Lifecycle management** &mdash; `dispose()` releases all resources (terminates web workers, resets singleton).

## Platform Support

| Platform | Implementation |
|----------|---------------|
| Android  | `dart:io`     |
| iOS      | `dart:io`     |
| macOS    | `dart:io`     |
| Linux    | `dart:io`     |
| Windows  | `dart:io`     |
| Web      | OPFS via Web Worker pool |

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
```

### Rename, copy, and move

```dart
await fs.renameFile(oldPath, newPath);           // atomic on native
await fs.renameDirectory(oldDirPath, newDirPath); // atomic on native
await fs.copyFile(sourcePath, destPath);
await fs.moveFile(sourcePath, destPath);          // cross-device safe
```

### Directory operations

```dart
await fs.createDirectory(dirPath);
final entries = await fs.listDirectory(dirPath); // forward-slash paths on all platforms
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

### Error handling

```dart
try {
  await fs.readFile('/nonexistent');
} on FileNotFoundException catch (e) {
  print(e.path); // '/nonexistent'
} on DbasFileSystemException catch (e) {
  print(e.message);
}
```

## API Reference

| Method | Description |
|--------|-------------|
| `getInstance({workerPoolSize})` | Returns the singleton `DbasFileSystem` instance. |
| `dispose()` | Releases all resources and resets the singleton. |
| `getAppFilePath(fileName)` | Resolves a platform-specific path (forward-slash normalized). |
| `writeFile(path, bytes, {overwrite})` | Writes a `Uint8List` to a file. |
| `writeFileStream(path, stream, {overwrite})` | Writes a stream of byte chunks to a file. |
| `readFile(path)` | Reads a file as a `Uint8List`. |
| `readFileStream(path, {chunkSize})` | Reads a file as a `Stream<Uint8List>`. |
| `deleteFile(path)` | Deletes a file (no-op if missing). |
| `fileExists(path)` | Checks whether a file exists. |
| `copyFile(source, dest)` | Copies a file. |
| `moveFile(source, dest)` | Moves a file with cross-device fallback. |
| `renameFile(oldPath, newPath)` | Renames a file (atomic on native, copy+delete on web). |
| `getFileSize(path)` | Returns the file size in bytes. |
| `getLastModified(path)` | Returns the last modified timestamp (UTC). |
| `writeFiles(files, {maxConcurrency})` | Writes multiple files (`Map<String, Uint8List>`) concurrently. |
| `writeFilesStream(files, {maxConcurrency})` | Writes multiple files from streams concurrently. |
| `readFiles(paths, {maxConcurrency})` | Reads multiple files concurrently, returns `Map<String, Uint8List>`. |
| `createDirectory(path, {recursive})` | Creates a directory. |
| `directoryExists(path)` | Checks whether a directory exists. |
| `listDirectory(path)` | Lists entries in a directory (forward-slash paths). |
| `deleteDirectory(path, {recursive})` | Deletes a directory. |
| `renameDirectory(oldPath, newPath)` | Renames a directory (atomic on native, recursive copy+delete on web). |

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
