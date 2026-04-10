## 2.0.0

### Breaking changes

* **`Uint8List` API**: All byte parameters and return types changed from `List<int>` to `Uint8List` for proper binary semantics and memory efficiency.
* **Bulk operations removed from native interface**: `writeFiles`, `readFiles`, and `writeFilesStream` are now handled exclusively by the platform layer, eliminating duplication and ensuring all bulk calls route through `PathLock`.
* **Removed `ffiPlugin` declarations**: No native FFI code exists; the misleading `ffiPlugin: true` entries have been removed from `pubspec.yaml`.

### New features

* **`writeFileStream` overwrite protection**: Added `overwrite` parameter (default `true`) to match `writeFile` behavior.
* **`dispose()` method**: Releases all resources (terminates web workers, resets singleton). Allows re-initialization via `getInstance()`. Callers holding old references get `StateError`.
* **Use-after-dispose guard**: All platform methods throw `StateError` if called after `dispose()`.
* **Directory locking**: Directory operations now acquire `PathLock`, consistent with file operations. `renameDirectory` locks both paths in sorted order.
* **Path normalization**: `listDirectory` and `getAppFilePath` return forward-slash paths on all platforms.

### Fixes

* **Web binary transfer**: Worker returns data via reliable `Array.from()` conversion for correct `dartify()` interop. Bytes sent to the worker are sanitized to plain `List<int>` for safe `jsify()` conversion.
* **`moveFile` partial cleanup**: Failed cross-device moves (native) and copy+delete moves (web) now clean up partial destination files. Source delete failure also rolls back the destination.
* **`createDirectory` recursive parameter on web**: Non-recursive mode now correctly fails if parent directory does not exist.
* **`renameDirectory` on web**: Cleans up partial destination on failure instead of leaving orphaned directories.
* **`readFileStream` cancellation**: `onCancel` now always returns a valid `Future` (via `Completer`) ensuring the path lock is properly released on cancel. Web implementation no longer `await`s `controller.close()` in `finally`.
* **Dispose race condition**: Singleton `_instance` is nulled *before* awaiting async teardown, preventing concurrent `getInstance()` from returning a being-disposed instance.

### Internal improvements

* **Removed `DbasFileSystemPlatform` singleton**: Platform is now constructed directly by `DbasFileSystem.getInstance()`, eliminating duplicate singleton boilerplate.
* **Consolidated stub files**: Two identical 77-line stubs replaced with a shared `DbasFileSystemNativeStub` base class.
* **JS Worker DRY cleanup**: Extracted `getFileObject()`, `assertNotExists()`, and `writeFileChunked()` helpers. `renameFile` delegates to `moveFile` instead of duplicating logic.

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
