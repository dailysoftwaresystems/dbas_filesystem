import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbas_filesystem/dbas_filesystem.dart';

void main() {
  late DbasFileSystem fs;
  late String testDir;

  setUpAll(() async {
    testDir = '${Directory.current.path}/test/files';
    final dir = Directory(testDir);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    dir.createSync(recursive: true);

    fs = await DbasFileSystem.getInstance();
  });

  tearDownAll(() {
    final dir = Directory(testDir);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('writeFile and readFile', () async {
    final filePath = '$testDir/test.bin';
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    await fs.writeFile(filePath, bytes);
    final result = await fs.readFile(filePath);

    expect(result, equals([1, 2, 3, 4, 5]));
  });

  test('fileExists', () async {
    final filePath = '$testDir/exists_test.bin';
    expect(await fs.fileExists(filePath), isFalse);

    await fs.writeFile(filePath, [10, 20]);
    expect(await fs.fileExists(filePath), isTrue);
  });

  test('deleteFile', () async {
    final filePath = '$testDir/delete_test.bin';
    await fs.writeFile(filePath, [1, 2, 3]);
    expect(await fs.fileExists(filePath), isTrue);

    await fs.deleteFile(filePath);
    expect(await fs.fileExists(filePath), isFalse);
  });

  test('writeFileStream and readFile', () async {
    final filePath = '$testDir/stream_write.bin';
    final chunks = [
      Uint8List.fromList([1, 2, 3]),
      Uint8List.fromList([4, 5, 6]),
    ];
    final stream = Stream.fromIterable(chunks);

    await fs.writeFileStream(filePath, stream);
    final result = await fs.readFile(filePath);

    expect(result, equals([1, 2, 3, 4, 5, 6]));
  });

  test('readFileStream', () async {
    final filePath = '$testDir/stream_read.bin';
    final bytes = Uint8List.fromList(List.generate(100, (i) => i % 256));
    await fs.writeFile(filePath, bytes);

    final readBytes = <int>[];
    await for (final chunk in fs.readFileStream(filePath)) {
      readBytes.addAll(chunk);
    }

    expect(readBytes, equals(bytes));
  });

  test('copyFile', () async {
    final sourcePath = '$testDir/copy_source.bin';
    final destPath = '$testDir/copy_dest.bin';
    final bytes = [10, 20, 30, 40, 50];

    await fs.writeFile(sourcePath, bytes);
    await fs.copyFile(sourcePath, destPath);

    expect(await fs.fileExists(destPath), isTrue);
    expect(await fs.readFile(destPath), equals(bytes));
  });

  test('moveFile', () async {
    final sourcePath = '$testDir/move_source.bin';
    final destPath = '$testDir/move_dest.bin';
    final bytes = [10, 20, 30];

    await fs.writeFile(sourcePath, bytes);
    await fs.moveFile(sourcePath, destPath);

    expect(await fs.fileExists(sourcePath), isFalse);
    expect(await fs.fileExists(destPath), isTrue);
    expect(await fs.readFile(destPath), equals(bytes));
  });

  test('writeFiles and readFiles (bulk)', () async {
    final files = {
      '$testDir/bulk_1.bin': <int>[1, 2, 3],
      '$testDir/bulk_2.bin': <int>[4, 5, 6],
      '$testDir/bulk_3.bin': <int>[7, 8, 9],
    };

    await fs.writeFiles(files);
    final result = await fs.readFiles(files.keys.toList());

    expect(result.length, equals(3));
    expect(result['$testDir/bulk_1.bin'], equals([1, 2, 3]));
    expect(result['$testDir/bulk_2.bin'], equals([4, 5, 6]));
    expect(result['$testDir/bulk_3.bin'], equals([7, 8, 9]));
  });

  test('createDirectory and directoryExists', () async {
    final dirPath = '$testDir/subdir/nested';
    expect(await fs.directoryExists(dirPath), isFalse);

    await fs.createDirectory(dirPath);
    expect(await fs.directoryExists(dirPath), isTrue);
  });

  test('listDirectory', () async {
    final dirPath = '$testDir/list_test';
    await fs.createDirectory(dirPath);
    await fs.writeFile('$dirPath/a.bin', [1]);
    await fs.writeFile('$dirPath/b.bin', [2]);

    final entries = await fs.listDirectory(dirPath);
    final names = entries.map((e) => e.split('/').last.split('\\').last).toList()..sort();

    expect(names, equals(['a.bin', 'b.bin']));
  });

  test('deleteDirectory', () async {
    final dirPath = '$testDir/delete_dir';
    await fs.createDirectory(dirPath);
    await fs.writeFile('$dirPath/file.bin', [1]);

    await fs.deleteDirectory(dirPath, recursive: true);
    expect(await fs.directoryExists(dirPath), isFalse);
  });

  test('getInstance returns same instance on subsequent calls', () async {
    final fs1 = await DbasFileSystem.getInstance();
    final fs2 = await DbasFileSystem.getInstance();
    expect(identical(fs1, fs2), isTrue);
  });

  test('getAppFilePath returns path under test/files/', () async {
    final filePath = await fs.getAppFilePath('test_file.bin');
    expect(filePath, contains('test'));
    expect(filePath, contains('files'));
    expect(filePath, endsWith('test_file.bin'));
  });
}
