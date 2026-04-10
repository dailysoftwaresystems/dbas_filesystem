# dbas_filesystem

A Flutter plugin for cross-platform file system operations with streaming, byte array, and directory support across **Android, iOS, macOS, Linux, Windows, and Web**.

## Features

- **File operations** &mdash; read, write, copy, move, rename, delete, and existence check.
- **File metadata** &mdash; get file size and last modified timestamp.
- **Overwrite protection** &mdash; `writeFile` accepts an `overwrite` parameter to prevent accidental overwrites.
- **Stream support** &mdash; stream-based read and write for memory-efficient large file handling.
- **Parallel bulk operations** &mdash; read or write multiple files concurrently with configurable `maxConcurrency`.
- **Directory operations** &mdash; create, list, delete, rename, and existence check.
- **Cross-device move** &mdash; automatic copy+delete fallback when source and destination are on different devices.
- **Per-file thread safety** &mdash; concurrent operations on the same file are automatically serialized; different files proceed in parallel.
- **Typed exceptions** &mdash; `FileNotFoundException`, `FileAlreadyExistsException`, `DirectoryNotFoundException`, `DirectoryNotEmptyException`.
- **Web worker pool** &mdash; configurable pool of OPFS Web Workers for true parallel I/O on web.
- **Configurable chunking** &mdash; streamed reads use a configurable chunk size (default 64 KB).

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
import 'package:dbas_filesystem/dbas_filesystem.dart';

final fs = await DbasFileSystem.getInstance();
```

### Write and read a file

```dart
final path = await fs.getAppFilePath('example.txt');

// Write
await fs.writeFile(path, utf8.encode('Hello, world!'));

// Write with overwrite protection
await fs.writeFile(path, utf8.encode('data'), overwrite: false);
// throws FileAlreadyExistsException if file exists

// Read
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
// Write from stream
Stream<List<int>> chunks() async* {
  for (int i = 0; i < 100; i++) {
    yield Uint8List(65536); // 64 KB chunks
  }
}
await fs.writeFileStream(path, chunks());

// Read as stream
await for (final chunk in fs.readFileStream(path)) {
  // process chunk
}
```

### Bulk operations (parallel)

```dart
// Write 100 files with up to 10 concurrent writes
await fs.writeFiles(fileMap, maxConcurrency: 10);

// Read multiple files concurrently
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
final entries = await fs.listDirectory(dirPath);
await fs.deleteDirectory(dirPath, recursive: true);
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
| `getAppFilePath(fileName)` | Resolves a platform-specific path for the given file name. |
| `writeFile(path, bytes, {overwrite})` | Writes a byte array to a file. |
| `writeFileStream(path, stream)` | Writes a stream of byte chunks to a file. |
| `readFile(path)` | Reads a file as a byte array. |
| `readFileStream(path, {chunkSize})` | Reads a file as a stream of byte chunks. |
| `deleteFile(path)` | Deletes a file. |
| `fileExists(path)` | Checks whether a file exists. |
| `copyFile(source, dest)` | Copies a file. |
| `moveFile(source, dest)` | Moves a file with cross-device fallback. |
| `renameFile(oldPath, newPath)` | Renames a file (atomic on native, copy+delete on web). |
| `getFileSize(path)` | Returns the file size in bytes. |
| `getLastModified(path)` | Returns the last modified timestamp (UTC). |
| `writeFiles(files, {maxConcurrency})` | Writes multiple files concurrently. |
| `writeFilesStream(files, {maxConcurrency})` | Writes multiple files from streams concurrently. |
| `readFiles(paths, {maxConcurrency})` | Reads multiple files concurrently. |
| `createDirectory(path, {recursive})` | Creates a directory. |
| `directoryExists(path)` | Checks whether a directory exists. |
| `listDirectory(path)` | Lists entries in a directory. |
| `deleteDirectory(path, {recursive})` | Deletes a directory. |
| `renameDirectory(oldPath, newPath)` | Renames a directory (atomic on native, recursive copy+delete on web). |

## Thread Safety

All operations are routed through a per-file lock (`PathLock`). Concurrent operations on the **same file** are automatically serialized, while operations on **different files** proceed in parallel.

- **Single-file operations** (`writeFile`, `readFile`, etc.) acquire the lock for their path.
- **Multi-path operations** (`copyFile`, `moveFile`, `renameFile`) lock both paths in sorted order to prevent deadlocks.
- **Bulk operations** (`writeFiles`, `readFiles`) run through the locked single-file methods with a configurable concurrency limit (`maxConcurrency`, default 10).
- **Web worker pool** distributes unlocked work across N workers (default 4) for true parallel I/O via OPFS.

```
Different files → parallel (worker pool + PathLock allows both through)
Same file       → serialized (PathLock queues second operation until first completes)
Bulk operations → bounded parallelism (ConcurrencyPool) + per-file serialization (PathLock)
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
