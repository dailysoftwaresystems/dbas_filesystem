import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dbas_filesystem/dbas_filesystem.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _runExample();
  }

  Future<void> _runExample() async {
    final fs = await DbasFileSystem.getInstance();
    final filePath = await fs.getAppFilePath('example.bin');

    final bytes = Uint8List.fromList([72, 101, 108, 108, 111]); // "Hello"
    await fs.writeFile(filePath, bytes);

    final content = await fs.readFile(filePath);

    if (!mounted) return;
    setState(() {
      _status = 'Wrote ${bytes.length} bytes, read back ${content.length} bytes';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('DbasFileSystem Example')),
        body: Center(child: Text(_status)),
      ),
    );
  }
}
