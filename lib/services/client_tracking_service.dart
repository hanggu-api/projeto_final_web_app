import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import 'api_service.dart';
import 'network_status_service.dart';

class ClientTrackingService {
  const ClientTrackingService._();

  static const String trackingEnabledKey = 'fixed_client_tracking_enabled';
  static const String serviceIdKey = 'fixed_client_tracking_service_id';
  static const String sessionJsonKey = 'fixed_client_tracking_session_json';
  static const String userIdKey = 'fixed_client_tracking_user_id';
  static const String userUidKey = 'fixed_client_tracking_user_uid';
  static const String lastLatKey = 'fixed_client_tracking_last_lat';
  static const String lastLonKey = 'fixed_client_tracking_last_lon';
  static const String originLatKey = 'fixed_client_tracking_origin_lat';
  static const String originLonKey = 'fixed_client_tracking_origin_lon';
  static const String lastSentIsoKey = 'fixed_client_tracking_last_sent_at';
  static const String lastIssueKey = 'fixed_client_tracking_last_issue';
  static const String departureMarkedKey =
      'fixed_client_tracking_departure_marked';
  static const int foregroundNotifId = 889;
  static const Duration tickInterval = Duration(seconds: 30);
  static const double _movementThresholdMeters = 20;
  static const double _departureThresholdMeters = 120;

  static final NetworkStatusService _networkStatus = NetworkStatusService();

  static bool get supportsBackgroundService =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> persistContext({
    required String serviceId,
    required String userId,
    required String userUid,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(trackingEnabledKey, true);
    await prefs.setString(serviceIdKey, serviceId);
    await prefs.setString(userIdKey, userId);
    await prefs.setString(userUidKey, userUid);
    await prefs.remove(lastIssueKey);
    await prefs.setBool(departureMarkedKey, false);

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      await prefs.setString(sessionJsonKey, jsonEncode(session.toJson()));
    }
  }

  static Future<void> clearContext({
    bool stopBackground = true,
    String? finalStatus,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final serviceId = prefs.getString(serviceIdKey)?.trim() ?? '';
    if (serviceId.isNotEmpty && finalStatus != null) {
      try {
        await ensureSupabaseReady();
        await ApiService().updateClientTrackingState(
          serviceId,
          isActive: false,
          status: finalStatus,
          source: 'client_tracking_stop',
        );
      } catch (_) {
        // best effort
      }
    }

    await prefs.remove(trackingEnabledKey);
    await prefs.remove(serviceIdKey);
    await prefs.remove(lastLatKey);
    await prefs.remove(lastLonKey);
    await prefs.remove(originLatKey);
    await prefs.remove(originLonKey);
    await prefs.remove(lastSentIsoKey);
    await prefs.remove(lastIssueKey);
    await prefs.remove(departureMarkedKey);

    if (!stopBackground || !supportsBackgroundService) return;
    final service = FlutterBackgroundService();
    try {
      final running = await service.isRunning();
      if (running) {
        service.invoke('refreshContext');
      }
    } catch (_) {
      // ignore
    }
  }

  static Future<bool> isTrackingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(trackingEnabledKey) ?? false;
  }

  static Future<String?> activeServiceId() async {
    final prefs = await SharedPreferences.getInstance();
    final serviceId = prefs.getString(serviceIdKey)?.trim();
    return serviceId == null || serviceId.isEmpty ? null : serviceId;
  }

  static Future<String?> activeServiceIdForCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    final serviceId = prefs.getString(serviceIdKey)?.trim() ?? '';
    final persistedUid = prefs.getString(userUidKey)?.trim() ?? '';
    if (serviceId.isEmpty || persistedUid.isEmpty) return null;

    await ensureSupabaseReady();
    final currentUid =
        Supabase.instance.client.auth.currentUser?.id.trim() ?? '';
    if (currentUid.isEmpty || currentUid != persistedUid) return null;
    return serviceId;
  }

  static Future<String?> lastIssue() async {
    final prefs = await SharedPreferences.getInstance();
    final issue = prefs.getString(lastIssueKey)?.trim();
    return issue == null || issue.isEmpty ? null : issue;
  }

  static Future<void> startTrackingForService(
    Map<String, dynamic> service,
  ) async {
    final serviceId = (service['id'] ?? '').toString().trim();
    if (serviceId.isEmpty) return;

    final currentUser = Supabase.instance.client.auth.currentUser;
    final userUid = currentUser?.id.trim() ?? '';
    final api = ApiService();
    final userId = (api.userIdInt?.toString() ?? '').trim();
    if (userUid.isEmpty || userId.isEmpty) return;

    await persistContext(
      serviceId: serviceId,
      userId: userId,
      userUid: userUid,
    );
    await updateTrackingStateFromService(service);

    if (!supportsBackgroundService) return;
    final serviceController = FlutterBackgroundService();
    try {
      final running = await serviceController.isRunning();
      if (!running) {
        await serviceController.startService();
      }
      serviceController.invoke('refreshContext');
    } catch (e) {
      debugPrint('⚠️ [ClientTracking] Falha ao iniciar background service: $e');
    }
  }

  static Future<void> syncTrackingForService(
    Map<String, dynamic>? service,
  ) async {
    if (service == null) {
      await clearContext(finalStatus: 'inactive');
      return;
    }

    final scopeTag = ApiService().getServiceScopeTag(service);
    if (scopeTag != 'fixed') return;

    final status = (service['status'] ?? '').toString().toLowerCase().trim();
    final paymentStatus = (service['payment_status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final depositPaid =
        paymentStatus == 'paid' || paymentStatus == 'partially_paid';
    final isPrePaymentActive =
        status == 'waiting_payment' ||
        status == 'pending_payment' ||
        status == 'awaiting_payment';
    final shouldTrack =
        (depositPaid || isPrePaymentActive) &&
        !{'completed', 'cancelled', 'canceled', 'deleted'}.contains(status);

    final serviceId = (service['id'] ?? '').toString().trim();
    final currentServiceId = await activeServiceId();

    if (!shouldTrack) {
      if (currentServiceId == serviceId) {
        await clearContext(finalStatus: status.isEmpty ? 'inactive' : status);
      }
      return;
    }

    await startTrackingForService(service);
  }

  static Future<void> ensureSupabaseReady() async {
    await _networkStatus.ensureInitialized();
    if (!SupabaseConfig.isInitialized) {
      await SupabaseConfig.initialize(
        disableAuthAutoRefresh: true,
        detectSessionInUri: false,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final persistedSession = prefs.getString(sessionJsonKey);
    if (persistedSession == null || persistedSession.trim().isEmpty) return;

    final currentSession = Supabase.instance.client.auth.currentSession;
    if (currentSession == null) {
      try {
        await Supabase.instance.client.auth.recoverSession(persistedSession);
      } catch (e) {
        debugPrint(
          '⚠️ [ClientTracking] Falha ao recuperar sessão em background: $e',
        );
      }
    }
  }

  static Future<void> refreshServiceNotification(
    ServiceInstance service,
  ) async {
    if (service is! AndroidServiceInstance) return;
    final trackedServiceId = await activeServiceId();
    final content = trackedServiceId == null
        ? 'Acompanhamento do cliente inativo'
        : 'Acompanhando trajeto do cliente ate o local';
    await service.setForegroundNotificationInfo(
      title: '101 Service',
      content: content,
    );
    await service.setAsForegroundService();
    await service.setAutoStartOnBootMode(trackedServiceId != null);
  }

  static Future<void> updateTrackingStateFromService(
    Map<String, dynamic> service,
  ) async {
    final serviceId = (service['id'] ?? '').toString().trim();
    if (serviceId.isEmpty) return;
    final status = (service['status'] ?? '').toString().toLowerCase().trim();
    final active = !{
      'completed',
      'cancelled',
      'canceled',
      'deleted',
    }.contains(status);
    try {
      await ApiService().updateClientTrackingState(
        serviceId,
        isActive: active,
        status: status.isEmpty ? 'tracking_active' : status,
        source: 'client_tracking_sync',
      );
    } catch (_) {
      // best effort
    }
  }

  static Future<void> sendTrackingTick({String source = 'foreground'}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(trackingEnabledKey) ?? false)) return;

    final serviceId = prefs.getString(serviceIdKey)?.trim() ?? '';
    final persistedUid = prefs.getString(userUidKey)?.trim() ?? '';
    if (serviceId.isEmpty) return;

    await _networkStatus.ensureInitialized();
    await ensureSupabaseReady();
    final authUid = Supabase.instance.client.auth.currentUser?.id.trim() ?? '';
    if (persistedUid.isNotEmpty &&
        authUid.isNotEmpty &&
        persistedUid != authUid) {
      await clearContext(finalStatus: 'inactive');
      return;
    }

    final service = await ApiService().getServiceDetails(
      serviceId,
      scope: ServiceDataScope.fixedOnly,
      forceRefresh: true,
    );
    final status = (service['status'] ?? '').toString().toLowerCase().trim();
    if (service['not_found'] == true ||
        {'completed', 'cancelled', 'canceled', 'deleted'}.contains(status)) {
      await clearContext(finalStatus: status.isEmpty ? 'inactive' : status);
      return;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await prefs.setString(lastIssueKey, 'permission_denied');
      await ApiService().updateClientTrackingState(
        serviceId,
        isActive: false,
        status: 'permission_denied',
        source: source,
      );
      return;
    }

    final coords = await _resolveBestEffortCoords();
    if (coords == null) {
      await prefs.setString(lastIssueKey, 'location_unavailable');
      await ApiService().updateClientTrackingState(
        serviceId,
        isActive: false,
        status: 'location_unavailable',
        source: source,
      );
      return;
    }

    await prefs.remove(lastIssueKey);

    final previousLat = prefs.getDouble(lastLatKey);
    final previousLon = prefs.getDouble(lastLonKey);
    final lastSentAt = DateTime.tryParse(prefs.getString(lastSentIsoKey) ?? '');
    if (previousLat != null && previousLon != null && lastSentAt != null) {
      final movedMeters = Geolocator.distanceBetween(
        previousLat,
        previousLon,
        coords.$1,
        coords.$2,
      );
      final elapsed = DateTime.now().difference(lastSentAt);
      if (movedMeters < _movementThresholdMeters &&
          elapsed < const Duration(seconds: 90)) {
        return;
      }
    }

    final originLat = prefs.getDouble(originLatKey);
    final originLon = prefs.getDouble(originLonKey);
    if (originLat == null || originLon == null) {
      await prefs.setDouble(originLatKey, coords.$1);
      await prefs.setDouble(originLonKey, coords.$2);
    }

    final serviceStatus = (service['status'] ?? '').toString().toLowerCase();
    var trackingStatus = 'tracking_active';
    if (serviceStatus == 'client_arrived') {
      trackingStatus = 'client_arrived';
    } else if (serviceStatus == 'in_progress') {
      trackingStatus = 'in_progress';
    } else if (serviceStatus == 'client_departing') {
      trackingStatus = 'client_departing';
    }

    final shouldMarkDeparture = await _shouldMarkDeparture(
      serviceStatus: serviceStatus,
      currentLat: coords.$1,
      currentLon: coords.$2,
    );
    if (shouldMarkDeparture) {
      try {
        await ApiService().markClientDeparting(serviceId);
        await prefs.setBool(departureMarkedKey, true);
        trackingStatus = 'client_departing';
      } catch (_) {
        // best effort
      }
    }

    await ApiService().upsertClientTrackingLocation(
      serviceId,
      latitude: coords.$1,
      longitude: coords.$2,
      trackingStatus: trackingStatus,
      source: source,
    );

    await prefs.setDouble(lastLatKey, coords.$1);
    await prefs.setDouble(lastLonKey, coords.$2);
    await prefs.setString(lastSentIsoKey, DateTime.now().toIso8601String());
  }

  static Future<bool> _shouldMarkDeparture({
    required String serviceStatus,
    required double currentLat,
    required double currentLon,
  }) async {
    if (serviceStatus == 'client_departing' ||
        serviceStatus == 'client_arrived' ||
        serviceStatus == 'in_progress') {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(departureMarkedKey) ?? false) {
      return false;
    }

    final originLat = prefs.getDouble(originLatKey);
    final originLon = prefs.getDouble(originLonKey);
    if (originLat == null || originLon == null) return false;

    final movedMeters = Geolocator.distanceBetween(
      originLat,
      originLon,
      currentLat,
      currentLon,
    );
    return movedMeters >= _departureThresholdMeters;
  }

  static Future<(double, double)?> _resolveBestEffortCoords() async {
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return (lastKnown.latitude, lastKnown.longitude);
      }
    } catch (_) {}

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return (position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }
}
