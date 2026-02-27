import 'dart:typed_data';
import 'dart:io' as io;

Future<Uint8List> readFileBytes(String path) async {
  return await io.File(path).readAsBytes();
}
