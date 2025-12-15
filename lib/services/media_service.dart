import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'api_service.dart';

class MediaService {
  final _api = ApiService();

  Future<XFile?> pickImageMobile(ImageSource source) async {
    final picker = ImagePicker();
    return await picker.pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
  }

  Future<FilePickerResult?> pickImageWeb() async {
    return await FilePicker.platform.pickFiles(type: FileType.image, withData: true, compressionQuality: 85);
  }

  Future<Map<String, dynamic>> uploadAvatarBytes(List<int> bytes, String filename, String mimeType) async {
    return await _api.uploadMultipart('/media/avatar', 'file', bytes, filename: filename, mimeType: mimeType);
  }

  Future<Uint8List?> loadMyAvatarBytes() async {
    final resp = await _api.getRaw('/media/avatar/me', extraHeaders: {'Accept': 'image/webp'});
    if (resp.statusCode == 200) {
      return resp.bodyBytes;
    }
    return null;
  }
}