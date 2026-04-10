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

  // ── Basic file operations ─────────────────────────────────────────────

  test('writeFile and readFile', () async {
    final filePath = '$testDir/test.bin';
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    await fs.writeFile(filePath, bytes);
    final result = await fs.readFile(filePath);

    expect(result, isA<Uint8List>());
    expect(result, equals(Uint8List.fromList([1, 2, 3, 4, 5])));
  });

  test('fileExists', () async {
    final filePath = '$testDir/exists_test.bin';
    expect(await fs.fileExists(filePath), isFalse);

    await fs.writeFile(filePath, Uint8List.fromList([10, 20]));
    expect(await fs.fileExists(filePath), isTrue);
  });

  test('deleteFile', () async {
    final filePath = '$testDir/delete_test.bin';
    await fs.writeFile(filePath, Uint8List.fromList([1, 2, 3]));
    expect(await fs.fileExists(filePath), isTrue);

    await fs.deleteFile(filePath);
    expect(await fs.fileExists(filePath), isFalse);
  });

  test('deleteFile on non-existent file is a no-op', () async {
    await fs.deleteFile('$testDir/does_not_exist.bin');
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

    expect(result, isA<Uint8List>());
    expect(result, equals(Uint8List.fromList([1, 2, 3, 4, 5, 6])));
  });

  test('readFileStream', () async {
    final filePath = '$testDir/stream_read.bin';
    final bytes = Uint8List.fromList(List.generate(100, (i) => i % 256));
    await fs.writeFile(filePath, bytes);

    final readBytes = <int>[];
    await for (final chunk in fs.readFileStream(filePath)) {
      expect(chunk, isA<Uint8List>());
      readBytes.addAll(chunk);
    }

    expect(readBytes, equals(bytes));
  });

  test('copyFile', () async {
    final sourcePath = '$testDir/copy_source.bin';
    final destPath = '$testDir/copy_dest.bin';
    final bytes = Uint8List.fromList([10, 20, 30, 40, 50]);

    await fs.writeFile(sourcePath, bytes);
    await fs.copyFile(sourcePath, destPath);

    expect(await fs.fileExists(destPath), isTrue);
    expect(await fs.readFile(destPath), equals(bytes));
  });

  test('moveFile', () async {
    final sourcePath = '$testDir/move_source.bin';
    final destPath = '$testDir/move_dest.bin';
    final bytes = Uint8List.fromList([10, 20, 30]);

    await fs.writeFile(sourcePath, bytes);
    await fs.moveFile(sourcePath, destPath);

    expect(await fs.fileExists(sourcePath), isFalse);
    expect(await fs.fileExists(destPath), isTrue);
    expect(await fs.readFile(destPath), equals(bytes));
  });

  // ── writeFile overwrite ───────────────────────────────────────────────

  test('writeFile with overwrite: true overwrites existing file', () async {
    final filePath = '$testDir/overwrite_test.bin';
    await fs.writeFile(filePath, Uint8List.fromList([1, 2, 3]));
    await fs.writeFile(filePath, Uint8List.fromList([4, 5, 6]), overwrite: true);

    expect(await fs.readFile(filePath), equals(Uint8List.fromList([4, 5, 6])));
  });

  test('writeFile with overwrite: false throws FileAlreadyExistsException', () async {
    final filePath = '$testDir/overwrite_false_test.bin';
    await fs.writeFile(filePath, Uint8List.fromList([1, 2, 3]));

    await expectLater(
      () => fs.writeFile(filePath, Uint8List.fromList([4, 5, 6]), overwrite: false),
      throwsA(isA<FileAlreadyExistsException>()),
    );
  });

  test('writeFile with overwrite: false succeeds on new file', () async {
    final filePath = '$testDir/overwrite_new.bin';
    await fs.writeFile(filePath, Uint8List.fromList([1, 2, 3]), overwrite: false);

    expect(await fs.readFile(filePath), equals(Uint8List.fromList([1, 2, 3])));
  });

  // ── writeFileStream overwrite ─────────────────────────────────────────

  test('writeFileStream with overwrite: true overwrites existing file', () async {
    final filePath = '$testDir/stream_overwrite_test.bin';
    await fs.writeFile(filePath, Uint8List.fromList([1, 2, 3]));
    await fs.writeFileStream(
      filePath,
      Stream.fromIterable([Uint8List.fromList([4, 5, 6])]),
      overwrite: true,
    );

    expect(await fs.readFile(filePath), equals(Uint8List.fromList([4, 5, 6])));
  });

  test('writeFileStream with overwrite: false throws FileAlreadyExistsException', () async {
    final filePath = '$testDir/stream_overwrite_false.bin';
    await fs.writeFile(filePath, Uint8List.fromList([1, 2, 3]));

    await expectLater(
      () => fs.writeFileStream(
        filePath,
        Stream.fromIterable([Uint8List.fromList([4, 5, 6])]),
        overwrite: false,
      ),
      throwsA(isA<FileAlreadyExistsException>()),
    );
  });

  test('writeFileStream with overwrite: false succeeds on new file', () async {
    final filePath = '$testDir/stream_overwrite_new.bin';
    await fs.writeFileStream(
      filePath,
      Stream.fromIterable([Uint8List.fromList([1, 2, 3])]),
      overwrite: false,
    );

    expect(await fs.readFile(filePath), equals(Uint8List.fromList([1, 2, 3])));
  });

  // ── File metadata ─────────────────────────────────────────────────────

  test('getFileSize returns correct byte count', () async {
    final filePath = '$testDir/size_test.bin';
    final bytes = Uint8List.fromList(List.generate(256, (i) => i));
    await fs.writeFile(filePath, bytes);

    final size = await fs.getFileSize(filePath);
    expect(size, equals(256));
  });

  test('getFileSize throws FileNotFoundException for missing file', () async {
    await expectLater(
      () => fs.getFileSize('$testDir/no_such_file.bin'),
      throwsA(isA<FileNotFoundException>()),
    );
  });

  test('getLastModified returns recent DateTime', () async {
    final filePath = '$testDir/modified_test.bin';
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
    await fs.writeFile(filePath, Uint8List.fromList([1, 2, 3]));
    final after = DateTime.now().toUtc().add(const Duration(seconds: 2));

    final modified = await fs.getLastModified(filePath);
    expect(modified.isAfter(before), isTrue);
    expect(modified.isBefore(after), isTrue);
  });

  test('getLastModified throws FileNotFoundException for missing file', () async {
    await expectLater(
      () => fs.getLastModified('$testDir/no_such_file.bin'),
      throwsA(isA<FileNotFoundException>()),
    );
  });

  // ── Rename ────────────────────────────────────────────────────────────

  test('renameFile moves content and removes old path', () async {
    final oldPath = '$testDir/rename_old.bin';
    final newPath = '$testDir/rename_new.bin';
    final bytes = Uint8List.fromList([10, 20, 30]);

    await fs.writeFile(oldPath, bytes);
    await fs.renameFile(oldPath, newPath);

    expect(await fs.fileExists(oldPath), isFalse);
    expect(await fs.fileExists(newPath), isTrue);
    expect(await fs.readFile(newPath), equals(bytes));
  });

  test('renameFile throws FileNotFoundException for missing source', () async {
    await expectLater(
      () => fs.renameFile('$testDir/no_such.bin', '$testDir/dest.bin'),
      throwsA(isA<FileNotFoundException>()),
    );
  });

  test('renameDirectory moves contents and removes old path', () async {
    final oldDir = '$testDir/rename_dir_old';
    final newDir = '$testDir/rename_dir_new';

    await fs.createDirectory(oldDir);
    await fs.writeFile('$oldDir/a.bin', Uint8List.fromList([1, 2]));
    await fs.writeFile('$oldDir/b.bin', Uint8List.fromList([3, 4]));

    await fs.renameDirectory(oldDir, newDir);

    expect(await fs.directoryExists(oldDir), isFalse);
    expect(await fs.directoryExists(newDir), isTrue);
    expect(await fs.readFile('$newDir/a.bin'), equals(Uint8List.fromList([1, 2])));
    expect(await fs.readFile('$newDir/b.bin'), equals(Uint8List.fromList([3, 4])));
  });

  test('renameDirectory throws DirectoryNotFoundException for missing source', () async {
    await expectLater(
      () => fs.renameDirectory('$testDir/no_such_dir', '$testDir/dest_dir'),
      throwsA(isA<DirectoryNotFoundException>()),
    );
  });

  // ── Bulk operations ───────────────────────────────────────────────────

  test('writeFiles and readFiles (bulk)', () async {
    final files = {
      '$testDir/bulk_1.bin': Uint8List.fromList([1, 2, 3]),
      '$testDir/bulk_2.bin': Uint8List.fromList([4, 5, 6]),
      '$testDir/bulk_3.bin': Uint8List.fromList([7, 8, 9]),
    };

    await fs.writeFiles(files);
    final result = await fs.readFiles(files.keys.toList());

    expect(result.length, equals(3));
    for (final entry in result.entries) {
      expect(entry.value, isA<Uint8List>());
    }
    expect(result['$testDir/bulk_1.bin'], equals(Uint8List.fromList([1, 2, 3])));
    expect(result['$testDir/bulk_2.bin'], equals(Uint8List.fromList([4, 5, 6])));
    expect(result['$testDir/bulk_3.bin'], equals(Uint8List.fromList([7, 8, 9])));
  });

  test('parallel bulk write with maxConcurrency', () async {
    final files = <String, Uint8List>{};
    for (var i = 0; i < 20; i++) {
      files['$testDir/parallel_$i.bin'] = Uint8List.fromList(List.generate(10, (j) => i + j));
    }

    await fs.writeFiles(files, maxConcurrency: 5);

    for (final entry in files.entries) {
      final content = await fs.readFile(entry.key);
      expect(content, equals(entry.value));
    }
  });

  test('parallel bulk read with maxConcurrency', () async {
    final files = <String, Uint8List>{};
    for (var i = 0; i < 20; i++) {
      final path = '$testDir/par_read_$i.bin';
      files[path] = Uint8List.fromList(List.generate(10, (j) => i + j));
      await fs.writeFile(path, files[path]!);
    }

    final result = await fs.readFiles(files.keys.toList(), maxConcurrency: 5);

    expect(result.length, equals(20));
    for (final entry in files.entries) {
      expect(result[entry.key], equals(entry.value));
    }
  });

  // ── Directory operations ──────────────────────────────────────────────

  test('createDirectory and directoryExists', () async {
    final dirPath = '$testDir/subdir/nested';
    expect(await fs.directoryExists(dirPath), isFalse);

    await fs.createDirectory(dirPath);
    expect(await fs.directoryExists(dirPath), isTrue);
  });

  test('listDirectory returns normalized forward-slash paths', () async {
    final dirPath = '$testDir/list_test';
    await fs.createDirectory(dirPath);
    await fs.writeFile('$dirPath/a.bin', Uint8List.fromList([1]));
    await fs.writeFile('$dirPath/b.bin', Uint8List.fromList([2]));

    final entries = await fs.listDirectory(dirPath);

    // All paths should use forward slashes
    for (final entry in entries) {
      expect(entry.contains('\\'), isFalse, reason: 'Path should be normalized: $entry');
    }

    final names = entries.map((e) => e.split('/').last).toList()..sort();
    expect(names, equals(['a.bin', 'b.bin']));
  });

  test('deleteDirectory', () async {
    final dirPath = '$testDir/delete_dir';
    await fs.createDirectory(dirPath);
    await fs.writeFile('$dirPath/file.bin', Uint8List.fromList([1]));

    await fs.deleteDirectory(dirPath, recursive: true);
    expect(await fs.directoryExists(dirPath), isFalse);
  });

  test('deleteDirectory non-recursive throws DirectoryNotEmptyException', () async {
    final dirPath = '$testDir/nonempty_dir';
    await fs.createDirectory(dirPath);
    await fs.writeFile('$dirPath/file.bin', Uint8List.fromList([1]));

    await expectLater(
      () => fs.deleteDirectory(dirPath, recursive: false),
      throwsA(isA<DirectoryNotEmptyException>()),
    );

    // Cleanup
    await fs.deleteDirectory(dirPath, recursive: true);
  });

  // ── Exception hierarchy ───────────────────────────────────────────────

  test('readFile throws FileNotFoundException for missing file', () async {
    await expectLater(
      () => fs.readFile('$testDir/nonexistent.bin'),
      throwsA(isA<FileNotFoundException>()),
    );
  });

  test('copyFile throws FileNotFoundException for missing source', () async {
    await expectLater(
      () => fs.copyFile('$testDir/nonexistent.bin', '$testDir/dest.bin'),
      throwsA(isA<FileNotFoundException>()),
    );
  });

  test('all custom exceptions implement DbasFileSystemException', () {
    expect(const FileNotFoundException('x'), isA<DbasFileSystemException>());
    expect(const DirectoryNotFoundException('x'), isA<DbasFileSystemException>());
    expect(const FileAlreadyExistsException('x'), isA<DbasFileSystemException>());
    expect(const DirectoryNotEmptyException('x'), isA<DbasFileSystemException>());
  });

  test('exception toString includes path once', () {
    final e = const FileNotFoundException('/some/path');
    final str = e.toString();
    expect(str, contains('/some/path'));
    expect(str, equals('FileNotFoundException: File not found [path: /some/path]'));
    expect(e.path, equals('/some/path'));
  });

  // ── Singleton ─────────────────────────────────────────────────────────

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
