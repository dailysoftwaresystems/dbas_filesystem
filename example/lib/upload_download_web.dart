import 'dart:typed_data';
import 'package:dbas_filesystem/dbas_filesystem.dart';
import 'package:file_picker/file_picker.dart';

Future<bool> uploadFile(PlatformFile file, String destPath, DbasFileSystem fs) async {
  if (file.bytes == null) return false;
  await fs.writeFile(destPath, file.bytes!);
  return true;
}

Future<bool> downloadFile(String fileName, Uint8List bytes) async {
  await FilePicker.saveFile(
    dialogTitle: 'Save "$fileName"',
    fileName: fileName,
    bytes: bytes,
  );
  return true;
}
