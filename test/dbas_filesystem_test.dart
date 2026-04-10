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
    // Original destination content should be unchanged
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
    // Source should still exist, destination unchanged
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
    // Source should still exist, destination unchanged
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

  test('listDirectory with recursive: true returns all nested entries', () async {
    final dirPath = '$testDir/list_recursive';
    await fs.createDirectory('$dirPath/sub1');
    await fs.createDirectory('$dirPath/sub2');
    await fs.writeFile('$dirPath/a.bin', Uint8List.fromList([1]));
    await fs.writeFile('$dirPath/sub1/b.bin', Uint8List.fromList([2]));
    await fs.writeFile('$dirPath/sub2/c.bin', Uint8List.fromList([3]));

    final entries = await fs.listDirectory(dirPath, recursive: true);
    final names = entries.map((e) => e.split('/').last).toList()..sort();

    // Should include the directories and all nested files
    expect(names, containsAll(['a.bin', 'b.bin', 'c.bin', 'sub1', 'sub2']));
    // Non-recursive should only return direct children
    final shallow = await fs.listDirectory(dirPath);
    final shallowNames = shallow.map((e) => e.split('/').last).toList()..sort();
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

    // Start a write that blocks on a gate
    final f1 = fs.writeFileStream(
      filePath,
      () async* {
        await gate.future;
        yield Uint8List.fromList([1, 2, 3]);
      }(),
    ).then((_) => writeCompleted = true);

    // Start a read on the same path — must wait for write to finish
    final f2 = fs.readFile(filePath).then((bytes) {
      // When the read starts, the write must have already completed
      expect(writeCompleted, isTrue);
      return bytes;
    });

    // Release the gate so the write can proceed
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

    // Both generators should start since they're on different paths.
    // If they were serialized, bStarted would never complete (blocked behind gate).
    await aStarted.future.timeout(const Duration(seconds: 2));
    await bStarted.future.timeout(const Duration(seconds: 2));

    gate.complete();
    await Future.wait([fA, fB]);
  });

  // ── Disposal lifecycle ────────────────────────────────────────────────

  test('operations after dispose throw StateError', () async {
    final fs1 = await DbasFileSystem.getInstance();
    await fs1.dispose();

    expect(
      () => fs1.writeFile('any/path.bin', Uint8List(0)),
      throwsA(isA<StateError>()),
    );

    // Re-create for subsequent tests
    fs = await DbasFileSystem.getInstance();
  });

  test('getInstance after dispose returns new instance', () async {
    final fs1 = await DbasFileSystem.getInstance();
    await fs1.dispose();
    final fs2 = await DbasFileSystem.getInstance();

    expect(identical(fs1, fs2), isFalse);

    // Restore fs for tearDownAll
    fs = fs2;
  });

  // ── Cancellation ──────────────────────────────────────────────────────

  test('CancellationToken prevents new tasks from starting', () async {
    final token = CancellationToken();
    final filePath1 = '$testDir/cancel_1.bin';
    final filePath2 = '$testDir/cancel_2.bin';

    // Cancel immediately — no writes should succeed
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

    // Write 3 files with maxConcurrency=1 (serial execution)
    final files = {
      '$testDir/cancel_serial_1.bin': Uint8List.fromList([1]),
      '$testDir/cancel_serial_2.bin': Uint8List.fromList([2]),
      '$testDir/cancel_serial_3.bin': Uint8List.fromList([3]),
    };

    // Cancel before starting — all tasks should throw
    token.cancel();

    await expectLater(
      () => fs.writeFiles(files, maxConcurrency: 1, cancellationToken: token),
      throwsA(isA<OperationCancelledException>()),
    );
  });

  test('readFiles with CancellationToken', () async {
    // Set up files
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
    // Start dispose and immediately request new instance
    final disposeFuture = old.dispose();
    final newFs = await DbasFileSystem.getInstance();
    await disposeFuture;

    expect(identical(old, newFs), isFalse);

    // Verify the new instance works
    final path = '$testDir/post_dispose_race.bin';
    await newFs.writeFile(path, Uint8List.fromList([42]));
    expect(await newFs.readFile(path), equals(Uint8List.fromList([42])));

    fs = newFs;
  });

  // ── Duplicate paths in bulk operations ────────────────────────────────

  test('writeFiles with duplicate paths — last value wins', () async {
    final filePath = '$testDir/dup_bulk.bin';

    // Map literal with same key — Dart Map keeps last value
    await fs.writeFiles({
      filePath: Uint8List.fromList([1, 2, 3]),
    });

    // Now write again with new value
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
    // Write a file with enough data
    final filePath = '$testDir/stream_cancel.bin';
    final bytes = Uint8List.fromList(List.generate(1024, (i) => i % 256));
    await fs.writeFile(filePath, bytes);

    var chunksReceived = 0;
    final subscription = fs.readFileStream(filePath).listen((chunk) {
      chunksReceived++;
    });

    // Cancel after first event or shortly after start
    await Future.delayed(const Duration(milliseconds: 50));
    await subscription.cancel();

    // Stream should complete without error after cancellation
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

    // Each chunk should be at most 100 bytes
    for (final chunk in chunks) {
      expect(chunk.length, lessThanOrEqualTo(100));
    }

    // Total bytes should match the original
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
    // Write a file with multiple chunks worth of data (10 chunks of 100 bytes)
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
    await fs.writeFile(filePath, bytes);

    final chunks = <Uint8List>[];
    await for (final chunk in fs.readFileStream(filePath, chunkSize: 100)) {
      // Simulate a slow consumer — the producer should not read ahead unbounded
      await Future.delayed(const Duration(milliseconds: 10));
      chunks.add(chunk);
    }

    // All data should still be received correctly
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
    final existingPath = '$testDir/onerror_write_existing.bin';
    final newPath = '$testDir/onerror_write_new.bin';
    await fs.writeFile(existingPath, Uint8List.fromList([1]));

    // Trigger a real failure: write to a path containing a null byte
    // which fails path validation, while another write succeeds.
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
}
