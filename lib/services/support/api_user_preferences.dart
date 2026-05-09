import 'package:flutter/foundation.dart';

import '../../core/network/backend_api_client.dart';

class ApiUserPreferences {
  final BackendApiClient _backend = const BackendApiClient();

  Future<void> markNotificationRead(int id) async {
    try {
      await _backend.putJson(
        '/api/v1/notifications/$id/read',
        body: {'read': true},
      );
    } catch (e) {
      debugPrint('⚠️ [ApiUserPreferences] markNotificationRead: $e');
    }
  }

  Future<void> markAllNotificationsRead(int? userId) async {
    if (userId == null) return;
    try {
      await _backend.putJson(
        '/api/v1/users/$userId/notifications/read-all',
        body: {'read': true},
      );
    } catch (e) {
      debugPrint('⚠️ [ApiUserPreferences] markAllNotificationsRead: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getSavedPlaces(int? userId) async {
    if (userId == null) return [];
    try {
      final res = await _backend.getJson('/api/v1/users/$userId/saved-places');
      final list = res?['data'] as List?;
      return list?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
          [];
    } catch (e) {
      debugPrint('⚠️ [ApiUserPreferences] getSavedPlaces: $e');
      return [];
    }
  }

  Future<void> saveSavedPlace(int? userId, Map<String, dynamic> place) async {
    if (userId == null) throw Exception('Não autenticado');
    try {
      await _backend.postJson(
        '/api/v1/users/$userId/saved-places',
        body: place,
      );
    } catch (e) {
      debugPrint('⚠️ [ApiUserPreferences] saveSavedPlace: $e');
      rethrow;
    }
  }
}
