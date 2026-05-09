import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/backend_api_client.dart';
import '../network_status_service.dart';
import 'provider_presence_policy.dart';

class ProviderPresenceService {
  const ProviderPresenceService._();

  static const String onlineKey = 'provider_online_for_dispatch';
  static const String userIdKey = 'provider_keepalive_user_id';
  static const String userUidKey = 'provider_keepalive_user_uid';
  static const String isFixedKey = 'provider_keepalive_is_fixed_location';
  static const String lastLatKey = 'provider_keepalive_last_lat';
  static const String lastLonKey = 'provider_keepalive_last_lon';
  static const String lastHeartbeatIsoKey =
      'provider_keepalive_last_heartbeat_at';
  static const String lastTickResultKey = 'provider_keepalive_last_tick_result';
  static const Duration heartbeatInterval = Duration(seconds: 30);

  static final NetworkStatusService _networkStatus = NetworkStatusService();
  static final BackendApiClient _backend = const BackendApiClient();

  static bool get supportsBackgroundService =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> persistContext({
    required bool onlineForDispatch,
    required String userId,
    String? userUid,
    required bool isFixedLocation,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onlineKey, onlineForDispatch);
    await prefs.setString(userIdKey, userId);
    if (userUid != null && userUid.trim().isNotEmpty) {
      await prefs.setString(userUidKey, userUid.trim());
    }
    await prefs.setBool(isFixedKey, isFixedLocation);
  }

  static Future<void> clearContext() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onlineKey, false);
    await prefs.remove(lastHeartbeatIsoKey);
    await _recordTickResult(ProviderPresenceTickResult.skippedOffline);
    await stopBackgroundService();
  }

  static Future<void> cacheLastKnownCoords(double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(lastLatKey, lat);
    await prefs.setDouble(lastLonKey, lon);
  }

  static Future<(double, double)?> getCachedLastKnownCoords() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(lastLatKey);
    final lon = prefs.getDouble(lastLonKey);
    if (lat == null || lon == null) return null;
    return (lat, lon);
  }

  static Future<bool> isOnlineForDispatch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(onlineKey) ?? false;
  }

  static Future<void> startBackgroundService() async {
    if (!supportsBackgroundService) return;
    final service = FlutterBackgroundService();
    try {
      final running = await service.isRunning();
      if (!running) {
        await service.startService();
      }
      service.invoke('refreshContext');
    } catch (e) {
      debugPrint(
        '[ProviderPresenceService] Falha ao iniciar background service: $e',
      );
    }
  }

  static Future<void> stopBackgroundService() async {
    if (!supportsBackgroundService) return;
    try {
      final service = FlutterBackgroundService();
      final running = await service.isRunning();
      if (!running) return;
      service.invoke('stopService');
    } catch (e) {
      debugPrint(
        '[ProviderPresenceService] Falha ao parar background service: $e',
      );
    }
  }

  static Future<void> ensureSupabaseReady() async {
    // Compat: preserva assinatura enquanto removemos dependência de sessão
    // no cliente. Toda autenticação/renovação deve vir do backend REST.
    await _networkStatus.ensureInitialized();
  }

  static Future<(double, double)?> resolveBestEffortCoords() async {
    try {
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null) {
        await cacheLastKnownCoords(lastPos.latitude, lastPos.longitude);
        return (lastPos.latitude, lastPos.longitude);
      }
    } catch (_) {}

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await cacheLastKnownCoords(pos.latitude, pos.longitude);
      return (pos.latitude, pos.longitude);
    } catch (_) {}

    final cached = await getCachedLastKnownCoords();
    if (cached != null) return cached;

    try {
      await ensureSupabaseReady();
      if (!_networkStatus.canAttemptSupabase) {
        return cached;
      }
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(userUidKey)?.trim();
      final userIdRaw = prefs.getString(userIdKey)?.trim();
      final userId = int.tryParse(userIdRaw ?? '');

      // Tenta via REST primeiro, fallback para Supabase direto
      if (uid != null && uid.isNotEmpty) {
        final row = await _backend.getJson(
          '/api/v1/providers/location?uid=$uid',
        );
        final lat = (row?['latitude'] as num?)?.toDouble();
        final lon = (row?['longitude'] as num?)?.toDouble();
        if (lat != null && lon != null) {
          await cacheLastKnownCoords(lat, lon);
          return (lat, lon);
        }
      }

      if (userId != null) {
        final row = await _backend.getJson(
          '/api/v1/providers/$userId/location',
        );
        final fallbackLat = (row?['latitude'] as num?)?.toDouble();
        final fallbackLon = (row?['longitude'] as num?)?.toDouble();
        if (fallbackLat != null && fallbackLon != null) {
          await cacheLastKnownCoords(fallbackLat, fallbackLon);
          return (fallbackLat, fallbackLon);
        }
      }
    } catch (e) {
      debugPrint(
        '[ProviderPresenceService] Falha no fallback de coordenadas: $e',
      );
    }

    return null;
  }

  static Future<void> touchLastSeen() async {
    try {
      await ensureSupabaseReady();
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(userUidKey)?.trim();
      final userIdRaw = prefs.getString(userIdKey)?.trim();
      final nowIso = DateTime.now().toIso8601String();
      final body = {'last_seen_at': nowIso};
      if (uid != null && uid.isNotEmpty) {
        await _backend.putJson('/api/v1/users/me/last-seen', body: body);
        return;
      }
      final userId = int.tryParse(userIdRaw ?? '');
      if (userId != null) {
        await _backend.putJson('/api/v1/users/$userId/last-seen', body: body);
      }
    } catch (e) {
      debugPrint('[ProviderPresenceService] Falha ao tocar last_seen_at: $e');
    }
  }

  static Future<ProviderPresenceTickResult> sendHeartbeatTick({
    String source = 'foreground',
    bool allowFixedProviders = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final online = prefs.getBool(onlineKey) ?? false;
    final isFixed = prefs.getBool(isFixedKey) ?? false;

    await _networkStatus.ensureInitialized();

    final canAttemptBackend = _networkStatus.canAttemptSupabase;
    if (!online || !canAttemptBackend || (isFixed && !allowFixedProviders)) {
      final decision = ProviderPresencePolicy.resolve(
        onlineForDispatch: online,
        isFixedLocation: isFixed,
        canAttemptBackend: canAttemptBackend,
        hasCoords: false,
        allowFixedProviders: allowFixedProviders,
      );
      await _applyNonSendingDecision(decision);
      return _recordAndReturn(decision.result);
    }

    final coords = await resolveBestEffortCoords();
    if (coords == null) {
      const result = ProviderPresenceTickResult.missingCoords;
      await touchLastSeen();
      return _recordAndReturn(result);
    }

    return sendHeartbeatWithCoords(
      lat: coords.$1,
      lon: coords.$2,
      source: source,
      allowFixedProviders: allowFixedProviders,
    );
  }

  static Future<ProviderPresenceTickResult> sendHeartbeatWithCoords({
    required double lat,
    required double lon,
    String source = 'foreground',
    bool allowFixedProviders = false,
  }) async {
    await cacheLastKnownCoords(lat, lon);

    final prefs = await SharedPreferences.getInstance();
    final online = prefs.getBool(onlineKey) ?? false;
    final isFixed = prefs.getBool(isFixedKey) ?? false;

    await _networkStatus.ensureInitialized();
    final decision = ProviderPresencePolicy.resolve(
      onlineForDispatch: online,
      isFixedLocation: isFixed,
      canAttemptBackend: _networkStatus.canAttemptSupabase,
      hasCoords: true,
      allowFixedProviders: allowFixedProviders,
    );

    if (!decision.shouldSendHeartbeat) {
      await _applyNonSendingDecision(decision);
      return _recordAndReturn(decision.result);
    }

    try {
      await ensureSupabaseReady();
      dynamic res;
      try {
        res = await _backend.postJson(
          '/api/v1/providers/heartbeat',
          body: {'lat': lat, 'lon': lon},
        );
      } catch (_) {
        // Compatibilidade com backends que expõem o heartbeat como PUT.
        res = await _backend.putJson(
          '/api/v1/providers/heartbeat',
          body: {'lat': lat, 'lon': lon},
        );
      }
      if (res == null) {
        throw StateError(
          'Heartbeat não autenticado ou rejeitado pelo backend.',
        );
      }
      _networkStatus.markBackendRecovered();
      await prefs.setString(
        lastHeartbeatIsoKey,
        DateTime.now().toIso8601String(),
      );
      debugPrint(
        '[ProviderPresenceService] heartbeat ok source=$source res=$res',
      );
      return _recordAndReturn(ProviderPresenceTickResult.sent);
    } catch (e) {
      await _networkStatus.markBackendFailure(e);
      debugPrint(
        '[ProviderPresenceService] heartbeat falhou source=$source error=$e',
      );
      await touchLastSeen();
      return _recordAndReturn(ProviderPresenceTickResult.failed);
    }
  }

  static Future<void> refreshServiceNotification(
    ServiceInstance service,
  ) async {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: '101 Service',
        content: 'Online para receber pedidos',
      );
      await service.setAsForegroundService();
      final online = await isOnlineForDispatch();
      await service.setAutoStartOnBootMode(online);
    }
  }

  static Future<void> _applyNonSendingDecision(
    ProviderPresenceDecision decision,
  ) async {
    if (decision.shouldTouchLastSeen) {
      await touchLastSeen();
    }
  }

  static Future<ProviderPresenceTickResult> _recordAndReturn(
    ProviderPresenceTickResult result,
  ) async {
    await _recordTickResult(result);
    return result;
  }

  static Future<void> _recordTickResult(
    ProviderPresenceTickResult result,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastTickResultKey, result.name);
  }
}
