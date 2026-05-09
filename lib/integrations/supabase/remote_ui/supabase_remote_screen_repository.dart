import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/remote_ui/component_registry.dart';
import '../../../core/runtime/app_runtime_service.dart';
import '../../../core/network/backend_api_client.dart';
import '../../../domains/remote_ui/data/remote_screen_repository.dart';
import '../../../domains/remote_ui/models/loaded_remote_screen.dart';
import '../../../domains/remote_ui/models/remote_screen.dart';
import '../../../domains/remote_ui/models/remote_screen_request.dart';

class SupabaseRemoteScreenRepository implements RemoteScreenRepository {
  static const _endpoint = '/api/v1/remote-ui/get-screen';
  static const _cachePrefix = 'remote_screen_cache:';

  final BackendApiClient _client;

  SupabaseRemoteScreenRepository({BackendApiClient? client})
    : _client = client ?? const BackendApiClient();

  @override
  Future<LoadedRemoteScreen?> fetchScreen(RemoteScreenRequest request) async {
    try {
      final response = await _client.postJson(
        _endpoint,
        body: request.toJson(),
      );

      final data = _readMap(response);
      final screenPayload = _readMap(data['screen']);
      if (screenPayload.isEmpty) {
        debugPrint(
          '⚠️ [RemoteUI] get_screen returned empty payload for ${request.screenKey}',
        );
        return null;
      }

      final screen = RemoteScreen.fromJson(screenPayload);
      if (!ComponentRegistry.supportsTree(screen.components)) {
        debugPrint(
          '⚠️ [RemoteUI] Unsupported component/action in screen ${request.screenKey}',
        );
        return null;
      }

      await _writeCache(request.screenKey, screenPayload);
      return LoadedRemoteScreen(
        screen: screen,
        source: RemoteScreenSource.remote,
      );
    } catch (error) {
      debugPrint(
        '⚠️ [RemoteUI] fetchScreen failed for ${request.screenKey}: $error',
      );
      AppRuntimeService.instance.logConfigFailure(
        'remote_ui:fetch:${request.screenKey}',
        error,
      );
      return null;
    }
  }

  @override
  Future<LoadedRemoteScreen?> readCachedScreen(String screenKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$screenKey');
      if (raw == null || raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final payload = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final screen = RemoteScreen.fromJson(payload);
      if (!screen.fallbackPolicy.allowCache) return null;
      if (!ComponentRegistry.supportsTree(screen.components)) return null;

      return LoadedRemoteScreen(
        screen: screen,
        source: RemoteScreenSource.cache,
      );
    } catch (error) {
      debugPrint(
        '⚠️ [RemoteUI] readCachedScreen failed for $screenKey: $error',
      );
      AppRuntimeService.instance.logConfigFailure(
        'remote_ui:cache:$screenKey',
        error,
      );
      return null;
    }
  }

  @override
  Future<void> invalidateScreen(String screenKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_cachePrefix$screenKey');
  }

  Future<void> _writeCache(
    String screenKey,
    Map<String, dynamic> payload,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_cachePrefix$screenKey', jsonEncode(payload));
  }

  static Map<String, dynamic> _readMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }
}
