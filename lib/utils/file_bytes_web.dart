import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<Uint8List> readFileBytes(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
