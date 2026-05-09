import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final ApiService _api = ApiService();
  static const _secureStorage = FlutterSecureStorage();
  static const _lastFaceValidationKey = 'last_face_validation_timestamp';
  static const _lastValidatedUserKey = 'last_validated_user_id';

  Future<bool> needsFaceValidation() async {
    final lastValidationStr = await _secureStorage.read(key: _lastFaceValidationKey);
    final lastUser = await _secureStorage.read(key: _lastValidatedUserKey);
    final currentUserId = _api.userId;

    if (lastValidationStr == null || lastUser == null || currentUserId == null) {
      return true;
    }

    if (lastUser != currentUserId) return true;

    final lastValidation = int.tryParse(lastValidationStr);
    if (lastValidation == null) return true;

    final lastDate = DateTime.fromMillisecondsSinceEpoch(lastValidation);
    return DateTime.now().difference(lastDate).inHours >= 12;
  }

  Future<void> recordSuccessfulValidation() async {
    final currentUserId = _api.userId;
    if (currentUserId == null) return;

    await _secureStorage.write(
      key: _lastFaceValidationKey,
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    await _secureStorage.write(key: _lastValidatedUserKey, value: currentUserId);
  }

  /// Chama a Edge Function para comparar a selfie atual com a original de cadastro.
  Future<Map<String, dynamic>> verifyFace(String selfiePath) async {
    try {
      final data = await _api.verifyCardFace(selfiePath: selfiePath);

      if (data['success'] == true) {
        await recordSuccessfulValidation();
      }

      return data;
    } catch (e) {
      rethrow;
    }
  }
}
