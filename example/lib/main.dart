import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dbas_filesystem/dbas_filesystem.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DbasFileSystem Example',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const FileSystemDemo(),
    );
  }
}

class FileSystemDemo extends StatefulWidget {
  const FileSystemDemo({super.key});

  @override
  State<FileSystemDemo> createState() => _FileSystemDemoState();
}

class _FileSystemDemoState extends State<FileSystemDemo> {
  DbasFileSystem? _fs;
  String _basePath = '';
  List<_FileEntry> _files = [];
  bool _loading = true;
  String? _error;
  String? _previewContent;
  String? _previewName;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _fs = await DbasFileSystem.getInstance();
      _basePath = await _fs!.getAppFilePath('');
      await _fs!.createDirectory(_basePath);
      await _refreshFiles();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshFiles() async {
    setState(() => _loading = true);
    try {
      final entries = <_FileEntry>[];
      if (await _fs!.directoryExists(_basePath)) {
        final paths = await _fs!.listDirectory(_basePath);
        for (final path in paths) {
          final name = path.split('/').last.split('\\').last;
          final content = await _fs!.readFile(path);
          entries.add(_FileEntry(name: name, path: path, size: content.length));
        }
        entries.sort((a, b) => a.name.compareTo(b.name));
      }
      setState(() {
        _files = entries;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _writeTextFile() async {
    final controller = TextEditingController();
    final nameController = TextEditingController(text: 'example.txt');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Write Text File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'File name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Content'),
              maxLines: 5,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Write')),
        ],
      ),
    );

    if (result != true) return;

    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final bytes = utf8.encode(controller.text);
    final path = await _fs!.getAppFilePath(name);
    await _fs!.writeFile(path, bytes);
    await _refreshFiles();
  }

  Future<void> _writeBinaryFile() async {
    final nameController = TextEditingController(text: 'data.bin');
    final sizeController = TextEditingController(text: '1024');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Write Binary File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'File name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: sizeController,
              decoration: const InputDecoration(labelText: 'Size (bytes)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Write')),
        ],
      ),
    );

    if (result != true) return;

    final name = nameController.text.trim();
    final size = int.tryParse(sizeController.text.trim()) ?? 0;
    if (name.isEmpty || size <= 0) return;

    final bytes = Uint8List(size);
    for (int i = 0; i < size; i++) {
      bytes[i] = i % 256;
    }

    final path = await _fs!.getAppFilePath(name);
    await _fs!.writeFile(path, bytes);
    await _refreshFiles();
  }

  Future<void> _writeStreamFile() async {
    final nameController = TextEditingController(text: 'streamed.bin');
    final chunksController = TextEditingController(text: '10');
    final chunkSizeController = TextEditingController(text: '1024');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stream Write File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'File name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: chunksController,
              decoration: const InputDecoration(labelText: 'Number of chunks'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: chunkSizeController,
              decoration: const InputDecoration(labelText: 'Chunk size (bytes)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stream Write')),
        ],
      ),
    );

    if (result != true) return;

    final name = nameController.text.trim();
    final chunks = int.tryParse(chunksController.text.trim()) ?? 0;
    final chunkSize = int.tryParse(chunkSizeController.text.trim()) ?? 0;
    if (name.isEmpty || chunks <= 0 || chunkSize <= 0) return;

    Stream<List<int>> generateChunks() async* {
      for (int i = 0; i < chunks; i++) {
        final chunk = Uint8List(chunkSize);
        for (int j = 0; j < chunkSize; j++) {
          chunk[j] = (i * chunkSize + j) % 256;
        }
        yield chunk;
      }
    }

    final path = await _fs!.getAppFilePath(name);
    await _fs!.writeFileStream(path, generateChunks());
    await _refreshFiles();
  }

  Future<void> _readFile(_FileEntry entry) async {
    final content = await _fs!.readFile(entry.path);

    String preview;
    try {
      preview = utf8.decode(content, allowMalformed: false);
      if (preview.length > 2000) {
        preview = '${preview.substring(0, 2000)}\n... (${content.length} bytes total)';
      }
    } catch (_) {
      final hex = content.take(512).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      preview = 'Binary (${content.length} bytes):\n$hex';
      if (content.length > 512) {
        preview += '\n... (${content.length} bytes total)';
      }
    }

    setState(() {
      _previewContent = preview;
      _previewName = entry.name;
    });
  }

  Future<void> _readFileStream(_FileEntry entry) async {
    int totalBytes = 0;
    int chunkCount = 0;

    await for (final chunk in _fs!.readFileStream(entry.path)) {
      totalBytes += chunk.length;
      chunkCount++;
    }

    setState(() {
      _previewContent = 'Stream read complete:\n'
          '  Chunks: $chunkCount\n'
          '  Total bytes: $totalBytes';
      _previewName = entry.name;
    });
  }

  Future<void> _copyFile(_FileEntry entry) async {
    final nameController = TextEditingController(text: 'copy_${entry.name}');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy File'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Destination name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Copy')),
        ],
      ),
    );

    if (result != true) return;

    final destName = nameController.text.trim();
    if (destName.isEmpty) return;

    final destPath = await _fs!.getAppFilePath(destName);
    await _fs!.copyFile(entry.path, destPath);
    await _refreshFiles();
  }

  Future<void> _deleteFile(_FileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Delete "${entry.name}" (${_formatSize(entry.size)})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _fs!.deleteFile(entry.path);
    if (_previewName == entry.name) {
      setState(() {
        _previewContent = null;
        _previewName = null;
      });
    }
    await _refreshFiles();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DbasFileSystem Example'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fs != null ? _refreshFiles : null,
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(),
      floatingActionButton: _fs == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'stream',
                  onPressed: _writeStreamFile,
                  tooltip: 'Stream write',
                  child: const Icon(Icons.stream),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'binary',
                  onPressed: _writeBinaryFile,
                  tooltip: 'Write binary',
                  child: const Icon(Icons.memory),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'text',
                  onPressed: _writeTextFile,
                  tooltip: 'Write text file',
                  child: const Icon(Icons.note_add),
                ),
              ],
            ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            'Storage: $_basePath',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          flex: 3,
          child: _files.isEmpty
              ? const Center(child: Text('No files. Tap + to create one.'))
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final entry = _files[index];
                    final isSelected = _previewName == entry.name;
                    return ListTile(
                      leading: Icon(
                        entry.name.endsWith('.txt') ? Icons.description : Icons.insert_drive_file,
                      ),
                      title: Text(entry.name),
                      subtitle: Text(_formatSize(entry.size)),
                      selected: isSelected,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.stream, size: 20),
                            tooltip: 'Stream read',
                            onPressed: () => _readFileStream(entry),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            tooltip: 'Copy',
                            onPressed: () => _copyFile(entry),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20),
                            tooltip: 'Delete',
                            onPressed: () => _deleteFile(entry),
                          ),
                        ],
                      ),
                      onTap: () => _readFile(entry),
                    );
                  },
                ),
        ),
        if (_previewContent != null) ...[
          const Divider(height: 1),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _previewName ?? '',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _previewContent = null;
                          _previewName = null;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _previewContent!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FileEntry {
  final String name;
  final String path;
  final int size;

  _FileEntry({required this.name, required this.path, required this.size});
}
