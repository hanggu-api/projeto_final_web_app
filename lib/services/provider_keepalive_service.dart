import 'package:flutter_background_service/flutter_background_service.dart';

import 'provider_presence/provider_presence_policy.dart';
import 'provider_presence/provider_presence_service.dart';

class ProviderKeepaliveService {
  const ProviderKeepaliveService._();

  static const String onlineKey = ProviderPresenceService.onlineKey;
  static const String userIdKey = ProviderPresenceService.userIdKey;
  static const String userUidKey = ProviderPresenceService.userUidKey;
  // Legado: mantemos a chave para compatibilidade, mas a presença atual
  // não depende mais de payload de sessão serializada.
  static const String sessionJsonKey = 'provider_keepalive_session_json';
  static const String isFixedKey = ProviderPresenceService.isFixedKey;
  static const String lastLatKey = ProviderPresenceService.lastLatKey;
  static const String lastLonKey = ProviderPresenceService.lastLonKey;
  static const String lastHeartbeatIsoKey =
      ProviderPresenceService.lastHeartbeatIsoKey;
  static const String lastTickResultKey =
      ProviderPresenceService.lastTickResultKey;
  static const Duration heartbeatInterval =
      ProviderPresenceService.heartbeatInterval;

  static bool get supportsBackgroundService =>
      ProviderPresenceService.supportsBackgroundService;

  static Future<void> persistKeepaliveContext({
    required bool onlineForDispatch,
    required String userId,
    String? userUid,
    required bool isFixedLocation,
  }) {
    return ProviderPresenceService.persistContext(
      onlineForDispatch: onlineForDispatch,
      userId: userId,
      userUid: userUid,
      isFixedLocation: isFixedLocation,
    );
  }

  static Future<void> clearKeepaliveContext() {
    return ProviderPresenceService.clearContext();
  }

  static Future<void> cacheLastKnownCoords(double lat, double lon) {
    return ProviderPresenceService.cacheLastKnownCoords(lat, lon);
  }

  static Future<(double, double)?> getCachedLastKnownCoords() {
    return ProviderPresenceService.getCachedLastKnownCoords();
  }

  static Future<bool> isOnlineForDispatch() {
    return ProviderPresenceService.isOnlineForDispatch();
  }

  static Future<void> startBackgroundService() {
    return ProviderPresenceService.startBackgroundService();
  }

  static Future<void> stopBackgroundService() {
    return ProviderPresenceService.stopBackgroundService();
  }

  static Future<void> ensureSupabaseReady() {
    return ProviderPresenceService.ensureSupabaseReady();
  }

  static Future<(double, double)?> resolveBestEffortCoords() {
    return ProviderPresenceService.resolveBestEffortCoords();
  }

  static Future<void> touchLastSeen() {
    return ProviderPresenceService.touchLastSeen();
  }

  static Future<ProviderPresenceTickResult> sendHeartbeatTick({
    String source = 'foreground',
    bool allowFixedProviders = false,
  }) {
    return ProviderPresenceService.sendHeartbeatTick(
      source: source,
      allowFixedProviders: allowFixedProviders,
    );
  }

  static Future<ProviderPresenceTickResult> sendHeartbeatWithCoords({
    required double lat,
    required double lon,
    String source = 'foreground',
    bool allowFixedProviders = false,
  }) {
    return ProviderPresenceService.sendHeartbeatWithCoords(
      lat: lat,
      lon: lon,
      source: source,
      allowFixedProviders: allowFixedProviders,
    );
  }

  static Future<void> refreshServiceNotification(ServiceInstance service) {
    return ProviderPresenceService.refreshServiceNotification(service);
  }
}
