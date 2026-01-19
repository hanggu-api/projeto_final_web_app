import 'package:record/record.dart' as rec;

class AudioRecorder {
  final rec.AudioRecorder _record = rec.AudioRecorder();

  Future<bool> hasPermission() => _record.hasPermission();

  Future<void> start({String? path}) async {
    // Web requires no path (blob) or specific config
    await _record.start(
      const rec.RecordConfig(),
      path: '', // Web uses memory/blob
    );
  }

  Future<String?> stop() async {
    return await _record.stop();
  }

  void dispose() {
    _record.dispose();
  }
}
