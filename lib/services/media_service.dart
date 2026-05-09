import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../core/profile/backend_profile_api.dart';
import '../core/network/backend_api_client.dart';
import 'api_service.dart';

class MediaService {
  final ApiService _api = ApiService();
  final BackendProfileApi _backendProfileApi = const BackendProfileApi();
  final BackendApiClient _backendApiClient = const BackendApiClient();

  void _avatarTrace(String message) {
    debugPrint(message);
    // ignore: avoid_print
    print(message);
  }

  ({Uint8List bytes, String filename, String mimeType})
  _normalizeAvatarForUpload(
    List<int> rawBytes,
    String filename,
    String mimeType,
  ) {
    final lowerName = filename.toLowerCase();
    final isPng =
        mimeType.toLowerCase() == 'image/png' || lowerName.endsWith('.png');
    if (!isPng) {
      return (
        bytes: Uint8List.fromList(rawBytes),
        filename: filename,
        mimeType: mimeType,
      );
    }

    final decoded = img.decodeImage(Uint8List.fromList(rawBytes));
    if (decoded == null) {
      return (
        bytes: Uint8List.fromList(rawBytes),
        filename: filename,
        mimeType: mimeType,
      );
    }

    final jpgBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 88));
    final normalizedFilename = lowerName.endsWith('.png')
        ? '${filename.substring(0, filename.length - 4)}.jpg'
        : '$filename.jpg';
    return (
      bytes: jpgBytes,
      filename: normalizedFilename,
      mimeType: 'image/jpeg',
    );
  }

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
    _avatarTrace(
      '🧭 [AvatarFlow] MediaService recebeu arquivo | originalName=$filename | originalMime=$mimeType | bytes=${bytes.length}',
    );
    final normalized = _normalizeAvatarForUpload(bytes, filename, mimeType);
    _avatarTrace(
      '🧭 [AvatarFlow] Arquivo normalizado | uploadName=${normalized.filename} | uploadMime=${normalized.mimeType} | uploadBytes=${normalized.bytes.length}',
    );
    final String publicUrl = await _api.uploadAvatarImage(
      normalized.bytes,
      filename: normalized.filename,
      mimeType: normalized.mimeType,
    );
    _avatarTrace('🧭 [AvatarFlow] Upload retornou URL | url=$publicUrl');
    return {'url': publicUrl};
  }

  Future<Uint8List?> loadMyAvatarBytes() async {
    try {
      final backendProfile = await _backendProfileApi.fetchMyProfile();
      final avatarUrl = (backendProfile?.toApiUserMap()['avatar_url'] ?? '')
          .toString()
          .trim();
      _avatarTrace(
        '🧭 [AvatarFlow] loadMyAvatarBytes | avatarUrl=${avatarUrl.isEmpty ? '(vazio)' : avatarUrl}',
      );
      if (avatarUrl.isEmpty) return null;
      return await _api.getMediaBytes(avatarUrl);
    } catch (e) {
      _avatarTrace('⚠️ [AvatarFlow] loadMyAvatarBytes falhou: $e');
      return null;
    }
  }

  Future<Uint8List?> loadUserAvatarBytes(String userId) async {
    try {
      if (ApiService().currentUserId?.trim() == userId.trim()) {
        final ownAvatar = await loadMyAvatarBytes();
        if (ownAvatar != null) return ownAvatar;
      }

      var userData = await _backendApiClient.getJson('/api/v1/users/$userId');
      if (userData?['data'] is Map) {
        userData = Map<String, dynamic>.from(userData!['data'] as Map);
      }

      final avatarUrl =
          userData?['avatar_url']?.toString() ??
          userData?['photo']?.toString() ??
          '';

      if (avatarUrl.isNotEmpty) {
        return await _api.getMediaBytes(avatarUrl);
      }

      if (ApiService.isLocalWebEnvironment || kIsWeb) {
        return null;
      }

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

  Future<String> uploadVerificationSelfie(
    List<int> bytes,
    String filename,
  ) async {
    return await _api.uploadVerificationImage(bytes, filename: filename);
  }
}
