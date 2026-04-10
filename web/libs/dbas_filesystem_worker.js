'use strict';

let root = null;
let filesRoot = null;
const activeWritables = new Map();

self.onmessage = async function (e) {
    const { id, method, args } = e.data;
    try {
        const result = await handleMessage(method, args || {});
        // Convert Uint8Array to plain Array for reliable dartify() interop.
        // Structured clone of Uint8Array doesn't consistently map to Dart Uint8List
        // across all runtimes, but Array of ints always maps to List<dynamic>.
        if (result && result.bytes instanceof Uint8Array) {
            result.bytes = Array.from(result.bytes);
        }
        self.postMessage({ id, result });
    } catch (error) {
        if (error && error.fsCode) {
            self.postMessage({ id, error: { code: error.fsCode, path: error.fsPath || null } });
        } else {
            const msg = error ? (error.message || String(error)) : 'Unknown error';
            self.postMessage({ id, error: { code: 'UNKNOWN', message: msg } });
        }
    }
};

async function handleMessage(method, args) {
    switch (method) {
        // ── Lifecycle ──

        case 'initialize': {
            if (!self.navigator || !self.navigator.storage || !self.navigator.storage.getDirectory) {
                throw new Error('OPFS is not supported in this browser.');
            }
            root = await navigator.storage.getDirectory();
            filesRoot = await root.getDirectoryHandle('dbas_files', { create: true });

            let persistentStorage = true;
            if (navigator.storage && navigator.storage.persist) {
                const alreadyPersisted = await navigator.storage.persisted();
                if (!alreadyPersisted) {
                    const granted = await navigator.storage.persist();
                    persistentStorage = granted;
                    if (!granted) {
                        console.warn(
                            'OPFS persistent storage was not granted. ' +
                            'Data may be evicted under storage pressure. ' +
                            'Check DbasFileSystem.isPersistentStorage at runtime.'
                        );
                    }
                }
            } else {
                persistentStorage = false;
            }
            return { persistentStorage };
        }

        // ── Single file operations ──

        case 'writeFile': {
            const dirHandle = await ensureParentDir(args.path);
            const name = getFileName(args.path);
            await assertNotExists(dirHandle, name, args.path, args.overwrite);
            const fileHandle = await dirHandle.getFileHandle(name, { create: true });
            const writable = await fileHandle.createWritable();
            await writable.write(new Uint8Array(args.bytes));
            await writable.close();
            return true;
        }

        case 'readFile': {
            const file = await getFileObject(args.path);
            const buffer = await file.arrayBuffer();
            return { bytes: new Uint8Array(buffer) };
        }

        case 'readFileChunk': {
            const file = await getFileObject(args.path);
            const slice = file.slice(args.offset, args.offset + args.length);
            const buffer = await slice.arrayBuffer();
            return {
                bytes: new Uint8Array(buffer),
                totalSize: file.size,
            };
        }

        case 'deleteFile': {
            const dirHandle = await getParentDir(args.path);
            if (!dirHandle) return true;
            const name = getFileName(args.path);
            try {
                await dirHandle.removeEntry(name);
            } catch (e) {
                if (e.name !== 'NotFoundError') throw e;
            }
            return true;
        }

        case 'fileExists': {
            const dirHandle = await getParentDir(args.path);
            if (!dirHandle) return false;
            const name = getFileName(args.path);
            try {
                await dirHandle.getFileHandle(name);
                return true;
            } catch (e) {
                if (e.name === 'NotFoundError' || e.name === 'TypeMismatchError') return false;
                throw e;
            }
        }

        case 'copyFile': {
            const srcFile = await getFileObject(args.sourcePath);
            const destDir = await ensureParentDir(args.destPath);
            const destName = getFileName(args.destPath);
            const destHandle = await destDir.getFileHandle(destName, { create: true });
            const writable = await destHandle.createWritable();

            try {
                await writeFileChunked(writable, srcFile);
                await writable.close();
            } catch (e) {
                try { await writable.abort(); } catch (_) {}
                try { await destDir.removeEntry(destName); } catch (_) {}
                throw e;
            }
            return true;
        }

        case 'moveFile': {
            await handleMessage('copyFile', { sourcePath: args.sourcePath, destPath: args.destPath });
            await handleMessage('deleteFile', { path: args.sourcePath });
            return true;
        }

        case 'renameFile': {
            await handleMessage('moveFile', { sourcePath: args.oldPath, destPath: args.newPath });
            return true;
        }

        // ── Streamed write (begin/chunk/end protocol) ──

        case 'beginStreamWrite': {
            const dirHandle = await ensureParentDir(args.path);
            const name = getFileName(args.path);
            await assertNotExists(dirHandle, name, args.path, args.overwrite);
            const fileHandle = await dirHandle.getFileHandle(name, { create: true });
            const writable = await fileHandle.createWritable();
            activeWritables.set(args.streamId, writable);
            return true;
        }

        case 'streamWriteChunk': {
            const writable = activeWritables.get(args.streamId);
            if (!writable) throw new Error('No active stream for id: ' + args.streamId);
            await writable.write(new Uint8Array(args.bytes));
            return true;
        }

        case 'endStreamWrite': {
            const writable = activeWritables.get(args.streamId);
            if (!writable) throw new Error('No active stream to end for id: ' + args.streamId);
            await writable.close();
            activeWritables.delete(args.streamId);
            return true;
        }

        case 'abortStreamWrite': {
            const writable = activeWritables.get(args.streamId);
            if (writable) {
                try { await writable.abort(); } catch (_) {}
                activeWritables.delete(args.streamId);
            }
            return true;
        }

        // ── File metadata ──

        case 'getFileSize': {
            const file = await getFileObject(args.path);
            return file.size;
        }

        case 'getLastModified': {
            const file = await getFileObject(args.path);
            return file.lastModified;
        }

        // ── Directory operations ──

        case 'createDirectory': {
            if (args.recursive === false) {
                const parts = normalizePath(args.path).split('/').filter(p => p.length > 0);
                if (parts.length === 0) return true;
                const parentParts = parts.slice(0, -1);
                const dirName = parts[parts.length - 1];
                let parentDir = filesRoot;
                for (const part of parentParts) {
                    try {
                        parentDir = await parentDir.getDirectoryHandle(part);
                    } catch (e) {
                        if (e.name === 'NotFoundError') {
                            throw fsError('DIRECTORY_NOT_FOUND', args.path);
                        }
                        throw e;
                    }
                }
                await parentDir.getDirectoryHandle(dirName, { create: true });
            } else {
                await ensureDir(args.path);
            }
            return true;
        }

        case 'directoryExists': {
            try {
                await navigateToDir(args.path);
                return true;
            } catch (e) {
                if (e.name === 'NotFoundError' || e.name === 'TypeMismatchError') return false;
                throw e;
            }
        }

        case 'listDirectory': {
            let dirHandle;
            try {
                dirHandle = await navigateToDir(args.path);
            } catch (e) {
                if (e.name === 'NotFoundError') throw fsError('DIRECTORY_NOT_FOUND', args.path);
                throw e;
            }
            const normalized = normalizePath(args.path);
            const prefix = normalized.length > 0 ? normalized + '/' : '';
            const entries = [];
            for await (const [name] of dirHandle.entries()) {
                entries.push(prefix + name);
            }
            return entries;
        }

        case 'deleteDirectory': {
            const parts = normalizePath(args.path).split('/').filter(p => p.length > 0);
            if (parts.length === 0) throw new Error('Cannot delete root directory');
            const parentParts = parts.slice(0, -1);
            const dirName = parts[parts.length - 1];

            let parentDir = filesRoot;
            for (const part of parentParts) {
                try {
                    parentDir = await parentDir.getDirectoryHandle(part);
                } catch (e) {
                    if (e.name === 'NotFoundError') return true;
                    throw e;
                }
            }

            // Check existence explicitly for non-recursive case
            let dirExists = true;
            try {
                await parentDir.getDirectoryHandle(dirName);
            } catch (e) {
                if (e.name === 'NotFoundError') dirExists = false;
                else throw e;
            }
            if (!dirExists) return true;

            if (!args.recursive) {
                const dirHandle = await parentDir.getDirectoryHandle(dirName);
                for await (const _ of dirHandle.entries()) {
                    throw fsError('DIRECTORY_NOT_EMPTY', args.path);
                }
            }

            try {
                await parentDir.removeEntry(dirName, { recursive: args.recursive || false });
            } catch (e) {
                if (e.name !== 'NotFoundError') throw e;
            }
            return true;
        }

        case 'renameDirectory': {
            let srcDir;
            try {
                srcDir = await navigateToDir(args.oldPath);
            } catch (e) {
                if (e.name === 'NotFoundError') throw fsError('DIRECTORY_NOT_FOUND', args.oldPath);
                throw e;
            }
            try {
                await copyDirectoryRecursive(srcDir, args.newPath);
                await handleMessage('deleteDirectory', { path: args.oldPath, recursive: true });
            } catch (e) {
                try { await handleMessage('deleteDirectory', { path: args.newPath, recursive: true }); } catch (_) {}
                throw e;
            }
            return true;
        }

        default:
            throw new Error('Unknown method: ' + method);
    }
}

// ── Shared helpers ──

/// Creates a typed file system error with a code and path for structured error reporting.
function fsError(code, path) {
    const e = new Error(code + (path ? ': ' + path : ''));
    e.fsCode = code;
    e.fsPath = path || null;
    return e;
}

/// Resolves a file path to a File object, throwing FILE_NOT_FOUND on missing.
async function getFileObject(path) {
    const dirHandle = await getParentDir(path);
    if (!dirHandle) throw fsError('FILE_NOT_FOUND', path);
    const name = getFileName(path);
    try {
        const fileHandle = await dirHandle.getFileHandle(name);
        return await fileHandle.getFile();
    } catch (e) {
        if (e.name === 'NotFoundError') throw fsError('FILE_NOT_FOUND', path);
        throw e;
    }
}

/// Throws FILE_ALREADY_EXISTS if overwrite is false and the file exists.
async function assertNotExists(dirHandle, name, path, overwrite) {
    if (overwrite !== false) return;
    try {
        await dirHandle.getFileHandle(name);
        throw fsError('FILE_ALREADY_EXISTS', path);
    } catch (e) {
        if (e.fsCode) throw e;
        if (e.name !== 'NotFoundError') throw e;
    }
}

/// Writes a File object's content to a writable in 64KB chunks.
async function writeFileChunked(writable, file) {
    const chunkSize = 65536;
    let offset = 0;
    while (offset < file.size) {
        const end = Math.min(offset + chunkSize, file.size);
        const slice = file.slice(offset, end);
        const chunk = await slice.arrayBuffer();
        await writable.write(new Uint8Array(chunk));
        offset = end;
    }
}

// ── OPFS path helpers ──
// All paths are relative to the 'dbas_files/' OPFS root.

function normalizePath(p) {
    return p.replace(/\\/g, '/').replace(/^\/+/, '').replace(/\/+$/, '');
}

function getFileName(p) {
    const parts = normalizePath(p).split('/');
    return parts[parts.length - 1];
}

function getParentParts(p) {
    const parts = normalizePath(p).split('/');
    return parts.slice(0, -1);
}

async function ensureParentDir(filePath) {
    const parts = getParentParts(filePath);
    let dir = filesRoot;
    for (const part of parts) {
        dir = await dir.getDirectoryHandle(part, { create: true });
    }
    return dir;
}

async function getParentDir(filePath) {
    const parts = getParentParts(filePath);
    let dir = filesRoot;
    for (const part of parts) {
        try {
            dir = await dir.getDirectoryHandle(part);
        } catch (e) {
            if (e.name === 'NotFoundError') return null;
            throw e;
        }
    }
    return dir;
}

async function ensureDir(dirPath) {
    const parts = normalizePath(dirPath).split('/').filter(p => p.length > 0);
    let dir = filesRoot;
    for (const part of parts) {
        dir = await dir.getDirectoryHandle(part, { create: true });
    }
    return dir;
}

async function navigateToDir(dirPath) {
    const parts = normalizePath(dirPath).split('/').filter(p => p.length > 0);
    let dir = filesRoot;
    for (const part of parts) {
        dir = await dir.getDirectoryHandle(part);
    }
    return dir;
}

async function copyDirectoryRecursive(srcDirHandle, destPath) {
    const destDirHandle = await ensureDir(destPath);
    for await (const [name, handle] of srcDirHandle.entries()) {
        const childDest = normalizePath(destPath) + '/' + name;
        if (handle.kind === 'file') {
            const file = await handle.getFile();
            const destFileHandle = await destDirHandle.getFileHandle(name, { create: true });
            const writable = await destFileHandle.createWritable();
            try {
                await writeFileChunked(writable, file);
                await writable.close();
            } catch (e) {
                try { await writable.abort(); } catch (_) {}
                throw e;
            }
        } else if (handle.kind === 'directory') {
            await copyDirectoryRecursive(handle, childDest);
        }
    }
}
