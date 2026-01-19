import 'package:record/record.dart' as rec;
import 'package:path_provider/path_provider.dart';

class AudioRecorder {
  final rec.AudioRecorder _record = rec.AudioRecorder();

  Future<bool> hasPermission() => _record.hasPermission();

  Future<void> start({String? path}) async {
    String filePath;
    if (path != null) {
      filePath = path;
    } else {
      final dir = await getTemporaryDirectory();
      filePath = '${dir.path}/chat_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }

    await _record.start(
      const rec.RecordConfig(
        encoder: rec.AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: filePath,
    );
  }

  Future<String?> stop() async {
    return await _record.stop();
  }

  void dispose() {
    _record.dispose();
  }
}
