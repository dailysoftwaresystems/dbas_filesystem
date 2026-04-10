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

  // ── Bulk operations ───────────────────────────────────────────────────

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
}
