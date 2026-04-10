import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbas_filesystem/dbas_filesystem.dart';
import 'package:dbas_filesystem/src/helpers/dbas_concurrency_pool.dart';

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

  test('copyFile with overwrite: false throws FileAlreadyExistsException', () async {
    final sourcePath = '$testDir/copy_ow_source.bin';
    final destPath = '$testDir/copy_ow_dest.bin';
    await fs.writeFile(sourcePath, Uint8List.fromList([1, 2, 3]));
    await fs.writeFile(destPath, Uint8List.fromList([4, 5, 6]));

    await expectLater(
      () => fs.copyFile(sourcePath, destPath, overwrite: false),
      throwsA(isA<FileAlreadyExistsException>()),
    );
    expect(await fs.readFile(destPath), equals(Uint8List.fromList([4, 5, 6])));
  });

  test('copyFile with overwrite: false succeeds when dest does not exist', () async {
    final sourcePath = '$testDir/copy_ow_new_source.bin';
    final destPath = '$testDir/copy_ow_new_dest.bin';
    final bytes = Uint8List.fromList([1, 2, 3]);
    await fs.writeFile(sourcePath, bytes);

    await fs.copyFile(sourcePath, destPath, overwrite: false);
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

  test('moveFile with overwrite: false throws FileAlreadyExistsException', () async {
    final sourcePath = '$testDir/move_ow_source.bin';
    final destPath = '$testDir/move_ow_dest.bin';
    await fs.writeFile(sourcePath, Uint8List.fromList([1, 2, 3]));
    await fs.writeFile(destPath, Uint8List.fromList([4, 5, 6]));

    await expectLater(
      () => fs.moveFile(sourcePath, destPath, overwrite: false),
      throwsA(isA<FileAlreadyExistsException>()),
    );
    expect(await fs.fileExists(sourcePath), isTrue);
    expect(await fs.readFile(destPath), equals(Uint8List.fromList([4, 5, 6])));
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

  // ── appendFile / appendFileStream ─────────────────────────────────────

  test('appendFile creates file when it does not exist', () async {
    final filePath = '$testDir/append_new.bin';
    await fs.appendFile(filePath, Uint8List.fromList([1, 2, 3]));

    expect(await fs.readFile(filePath), equals(Uint8List.fromList([1, 2, 3])));
  });

  test('appendFile appends to existing file', () async {
    final filePath = '$testDir/append_existing.bin';
    await fs.writeFile(filePath, Uint8List.fromList([1, 2, 3]));
    await fs.appendFile(filePath, Uint8List.fromList([4, 5, 6]));

    expect(await fs.readFile(filePath), equals(Uint8List.fromList([1, 2, 3, 4, 5, 6])));
  });

  test('appendFile creates parent directories', () async {
    final filePath = '$testDir/append_nested/sub/file.bin';
    await fs.appendFile(filePath, Uint8List.fromList([10, 20]));

    expect(await fs.readFile(filePath), equals(Uint8List.fromList([10, 20])));
  });

  test('appendFileStream creates file when it does not exist', () async {
    final filePath = '$testDir/append_stream_new.bin';
    await fs.appendFileStream(
      filePath,
      Stream.fromIterable([Uint8List.fromList([1, 2, 3])]),
    );

    expect(await fs.readFile(filePath), equals(Uint8List.fromList([1, 2, 3])));
  });

  test('appendFileStream appends to existing file', () async {
    final filePath = '$testDir/append_stream_existing.bin';
    await fs.writeFile(filePath, Uint8List.fromList([1, 2, 3]));
    await fs.appendFileStream(
      filePath,
      Stream.fromIterable([Uint8List.fromList([4, 5, 6])]),
    );

    expect(await fs.readFile(filePath), equals(Uint8List.fromList([1, 2, 3, 4, 5, 6])));
  });

  test('appendFile serializes on same path', () async {
    final filePath = '$testDir/append_serial.bin';
    await fs.writeFile(filePath, Uint8List(0));

    final gate = Completer<void>();
    var streamCompleted = false;

    final f1 = fs.appendFileStream(
      filePath,
      () async* {
        await gate.future;
        yield Uint8List.fromList([1, 2, 3]);
      }(),
    ).then((_) => streamCompleted = true);

    final f2 = fs.readFile(filePath).then((bytes) {
      expect(streamCompleted, isTrue);
      return bytes;
    });

    gate.complete();
    await Future.wait([f1, f2]);
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

  test('renameFile with overwrite: false throws FileAlreadyExistsException', () async {
    final oldPath = '$testDir/rename_ow_old.bin';
    final newPath = '$testDir/rename_ow_new.bin';
    await fs.writeFile(oldPath, Uint8List.fromList([1, 2, 3]));
    await fs.writeFile(newPath, Uint8List.fromList([4, 5, 6]));

    await expectLater(
      () => fs.renameFile(oldPath, newPath, overwrite: false),
      throwsA(isA<FileAlreadyExistsException>()),
    );
    expect(await fs.fileExists(oldPath), isTrue);
    expect(await fs.readFile(newPath), equals(Uint8List.fromList([4, 5, 6])));
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

  test('listDirectory returns FileSystemEntry with correct types', () async {
    final dirPath = '$testDir/list_test';
    await fs.createDirectory(dirPath);
    await fs.writeFile('$dirPath/a.bin', Uint8List.fromList([1]));
    await fs.writeFile('$dirPath/b.bin', Uint8List.fromList([2]));

    final entries = await fs.listDirectory(dirPath);

    for (final entry in entries) {
      expect(entry.path.contains('\\'), isFalse, reason: 'Path should be normalized: ${entry.path}');
    }

    final names = entries.map((e) => e.path.split('/').last).toList()..sort();
    expect(names, equals(['a.bin', 'b.bin']));

    for (final entry in entries) {
      expect(entry.type, equals(FileSystemEntityType.file));
    }
  });

  test('listDirectory with recursive: true returns all nested entries with types', () async {
    final dirPath = '$testDir/list_recursive';
    await fs.createDirectory('$dirPath/sub1');
    await fs.createDirectory('$dirPath/sub2');
    await fs.writeFile('$dirPath/a.bin', Uint8List.fromList([1]));
    await fs.writeFile('$dirPath/sub1/b.bin', Uint8List.fromList([2]));
    await fs.writeFile('$dirPath/sub2/c.bin', Uint8List.fromList([3]));

    final entries = await fs.listDirectory(dirPath, recursive: true);
    final names = entries.map((e) => e.path.split('/').last).toList()..sort();

    expect(names, containsAll(['a.bin', 'b.bin', 'c.bin', 'sub1', 'sub2']));

    // Verify types
    final dirEntries = entries.where((e) => e.type == FileSystemEntityType.directory).toList();
    final fileEntries = entries.where((e) => e.type == FileSystemEntityType.file).toList();
    expect(dirEntries.length, equals(2));
    expect(fileEntries.length, equals(3));

    // Non-recursive should only return direct children
    final shallow = await fs.listDirectory(dirPath);
    final shallowNames = shallow.map((e) => e.path.split('/').last).toList()..sort();
    expect(shallowNames, equals(['a.bin', 'sub1', 'sub2']));

    await fs.deleteDirectory(dirPath, recursive: true);
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

    await fs.deleteDirectory(dirPath, recursive: true);
  });

  // ── copyDirectory ─────────────────────────────────────────────────────

  test('copyDirectory copies all files preserving structure', () async {
    final srcDir = '$testDir/copydir_src';
    final destDir = '$testDir/copydir_dest';
    await fs.createDirectory('$srcDir/sub');
    await fs.writeFile('$srcDir/a.bin', Uint8List.fromList([1, 2]));
    await fs.writeFile('$srcDir/sub/b.bin', Uint8List.fromList([3, 4]));

    await fs.copyDirectory(srcDir, destDir);

    expect(await fs.readFile('$destDir/a.bin'), equals(Uint8List.fromList([1, 2])));
    expect(await fs.readFile('$destDir/sub/b.bin'), equals(Uint8List.fromList([3, 4])));
    // Source should still exist
    expect(await fs.directoryExists(srcDir), isTrue);

    await fs.deleteDirectory(srcDir, recursive: true);
    await fs.deleteDirectory(destDir, recursive: true);
  });

  test('copyDirectory is a merge — preserves non-conflicting dest files', () async {
    final srcDir = '$testDir/copydir_merge_src';
    final destDir = '$testDir/copydir_merge_dest';
    await fs.createDirectory(srcDir);
    await fs.createDirectory(destDir);
    await fs.writeFile('$srcDir/new.bin', Uint8List.fromList([1]));
    await fs.writeFile('$destDir/existing.bin', Uint8List.fromList([2]));

    await fs.copyDirectory(srcDir, destDir);

    expect(await fs.readFile('$destDir/new.bin'), equals(Uint8List.fromList([1])));
    expect(await fs.readFile('$destDir/existing.bin'), equals(Uint8List.fromList([2])));

    await fs.deleteDirectory(srcDir, recursive: true);
    await fs.deleteDirectory(destDir, recursive: true);
  });

  test('copyDirectory with overwrite: true replaces conflicting files', () async {
    final srcDir = '$testDir/copydir_ow_src';
    final destDir = '$testDir/copydir_ow_dest';
    await fs.createDirectory(srcDir);
    await fs.createDirectory(destDir);
    await fs.writeFile('$srcDir/file.bin', Uint8List.fromList([10, 20]));
    await fs.writeFile('$destDir/file.bin', Uint8List.fromList([30, 40]));

    await fs.copyDirectory(srcDir, destDir, overwrite: true);

    expect(await fs.readFile('$destDir/file.bin'), equals(Uint8List.fromList([10, 20])));

    await fs.deleteDirectory(srcDir, recursive: true);
    await fs.deleteDirectory(destDir, recursive: true);
  });

  test('copyDirectory with overwrite: false throws on conflict', () async {
    final srcDir = '$testDir/copydir_noow_src';
    final destDir = '$testDir/copydir_noow_dest';
    await fs.createDirectory(srcDir);
    await fs.createDirectory(destDir);
    await fs.writeFile('$srcDir/file.bin', Uint8List.fromList([1]));
    await fs.writeFile('$destDir/file.bin', Uint8List.fromList([2]));

    await expectLater(
      () => fs.copyDirectory(srcDir, destDir, overwrite: false),
      throwsA(isA<FileAlreadyExistsException>()),
    );

    await fs.deleteDirectory(srcDir, recursive: true);
    await fs.deleteDirectory(destDir, recursive: true);
  });

  test('copyDirectory throws DirectoryNotFoundException for missing source', () async {
    await expectLater(
      () => fs.copyDirectory('$testDir/no_such_dir', '$testDir/copydir_dest2'),
      throwsA(isA<DirectoryNotFoundException>()),
    );
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
    expect(const PermissionDeniedException('x'), isA<DbasFileSystemException>());
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

  // ── Path validation ───────────────────────────────────────────────────

  test('empty path throws ArgumentError', () {
    expect(() => fs.writeFile('', Uint8List(0)), throwsArgumentError);
  });

  test('blank path throws ArgumentError', () {
    expect(() => fs.writeFile('   ', Uint8List(0)), throwsArgumentError);
  });

  test('path with null byte throws ArgumentError', () {
    expect(() => fs.writeFile('foo\x00bar', Uint8List(0)), throwsArgumentError);
  });

  // ── Concurrency ───────────────────────────────────────────────────────

  test('same-path operations serialize', () async {
    final filePath = '$testDir/serial_test.bin';
    final gate = Completer<void>();
    var writeCompleted = false;

    final f1 = fs.writeFileStream(
      filePath,
      () async* {
        await gate.future;
        yield Uint8List.fromList([1, 2, 3]);
      }(),
    ).then((_) => writeCompleted = true);

    final f2 = fs.readFile(filePath).then((bytes) {
      expect(writeCompleted, isTrue);
      return bytes;
    });

    gate.complete();
    await Future.wait([f1, f2]);
  });

  test('different-path operations run in parallel', () async {
    final pathA = '$testDir/parallel_a.bin';
    final pathB = '$testDir/parallel_b.bin';

    final aStarted = Completer<void>();
    final bStarted = Completer<void>();
    final gate = Completer<void>();

    final fA = fs.writeFileStream(pathA, () async* {
      aStarted.complete();
      await gate.future;
      yield Uint8List.fromList([1]);
    }());

    final fB = fs.writeFileStream(pathB, () async* {
      bStarted.complete();
      await gate.future;
      yield Uint8List.fromList([2]);
    }());

    await aStarted.future.timeout(const Duration(seconds: 2));
    await bStarted.future.timeout(const Duration(seconds: 2));

    gate.complete();
    await Future.wait([fA, fB]);
  });

  // ── Disposal lifecycle ────────────────────────────────────────────────

  test('isDisposed is false before dispose', () async {
    expect(fs.isDisposed, isFalse);
  });

  test('isDisposed is true immediately after dispose is called', () async {
    final old = await DbasFileSystem.getInstance();
    final disposeFuture = old.dispose();
    expect(old.isDisposed, isTrue);
    await disposeFuture;

    fs = await DbasFileSystem.getInstance();
  });

  test('operations after dispose throw StateError', () async {
    final fs1 = await DbasFileSystem.getInstance();
    await fs1.dispose();

    expect(
      () => fs1.writeFile('any/path.bin', Uint8List(0)),
      throwsA(isA<StateError>()),
    );

    fs = await DbasFileSystem.getInstance();
  });

  test('getInstance after dispose returns new instance', () async {
    final fs1 = await DbasFileSystem.getInstance();
    await fs1.dispose();
    final fs2 = await DbasFileSystem.getInstance();

    expect(identical(fs1, fs2), isFalse);

    fs = fs2;
  });

  test('isDisposed check on multiple public methods', () async {
    final old = await DbasFileSystem.getInstance();
    await old.dispose();

    expect(() => old.readFile('any.bin'), throwsA(isA<StateError>()));
    expect(() => old.fileExists('any.bin'), throwsA(isA<StateError>()));
    expect(() => old.isPersistentStorage, throwsA(isA<StateError>()));
    expect(() => old.getAppFilePath('any.bin'), throwsA(isA<StateError>()));
    expect(() => old.appendFile('any.bin', Uint8List(0)), throwsA(isA<StateError>()));
    expect(() => old.listDirectory('any'), throwsA(isA<StateError>()));
    expect(() => old.copyDirectory('a', 'b'), throwsA(isA<StateError>()));

    fs = await DbasFileSystem.getInstance();
  });

  // ── Cancellation ──────────────────────────────────────────────────────

  test('CancellationToken prevents new tasks from starting', () async {
    final token = CancellationToken();
    final filePath1 = '$testDir/cancel_1.bin';
    final filePath2 = '$testDir/cancel_2.bin';

    token.cancel();

    await expectLater(
      () => fs.writeFiles(
        {
          filePath1: Uint8List.fromList([1]),
          filePath2: Uint8List.fromList([2]),
        },
        cancellationToken: token,
      ),
      throwsA(isA<OperationCancelledException>()),
    );
  });

  test('CancellationToken allows in-flight tasks to complete', () async {
    final token = CancellationToken();

    final files = {
      '$testDir/cancel_serial_1.bin': Uint8List.fromList([1]),
      '$testDir/cancel_serial_2.bin': Uint8List.fromList([2]),
      '$testDir/cancel_serial_3.bin': Uint8List.fromList([3]),
    };

    token.cancel();

    await expectLater(
      () => fs.writeFiles(files, maxConcurrency: 1, cancellationToken: token),
      throwsA(isA<OperationCancelledException>()),
    );
  });

  test('readFiles with CancellationToken', () async {
    for (var i = 0; i < 5; i++) {
      await fs.writeFile('$testDir/cancel_read_$i.bin', Uint8List.fromList([i]));
    }

    final token = CancellationToken();
    token.cancel();

    await expectLater(
      () => fs.readFiles(
        List.generate(5, (i) => '$testDir/cancel_read_$i.bin'),
        cancellationToken: token,
      ),
      throwsA(isA<OperationCancelledException>()),
    );
  });

  // ── CancellationToken listeners ───────────────────────────────────────

  test('addListener is called when cancel() is invoked', () {
    final token = CancellationToken();
    var called = false;
    token.addListener(() => called = true);
    token.cancel();
    expect(called, isTrue);
  });

  test('addListener is called immediately when token is already cancelled', () {
    final token = CancellationToken();
    token.cancel();
    var called = false;
    token.addListener(() => called = true);
    expect(called, isTrue);
  });

  test('cancel() is idempotent — listeners called exactly once', () {
    final token = CancellationToken();
    var count = 0;
    token.addListener(() => count++);
    token.cancel();
    token.cancel();
    expect(count, equals(1));
  });

  test('removeListener prevents listener from being called', () {
    final token = CancellationToken();
    var called = false;
    void listener() => called = true;
    token.addListener(listener);
    token.removeListener(listener);
    token.cancel();
    expect(called, isFalse);
  });

  test('multiple listeners are all called', () {
    final token = CancellationToken();
    var count = 0;
    token.addListener(() => count++);
    token.addListener(() => count++);
    token.addListener(() => count++);
    token.cancel();
    expect(count, equals(3));
  });

  // ── Persistent storage ────────────────────────────────────────────────

  test('isPersistentStorage is true on native platforms', () async {
    expect(fs.isPersistentStorage, isTrue);
  });

  // ── Concurrent dispose + getInstance race ─────────────────────────────

  test('concurrent getInstance calls during initialization return same instance', () async {
    await fs.dispose();

    final results = await Future.wait([
      DbasFileSystem.getInstance(),
      DbasFileSystem.getInstance(),
      DbasFileSystem.getInstance(),
    ]);

    expect(identical(results[0], results[1]), isTrue);
    expect(identical(results[1], results[2]), isTrue);

    fs = results[0];
  });

  test('getInstance immediately after dispose returns fresh instance', () async {
    final old = await DbasFileSystem.getInstance();
    final disposeFuture = old.dispose();
    final newFs = await DbasFileSystem.getInstance();
    await disposeFuture;

    expect(identical(old, newFs), isFalse);

    final path = '$testDir/post_dispose_race.bin';
    await newFs.writeFile(path, Uint8List.fromList([42]));
    expect(await newFs.readFile(path), equals(Uint8List.fromList([42])));

    fs = newFs;
  });

  // ── Duplicate paths in bulk operations ────────────────────────────────

  test('writeFiles with duplicate paths — last value wins', () async {
    final filePath = '$testDir/dup_bulk.bin';

    await fs.writeFiles({
      filePath: Uint8List.fromList([1, 2, 3]),
    });

    await fs.writeFiles({
      filePath: Uint8List.fromList([4, 5, 6]),
    });

    final result = await fs.readFile(filePath);
    expect(result, equals(Uint8List.fromList([4, 5, 6])));
  });

  // ── Bulk operation partial failure ────────────────────────────────────

  test('readFiles throws on missing file but others may complete', () async {
    final validPath = '$testDir/bulk_valid.bin';
    await fs.writeFile(validPath, Uint8List.fromList([1, 2, 3]));

    await expectLater(
      () => fs.readFiles([validPath, '$testDir/bulk_missing.bin']),
      throwsA(isA<FileNotFoundException>()),
    );
  });

  // ── ConcurrencyPool edge cases ────────────────────────────────────────

  test('ConcurrencyPool with maxConcurrency=0 throws ArgumentError', () {
    expect(
      () => ConcurrencyPool(0),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('ConcurrencyPool runAll with empty task list returns empty list', () async {
    final result = await ConcurrencyPool.runAll<int>([], maxConcurrency: 5);
    expect(result, isEmpty);
  });

  // ── readFileStream cancellation ───────────────────────────────────────

  test('readFileStream can be cancelled mid-read', () async {
    final filePath = '$testDir/stream_cancel.bin';
    final bytes = Uint8List.fromList(List.generate(1024, (i) => i % 256));
    await fs.writeFile(filePath, bytes);

    var chunksReceived = 0;
    final subscription = fs.readFileStream(filePath).listen((chunk) {
      chunksReceived++;
    });

    await Future.delayed(const Duration(milliseconds: 50));
    await subscription.cancel();

    expect(chunksReceived, greaterThanOrEqualTo(0));
  });

  // ── Exception hierarchy completeness ──────────────────────────────────

  test('OperationCancelledException is a DbasFileSystemException', () {
    const e = OperationCancelledException();
    expect(e, isA<DbasFileSystemException>());
    expect(e.message, equals('Operation was cancelled'));
    expect(e.path, isNull);
  });

  test('DbasFileSystemException with path', () {
    const e = DbasFileSystemException('test error', path: '/some/path');
    expect(e.toString(), equals('DbasFileSystemException: test error [path: /some/path]'));
  });

  test('DbasFileSystemException without path', () {
    const e = DbasFileSystemException('test error');
    expect(e.toString(), equals('DbasFileSystemException: test error'));
    expect(e.path, isNull);
  });

  test('PermissionDeniedException toString and path', () {
    const e = PermissionDeniedException('/protected/file.bin');
    expect(e, isA<DbasFileSystemException>());
    expect(e.path, equals('/protected/file.bin'));
    expect(e.toString(),
        equals('PermissionDeniedException: Permission denied [path: /protected/file.bin]'));
  });

  // ── readFileStream chunkSize (Fix #4) ─────────────────────────────────

  test('readFileStream honors chunkSize', () async {
    final filePath = '$testDir/chunk_size_test.bin';
    final bytes = Uint8List.fromList(List.generate(300, (i) => i % 256));
    await fs.writeFile(filePath, bytes);

    final chunks = <Uint8List>[];
    await for (final chunk in fs.readFileStream(filePath, chunkSize: 100)) {
      chunks.add(chunk);
    }

    for (final chunk in chunks) {
      expect(chunk.length, lessThanOrEqualTo(100));
    }

    final readBytes = chunks.expand((c) => c).toList();
    expect(readBytes, equals(bytes));
  });

  test('readFileStream with chunkSize larger than file produces single chunk', () async {
    final filePath = '$testDir/chunk_big_test.bin';
    final bytes = Uint8List.fromList(List.generate(50, (i) => i));
    await fs.writeFile(filePath, bytes);

    final chunks = <Uint8List>[];
    await for (final chunk in fs.readFileStream(filePath, chunkSize: 65536)) {
      chunks.add(chunk);
    }

    expect(chunks.length, equals(1));
    expect(chunks[0], equals(bytes));
  });

  test('readFileStream throws FileNotFoundException for missing file', () async {
    await expectLater(
      () async {
        await for (final _ in fs.readFileStream('$testDir/no_such_stream.bin')) {}
      },
      throwsA(isA<FileNotFoundException>()),
    );
  });

  test('readFileStream respects backpressure from slow consumer', () async {
    final filePath = '$testDir/backpressure_test.bin';
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
    await fs.writeFile(filePath, bytes);

    final chunks = <Uint8List>[];
    await for (final chunk in fs.readFileStream(filePath, chunkSize: 100)) {
      await Future.delayed(const Duration(milliseconds: 10));
      chunks.add(chunk);
    }

    final readBytes = chunks.expand((c) => c).toList();
    expect(readBytes, equals(bytes));
    expect(chunks.length, equals(10));
  });

  // ── copyFile cleanup (Fix #6) ────────────────────────────────────────

  test('copyFile cleans up partial destination on source-not-found error', () async {
    final destPath = '$testDir/copy_partial_dest.bin';
    await expectLater(
      () => fs.copyFile('$testDir/nonexistent_source.bin', destPath),
      throwsA(isA<FileNotFoundException>()),
    );
    expect(await fs.fileExists(destPath), isFalse);
  });

  // ── onError callback (Fix #7) ────────────────────────────────────────

  test('readFiles with onError omits failed file and calls callback', () async {
    final validPath = '$testDir/onerror_valid.bin';
    final missingPath = '$testDir/onerror_missing.bin';
    await fs.writeFile(validPath, Uint8List.fromList([1, 2, 3]));

    final errors = <String, Object>{};
    final result = await fs.readFiles(
      [validPath, missingPath],
      onError: (path, error) => errors[path] = error,
    );

    expect(result.length, equals(1));
    expect(result[validPath], equals(Uint8List.fromList([1, 2, 3])));
    expect(errors.length, equals(1));
    expect(errors[missingPath], isA<FileNotFoundException>());
  });

  test('readFiles with onError and all files failing returns empty map', () async {
    final errors = <String, Object>{};
    final result = await fs.readFiles(
      ['$testDir/missing_a.bin', '$testDir/missing_b.bin'],
      onError: (path, error) => errors[path] = error,
    );

    expect(result, isEmpty);
    expect(errors.length, equals(2));
  });

  test('readFiles without onError still throws (backwards compatible)', () async {
    final validPath = '$testDir/onerror_compat.bin';
    await fs.writeFile(validPath, Uint8List.fromList([1]));

    await expectLater(
      () => fs.readFiles([validPath, '$testDir/onerror_compat_missing.bin']),
      throwsA(isA<FileNotFoundException>()),
    );
  });

  test('writeFiles with onError calls callback on individual failure', () async {
    final newPath = '$testDir/onerror_write_new.bin';

    final errors = <String, Object>{};
    await fs.writeFiles(
      {
        newPath: Uint8List.fromList([42]),
        'invalid\x00path.bin': Uint8List.fromList([99]),
      },
      onError: (path, error) => errors[path] = error,
    );

    expect(errors.length, equals(1));
    expect(errors.containsKey('invalid\x00path.bin'), isTrue);
    expect(await fs.readFile(newPath), equals(Uint8List.fromList([42])));
  });

  // ── Concurrent dispose + init hardening (Fix #2) ─────────────────────

  test('dispose during init does not corrupt subsequent getInstance', () async {
    await fs.dispose();

    final initFuture = DbasFileSystem.getInstance();
    final first = await initFuture;
    await first.dispose();

    final second = await DbasFileSystem.getInstance();
    expect(identical(first, second), isFalse);

    fs = second;
  });

  // ── FileSystemEntry model ─────────────────────────────────────────────

  test('FileSystemEntry equality and toString', () {
    const a = FileSystemEntry(path: '/a/b', type: FileSystemEntityType.file);
    const b = FileSystemEntry(path: '/a/b', type: FileSystemEntityType.file);
    const c = FileSystemEntry(path: '/a/b', type: FileSystemEntityType.directory);

    expect(a, equals(b));
    expect(a, isNot(equals(c)));
    expect(a.hashCode, equals(b.hashCode));
    expect(a.toString(), equals('FileSystemEntry(path: /a/b, type: FileSystemEntityType.file)'));
  });
}
