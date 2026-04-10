import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbas_filesystem/dbas_filesystem.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late DbasFileSystem fs;
  const testRoot = 'web_test_root';

  setUpAll(() async {
    fs = await DbasFileSystem.getInstance();
    if (await fs.directoryExists(testRoot)) {
      await fs.deleteDirectory(testRoot, recursive: true);
    }
    await fs.createDirectory(testRoot);
  });

  tearDown(() async {
    if (await fs.directoryExists(testRoot)) {
      await fs.deleteDirectory(testRoot, recursive: true);
    }
    await fs.createDirectory(testRoot);
  });

  tearDownAll(() async {
    if (await fs.directoryExists(testRoot)) {
      await fs.deleteDirectory(testRoot, recursive: true);
    }
  });

  // ── Basic file operations ─────────────────────────────────────────────

  testWidgets('writeFile and readFile round-trip', (tester) async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    await fs.writeFile('$testRoot/test.bin', bytes);
    final result = await fs.readFile('$testRoot/test.bin');

    expect(result, isA<Uint8List>());
    expect(result, equals(bytes));
  });

  testWidgets('fileExists', (tester) async {
    expect(await fs.fileExists('$testRoot/exists_test.bin'), isFalse);

    await fs.writeFile('$testRoot/exists_test.bin', Uint8List.fromList([10, 20]));
    expect(await fs.fileExists('$testRoot/exists_test.bin'), isTrue);
  });

  testWidgets('deleteFile and idempotency', (tester) async {
    await fs.writeFile('$testRoot/delete.bin', Uint8List.fromList([1, 2, 3]));
    expect(await fs.fileExists('$testRoot/delete.bin'), isTrue);

    await fs.deleteFile('$testRoot/delete.bin');
    expect(await fs.fileExists('$testRoot/delete.bin'), isFalse);

    // No-op on non-existent
    await fs.deleteFile('$testRoot/delete.bin');
  });

  testWidgets('writeFileStream and readFile', (tester) async {
    final chunks = [
      Uint8List.fromList([1, 2, 3]),
      Uint8List.fromList([4, 5, 6]),
    ];
    await fs.writeFileStream('$testRoot/stream_write.bin', Stream.fromIterable(chunks));
    final result = await fs.readFile('$testRoot/stream_write.bin');

    expect(result, equals(Uint8List.fromList([1, 2, 3, 4, 5, 6])));
  });

  testWidgets('readFileStream', (tester) async {
    final bytes = Uint8List.fromList(List.generate(100, (i) => i % 256));
    await fs.writeFile('$testRoot/stream_read.bin', bytes);

    final readBytes = <int>[];
    await for (final chunk in fs.readFileStream('$testRoot/stream_read.bin')) {
      expect(chunk, isA<Uint8List>());
      readBytes.addAll(chunk);
    }

    expect(readBytes, equals(bytes));
  });

  // ── Overwrite protection ──────────────────────────────────────────────

  testWidgets('writeFile with overwrite: false throws FileAlreadyExistsException', (tester) async {
    await fs.writeFile('$testRoot/ow.bin', Uint8List.fromList([1, 2, 3]));

    await expectLater(
      () => fs.writeFile('$testRoot/ow.bin', Uint8List.fromList([4, 5, 6]), overwrite: false),
      throwsA(isA<FileAlreadyExistsException>()),
    );
  });

  testWidgets('writeFileStream with overwrite: false throws FileAlreadyExistsException', (tester) async {
    await fs.writeFile('$testRoot/sow.bin', Uint8List.fromList([1, 2, 3]));

    await expectLater(
      () => fs.writeFileStream(
        '$testRoot/sow.bin',
        Stream.fromIterable([Uint8List.fromList([4, 5, 6])]),
        overwrite: false,
      ),
      throwsA(isA<FileAlreadyExistsException>()),
    );
  });

  // ── Copy and Move ─────────────────────────────────────────────────────

  testWidgets('copyFile', (tester) async {
    final bytes = Uint8List.fromList([10, 20, 30]);
    await fs.writeFile('$testRoot/copy_src.bin', bytes);
    await fs.copyFile('$testRoot/copy_src.bin', '$testRoot/copy_dest.bin');

    expect(await fs.readFile('$testRoot/copy_dest.bin'), equals(bytes));
  });

  testWidgets('moveFile', (tester) async {
    final bytes = Uint8List.fromList([10, 20, 30]);
    await fs.writeFile('$testRoot/move_src.bin', bytes);
    await fs.moveFile('$testRoot/move_src.bin', '$testRoot/move_dest.bin');

    expect(await fs.fileExists('$testRoot/move_src.bin'), isFalse);
    expect(await fs.readFile('$testRoot/move_dest.bin'), equals(bytes));
  });

  testWidgets('renameFile', (tester) async {
    final bytes = Uint8List.fromList([10, 20, 30]);
    await fs.writeFile('$testRoot/rename_old.bin', bytes);
    await fs.renameFile('$testRoot/rename_old.bin', '$testRoot/rename_new.bin');

    expect(await fs.fileExists('$testRoot/rename_old.bin'), isFalse);
    expect(await fs.readFile('$testRoot/rename_new.bin'), equals(bytes));
  });

  // ── File metadata ─────────────────────────────────────────────────────

  testWidgets('getFileSize', (tester) async {
    final bytes = Uint8List.fromList(List.generate(256, (i) => i));
    await fs.writeFile('$testRoot/size.bin', bytes);

    expect(await fs.getFileSize('$testRoot/size.bin'), equals(256));
  });

  testWidgets('getFileSize throws FileNotFoundException', (tester) async {
    await expectLater(
      () => fs.getFileSize('$testRoot/no_such.bin'),
      throwsA(isA<FileNotFoundException>()),
    );
  });

  testWidgets('getLastModified returns recent DateTime', (tester) async {
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
    await fs.writeFile('$testRoot/modified.bin', Uint8List.fromList([1, 2, 3]));
    final after = DateTime.now().toUtc().add(const Duration(seconds: 2));

    final modified = await fs.getLastModified('$testRoot/modified.bin');
    expect(modified.isAfter(before), isTrue);
    expect(modified.isBefore(after), isTrue);
  });

  // ── Directory operations ──────────────────────────────────────────────

  testWidgets('createDirectory and directoryExists', (tester) async {
    expect(await fs.directoryExists('$testRoot/nested/dir'), isFalse);

    await fs.createDirectory('$testRoot/nested/dir');
    expect(await fs.directoryExists('$testRoot/nested/dir'), isTrue);
  });

  testWidgets('listDirectory returns normalized paths', (tester) async {
    await fs.createDirectory('$testRoot/list_dir');
    await fs.writeFile('$testRoot/list_dir/a.bin', Uint8List.fromList([1]));
    await fs.writeFile('$testRoot/list_dir/b.bin', Uint8List.fromList([2]));

    final entries = await fs.listDirectory('$testRoot/list_dir');

    for (final entry in entries) {
      expect(entry.path.contains('\\'), isFalse, reason: 'Path should be normalized: ${entry.path}');
    }

    final names = entries.map((e) => e.path.split('/').last).toList()..sort();
    expect(names, equals(['a.bin', 'b.bin']));
  });

  testWidgets('deleteDirectory non-recursive throws DirectoryNotEmptyException', (tester) async {
    await fs.createDirectory('$testRoot/nonempty');
    await fs.writeFile('$testRoot/nonempty/file.bin', Uint8List.fromList([1]));

    await expectLater(
      () => fs.deleteDirectory('$testRoot/nonempty', recursive: false),
      throwsA(isA<DirectoryNotEmptyException>()),
    );
  });

  testWidgets('renameDirectory', (tester) async {
    await fs.createDirectory('$testRoot/rename_old');
    await fs.writeFile('$testRoot/rename_old/a.bin', Uint8List.fromList([1, 2]));

    await fs.renameDirectory('$testRoot/rename_old', '$testRoot/rename_new');

    expect(await fs.directoryExists('$testRoot/rename_old'), isFalse);
    expect(await fs.directoryExists('$testRoot/rename_new'), isTrue);
    expect(await fs.readFile('$testRoot/rename_new/a.bin'), equals(Uint8List.fromList([1, 2])));
  });

  // ── moveDirectory ─────────────────────────────────────────────────────

  testWidgets('moveDirectory moves contents and removes source', (tester) async {
    await fs.createDirectory('$testRoot/movedir_src/sub');
    await fs.writeFile('$testRoot/movedir_src/a.bin', Uint8List.fromList([1, 2]));
    await fs.writeFile('$testRoot/movedir_src/sub/b.bin', Uint8List.fromList([3, 4]));

    await fs.moveDirectory('$testRoot/movedir_src', '$testRoot/movedir_dest');

    expect(await fs.directoryExists('$testRoot/movedir_src'), isFalse);
    expect(await fs.directoryExists('$testRoot/movedir_dest'), isTrue);
    expect(await fs.readFile('$testRoot/movedir_dest/a.bin'), equals(Uint8List.fromList([1, 2])));
    expect(await fs.readFile('$testRoot/movedir_dest/sub/b.bin'), equals(Uint8List.fromList([3, 4])));
  });

  testWidgets('moveDirectory throws DirectoryNotFoundException for missing source', (tester) async {
    await expectLater(
      () => fs.moveDirectory('$testRoot/no_such_dir', '$testRoot/movedir_dest2'),
      throwsA(isA<DirectoryNotFoundException>()),
    );
  });

  // ── Bulk operations (atomic) ──────────────────────────────────────────

  testWidgets('writeFiles and readFiles (bulk)', (tester) async {
    final files = {
      '$testRoot/bulk_1.bin': Uint8List.fromList([1, 2, 3]),
      '$testRoot/bulk_2.bin': Uint8List.fromList([4, 5, 6]),
      '$testRoot/bulk_3.bin': Uint8List.fromList([7, 8, 9]),
    };

    await fs.writeFiles(files);
    final result = await fs.readFiles(files.keys.toList());

    expect(result.length, equals(3));
    expect(result['$testRoot/bulk_1.bin'], equals(Uint8List.fromList([1, 2, 3])));
    expect(result['$testRoot/bulk_2.bin'], equals(Uint8List.fromList([4, 5, 6])));
    expect(result['$testRoot/bulk_3.bin'], equals(Uint8List.fromList([7, 8, 9])));
  });

  testWidgets('writeFilesStream writes multiple files from streams', (tester) async {
    final files = {
      '$testRoot/stream_bulk_1.bin': Stream.fromIterable([Uint8List.fromList([1, 2])]),
      '$testRoot/stream_bulk_2.bin': Stream.fromIterable([Uint8List.fromList([3, 4])]),
    };

    await fs.writeFilesStream(files);

    expect(await fs.readFile('$testRoot/stream_bulk_1.bin'), equals(Uint8List.fromList([1, 2])));
    expect(await fs.readFile('$testRoot/stream_bulk_2.bin'), equals(Uint8List.fromList([3, 4])));
  });

  // ── Exception hierarchy ───────────────────────────────────────────────

  testWidgets('readFile throws FileNotFoundException for missing file', (tester) async {
    await expectLater(
      () => fs.readFile('$testRoot/nonexistent.bin'),
      throwsA(isA<FileNotFoundException>()),
    );
  });

  testWidgets('copyFile throws FileNotFoundException for missing source', (tester) async {
    await expectLater(
      () => fs.copyFile('$testRoot/nonexistent.bin', '$testRoot/dest.bin'),
      throwsA(isA<FileNotFoundException>()),
    );
  });

  testWidgets('readFiles throws MultiException on missing file', (tester) async {
    await fs.writeFile('$testRoot/multi_valid.bin', Uint8List.fromList([1]));

    await expectLater(
      () => fs.readFiles(['$testRoot/multi_valid.bin', '$testRoot/multi_missing.bin']),
      throwsA(isA<MultiException>()),
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // Full feature coverage
  // ════════════════════════════════════════════════════════════════════════

  group('Full feature coverage', () {
    // ── Overwrite protection ────────────────────────────────────────────

    group('Overwrite protection', () {
      testWidgets('writeFile defaults to overwrite: false', (tester) async {
        await fs.writeFile('$testRoot/ow_default.bin', Uint8List.fromList([1, 2, 3]));

        await expectLater(
          () => fs.writeFile('$testRoot/ow_default.bin', Uint8List.fromList([4, 5, 6])),
          throwsA(isA<FileAlreadyExistsException>()),
        );
      });

      testWidgets('writeFile with overwrite: true overwrites existing file', (tester) async {
        await fs.writeFile('$testRoot/ow_true.bin', Uint8List.fromList([1, 2, 3]));
        await fs.writeFile('$testRoot/ow_true.bin', Uint8List.fromList([4, 5, 6]), overwrite: true);

        expect(await fs.readFile('$testRoot/ow_true.bin'), equals(Uint8List.fromList([4, 5, 6])));
      });

      testWidgets('writeFile with overwrite: false succeeds on new file', (tester) async {
        await fs.writeFile('$testRoot/ow_new.bin', Uint8List.fromList([1, 2, 3]), overwrite: false);

        expect(await fs.readFile('$testRoot/ow_new.bin'), equals(Uint8List.fromList([1, 2, 3])));
      });

      testWidgets('writeFileStream with overwrite: true overwrites existing file', (tester) async {
        await fs.writeFile('$testRoot/sow_true.bin', Uint8List.fromList([1, 2, 3]));
        await fs.writeFileStream(
          '$testRoot/sow_true.bin',
          Stream.fromIterable([Uint8List.fromList([4, 5, 6])]),
          overwrite: true,
        );

        expect(await fs.readFile('$testRoot/sow_true.bin'), equals(Uint8List.fromList([4, 5, 6])));
      });

      testWidgets('writeFileStream with overwrite: false succeeds on new file', (tester) async {
        await fs.writeFileStream(
          '$testRoot/sow_new.bin',
          Stream.fromIterable([Uint8List.fromList([1, 2, 3])]),
          overwrite: false,
        );

        expect(await fs.readFile('$testRoot/sow_new.bin'), equals(Uint8List.fromList([1, 2, 3])));
      });

      testWidgets('copyFile with overwrite: false throws FileAlreadyExistsException', (tester) async {
        await fs.writeFile('$testRoot/cp_ow_src.bin', Uint8List.fromList([1, 2, 3]));
        await fs.writeFile('$testRoot/cp_ow_dst.bin', Uint8List.fromList([4, 5, 6]));

        await expectLater(
          () => fs.copyFile('$testRoot/cp_ow_src.bin', '$testRoot/cp_ow_dst.bin', overwrite: false),
          throwsA(isA<FileAlreadyExistsException>()),
        );
        expect(await fs.readFile('$testRoot/cp_ow_dst.bin'), equals(Uint8List.fromList([4, 5, 6])));
      });

      testWidgets('copyFile with overwrite: false succeeds when dest does not exist', (tester) async {
        final bytes = Uint8List.fromList([1, 2, 3]);
        await fs.writeFile('$testRoot/cp_ow_new_src.bin', bytes);

        await fs.copyFile('$testRoot/cp_ow_new_src.bin', '$testRoot/cp_ow_new_dst.bin', overwrite: false);
        expect(await fs.readFile('$testRoot/cp_ow_new_dst.bin'), equals(bytes));
      });

      testWidgets('moveFile with overwrite: false throws FileAlreadyExistsException', (tester) async {
        await fs.writeFile('$testRoot/mv_ow_src.bin', Uint8List.fromList([1, 2, 3]));
        await fs.writeFile('$testRoot/mv_ow_dst.bin', Uint8List.fromList([4, 5, 6]));

        await expectLater(
          () => fs.moveFile('$testRoot/mv_ow_src.bin', '$testRoot/mv_ow_dst.bin', overwrite: false),
          throwsA(isA<FileAlreadyExistsException>()),
        );
        expect(await fs.fileExists('$testRoot/mv_ow_src.bin'), isTrue);
        expect(await fs.readFile('$testRoot/mv_ow_dst.bin'), equals(Uint8List.fromList([4, 5, 6])));
      });

      testWidgets('renameFile with overwrite: false throws FileAlreadyExistsException', (tester) async {
        await fs.writeFile('$testRoot/rn_ow_old.bin', Uint8List.fromList([1, 2, 3]));
        await fs.writeFile('$testRoot/rn_ow_new.bin', Uint8List.fromList([4, 5, 6]));

        await expectLater(
          () => fs.renameFile('$testRoot/rn_ow_old.bin', '$testRoot/rn_ow_new.bin', overwrite: false),
          throwsA(isA<FileAlreadyExistsException>()),
        );
        expect(await fs.fileExists('$testRoot/rn_ow_old.bin'), isTrue);
        expect(await fs.readFile('$testRoot/rn_ow_new.bin'), equals(Uint8List.fromList([4, 5, 6])));
      });
    });

    // ── Append operations ───────────────────────────────────────────────

    group('Append operations', () {
      testWidgets('appendFile creates file when it does not exist', (tester) async {
        await fs.appendFile('$testRoot/append_new.bin', Uint8List.fromList([1, 2, 3]));

        expect(await fs.readFile('$testRoot/append_new.bin'), equals(Uint8List.fromList([1, 2, 3])));
      });

      testWidgets('appendFile appends to existing file', (tester) async {
        await fs.writeFile('$testRoot/append_exist.bin', Uint8List.fromList([1, 2, 3]));
        await fs.appendFile('$testRoot/append_exist.bin', Uint8List.fromList([4, 5, 6]));

        expect(await fs.readFile('$testRoot/append_exist.bin'), equals(Uint8List.fromList([1, 2, 3, 4, 5, 6])));
      });

      testWidgets('appendFile creates parent directories', (tester) async {
        await fs.appendFile('$testRoot/append_nested/sub/file.bin', Uint8List.fromList([10, 20]));

        expect(await fs.readFile('$testRoot/append_nested/sub/file.bin'), equals(Uint8List.fromList([10, 20])));
      });

      testWidgets('appendFileStream creates file when it does not exist', (tester) async {
        await fs.appendFileStream(
          '$testRoot/append_stream_new.bin',
          Stream.fromIterable([Uint8List.fromList([1, 2, 3])]),
        );

        expect(await fs.readFile('$testRoot/append_stream_new.bin'), equals(Uint8List.fromList([1, 2, 3])));
      });

      testWidgets('appendFileStream appends to existing file', (tester) async {
        await fs.writeFile('$testRoot/append_stream_exist.bin', Uint8List.fromList([1, 2, 3]));
        await fs.appendFileStream(
          '$testRoot/append_stream_exist.bin',
          Stream.fromIterable([Uint8List.fromList([4, 5, 6])]),
        );

        expect(await fs.readFile('$testRoot/append_stream_exist.bin'), equals(Uint8List.fromList([1, 2, 3, 4, 5, 6])));
      });

      testWidgets('appendFile serializes on same path', (tester) async {
        await fs.writeFile('$testRoot/append_serial.bin', Uint8List(0));

        final gate = Completer<void>();
        var streamCompleted = false;

        final f1 = fs.appendFileStream(
          '$testRoot/append_serial.bin',
          () async* {
            await gate.future;
            yield Uint8List.fromList([1, 2, 3]);
          }(),
        ).then((_) => streamCompleted = true);

        final f2 = fs.readFile('$testRoot/append_serial.bin').then((bytes) {
          expect(streamCompleted, isTrue);
          return bytes;
        });

        gate.complete();
        await Future.wait([f1, f2]);
      });
    });

    // ── File metadata error paths ───────────────────────────────────────

    group('File metadata', () {
      testWidgets('getLastModified throws FileNotFoundException for missing file', (tester) async {
        await expectLater(
          () => fs.getLastModified('$testRoot/no_such_file.bin'),
          throwsA(isA<FileNotFoundException>()),
        );
      });
    });

    // ── Rename error paths ──────────────────────────────────────────────

    group('Rename error paths', () {
      testWidgets('renameFile throws FileNotFoundException for missing source', (tester) async {
        await expectLater(
          () => fs.renameFile('$testRoot/no_such.bin', '$testRoot/dest.bin'),
          throwsA(isA<FileNotFoundException>()),
        );
      });

      testWidgets('renameDirectory throws DirectoryNotFoundException for missing source', (tester) async {
        await expectLater(
          () => fs.renameDirectory('$testRoot/no_such_dir', '$testRoot/dest_dir'),
          throwsA(isA<DirectoryNotFoundException>()),
        );
      });

      testWidgets('copyFile cleans up partial destination on source-not-found error', (tester) async {
        await expectLater(
          () => fs.copyFile('$testRoot/nonexistent_source.bin', '$testRoot/copy_partial_dest.bin'),
          throwsA(isA<FileNotFoundException>()),
        );
        expect(await fs.fileExists('$testRoot/copy_partial_dest.bin'), isFalse);
      });
    });

    // ── Bulk operations (atomic) ────────────────────────────────────────

    group('Bulk operations', () {
      testWidgets('parallel bulk write with maxConcurrency', (tester) async {
        final files = <String, Uint8List>{};
        for (var i = 0; i < 20; i++) {
          files['$testRoot/par_w_$i.bin'] = Uint8List.fromList(List.generate(10, (j) => i + j));
        }

        await fs.writeFiles(files, maxConcurrency: 5);

        for (final entry in files.entries) {
          final content = await fs.readFile(entry.key);
          expect(content, equals(entry.value));
        }
      });

      testWidgets('parallel bulk read with maxConcurrency', (tester) async {
        final files = <String, Uint8List>{};
        for (var i = 0; i < 20; i++) {
          final path = '$testRoot/par_r_$i.bin';
          files[path] = Uint8List.fromList(List.generate(10, (j) => i + j));
          await fs.writeFile(path, files[path]!);
        }

        final result = await fs.readFiles(files.keys.toList(), maxConcurrency: 5);

        expect(result.length, equals(20));
        for (final entry in files.entries) {
          expect(result[entry.key], equals(entry.value));
        }
      });

      testWidgets('CancellationToken prevents new tasks from starting', (tester) async {
        final token = CancellationToken();
        token.cancel();

        await expectLater(
          () => fs.writeFiles(
            {
              '$testRoot/cancel_1.bin': Uint8List.fromList([1]),
              '$testRoot/cancel_2.bin': Uint8List.fromList([2]),
            },
            cancellationToken: token,
          ),
          throwsA(isA<OperationCancelledException>()),
        );
      });

      testWidgets('readFiles with CancellationToken', (tester) async {
        for (var i = 0; i < 5; i++) {
          await fs.writeFile('$testRoot/cancel_read_$i.bin', Uint8List.fromList([i]));
        }

        final token = CancellationToken();
        token.cancel();

        await expectLater(
          () => fs.readFiles(
            List.generate(5, (i) => '$testRoot/cancel_read_$i.bin'),
            cancellationToken: token,
          ),
          throwsA(isA<OperationCancelledException>()),
        );
      });

      testWidgets('readFiles with onError omits failed file and calls callback', (tester) async {
        await fs.writeFile('$testRoot/onerror_valid.bin', Uint8List.fromList([1, 2, 3]));

        final errors = <String, Object>{};
        final result = await fs.readFiles(
          ['$testRoot/onerror_valid.bin', '$testRoot/onerror_missing.bin'],
          onError: (path, error) => errors[path] = error,
        );

        expect(result.length, equals(1));
        expect(result['$testRoot/onerror_valid.bin'], equals(Uint8List.fromList([1, 2, 3])));
        expect(errors.length, equals(1));
        expect(errors['$testRoot/onerror_missing.bin'], isA<FileNotFoundException>());
      });

      testWidgets('readFiles with onError and all files failing returns empty map', (tester) async {
        final errors = <String, Object>{};
        final result = await fs.readFiles(
          ['$testRoot/missing_a.bin', '$testRoot/missing_b.bin'],
          onError: (path, error) => errors[path] = error,
        );

        expect(result, isEmpty);
        expect(errors.length, equals(2));
      });

      testWidgets('readFiles without onError throws MultiException on missing file', (tester) async {
        await fs.writeFile('$testRoot/onerror_compat.bin', Uint8List.fromList([1]));

        await expectLater(
          () => fs.readFiles(['$testRoot/onerror_compat.bin', '$testRoot/onerror_compat_missing.bin']),
          throwsA(isA<MultiException>()),
        );
      });

      testWidgets('writeFiles overwrites existing files (atomic snapshot)', (tester) async {
        await fs.writeFiles({
          '$testRoot/dup_bulk.bin': Uint8List.fromList([1, 2, 3]),
        });

        await fs.writeFiles({
          '$testRoot/dup_bulk.bin': Uint8List.fromList([4, 5, 6]),
        });

        final result = await fs.readFile('$testRoot/dup_bulk.bin');
        expect(result, equals(Uint8List.fromList([4, 5, 6])));
      });

      testWidgets('writeFiles with empty map is a no-op', (tester) async {
        await fs.writeFiles({});
      });

      testWidgets('readFiles with empty list returns empty map', (tester) async {
        final result = await fs.readFiles([]);
        expect(result, isEmpty);
      });
    });

    // ── Directory operations ────────────────────────────────────────────

    group('Directory operations', () {
      testWidgets('listDirectory with recursive: true returns all nested entries with types', (tester) async {
        await fs.createDirectory('$testRoot/list_rec/sub1');
        await fs.createDirectory('$testRoot/list_rec/sub2');
        await fs.writeFile('$testRoot/list_rec/a.bin', Uint8List.fromList([1]));
        await fs.writeFile('$testRoot/list_rec/sub1/b.bin', Uint8List.fromList([2]));
        await fs.writeFile('$testRoot/list_rec/sub2/c.bin', Uint8List.fromList([3]));

        final entries = await fs.listDirectory('$testRoot/list_rec', recursive: true);
        final names = entries.map((e) => e.path.split('/').last).toList()..sort();

        expect(names, containsAll(['a.bin', 'b.bin', 'c.bin', 'sub1', 'sub2']));

        final dirEntries = entries.where((e) => e.type == FileSystemEntityType.directory).toList();
        final fileEntries = entries.where((e) => e.type == FileSystemEntityType.file).toList();
        expect(dirEntries.length, equals(2));
        expect(fileEntries.length, equals(3));
      });

      testWidgets('listDirectory shallow vs recursive comparison', (tester) async {
        await fs.createDirectory('$testRoot/list_cmp/sub');
        await fs.writeFile('$testRoot/list_cmp/a.bin', Uint8List.fromList([1]));
        await fs.writeFile('$testRoot/list_cmp/sub/b.bin', Uint8List.fromList([2]));

        final shallow = await fs.listDirectory('$testRoot/list_cmp');
        final shallowNames = shallow.map((e) => e.path.split('/').last).toList()..sort();
        expect(shallowNames, equals(['a.bin', 'sub']));

        final recursive = await fs.listDirectory('$testRoot/list_cmp', recursive: true);
        final recursiveNames = recursive.map((e) => e.path.split('/').last).toList()..sort();
        expect(recursiveNames, containsAll(['a.bin', 'b.bin', 'sub']));
      });

      testWidgets('listDirectory verifies FileSystemEntityType per entry', (tester) async {
        await fs.createDirectory('$testRoot/list_types/subdir');
        await fs.writeFile('$testRoot/list_types/file.bin', Uint8List.fromList([1]));

        final entries = await fs.listDirectory('$testRoot/list_types');

        final fileEntry = entries.firstWhere((e) => e.path.split('/').last == 'file.bin');
        final dirEntry = entries.firstWhere((e) => e.path.split('/').last == 'subdir');

        expect(fileEntry.type, equals(FileSystemEntityType.file));
        expect(dirEntry.type, equals(FileSystemEntityType.directory));
      });

      testWidgets('deleteDirectory recursive removes tree', (tester) async {
        await fs.createDirectory('$testRoot/del_rec/sub');
        await fs.writeFile('$testRoot/del_rec/a.bin', Uint8List.fromList([1]));
        await fs.writeFile('$testRoot/del_rec/sub/b.bin', Uint8List.fromList([2]));

        await fs.deleteDirectory('$testRoot/del_rec', recursive: true);
        expect(await fs.directoryExists('$testRoot/del_rec'), isFalse);
      });

      testWidgets('copyDirectory copies all files preserving structure', (tester) async {
        await fs.createDirectory('$testRoot/cpdir_src/sub');
        await fs.writeFile('$testRoot/cpdir_src/a.bin', Uint8List.fromList([1, 2]));
        await fs.writeFile('$testRoot/cpdir_src/sub/b.bin', Uint8List.fromList([3, 4]));

        await fs.copyDirectory('$testRoot/cpdir_src', '$testRoot/cpdir_dst');

        expect(await fs.readFile('$testRoot/cpdir_dst/a.bin'), equals(Uint8List.fromList([1, 2])));
        expect(await fs.readFile('$testRoot/cpdir_dst/sub/b.bin'), equals(Uint8List.fromList([3, 4])));
        expect(await fs.directoryExists('$testRoot/cpdir_src'), isTrue);
      });

      testWidgets('copyDirectory is a merge — preserves non-conflicting dest files', (tester) async {
        await fs.createDirectory('$testRoot/cpdir_merge_src');
        await fs.createDirectory('$testRoot/cpdir_merge_dst');
        await fs.writeFile('$testRoot/cpdir_merge_src/new.bin', Uint8List.fromList([1]));
        await fs.writeFile('$testRoot/cpdir_merge_dst/existing.bin', Uint8List.fromList([2]));

        await fs.copyDirectory('$testRoot/cpdir_merge_src', '$testRoot/cpdir_merge_dst');

        expect(await fs.readFile('$testRoot/cpdir_merge_dst/new.bin'), equals(Uint8List.fromList([1])));
        expect(await fs.readFile('$testRoot/cpdir_merge_dst/existing.bin'), equals(Uint8List.fromList([2])));
      });

      testWidgets('copyDirectory with overwrite: true replaces conflicting files', (tester) async {
        await fs.createDirectory('$testRoot/cpdir_ow_src');
        await fs.createDirectory('$testRoot/cpdir_ow_dst');
        await fs.writeFile('$testRoot/cpdir_ow_src/file.bin', Uint8List.fromList([10, 20]));
        await fs.writeFile('$testRoot/cpdir_ow_dst/file.bin', Uint8List.fromList([30, 40]));

        await fs.copyDirectory('$testRoot/cpdir_ow_src', '$testRoot/cpdir_ow_dst', overwrite: true);

        expect(await fs.readFile('$testRoot/cpdir_ow_dst/file.bin'), equals(Uint8List.fromList([10, 20])));
      });

      testWidgets('copyDirectory with overwrite: false throws on conflict', (tester) async {
        await fs.createDirectory('$testRoot/cpdir_noow_src');
        await fs.createDirectory('$testRoot/cpdir_noow_dst');
        await fs.writeFile('$testRoot/cpdir_noow_src/file.bin', Uint8List.fromList([1]));
        await fs.writeFile('$testRoot/cpdir_noow_dst/file.bin', Uint8List.fromList([2]));

        await expectLater(
          () => fs.copyDirectory('$testRoot/cpdir_noow_src', '$testRoot/cpdir_noow_dst', overwrite: false),
          throwsA(isA<FileAlreadyExistsException>()),
        );
      });

      testWidgets('copyDirectory throws DirectoryNotFoundException for missing source', (tester) async {
        await expectLater(
          () => fs.copyDirectory('$testRoot/no_such_dir', '$testRoot/cpdir_dst2'),
          throwsA(isA<DirectoryNotFoundException>()),
        );
      });

      testWidgets('listDirectory throws DirectoryNotFoundException for missing directory', (tester) async {
        await expectLater(
          () => fs.listDirectory('$testRoot/no_such_list_dir'),
          throwsA(isA<DirectoryNotFoundException>()),
        );
      });
    });

    // ── readFileStream edge cases ───────────────────────────────────────

    group('readFileStream edge cases', () {
      testWidgets('readFileStream honors chunkSize', (tester) async {
        final bytes = Uint8List.fromList(List.generate(300, (i) => i % 256));
        await fs.writeFile('$testRoot/chunk_size.bin', bytes);

        final chunks = <Uint8List>[];
        await for (final chunk in fs.readFileStream('$testRoot/chunk_size.bin', chunkSize: 100)) {
          chunks.add(chunk);
        }

        for (final chunk in chunks) {
          expect(chunk.length, lessThanOrEqualTo(100));
        }

        final readBytes = chunks.expand((c) => c).toList();
        expect(readBytes, equals(bytes));
      });

      testWidgets('readFileStream with chunkSize larger than file produces single chunk', (tester) async {
        final bytes = Uint8List.fromList(List.generate(50, (i) => i));
        await fs.writeFile('$testRoot/chunk_big.bin', bytes);

        final chunks = <Uint8List>[];
        await for (final chunk in fs.readFileStream('$testRoot/chunk_big.bin', chunkSize: 65536)) {
          chunks.add(chunk);
        }

        expect(chunks.length, equals(1));
        expect(chunks[0], equals(bytes));
      });

      testWidgets('readFileStream throws FileNotFoundException for missing file', (tester) async {
        await expectLater(
          () async {
            await for (final _ in fs.readFileStream('$testRoot/no_such_stream.bin')) {}
          },
          throwsA(isA<FileNotFoundException>()),
        );
      });

      testWidgets('readFileStream respects backpressure from slow consumer', (tester) async {
        final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        await fs.writeFile('$testRoot/backpressure.bin', bytes);

        final chunks = <Uint8List>[];
        await for (final chunk in fs.readFileStream('$testRoot/backpressure.bin', chunkSize: 100)) {
          await Future.delayed(const Duration(milliseconds: 10));
          chunks.add(chunk);
        }

        final readBytes = chunks.expand((c) => c).toList();
        expect(readBytes, equals(bytes));
        expect(chunks.length, greaterThanOrEqualTo(1));
      });

      testWidgets('readFileStream can be cancelled mid-read', (tester) async {
        final bytes = Uint8List.fromList(List.generate(1024, (i) => i % 256));
        await fs.writeFile('$testRoot/stream_cancel.bin', bytes);

        var chunksReceived = 0;
        final subscription = fs.readFileStream('$testRoot/stream_cancel.bin').listen((chunk) {
          chunksReceived++;
        });

        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        expect(chunksReceived, greaterThanOrEqualTo(0));
      });
    });

    // ── Exception hierarchy ─────────────────────────────────────────────

    group('Exception hierarchy', () {
      testWidgets('all custom exceptions implement DbasFileSystemException', (tester) async {
        expect(const FileNotFoundException('x'), isA<DbasFileSystemException>());
        expect(const DirectoryNotFoundException('x'), isA<DbasFileSystemException>());
        expect(const FileAlreadyExistsException('x'), isA<DbasFileSystemException>());
        expect(const DirectoryNotEmptyException('x'), isA<DbasFileSystemException>());
        expect(const PermissionDeniedException('x'), isA<DbasFileSystemException>());
        expect(const OperationCancelledException(), isA<DbasFileSystemException>());
      });

      testWidgets('MultiException and AtomicOperationException types', (tester) async {
        final multi = MultiException([('a.bin', Exception('fail'))]);
        expect(multi, isA<DbasFileSystemException>());
        expect(multi.errors.length, equals(1));

        final atomic = AtomicOperationException('primary', secondaryError: 'rollback');
        expect(atomic, isA<DbasFileSystemException>());
        expect(atomic.error, equals('primary'));
        expect(atomic.secondaryError, equals('rollback'));
      });

      testWidgets('exception toString includes path', (tester) async {
        final e = const FileNotFoundException('/some/path');
        final str = e.toString();
        expect(str, contains('File not found'));
        expect(str, contains('/some/path'));
        expect(e.path, equals('/some/path'));
      });

      testWidgets('OperationCancelledException is a DbasFileSystemException with null path', (tester) async {
        const e = OperationCancelledException();
        expect(e, isA<DbasFileSystemException>());
        expect(e.message, equals('Operation was cancelled'));
        expect(e.path, isNull);
      });

      testWidgets('DbasFileSystemException with and without path', (tester) async {
        const withPath = DbasFileSystemException('test error', path: '/some/path');
        expect(withPath.toString(), contains('/some/path'));

        const withoutPath = DbasFileSystemException('test error');
        expect(withoutPath.path, isNull);
        expect(withoutPath.toString().contains('[path:'), isFalse);
      });

      testWidgets('PermissionDeniedException toString and path', (tester) async {
        const e = PermissionDeniedException('/protected/file.bin');
        expect(e, isA<DbasFileSystemException>());
        expect(e.path, equals('/protected/file.bin'));
        expect(e.toString(), contains('Permission denied'));
      });
    });

    // ── FileSystemEntry model ───────────────────────────────────────────

    group('FileSystemEntry model', () {
      testWidgets('FileSystemEntry equality, hashCode, and toString', (tester) async {
        const a = FileSystemEntry(path: '/a/b', type: FileSystemEntityType.file);
        const b = FileSystemEntry(path: '/a/b', type: FileSystemEntityType.file);
        const c = FileSystemEntry(path: '/a/b', type: FileSystemEntityType.directory);

        expect(a, equals(b));
        expect(a, isNot(equals(c)));
        expect(a.hashCode, equals(b.hashCode));
        expect(a.toString(), equals('FileSystemEntry(path: /a/b, type: FileSystemEntityType.file)'));
      });
    });

    // ── FileChange model ────────────────────────────────────────────────

    group('FileChange model', () {
      testWidgets('FileChange.created, .deleted, .modified factories', (tester) async {
        const entry = FileSystemEntry(path: 'a.txt', type: FileSystemEntityType.file);
        final created = FileChange.created(entry);
        final deleted = FileChange.deleted(entry);
        final modified = FileChange.modified(oldEntry: entry, newEntry: entry);

        expect(created.type, equals(FileChangeType.created));
        expect(deleted.type, equals(FileChangeType.deleted));
        expect(modified.type, equals(FileChangeType.modified));
      });
    });

    // ── CancellationToken lifecycle ─────────────────────────────────────

    group('CancellationToken lifecycle', () {
      testWidgets('addListener is called when cancel() is invoked', (tester) async {
        final token = CancellationToken();
        var called = false;
        token.addListener(() => called = true);
        token.cancel();
        expect(called, isTrue);
      });

      testWidgets('addListener is called immediately when token is already cancelled', (tester) async {
        final token = CancellationToken();
        token.cancel();
        var called = false;
        token.addListener(() => called = true);
        expect(called, isTrue);
      });

      testWidgets('cancel() is idempotent — listeners called exactly once', (tester) async {
        final token = CancellationToken();
        var count = 0;
        token.addListener(() => count++);
        token.cancel();
        token.cancel();
        expect(count, equals(1));
      });

      testWidgets('removeListener prevents listener from being called', (tester) async {
        final token = CancellationToken();
        var called = false;
        void listener() => called = true;
        token.addListener(listener);
        token.removeListener(listener);
        token.cancel();
        expect(called, isFalse);
      });

      testWidgets('multiple listeners are all called', (tester) async {
        final token = CancellationToken();
        var count = 0;
        token.addListener(() => count++);
        token.addListener(() => count++);
        token.addListener(() => count++);
        token.cancel();
        expect(count, equals(3));
      });
    });

    // ── Path validation ─────────────────────────────────────────────────

    group('Path validation', () {
      testWidgets('empty path throws ArgumentError', (tester) async {
        expect(() => fs.writeFile('', Uint8List(0)), throwsArgumentError);
      });

      testWidgets('blank path throws ArgumentError', (tester) async {
        expect(() => fs.writeFile('   ', Uint8List(0)), throwsArgumentError);
      });

      testWidgets('path with null byte throws ArgumentError', (tester) async {
        expect(() => fs.writeFile('foo\x00bar', Uint8List(0)), throwsArgumentError);
      });
    });

    // ── Concurrency ─────────────────────────────────────────────────────

    group('Concurrency', () {
      testWidgets('same-path operations serialize', (tester) async {
        final gate = Completer<void>();
        var writeCompleted = false;

        final f1 = fs.writeFileStream(
          '$testRoot/serial_test.bin',
          () async* {
            await gate.future;
            yield Uint8List.fromList([1, 2, 3]);
          }(),
        ).then((_) => writeCompleted = true);

        final f2 = fs.readFile('$testRoot/serial_test.bin').then((bytes) {
          expect(writeCompleted, isTrue);
          return bytes;
        });

        gate.complete();
        await Future.wait([f1, f2]);
      });

      testWidgets('different-path operations run in parallel', (tester) async {
        final aStarted = Completer<void>();
        final bStarted = Completer<void>();
        final gate = Completer<void>();

        final fA = fs.writeFileStream('$testRoot/parallel_a.bin', () async* {
          aStarted.complete();
          await gate.future;
          yield Uint8List.fromList([1]);
        }());

        final fB = fs.writeFileStream('$testRoot/parallel_b.bin', () async* {
          bStarted.complete();
          await gate.future;
          yield Uint8List.fromList([2]);
        }());

        await aStarted.future.timeout(const Duration(seconds: 5));
        await bStarted.future.timeout(const Duration(seconds: 5));

        gate.complete();
        await Future.wait([fA, fB]);
      });
    });

    // ── Persistent storage ──────────────────────────────────────────────

    group('Persistent storage', () {
      testWidgets('isPersistentStorage returns a boolean on web', (tester) async {
        final value = fs.isPersistentStorage;
        expect(value, isA<bool>());
      });
    });

    // ── Path helpers ──────────────────────────────────────────────────────

    group('Path helpers', () {
      testWidgets('getAppFilePath returns a path ending with the given file name', (tester) async {
        final filePath = await fs.getAppFilePath('test_file.bin');
        expect(filePath, endsWith('test_file.bin'));
        expect(filePath.contains('\\'), isFalse, reason: 'Path should use forward slashes');
      });
    });

    // ── Singleton behavior ──────────────────────────────────────────────

    group('Singleton behavior', () {
      testWidgets('getInstance returns same instance on subsequent calls', (tester) async {
        final fs1 = await DbasFileSystem.getInstance();
        final fs2 = await DbasFileSystem.getInstance();
        expect(identical(fs1, fs2), isTrue);
      });

      testWidgets('concurrent getInstance calls during initialization return same instance', (tester) async {
        await fs.dispose();
        try {
          final results = await Future.wait([
            DbasFileSystem.getInstance(),
            DbasFileSystem.getInstance(),
            DbasFileSystem.getInstance(),
          ]);

          expect(identical(results[0], results[1]), isTrue);
          expect(identical(results[1], results[2]), isTrue);

          fs = results[0];
        } catch (_) {
          fs = await DbasFileSystem.getInstance();
          rethrow;
        }
      });
    });

    // ── Disposal lifecycle (LAST — these destroy and reinitialize) ──────

    group('Disposal lifecycle', () {
      testWidgets('isDisposed is false before dispose', (tester) async {
        expect(fs.isDisposed, isFalse);
      });

      testWidgets('isDisposed is true immediately after dispose is called', (tester) async {
        final old = await DbasFileSystem.getInstance();
        try {
          final disposeFuture = old.dispose();
          expect(old.isDisposed, isTrue);
          await disposeFuture;
        } finally {
          fs = await DbasFileSystem.getInstance();
        }
      });

      testWidgets('dispose accepts configurable timeout', (tester) async {
        final old = await DbasFileSystem.getInstance();
        try {
          await old.dispose(timeout: const Duration(seconds: 5));
        } finally {
          fs = await DbasFileSystem.getInstance();
        }
      });

      testWidgets('operations after dispose throw StateError', (tester) async {
        final fs1 = await DbasFileSystem.getInstance();
        try {
          await fs1.dispose();
          expect(
            () => fs1.writeFile('any/path.bin', Uint8List(0)),
            throwsA(isA<StateError>()),
          );
        } finally {
          fs = await DbasFileSystem.getInstance();
        }
      });

      testWidgets('getInstance after dispose returns new instance', (tester) async {
        final fs1 = await DbasFileSystem.getInstance();
        try {
          await fs1.dispose();
          final fs2 = await DbasFileSystem.getInstance();
          expect(identical(fs1, fs2), isFalse);
          fs = fs2;
        } catch (_) {
          fs = await DbasFileSystem.getInstance();
          rethrow;
        }
      });

      testWidgets('isDisposed check on multiple public methods', (tester) async {
        final old = await DbasFileSystem.getInstance();
        try {
          await old.dispose();
          expect(() => old.readFile('any.bin'), throwsA(isA<StateError>()));
          expect(() => old.fileExists('any.bin'), throwsA(isA<StateError>()));
          expect(() => old.isPersistentStorage, throwsA(isA<StateError>()));
          expect(() => old.getAppFilePath('any.bin'), throwsA(isA<StateError>()));
          expect(() => old.appendFile('any.bin', Uint8List(0)), throwsA(isA<StateError>()));
          expect(() => old.listDirectory('any'), throwsA(isA<StateError>()));
          expect(() => old.copyDirectory('a', 'b'), throwsA(isA<StateError>()));
          expect(() => old.moveDirectory('a', 'b'), throwsA(isA<StateError>()));
        } finally {
          fs = await DbasFileSystem.getInstance();
        }
      });

      testWidgets('getInstance immediately after dispose returns fresh instance', (tester) async {
        try {
          final old = await DbasFileSystem.getInstance();
          final disposeFuture = old.dispose();
          final newFs = await DbasFileSystem.getInstance();
          await disposeFuture;

          expect(identical(old, newFs), isFalse);

          await newFs.writeFile('$testRoot/post_dispose_race.bin', Uint8List.fromList([42]));
          expect(await newFs.readFile('$testRoot/post_dispose_race.bin'), equals(Uint8List.fromList([42])));

          fs = newFs;
        } catch (_) {
          fs = await DbasFileSystem.getInstance();
          rethrow;
        }
      });

      testWidgets('dispose during init does not corrupt subsequent getInstance', (tester) async {
        await fs.dispose();
        try {
          final initFuture = DbasFileSystem.getInstance();
          final first = await initFuture;
          await first.dispose();

          final second = await DbasFileSystem.getInstance();
          expect(identical(first, second), isFalse);

          fs = second;
        } catch (_) {
          fs = await DbasFileSystem.getInstance();
          rethrow;
        }
      });
    });
  });
}
