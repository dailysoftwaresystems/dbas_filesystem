'use strict';

let root = null;
let filesRoot = null;
const activeWritables = new Map();

self.onmessage = async function (e) {
    const { id, method, args } = e.data;
    try {
        const result = await handleMessage(method, args || {});
        self.postMessage({ id, result });
    } catch (error) {
        self.postMessage({ id, error: error.message || String(error) });
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

            if (navigator.storage && navigator.storage.persist) {
                const alreadyPersisted = await navigator.storage.persisted();
                if (!alreadyPersisted) {
                    const isPersisted = await navigator.storage.persist();
                    if (!isPersisted) {
                        console.warn('⚠️ Failed to request persistent file storage.');
                    }
                }
            }
            return true;
        }

        // ── Single file operations ──

        case 'writeFile': {
            const dirHandle = await ensureParentDir(args.path);
            const name = getFileName(args.path);
            const fileHandle = await dirHandle.getFileHandle(name, { create: true });
            const writable = await fileHandle.createWritable();
            await writable.write(new Uint8Array(args.bytes));
            await writable.close();
            return true;
        }

        case 'readFile': {
            const dirHandle = await getParentDir(args.path);
            if (!dirHandle) throw new Error('File not found: ' + args.path);
            const name = getFileName(args.path);
            try {
                const fileHandle = await dirHandle.getFileHandle(name);
                const file = await fileHandle.getFile();
                const buffer = await file.arrayBuffer();
                return { bytes: Array.from(new Uint8Array(buffer)) };
            } catch (e) {
                if (e.name === 'NotFoundError') throw new Error('File not found: ' + args.path);
                throw e;
            }
        }

        case 'readFileChunk': {
            const dirHandle = await getParentDir(args.path);
            if (!dirHandle) throw new Error('File not found: ' + args.path);
            const name = getFileName(args.path);
            try {
                const fileHandle = await dirHandle.getFileHandle(name);
                const file = await fileHandle.getFile();
                const slice = file.slice(args.offset, args.offset + args.length);
                const buffer = await slice.arrayBuffer();
                return {
                    bytes: Array.from(new Uint8Array(buffer)),
                    totalSize: file.size,
                };
            } catch (e) {
                if (e.name === 'NotFoundError') throw new Error('File not found: ' + args.path);
                throw e;
            }
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
            const srcDir = await getParentDir(args.sourcePath);
            if (!srcDir) throw new Error('Source file not found: ' + args.sourcePath);
            const srcName = getFileName(args.sourcePath);
            const srcHandle = await srcDir.getFileHandle(srcName);
            const srcFile = await srcHandle.getFile();

            const destDir = await ensureParentDir(args.destPath);
            const destName = getFileName(args.destPath);
            const destHandle = await destDir.getFileHandle(destName, { create: true });
            const writable = await destHandle.createWritable();

            const chunkSize = 65536;
            let offset = 0;
            try {
                while (offset < srcFile.size) {
                    const end = Math.min(offset + chunkSize, srcFile.size);
                    const slice = srcFile.slice(offset, end);
                    const chunk = await slice.arrayBuffer();
                    await writable.write(new Uint8Array(chunk));
                    offset = end;
                }
                await writable.close();
            } catch (e) {
                try { await writable.abort(); } catch (_) {}
                throw e;
            }
            return true;
        }

        case 'moveFile': {
            await handleMessage('copyFile', args);
            await handleMessage('deleteFile', { path: args.sourcePath });
            return true;
        }

        // ── Streamed write (begin/chunk/end protocol) ──

        case 'beginStreamWrite': {
            const dirHandle = await ensureParentDir(args.path);
            const name = getFileName(args.path);
            const fileHandle = await dirHandle.getFileHandle(name, { create: true });
            const writable = await fileHandle.createWritable();
            const streamId = args.streamId;
            activeWritables.set(streamId, writable);
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

        // ── Directory operations ──

        case 'createDirectory': {
            await ensureDir(args.path);
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
            const dirHandle = await navigateToDir(args.path);
            const entries = [];
            for await (const [name] of dirHandle.entries()) {
                const prefix = args.path.endsWith('/') ? args.path : args.path + '/';
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

            try {
                await parentDir.removeEntry(dirName, { recursive: args.recursive || false });
            } catch (e) {
                if (e.name !== 'NotFoundError') throw e;
            }
            return true;
        }

        // ── File info ──

        case 'getFileSize': {
            const dirHandle = await getParentDir(args.path);
            if (!dirHandle) return -1;
            const name = getFileName(args.path);
            try {
                const fileHandle = await dirHandle.getFileHandle(name);
                const file = await fileHandle.getFile();
                return file.size;
            } catch (e) {
                if (e.name === 'NotFoundError') return -1;
                throw e;
            }
        }

        default:
            throw new Error('Unknown method: ' + method);
    }
}

// ── OPFS path helpers ──
// All paths are relative to the 'files/' OPFS root.

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
