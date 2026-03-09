import 'dart:async';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'api_service.dart';

class MediaService {
  final ApiService _api = ApiService();

  // Define explicitamente o retorno como Future<XFile?>
  Future<XFile?> pickImageMobile(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    return await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
  }

  Future<FilePickerResult?> pickImageWeb() async {
    return await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      // compressionQuality não é suportado em todas as plataformas via FilePicker,
      // mas mantemos para compatibilidade onde disponível.
    );
  }

  Future<Map<String, dynamic>> uploadAvatarBytes(
    List<int> bytes,
    String filename,
    String mimeType,
  ) async {
    final String publicUrl = await _api.uploadToCloud(
      bytes,
      filename: filename,
      type: 'image',
    );
    return {'url': publicUrl};
  }

  Future<Uint8List?> loadMyAvatarBytes() async {
    try {
      final response = await _api.getRaw(
        '/media/avatar/me',
        extraHeaders: <String, String>{'Accept': 'image/webp'},
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      // O Analyzer com 'avoid_print' vai sugerir o uso do debugPrint
      // ou apenas silenciar se for um erro esperado.
    }
    return null;
  }

  Future<Uint8List?> loadUserAvatarBytes(int userId) async {
    try {
      final response = await _api.getRaw(
        '/media/avatar/$userId',
        extraHeaders: <String, String>{'Accept': 'image/webp'},
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }
}
