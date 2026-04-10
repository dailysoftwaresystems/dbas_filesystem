# dbas_filesystem

A Flutter plugin for cross-platform file system operations with streaming, byte array, and directory support across **Android, iOS, macOS, Linux, Windows, and Web**.

## Features

- **File operations** &mdash; read, write, copy, move, delete, and existence check.
- **Stream support** &mdash; stream-based read and write for memory-efficient large file handling.
- **Bulk operations** &mdash; read or write multiple files in a single call.
- **Directory operations** &mdash; create, list, delete, and existence check.
- **Cross-device move** &mdash; automatic copy+delete fallback when source and destination are on different devices.
- **Web support** &mdash; Origin Private File System (OPFS) with a background Web Worker for non-blocking I/O.
- **Configurable chunking** &mdash; streamed reads use a configurable chunk size (default 64 KB).

## Platform Support

| Platform | Implementation |
|----------|---------------|
| Android  | `dart:io`     |
| iOS      | `dart:io`     |
| macOS    | `dart:io`     |
| Linux    | `dart:io`     |
| Windows  | `dart:io`     |
| Web      | OPFS via Web Worker |

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

// Read
final bytes = await fs.readFile(path);
print(utf8.decode(bytes));
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

### Directory operations

```dart
await fs.createDirectory(dirPath);
final entries = await fs.listDirectory(dirPath);
await fs.deleteDirectory(dirPath, recursive: true);
```

### Copy and move

```dart
await fs.copyFile(sourcePath, destPath);
await fs.moveFile(sourcePath, destPath); // cross-device safe
```

## API Reference

| Method | Description |
|--------|-------------|
| `getInstance()` | Returns the singleton `DbasFileSystem` instance. |
| `getAppFilePath(fileName)` | Resolves a platform-specific path for the given file name. |
| `writeFile(path, bytes)` | Writes a byte array to a file. |
| `writeFileStream(path, stream)` | Writes a stream of byte chunks to a file. |
| `readFile(path)` | Reads a file as a byte array. |
| `readFileStream(path, {chunkSize})` | Reads a file as a stream of byte chunks. |
| `deleteFile(path)` | Deletes a file. |
| `fileExists(path)` | Checks whether a file exists. |
| `copyFile(source, dest)` | Copies a file. |
| `moveFile(source, dest)` | Moves a file with cross-device fallback. |
| `writeFiles(files)` | Writes multiple files from a map of path to bytes. |
| `writeFilesStream(files)` | Writes multiple files from a map of path to stream. |
| `readFiles(paths)` | Reads multiple files into a map of path to bytes. |
| `createDirectory(path, {recursive})` | Creates a directory. |
| `directoryExists(path)` | Checks whether a directory exists. |
| `listDirectory(path)` | Lists entries in a directory. |
| `deleteDirectory(path, {recursive})` | Deletes a directory. |

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
