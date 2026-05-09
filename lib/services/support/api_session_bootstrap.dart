import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/api_identity_snapshot.dart';

class ApiSessionBootstrap {
  static Future<ApiStoredSessionSnapshot> loadStoredSession({
    required SharedPreferences? prefs,
    required FlutterSecureStorage secureStorage,
    required bool supabaseInitialized,
  }) async {
    String? token;

    try {
      if (supabaseInitialized) {
        token = Supabase.instance.client.auth.currentSession?.accessToken;
      }
    } catch (_) {}

    if (token == null) {
      try {
        token = await secureStorage.read(key: 'auth_token');
      } catch (e) {
        debugPrint(
          '⚠️ [ApiSessionBootstrap] Falha ao ler token do storage seguro: $e',
        );
        token = null;
        try {
          await secureStorage.delete(key: 'auth_token');
        } catch (_) {}
      }
    }

    String? role;
    bool isMedical = false;
    bool isFixedLocation = false;

    try {
      role = await secureStorage.read(key: 'user_role');
      final secMedical = await secureStorage.read(key: 'is_medical');
      if (secMedical != null) isMedical = secMedical == 'true';

      final secFixed = await secureStorage.read(key: 'is_fixed_location');
      if (secFixed != null) isFixedLocation = secFixed == 'true';
    } catch (e) {
      debugPrint(
        '⚠️ [ApiSessionBootstrap] Falha ao ler identidade do storage: $e',
      );
    }

    final identity = ApiIdentitySnapshot(
      userId: prefs?.getInt('user_id'),
      role: role,
      isMedical: isMedical,
      isFixedLocation: isFixedLocation,
    );

    return ApiStoredSessionSnapshot(token: token, identity: identity);
  }

  static ApiIdentitySnapshot identityFromUserRow(
    Map<String, dynamic> userRow, {
    required bool Function(dynamic value) parseBool,
  }) {
    final resolvedId = userRow['id'] is num
        ? (userRow['id'] as num).toInt()
        : int.tryParse('${userRow['id']}');
    final roleRaw = userRow['role']?.toString().trim();

    return ApiIdentitySnapshot(
      userId: resolvedId,
      role: roleRaw != null && roleRaw.isNotEmpty ? roleRaw : null,
      isMedical: parseBool(userRow['is_medical']),
      isFixedLocation: parseBool(userRow['is_fixed_location']),
    );
  }
}
