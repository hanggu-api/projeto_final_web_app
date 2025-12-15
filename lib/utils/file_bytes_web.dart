import 'dart:typed_data';
import 'package:http/http.dart' as http;

Future<Uint8List> readFileBytes(String url) async {
  final resp = await http.get(Uri.parse(url));
  return resp.bodyBytes;
}