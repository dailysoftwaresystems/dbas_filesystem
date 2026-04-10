## 1.1.0

* File metadata: `getFileSize` and `getLastModified`.
* `writeFile` `overwrite` parameter to prevent accidental overwrites.
* Parallel bulk operations with configurable `maxConcurrency` (default 10).
* Rename support for files and directories (atomic on native, copy+delete on web).
* Per-file thread safety via `PathLock` — same-file operations serialized, different files parallel.
* Multi-path operations (`copyFile`, `moveFile`, `renameFile`) lock both paths in sorted order to prevent deadlocks.
* Bulk operations route through locked single-file methods with bounded concurrency via `ConcurrencyPool`.
* Typed exception hierarchy: `FileNotFoundException`, `FileAlreadyExistsException`, `DirectoryNotFoundException`, `DirectoryNotEmptyException`.
* Web Worker pool (default 4 workers) with least-pending dispatch for true parallel I/O.
* Worker pool crash recovery — crashed workers are removed from pool automatically.
* `readFileStream` error mapping for consistent `FileNotFoundException` across all methods.

## 1.0.0

* Initial stable release.
* File operations: read, write, copy, move, delete, and existence check.
* Stream-based read and write for memory-efficient large file handling.
* Directory operations: create, list, delete, and existence check.
* Cross-device move with automatic copy+delete fallback.
* Web support via OPFS with background Web Worker.
* Configurable chunk size for streamed reads (default 64 KB).
* Platform-aware path resolution via `getAppFilePath`.
* Thread-safe singleton initialization.
