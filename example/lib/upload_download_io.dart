import 'dart:io';
import 'dart:typed_data';
import 'package:dbas_filesystem/dbas_filesystem.dart';
import 'package:file_picker/file_picker.dart';

Future<bool> uploadFile(PlatformFile file, String destPath, DbasFileSystem fs) async {
  if (file.path == null) return false;
  final sourceFile = File(file.path!);
  await fs.writeFileStream(destPath, sourceFile.openRead());
  return true;
}

Future<bool> downloadFile(String fileName, Uint8List bytes) async {
  final outputPath = await FilePicker.saveFile(
    dialogTitle: 'Save "$fileName"',
    fileName: fileName,
  );
  if (outputPath == null) return false;

  final destFile = File(outputPath);
  await destFile.writeAsBytes(bytes);
  return true;
}
