## 3.2.0

### Improvements

* **Relative paths resolve under the app directory**: every file operation (`writeFile`, `writeFileStream`, `readFile`, `readFileStream`, `appendFile*`, `deleteFile`, `fileExists`, `getFileSize`, `getLastModified`, `copyFile`, `moveFile`, `renameFile`, `writeFiles`, `writeFilesStream`) now roots a RELATIVE path under the application storage directory — `<application-support>/dbas_files/` on native, `/dbas_files/` on web (OPFS), `<cwd>/test/files/` under test — the same location [getAppFilePath](README.md) already returned. Previously a relative path resolved against the process working directory on native, which is unpredictable in a packaged app. This makes a bucket-style path like `uploads/photo.jpg` land in the app's own storage area without each caller having to pre-resolve it through `getAppFilePath`.
* **Absolute paths are unchanged**: an already-absolute path (POSIX/OPFS `/…`, a Windows drive `C:…`, or a UNC `\\…` path — including any path previously returned by `getAppFilePath`) passes through untouched, so existing callers that resolve paths up front keep working with zero double-rooting. The app-directory root is resolved once and cached per instance.

### Behavioural note

* This changes where a **relative** path physically lands on native (app-support directory instead of the CWD). Callers that already passed absolute paths (the documented pattern via `getAppFilePath`) are unaffected. Empty / blank / null-byte paths still throw `ArgumentError` as before.

## 3.1.4

### Security

* **Pinned third-party CI action**: `subosito/flutter-action` is now pinned to a commit SHA instead of the floating `v2` tag, so the public repo can't run an unverified upstream action update on PRs from forks. First-party `actions/*` stay on their major tags.

### Documentation

* **License footer aligned with Apache 2.0**: replaced the README "All rights reserved" line with "Licensed under the Apache License, Version 2.0" to match the actual `LICENSE` file.

## 3.1.3

### Documentation

* **Install instructions for pub.dev**: README now installs `dbas_filesystem` from pub.dev (`flutter pub add dbas_filesystem`) instead of the previous git URL.

## 3.1.2

### Improvements

* **Public release**: relicensed under Apache License 2.0 and prepared the repo for public distribution (new CI/release/publish pipeline, `.pubignore`, `CODEOWNERS`).
* **SDK / Flutter floor**: bumped to `sdk: ^3.12.0` and `flutter: '>=3.44.0'`.
* **Dependencies**: refreshed `web` to `^1.1.1`.

## 3.1.1

### Improvements

* **Reduced lock contention for read-only operations**: `fileExists`, `getFileSize`, and `getLastModified` now acquire a shared lock instead of an exclusive lock. Multiple concurrent reads on the same path no longer serialize behind each other. This also reduces contention when `onFileChanged` is enabled, since every mutation performs an extra `fileExists` check before writing.

## 3.1.0

### Breaking changes

* **`overwrite` defaults to `false`**: `writeFile`, `writeFileStream`, `copyFile`, `moveFile`, `renameFile`, and `copyDirectory` now default to `overwrite: false`. Existing files are preserved unless you explicitly pass `overwrite: true`. This prevents silent data loss from accidental overwrites.
* **Atomic bulk writes (default)**: `writeFiles` and `writeFilesStream` are now atomic by default — if any write fails, all successfully written files are rolled back to their original state. Set `atomic: false` to restore the previous non-atomic behavior with `onError` support.
* **`readFiles` without `onError` throws `MultiException`**: When `onError` is not provided, `readFiles` now collects all errors and throws `MultiException` instead of propagating only the first error. Pass `onError` to get the previous partial-results behavior.

### New features

* **Atomic bulk operations with rollback**: `writeFiles` and `writeFilesStream` accept `{bool atomic = true}`. In atomic mode, existing files are snapshotted before writing. On failure, all changes are rolled back and `AtomicOperationException` is thrown (with an optional `secondaryError` if rollback itself partially failed).
* **`moveDirectory`**: Moves a directory tree. On native, attempts atomic `rename()` first, falling back to copy+delete across filesystems. On web, performs copy+delete via OPFS.
* **File change notifications**: `getInstance` accepts `onFileChanged` callback (also settable as a property). Fires after every successful mutation with a `Map<String, FileChange>` describing old/new state of each affected entry. Directory operations fire one notification with all affected entries.
* **Progress callbacks**: All operations accept `onProgress` with `OperationProgress` containing `current` (entry + progress) and `overall` (0.0-1.0). Bulk ops report per-file completion; copy operations report byte-level progress on native.
* **Configurable dispose timeout**: `dispose({Duration timeout})` replaces the hard-coded 30-second timeout.
* **Hierarchical per-path locking**: File operations acquire a shared lock on the parent directory and an exclusive lock on the file. Directory-destructive operations (delete, rename, move) acquire exclusive locks that block concurrent file operations in that directory. Non-destructive directory operations (list, exists, create) use shared locks.
* **Symlink resolution in `listDirectory`**: Symlinks on native platforms are now resolved to their target type instead of being misidentified as directories.
* **`MultiException`**: Collects all errors from parallel operations with path context. Immutable error list.
* **`AtomicOperationException`**: Contains the primary `error` and an optional `secondaryError` from rollback.
* **`FileChange` type**: Describes a single change with `oldEntry`/`newEntry` and derived `type` (created/modified/deleted). Named factories: `FileChange.created()`, `.deleted()`, `.modified()`.
* **`OperationProgress` / `CurrentEntryProgress`**: Progress reporting types with range-validated fields.
* **Web worker orphaned stream cleanup**: On worker restart, orphaned writable streams from a previous crash are aborted during initialization.
* **Web `moveDirectory` destination guard**: Web now checks that the destination doesn't already exist before moving, matching native `Directory.rename()` behavior.

### Fixes

* **Callback safety**: `onFileChanged` and `onProgress` callbacks are wrapped in try-catch — a bug in user code never masks a successful filesystem operation.
* **`PathLock.dispose` no longer orphans waiters**: On timeout, pending lock waiters receive `StateError` instead of hanging forever.
* **Cancellation token respected in snapshot phase**: `writeFiles`/`writeFilesStream` now check the cancellation token during the snapshot phase, not just the write phase.
* **`_RWLock` defensive assertions**: `releaseShared`/`releaseExclusive` assert correct pairing to prevent silent lock corruption.

### Improvements

* **Singleton documented as intentional**: Class-level documentation explains why the singleton pattern is used (coordinating per-path locks, worker pools, and change notifications).
* **Web worker double-copy overhead documented**: The `Uint8List` → `List<int>` conversion in `_sanitizeArgs` is documented as a known Dart JS interop limitation.
* **`readFileStream` lock behavior documented**: Doc comment explains that the file path lock is held for the entire stream lifetime.
* **JS worker cleanup logging**: Silent `catch (_) {}` blocks in worker cleanup (orphaned streams, move/rename rollback) now use `console.warn` for debuggability.
* **`_rollback` return clarity**: Uses `return _rollback(...)` for explicit non-return semantics.
* **JS worker minification**: Source moved to `web/libs/src/`. CI automatically minifies via esbuild and commits the built output to `web/libs/`. Local scripts available at `scripts/minify-js-worker.sh` and `.ps1`.

### Tests

* 129 tests (up from 92). New coverage:
  * Atomic rollback (success + failure paths)
  * `writeFilesStream` (happy path + atomic rollback)
  * `moveDirectory` (happy path + missing source)
  * File change notifications (writeFile create/modify, deleteFile, moveFile, renameFile, copyDirectory, moveDirectory, writeFiles)
  * Progress callbacks (writeFile, writeFiles)
  * Callback safety (throwing onFileChanged, throwing onProgress)
  * `PathLock.withLocks` (sorted acquisition, exclusive-overrides-shared)
  * PathLock writer-priority
  * Mid-flight cancellation
  * `onError` with `atomic: false` (non-atomic write + read)
  * `MultiException` immutability and error details
  * `FileChange` factories and equality
  * Configurable dispose timeout
  * `createDirectory(recursive: false)` error path
  * Empty bulk operation edge cases

## 3.0.0

### Breaking changes

* **`listDirectory` returns typed entries**: `listDirectory` now returns `List<FileSystemEntry>` instead of `List<String>`. Each `FileSystemEntry` has a `path` (normalized forward-slash string) and a `type` (`FileSystemEntityType.file` or `FileSystemEntityType.directory`). Update call sites from `entry` to `entry.path` for path access.

### New features

* **`appendFile` and `appendFileStream`**: Append bytes to existing files, or create them if they don't exist. Parent directories are created automatically, consistent with `writeFile`.
* **`copyDirectory`**: Copies a directory tree with merge semantics — files at matching paths in the destination are overwritten (or throw `FileAlreadyExistsException` with `overwrite: false`), while non-conflicting destination files are preserved.
* **`isDisposed` getter**: Returns `true` after `dispose()` has been called. All subsequent operations on a disposed instance throw `StateError`.
* **`CancellationToken` listener API**: `addListener` / `removeListener` for reactive cancellation. Listeners registered after cancellation are called immediately. Listeners are invoked synchronously in `cancel()` exactly once.
* **Web worker auto-restart**: Crashed workers are automatically restarted with exponential backoff (first 3 retries immediate, then 1s, 2s, 4s... capped at 60s, max 5 retries per slot). Previously, a crashed worker was permanently removed from the pool.

### Fixes

* **Unified error handling**: Replaced `_throwIfNotFound` / `_throwIfDirNotFound` with a single `handleError` method. All native methods now catch `FileSystemException` and map to typed exceptions. Added ENOTDIR (20), EISDIR (21), and Windows ERROR_PATH_NOT_FOUND (3) mappings.
* **Web `PermissionDeniedException`**: OPFS `NotAllowedError` now maps to `PermissionDeniedException` instead of a generic `DbasFileSystemException`.
* **Native `moveFile` rollback safety**: Cross-device move fallback no longer deletes the destination when source deletion fails. Matches web behaviour — data at the destination (which was successfully copied) is preserved.
* **Dispose race condition**: `getInstance()` and `dispose()` now use a static mutex to prevent overlapping execution. Previously, a concurrent `getInstance()` during `dispose()` could receive a being-disposed native interface.
* **Graceful dispose with timeout**: `dispose()` gives in-flight operations up to 30 seconds to complete before forcing teardown, instead of waiting indefinitely.

### Improvements

* **Documentation**: `getAppFilePath` doc comment clarifies it is side-effect free (no directory creation). README explains OPFS-only web strategy (no IndexedDB/LocalStorage fallback). Worker crash troubleshooting updated for auto-restart behaviour.
* **`_assertNotDisposed` guard**: Every public method on `DbasFileSystem` checks `isDisposed` before delegating, providing immediate `StateError` instead of relying on the `PathLock` disposed check.

### Tests

* 20+ new tests: `appendFile`/`appendFileStream` (6 tests), `copyDirectory` (5 tests), `listDirectory` typed entries (2 tests), `CancellationToken` listeners (5 tests), `isDisposed` lifecycle (3 tests), `FileSystemEntry` model (1 test).
* Updated all existing `listDirectory` tests for the new `FileSystemEntry` return type.

## 2.3.0

### New features

* **`overwrite` parameter on `copyFile`, `moveFile`, `renameFile`**: All three methods now accept `{bool overwrite = true}`. When `overwrite: false` and the destination already exists, throws `FileAlreadyExistsException`. Default behavior (`overwrite: true`) is unchanged — fully backwards compatible.
* **Recursive `listDirectory`**: `listDirectory` now accepts `{bool recursive = false}`. When `true`, returns all entries in subdirectories as well. Default behavior is unchanged.

### Fixes

* **Web `readFileStream` backpressure**: Added `onPause`/`onResume` handlers with `pauseCompleter` pattern (matching native implementation). Slow consumers on web no longer cause unbounded memory growth. Also added a missing `cancelled` check after worker round-trip to prevent adding chunks to a cancelled stream.
* **Web `moveFile` rollback safety**: Previously, if source deletion failed after a successful copy, the worker would delete the destination — destroying the user's data when `overwrite: true` had replaced a pre-existing file. Now the destination (with correct data) is preserved and the error propagates.
* **`EPERM` error mapping**: Linux `EPERM` (error code 1, "Operation not permitted") now maps to `PermissionDeniedException`, alongside the existing `EACCES` (13) and Windows `ERROR_ACCESS_DENIED` (5) mappings.
* **CI: test discovery**: Changed `flutter test test/dbas_filesystem_test.dart` to `flutter test test/` so new test files are automatically picked up.

### Improvements

* **`getAppFilePath` is now side-effect free**: No longer creates the application data directory on every call. Write operations (`writeFile`, `writeFileStream`) already create parent directories, so this was redundant. Callers that relied on the implicit directory creation should use `createDirectory` explicitly.
* **`isTest()` cached at startup**: The `FLUTTER_TEST` environment variable check is now evaluated once at library load time instead of on every `getAppFilePath` call.
* **DRY bulk operations**: The `onError` branching logic duplicated across `writeFiles`, `writeFilesStream`, and `readFiles` has been extracted into a shared `_withErrorHandler` helper.

### Tests

* 7 new tests: `copyFile`/`moveFile`/`renameFile` with `overwrite: false` (3 tests + 1 success case), recursive `listDirectory`, strengthened `writeFiles` `onError` callback with a real failure trigger.

## 2.2.2

### Fixes

* **CI: web integration tests use WebDriver protocol**: Switched from `-d chrome` (dwds) to `-d web-server --browser-name=chrome` (WebDriver via ChromeDriver). Fixes `AppConnectionException` / dwds connection failures on headless CI runners. Chrome runs headless natively via `integrationDriver()` — no `xvfb-run` needed.

## 2.2.1

### Fixes

* **CI: web integration tests on headless runners**: Fixed `Missing X server or $DISPLAY` error by wrapping `flutter drive` with `xvfb-run` for headless Chrome support on Ubuntu CI.
* **CI: ChromeDriver cleanup**: Added a `Stop ChromeDriver` step (`if: always()`) to kill the backgrounded process after tests complete.
* **CI: example dependencies**: Added `flutter pub get` for the `example/` project before running integration tests.

## 2.2.0

### New features

* **`onError` callback for bulk operations**: `readFiles`, `writeFiles`, and `writeFilesStream` now accept an optional `onError` callback. When provided, individual failures invoke the callback instead of throwing — successful results are still returned. `OperationCancelledException` always propagates regardless of `onError`.
* **`PermissionDeniedException`**: New typed exception for permission-denied errors. Maps `EACCES` (13) on Linux/macOS and `ERROR_ACCESS_DENIED` (5) on Windows to a typed exception instead of surfacing raw `FileSystemException`.
* **`chunkSize` honored on native**: `readFileStream` now respects the `chunkSize` parameter on all platforms (previously only affected web). Uses `RandomAccessFile` for precise chunk-level control with backpressure support — slow consumers no longer cause unbounded memory growth.

### Fixes

* **`copyFile` robustness**: Replaced fragile `pipe()` with a manual read/write loop and `try/finally` pattern. The writer is always closed, and partial destination files are cleaned up on failure (including on Windows where file handles must be released before deletion).
* **`getInstance()` hardening**: The `_initCompleter` is now captured into a local variable before accessing `.future`, eliminating a theoretical race if `dispose()` clears it between the null-check and usage. Error cleanup uses `identical()` to avoid stomping a concurrent re-initialization.

### Improvements

* **Memory guidance**: `readFiles`, `writeFiles`, and `writeFilesStream` doc comments now document memory implications. README adds guidance on when to use bulk APIs vs streaming.
* **Removed unused dependency**: `plugin_platform_interface` was listed in `pubspec.yaml` but never imported. Removed.

### Tests

* 12 new tests: `chunkSize` honoring (3 tests), `PermissionDeniedException` hierarchy, `copyFile` partial cleanup, `onError` callback (4 tests), `getInstance` hardening, backwards compatibility.

## 2.1.0

### New features

* **Cancellation tokens**: Bulk operations (`writeFiles`, `readFiles`, `writeFilesStream`) now accept an optional `CancellationToken`. When cancelled, tasks not yet started throw `OperationCancelledException`; in-flight tasks run to completion.
* **`isPersistentStorage` getter**: Reports whether the underlying storage is persistent. Always `true` on native platforms. On web, reflects whether the browser granted persistent OPFS storage via `navigator.storage.persist()`.
* **`OperationCancelledException`**: New typed exception for cancelled operations, extends `DbasFileSystemException`.

### Improvements

* **Bulk operation docs**: `writeFiles`, `readFiles`, and `writeFilesStream` doc comments now explicitly state that operations are **not atomic** — no rollback on partial failure.
* **Web worker error messages**: Crash errors now include recovery instructions ("Call dispose() and re-initialize.").
* **Web persistence visibility**: Worker returns persistence grant status to Dart instead of only logging to `console.warn`. Apps can check `isPersistentStorage` and warn users.
* **README**: Added migration guide (v1.x → v2.x), performance tuning table, bulk operation semantics, troubleshooting section, cancellation examples, and storage persistence examples.
* **pubspec.yaml**: Added `repository` and `issue_tracker` fields.

### Tests

* 16 new edge case tests: cancellation tokens, `isPersistentStorage`, concurrent `dispose()`+`getInstance()` race, duplicate paths in bulk ops, bulk partial failure, `ConcurrencyPool` edge cases, stream cancellation, and exception hierarchy completeness.

## 2.0.1

* Updated README to reflect all 2.0.0 changes: `Uint8List` API in examples, `dispose()` lifecycle section, `writeFileStream` overwrite parameter, directory locking in thread safety docs, path normalization, and updated API reference table.

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
