## 1.0.0

* Initial stable release.
* File operations: read, write, copy, move, delete, and existence check.
* Stream-based read and write for memory-efficient large file handling.
* Bulk read and write operations for multiple files.
* Directory operations: create, list, delete, and existence check.
* Cross-device move with automatic copy+delete fallback.
* Web support via Origin Private File System (OPFS) with background Web Worker.
* Configurable chunk size for streamed reads (default 64 KB).
* Platform-aware path resolution via `getAppFilePath`.
* Thread-safe singleton initialization.
