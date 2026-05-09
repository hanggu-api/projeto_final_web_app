import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domains/dispatch/dispatch_api.dart';
import '../domains/dispatch/models/service_offer_state.dart';
import '../domains/service_tracking/models/service_status_view.dart';
import '../domains/service_tracking/tracking_api.dart';
import 'realtime_service.dart';
import 'notification_service.dart';
import 'analytics_service.dart';
import '../core/utils/logger.dart';
import '../core/utils/fixed_booking_hold_policy.dart';
import '../core/utils/service_flow_classifier.dart';
import '../core/config/supabase_config.dart';
import 'remote_config_service.dart';
import 'task_autocomplete.dart';
import '../core/security/security_middleware.dart' as sm;
import '../core/home/backend_home_api.dart';
import '../core/network/backend_api_client.dart';
import '../core/scheduling/backend_scheduling_api.dart';
import '../core/tracking/backend_tracking_api.dart';
import '../core/models/agendamento_model.dart';
import 'models/api_identity_snapshot.dart';
import 'support/api_geo_service.dart';
import 'support/api_media_storage.dart';
import 'support/api_session_bootstrap.dart';
import 'support/api_user_preferences.dart';

enum ServiceDataScope { auto, mobileOnly, fixedOnly, tripOnly }

class ProviderScheduleConfigResult {
  final int providerId;
  final String? providerUid;
  final List<Map<String, dynamic>> configs;
  final bool usedLegacyFallback;
  final bool foundProviderSchedules;

  const ProviderScheduleConfigResult({
    required this.providerId,
    required this.providerUid,
    required this.configs,
    required this.usedLegacyFallback,
    required this.foundProviderSchedules,
  });

  bool get hasAnyConfig => configs.isNotEmpty;
  int get configCount => configs.length;
}

class ApiService {
  static const String _providerProfileReviewsProjection =
      'id,reviewer_id,reviewee_id,rating,comment,created_at';
  // ignore: unused_field
  static const String _serviceDisputeProjection =
      'id,service_id,user_id,status,type,platform_decision,reason,created_at,client_acknowledged_at';
  static StreamSubscription<AuthState>? _authStateSubscription;
  static bool _isHandlingAuthState = false;
  static final Map<String, Future<Map<String, dynamic>>>
  _serviceDetailsInFlight = <String, Future<Map<String, dynamic>>>{};
  static final Map<String, ({DateTime fetchedAt, Map<String, dynamic> data})>
  _serviceDetailsCache =
      <String, ({DateTime fetchedAt, Map<String, dynamic> data})>{};
  static const Duration _serviceDetailsCacheTtl = Duration(milliseconds: 800);
  // URLs Legadas (Mantidas comentadas para referência se necessário)
  // static const String _androidEmulatorApiUrl = 'http://10.0.2.2:4011/api';
  // static const String _iosRealDeviceApiUrl = 'http://localhost:4011/api';

  static List<Map<String, dynamic>>? _taskCatalogCache;
  static DateTime? _taskCatalogCacheAt;
  static const _mixBacuriLat = -5.5017472;
  static const _mixBacuriLon = -47.45835915;
  static const _mixBacuriAddress = 'Mix Mateus - Babaçulândia, Imperatriz - MA';
  static const _fixedProviderDefaultLat = -5.52639;
  static const _fixedProviderDefaultLon = -47.49167;
  static const _fixedProviderDefaultAddress = 'Centro, Imperatriz - MA';
  static const Duration fixedBookingLeadTime = Duration.zero;
  static const Duration fixedBookingPixHoldDuration = Duration(minutes: 10);
  static const Set<String> _blockingAppointmentStatuses = {
    'confirmed',
    'scheduled',
    'waiting_payment',
    'booked',
    'in_progress',
  };

  Future<Map<String, dynamic>?> _selectUserRowMaybeSingleBy(
    String field,
    dynamic value,
  ) async {
    try {
      final res = await _backendApiClient.getJson(
        '/api/v1/users?${field}_eq=${Uri.encodeQueryComponent('$value')}&limit=1',
      );
      final data = res?['data'];
      if (data is List && data.isNotEmpty) {
        return Map<String, dynamic>.from(data.first as Map);
      }
      if (res is Map<String, dynamic> && res['id'] != null) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [ApiService] _selectUserRowMaybeSingleBy falhou: $e');
      return null;
    }
  }

  // Nomes de prestadores suprimidos da busca pública (dados de teste/demo).
  // Idealmente migrar para coluna `is_suppressed` na tabela `providers` no banco.
  static const Set<String> _suppressedFixedProviderNames = {
    'demo prestador',
    'cabelo4',
  };
  late final DispatchApi _dispatchApi = DispatchApi(
    loadActiveProviderOfferState: getActiveProviderOfferState,
    acceptService: acceptService,
    rejectService: rejectService,
  );
  late final TrackingApi _trackingApi = TrackingApi(
    activeSnapshotGetter: () => activeServiceSnapshot,
    loadActiveSnapshot:
        ({
          bool forceRefresh = false,
          Duration ttl = _activeServiceSnapshotTtl,
        }) => getActiveServiceSnapshot(forceRefresh: forceRefresh, ttl: ttl),
    resolveScopeTag: getServiceScopeTag,
  );
  final BackendTrackingApi _backendTrackingApi = const BackendTrackingApi();
  final BackendHomeApi _backendHomeApi = const BackendHomeApi();
  final BackendSchedulingApi _backendSchedulingApi =
      const BackendSchedulingApi();
  final BackendApiClient _backendApiClient = const BackendApiClient();

  SupabaseClient get _supa {
    if (!SupabaseConfig.isInitialized) {
      throw StateError('Supabase não inicializado');
    }
    return Supabase.instance.client;
  }

  DispatchApi get dispatch => _dispatchApi;
  TrackingApi get tracking => _trackingApi;

  static String get baseUrl {
    // URL das Edge Functions do Supabase
    // Importante: deve seguir o mesmo SUPABASE_URL configurado no app,
    // para evitar "Invalid JWT" quando cair no HTTP fallback.
    final url = SupabaseConfig.url.trim();
    if (url.isNotEmpty) return '$url/functions/v1';
    // Fallback de segurança (dev legado)
    // Fallback de segurança: sem URL configurada, Edge Functions não funcionarão
    return '';
  }

  static String fixUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    return resolveStorageUrl(url) ?? url;
  }

  static bool get isLocalWebEnvironment {
    if (!kIsWeb) return false;
    final host = Uri.base.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  static String? resolveStorageUrl(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    const bucketPrefixes = <String, String>{
      'avatars/': 'avatars',
      'chat_media/': 'chat_media',
      'service_media/': 'service_media',
      'verification/': 'verification',
    };

    for (final entry in bucketPrefixes.entries) {
      if (trimmed.startsWith(entry.key)) {
        return Supabase.instance.client.storage
            .from(entry.value)
            .getPublicUrl(trimmed);
      }
    }

    return null;
  }

  bool _shouldSuppressFixedProvider(Map<String, dynamic> provider) {
    final providerData = provider['providers'] as Map<String, dynamic>?;
    final fullName = (provider['full_name']?.toString() ?? '')
        .trim()
        .toLowerCase();
    final commercialName = (providerData?['commercial_name']?.toString() ?? '')
        .trim()
        .toLowerCase();
    return _suppressedFixedProviderNames.contains(fullName) ||
        _suppressedFixedProviderNames.contains(commercialName);
  }

  String? _token;
  String? _role;
  int? _userId;
  Map<String, dynamic>? _currentUserData;
  bool _isMedical = false;
  bool _isFixedLocation = false;
  Map<String, dynamic>? _activeServiceSnapshot;
  DateTime? _activeServiceSnapshotAt;
  static const Duration _activeServiceSnapshotTtl = Duration(seconds: 15);

  // FCM Token
  String? _fcmToken;
  String? get fcmToken => _fcmToken;
  void setFcmToken(String token) => _fcmToken = token;

  final _secureStorage = const FlutterSecureStorage();
  final String _tokenKey = 'auth_token';

  bool get isMedical => _isMedical;
  bool get isFixedLocation => _isFixedLocation;
  String? get role => _role;
  String? get userId => _userId?.toString();
  String? get currentUserId => _userId?.toString();
  int? get userIdInt => _userId;
  Map<String, dynamic>? get userData => _currentUserData;
  bool get hasHydratedIdentity =>
      _userId != null ||
      (_role?.trim().isNotEmpty ?? false) ||
      _isFixedLocation;

  http.Client _client = http.Client();

  /// Sets a custom HTTP client (useful for testing)
  void setClient(http.Client client) {
    _client = client;
  }

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  late final ApiMediaStorage _mediaStorage = ApiMediaStorage(
    resolveStorageUrl: resolveStorageUrl,
    isLocalWebEnvironment: () => isLocalWebEnvironment,
    fetchRaw: getRaw,
    exceptionFactory: ({required message, required statusCode}) =>
        ApiException(message: message, statusCode: statusCode),
  );
  late final ApiGeoService _geoService = ApiGeoService(
    invokeEdgeFunction: invokeEdgeFunction,
  );
  final ApiUserPreferences _userPreferences = ApiUserPreferences();

  Future<void> _ensureFixedProviderSearchContract({
    required SupabaseClient client,
    required int providerUserId,
  }) async {
    await _backendApiClient.postJson(
      '/api/v1/providers/$providerUserId/search-contract',
      body: const <String, dynamic>{
        'mode': 'fixed',
        'serviceType': 'at_provider',
        'isFixedLocation': true,
      },
    );
  }

  // ignore: unused_element
  Future<void> _ensureMobileProviderSearchContract({
    required SupabaseClient client,
    required int providerUserId,
  }) async {
    await _backendApiClient.postJson(
      '/api/v1/providers/$providerUserId/search-contract',
      body: const <String, dynamic>{
        'mode': 'mobile',
        'serviceType': 'on_site',
        'isFixedLocation': false,
      },
    );

    // Garante espelho local consistente para redirect/layout.
    _isFixedLocation = false;
    _currentUserData ??= <String, dynamic>{};
    _currentUserData!['is_fixed_location'] = false;
    _currentUserData!['sub_role'] = 'mobile';
    await _secureStorage.write(key: 'is_fixed_location', value: 'false');
  }

  /// Inicializa listeners e estados que dependem do Supabase
  void init() {
    if (!SupabaseConfig.isInitialized) {
      debugPrint(
        '⚠️ [ApiService] init skipped because Supabase is not initialized',
      );
      return;
    }

    if (_authStateSubscription != null) {
      debugPrint('ℹ️ [ApiService] Auth listener already initialized');
      return;
    }

    try {
      // Escuta mudanças de sessão no Supabase Auth
      _authStateSubscription = _supa.auth.onAuthStateChange.listen((
        data,
      ) async {
        // Guarda contra loop de logout/reentrada
        if (_isHandlingAuthState) {
          debugPrint(
            'ℹ️ [ApiService] Auth state change ignored (already handling)',
          );
          return;
        }

        final session = data.session;
        if (session != null) {
          _token = session.accessToken;

          if (_userId == null || data.event == AuthChangeEvent.signedIn) {
            debugPrint(
              '🔄 [ApiService] Auto-syncing user profile after Auth event: ${data.event}',
            );
            _isHandlingAuthState = true;
            try {
              await loginWithFirebase(session.accessToken);
            } catch (e) {
              debugPrint('❌ [ApiService] Erro no auto-sync: $e');
            } finally {
              _isHandlingAuthState = false;
            }
          }
        } else {
          _token = null;
          _userId = null;
          _role = null;
        }
      });
      debugPrint('✅ [ApiService] Auth listener initialized');
    } catch (e) {
      debugPrint('⚠️ [ApiService] Failed to initialize auth listener: $e');
    }
  }

  Future<String?> _getToken() async {
    if (SupabaseConfig.isInitialized) {
      final session = _supa.auth.currentSession;
      if (session != null) {
        if (session.isExpired) {
          debugPrint(
            '🔄 [ApiService] Sessão Supabase expirada. Tentando refresh...',
          );
          try {
            await _supa.auth.refreshSession();
          } catch (e) {
            debugPrint('❌ [ApiService] Erro no refresh automático: $e');
          }
        }
        return _supa.auth.currentSession?.accessToken;
      }
    }

    // Fallback manual temporário para persistência (se o Auth client perder estado)
    if (_token != null && _token!.isNotEmpty) return _token;

    try {
      final storedToken = await _secureStorage.read(key: _tokenKey);
      if (storedToken != null && storedToken.isNotEmpty) {
        _token = storedToken;
        return _token;
      }
    } catch (_) {}

    return null;
  }

  // --- Appointments / Scheduling ---

  DateTime? _parseDateKeyLocal(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  bool _hasScheduleWorkingWindow(Map<String, dynamic> row) {
    final start = row['start_time']?.toString().trim() ?? '';
    final end = row['end_time']?.toString().trim() ?? '';
    return start.isNotEmpty && end.isNotEmpty;
  }

  bool _isScheduleEnabled(Map<String, dynamic> row) {
    final rawIsEnabled =
        row['is_enabled'] ?? row['enabled'] ?? row['is_active'];
    if (rawIsEnabled == null) {
      return _hasScheduleWorkingWindow(row);
    }
    return _parseBool(rawIsEnabled);
  }

  Map<String, dynamic> _mapScheduleRowToConfig(Map<String, dynamic> row) {
    return {
      'day_of_week': row['day_of_week'],
      'start_time': row['start_time'],
      'end_time': row['end_time'],
      'lunch_start': row['break_start'] ?? row['lunch_start'],
      'lunch_end': row['break_end'] ?? row['lunch_end'],
      'break_start': row['break_start'] ?? row['lunch_start'],
      'break_end': row['break_end'] ?? row['lunch_end'],
      'slot_duration': row['slot_duration'] ?? 30,
      'is_enabled': _isScheduleEnabled(row),
    };
  }

  String? _currentAuthUid() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.trim().isEmpty) return null;
    return uid.trim();
  }

  Future<Map<String, dynamic>?> _getUserRowById(int userId) async {
    // Backend-first: tenta resolver usuário via snapshot canônico da home.
    try {
      final snapshot = await _backendHomeApi.fetchClientHome();
      final candidates = <Map<String, dynamic>>[
        if (snapshot?.activeService != null) snapshot!.activeService!,
        if (snapshot?.pendingFixedPayment != null)
          snapshot!.pendingFixedPayment!,
        if (snapshot?.upcomingAppointment != null)
          snapshot!.upcomingAppointment!,
        ...?snapshot?.services,
      ];
      for (final row in candidates) {
        final candidateId = int.tryParse(
          '${row['user_id'] ?? row['client_id'] ?? row['id'] ?? ''}',
        );
        if (candidateId == userId) return Map<String, dynamic>.from(row);
      }
    } catch (_) {
      // fallback Supabase below
    }

    try {
      final row = await _backendApiClient.getJson('/api/v1/users/$userId');
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getUserRowByAuthUid(String authUid) async {
    // Backend-first: tenta resolver usuário via snapshot canônico da home.
    try {
      final snapshot = await _backendHomeApi.fetchClientHome();
      final candidates = <Map<String, dynamic>>[
        if (snapshot?.activeService != null) snapshot!.activeService!,
        if (snapshot?.pendingFixedPayment != null)
          snapshot!.pendingFixedPayment!,
        if (snapshot?.upcomingAppointment != null)
          snapshot!.upcomingAppointment!,
        ...?snapshot?.services,
      ];
      for (final row in candidates) {
        final candidateUid =
            '${row['supabase_uid'] ?? row['client_uid'] ?? row['auth_uid'] ?? ''}'
                .trim();
        if (candidateUid == authUid.trim()) {
          return Map<String, dynamic>.from(row);
        }
      }
    } catch (_) {
      // fallback Supabase below
    }

    try {
      final res = await _backendApiClient.getJson(
        '/api/v1/users?supabase_uid_eq=${Uri.encodeQueryComponent(authUid)}&limit=1',
      );
      final data = res?['data'];
      if (data is List && data.isNotEmpty) {
        return Map<String, dynamic>.from(data.first as Map);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _generateSlotsForDate({
    required int providerId,
    required DateTime selectedDate,
    required List<Map<String, dynamic>> configsRaw,
    required List<Map<String, dynamic>> appointmentsList,
    List<Map<String, dynamic>> slotHoldsList = const [],
    int? requiredDurationMinutes,
  }) {
    final int dayIndex = selectedDate.weekday % 7;
    final previousDate = selectedDate.subtract(const Duration(days: 1));
    final previousDayIndex = previousDate.weekday % 7;

    bool spansNextDay(Map<String, dynamic> conf) {
      final startRaw = '${conf['start_time'] ?? ''}'.trim();
      final endRaw = '${conf['end_time'] ?? ''}'.trim();
      if (startRaw.isEmpty || endRaw.isEmpty) return false;
      final startParts = startRaw.split(':').map(int.tryParse).toList();
      final endParts = endRaw.split(':').map(int.tryParse).toList();
      if (startParts.length < 2 ||
          endParts.length < 2 ||
          startParts[0] == null ||
          startParts[1] == null ||
          endParts[0] == null ||
          endParts[1] == null) {
        return false;
      }
      final anchor = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );
      final start = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
        startParts[0]!,
        startParts[1]!,
      );
      final end = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
        endParts[0]!,
        endParts[1]!,
      );
      return !start.isBefore(end);
    }

    final List<({Map<String, dynamic> config, DateTime anchorDate})>
    dayConfigsWithAnchor = [];
    for (final rawConf in configsRaw) {
      final conf = Map<String, dynamic>.from(rawConf);
      final confDay = conf['day_of_week'] is int
          ? conf['day_of_week'] as int
          : int.tryParse(conf['day_of_week']?.toString() ?? '') ?? -1;
      final isEnabled = _isScheduleEnabled(conf);
      if (!isEnabled) continue;

      if (confDay == dayIndex) {
        dayConfigsWithAnchor.add((config: conf, anchorDate: selectedDate));
        continue;
      }

      if (confDay == previousDayIndex && spansNextDay(conf)) {
        dayConfigsWithAnchor.add((config: conf, anchorDate: previousDate));
      }
    }

    if (dayConfigsWithAnchor.isEmpty) return <Map<String, dynamic>>[];

    DateTime? parseDateTime(String? value) {
      if (value == null) return null;
      try {
        return DateTime.parse(value).toLocal();
      } catch (_) {
        return null;
      }
    }

    final busyAppointments = appointmentsList
        .map((appt) {
          final status = (appt['status'] ?? '').toString().toLowerCase().trim();
          if (!_blockingAppointmentStatuses.contains(status)) return null;
          final start = parseDateTime(appt['start_time']?.toString());
          final end = parseDateTime(appt['end_time']?.toString());
          if (start == null || end == null) return null;
          return {'raw': appt, 'start': start, 'end': end};
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    final busyHolds = slotHoldsList
        .map((hold) {
          final holdMap = Map<String, dynamic>.from(hold);
          final holdDecision = FixedBookingHoldPolicy.resolveHold(
            holdMap,
            intent: _extractFixedBookingIntentSnapshotFromHold(holdMap),
          );
          if (!holdDecision.blocksAvailability) {
            return null;
          }
          final start = parseDateTime(holdMap['scheduled_at']?.toString());
          final end = parseDateTime(holdMap['scheduled_end_at']?.toString());
          if (start == null || end == null) return null;
          return {
            'raw': {
              ...holdMap,
              'service_status': holdDecision.providerAgendaServiceStatus,
              'hold_lifecycle': holdDecision.lifecycle.name,
            },
            'start': start,
            'end': end,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    final generatedSlots = <Map<String, dynamic>>[];
    for (final entry in dayConfigsWithAnchor) {
      final conf = entry.config;
      final anchorDate = entry.anchorDate;
      DateTime? parseTimeForAnchor(String? value) {
        if (value == null || value.isEmpty) return null;
        final parts = value.split(':').map((p) => int.tryParse(p)).toList();
        if (parts.length < 2 || parts[0] == null || parts[1] == null) {
          return null;
        }
        return DateTime(
          anchorDate.year,
          anchorDate.month,
          anchorDate.day,
          parts[0]!,
          parts[1]!,
        );
      }

      final start = parseTimeForAnchor(
        conf['start_time']?.toString() ?? '08:00',
      );
      var end = parseTimeForAnchor(conf['end_time']?.toString() ?? '18:00');
      if (start == null || end == null) continue;
      if (!start.isBefore(end)) {
        end = end.add(const Duration(days: 1));
      }

      final lunchStart = parseTimeForAnchor(
        conf['lunch_start']?.toString() ??
            conf['break_start']?.toString() ??
            '',
      );
      var lunchEnd = parseTimeForAnchor(
        conf['lunch_end']?.toString() ?? conf['break_end']?.toString() ?? '',
      );
      if (lunchStart != null &&
          lunchEnd != null &&
          !lunchStart.isBefore(lunchEnd)) {
        lunchEnd = lunchEnd.add(const Duration(days: 1));
      }

      final configuredSlotDuration = conf['slot_duration'] is int
          ? conf['slot_duration'] as int
          : int.tryParse(conf['slot_duration']?.toString() ?? '') ?? 30;
      final slotDurationMinutes = configuredSlotDuration.clamp(15, 180);

      DateTime slot = start;
      while (slot.isBefore(end)) {
        final slotEnd = slot.add(Duration(minutes: slotDurationMinutes));
        if (slotEnd.isAfter(end)) break;
        if (slotEnd.isBefore(selectedDate) ||
            slot.isAfter(selectedDate.add(const Duration(days: 1)))) {
          slot = slotEnd;
          continue;
        }

        if (lunchStart != null && lunchEnd != null) {
          final overlapsLunch =
              slot.isBefore(lunchEnd) && slotEnd.isAfter(lunchStart);
          if (overlapsLunch) {
            generatedSlots.add({
              'start_time': slot.toIso8601String(),
              'end_time': slotEnd.toIso8601String(),
              'status': 'lunch',
              'is_selectable': false,
              'provider_id': providerId,
              'lunch_label':
                  '${lunchStart.toString().substring(11, 16)}-${lunchEnd.toString().substring(11, 16)}',
            });
            slot = slotEnd;
            continue;
          }
        }

        bool occupied = false;
        Map<String, dynamic>? appointment;
        for (final appt in busyAppointments) {
          final apptStart = appt['start'] as DateTime;
          final apptEnd = appt['end'] as DateTime;
          if (slot.isBefore(apptEnd) && apptStart.isBefore(slotEnd)) {
            occupied = true;
            appointment = Map<String, dynamic>.from(
              appt['raw'] as Map<String, dynamic>,
            );
            break;
          }
        }

        if (!occupied) {
          for (final hold in busyHolds) {
            final holdStart = hold['start'] as DateTime;
            final holdEnd = hold['end'] as DateTime;
            if (slot.isBefore(holdEnd) && holdStart.isBefore(slotEnd)) {
              occupied = true;
              appointment = Map<String, dynamic>.from(
                hold['raw'] as Map<String, dynamic>,
              )..['is_slot_hold'] = true;
              break;
            }
          }
        }

        generatedSlots.add({
          'start_time': slot.toIso8601String(),
          'end_time': slotEnd.toIso8601String(),
          'status': occupied ? 'booked' : 'free',
          'is_manual_block': false,
          'provider_id': providerId,
          if (occupied) 'appointment': appointment,
        });

        slot = slotEnd;
      }
    }

    generatedSlots.sort((a, b) {
      final aStart = DateTime.parse(a['start_time'].toString());
      final bStart = DateTime.parse(b['start_time'].toString());
      return aStart.compareTo(bStart);
    });

    if (requiredDurationMinutes != null && requiredDurationMinutes > 0) {
      for (int i = 0; i < generatedSlots.length; i++) {
        final current = generatedSlots[i];
        if (current['status'] != 'free') {
          current['is_selectable'] = false;
          continue;
        }

        final startTime = DateTime.parse(current['start_time']);
        final targetEndTime = startTime.add(
          Duration(minutes: requiredDurationMinutes),
        );

        bool canFit = true;
        DateTime checkTime = startTime;
        int j = i;
        while (checkTime.isBefore(targetEndTime)) {
          if (j >= generatedSlots.length) {
            canFit = false;
            break;
          }
          final slotToCheck = generatedSlots[j];
          final slotStart = DateTime.parse(slotToCheck['start_time']);
          final slotEnd = DateTime.parse(slotToCheck['end_time']);
          if (slotToCheck['status'] != 'free' || slotStart != checkTime) {
            canFit = false;
            break;
          }
          checkTime = slotEnd;
          j++;
        }
        current['is_selectable'] = canFit;
      }
    } else {
      for (final s in generatedSlots) {
        s['is_selectable'] = s['status'] == 'free';
      }
    }

    return generatedSlots;
  }

  @visibleForTesting
  List<Map<String, dynamic>> debugGenerateSlotsForDate({
    required int providerId,
    required DateTime selectedDate,
    required List<Map<String, dynamic>> configsRaw,
    required List<Map<String, dynamic>> appointmentsList,
    List<Map<String, dynamic>> slotHoldsList = const [],
    int? requiredDurationMinutes,
  }) {
    return _generateSlotsForDate(
      providerId: providerId,
      selectedDate: selectedDate,
      configsRaw: configsRaw,
      appointmentsList: appointmentsList,
      slotHoldsList: slotHoldsList,
      requiredDurationMinutes: requiredDurationMinutes,
    );
  }

  Future<List<Map<String, dynamic>>> getProviderSlots(
    dynamic providerId, {
    String? date,
  }) async {
    final parsedProviderId = int.tryParse(providerId.toString()) ?? 0;
    if (parsedProviderId <= 0) return const <Map<String, dynamic>>[];

    // A agenda do prestador deve refletir apenas o dia selecionado.
    final DateTime targetDate = date != null
        ? (_parseDateKeyLocal(date) ?? DateTime.now().toLocal())
        : DateTime.now().toLocal();

    final backendSlots = await _backendSchedulingApi.fetchProviderSlots(
      parsedProviderId,
      date: date ?? targetDate.toIso8601String().split('T').first,
    );
    return backendSlots ?? const <Map<String, dynamic>>[];
  }

  Map<String, dynamic>? _extractFixedBookingIntentSnapshotFromHold(
    Map<String, dynamic> hold, {
    Map<String, dynamic>? intent,
  }) {
    if (intent != null) return intent;

    final snapshot = <String, dynamic>{
      'status': hold['intent_status'],
      'payment_status': hold['intent_payment_status'],
      'created_service_id': hold['created_service_id'],
      'hold_status': hold['status'],
      'hold_expires_at': hold['expires_at'],
    }..removeWhere((key, value) => value == null);

    return snapshot.isEmpty ? null : snapshot;
  }

  Future<List<Map<String, dynamic>>> getProviderAvailableSlots(
    dynamic providerId, {
    String? date,
    int? requiredDurationMinutes,
  }) async {
    final parsedProviderId = int.tryParse(providerId.toString()) ?? 0;
    if (parsedProviderId <= 0) return const <Map<String, dynamic>>[];
    final targetDate = date != null
        ? (_parseDateKeyLocal(date) ?? DateTime.now().toLocal())
        : DateTime.now().toLocal();
    final dateKey = targetDate.toIso8601String().split('T').first;
    final slots = await _backendSchedulingApi.fetchProviderAvailability(
      parsedProviderId,
      date: dateKey,
      requiredDurationMinutes: requiredDurationMinutes,
    );
    return slots ?? const <Map<String, dynamic>>[];
  }

  Future<Map<String, List<Map<String, dynamic>>>>
  getProvidersAvailableSlotsBatch({
    required List<int> providerIds,
    required List<String> dateKeys,
    int? requiredDurationMinutes,
  }) async {
    final ids = providerIds.toSet().where((id) => id > 0).toList()..sort();
    final normalizedDateKeys = dateKeys.toSet().toList()..sort();
    if (ids.isEmpty || normalizedDateKeys.isEmpty) {
      return const <String, List<Map<String, dynamic>>>{};
    }

    final dateMap = <String, DateTime>{};
    for (final key in normalizedDateKeys) {
      final parsed = _parseDateKeyLocal(key);
      if (parsed != null) dateMap[key] = parsed;
    }
    if (dateMap.isEmpty) return const <String, List<Map<String, dynamic>>>{};

    final result = <String, List<Map<String, dynamic>>>{};
    for (final providerId in ids) {
      for (final entry in dateMap.entries) {
        final key = '$providerId|${entry.key}';
        final slots = await _backendSchedulingApi.fetchProviderAvailability(
          providerId,
          date: entry.key,
          requiredDurationMinutes: requiredDurationMinutes,
        );
        result[key] = slots ?? const <Map<String, dynamic>>[];
      }
    }
    return result;
  }

  Future<Map<String, dynamic>?> getProviderNextAvailableSlot(
    int providerId, {
    int horizonDays = 14,
    int? requiredDurationMinutes,
  }) async {
    if (providerId <= 0 || horizonDays <= 0) return null;

    final today = DateTime.now();
    final dateKeys = List<String>.generate(horizonDays, (index) {
      final day = DateTime(
        today.year,
        today.month,
        today.day,
      ).add(Duration(days: index));
      return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    });

    final batch = await getProvidersAvailableSlotsBatch(
      providerIds: [providerId],
      dateKeys: dateKeys,
      requiredDurationMinutes: requiredDurationMinutes,
    );

    final minimumStartTime = DateTime.now().add(fixedBookingLeadTime);

    for (final dateKey in dateKeys) {
      final slots = batch['$providerId|$dateKey'] ?? const [];
      for (final slot in slots) {
        final slotMap = Map<String, dynamic>.from(slot);
        final slotStart = DateTime.tryParse(
          '${slotMap['start_time'] ?? ''}',
        )?.toLocal();
        final isEligible =
            slotStart != null && !slotStart.isBefore(minimumStartTime);
        if (slotMap['is_selectable'] == true && isEligible) {
          return slotMap;
        }
      }
    }

    return null;
  }

  Future<void> markSlotBusy(DateTime startTime, {DateTime? endTime}) async {
    if (_userId == null) throw Exception('Not authenticated');
    final ok = await _backendSchedulingApi.markProviderSlotBusy(
      _userId!,
      startTime,
      endTime: endTime ?? startTime.add(const Duration(hours: 1)),
    );
    if (!ok) {
      throw Exception(
        'Falha ao bloquear slot via /api/v1/providers/:id/slots/busy',
      );
    }
  }

  Future<void> bookSlot(
    int providerId,
    DateTime startTime, {
    DateTime? endTime,
    String? serviceRequestId,
    String? agendamentoServicoId,
    String? procedureName,
  }) async {
    if (_userId == null) throw Exception('Not authenticated');
    final ok = await _backendSchedulingApi.bookProviderSlot(
      providerId,
      clientId: _userId!,
      startTime: startTime,
      endTime: endTime ?? startTime.add(const Duration(hours: 1)),
      serviceRequestId: serviceRequestId,
      agendamentoServicoId: agendamentoServicoId,
      procedureName: procedureName,
    );
    if (!ok) {
      throw Exception(
        'Falha ao reservar slot via /api/v1/providers/:id/slots/book',
      );
    }
  }

  Future<String> createFixedBookingServiceRequest({
    required int providerId,
    required String procedureName,
    required DateTime scheduledStartUtc,
    DateTime? scheduledEndUtc,
    required double totalPrice,
    required double upfrontPrice,
    int? professionId,
    String? professionName,
    int? taskId,
    int? categoryId,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final intent = await createPendingFixedBookingIntent(
      providerId: providerId,
      procedureName: procedureName,
      scheduledStartUtc: scheduledStartUtc,
      scheduledEndUtc: scheduledEndUtc,
      totalPrice: totalPrice,
      upfrontPrice: upfrontPrice,
      professionId: professionId,
      professionName: professionName,
      taskId: taskId,
      categoryId: categoryId,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
    return intent['id'].toString();
  }

  Future<Map<String, dynamic>> createPendingFixedBookingIntent({
    required int providerId,
    required String procedureName,
    required DateTime scheduledStartUtc,
    DateTime? scheduledEndUtc,
    required double totalPrice,
    required double upfrontPrice,
    int? professionId,
    String? professionName,
    int? taskId,
    String? taskName,
    int? categoryId,
    String? address,
    double? latitude,
    double? longitude,
    List<String> imageKeys = const [],
    String? videoKey,
  }) async {
    if (_userId == null) {
      throw ApiException(message: 'Not authenticated', statusCode: 401);
    }

    final supabase = _supa;
    final authUid = supabase.auth.currentUser?.id;
    if (authUid == null || authUid.trim().isEmpty) {
      throw ApiException(
        message: 'Sessão inválida para gerar PIX do agendamento.',
        statusCode: 401,
      );
    }

    try {
      final backendIntent = await _backendHomeApi
          .createPendingFixedBookingIntent(
            providerId: providerId,
            procedureName: procedureName,
            scheduledStartUtc: scheduledStartUtc,
            scheduledEndUtc: scheduledEndUtc,
            totalPrice: totalPrice,
            upfrontPrice: upfrontPrice,
            professionId: professionId,
            professionName: professionName,
            taskId: taskId,
            taskName: taskName,
            categoryId: categoryId,
            address: address,
            latitude: latitude,
            longitude: longitude,
            imageKeys: imageKeys,
            videoKey: videoKey,
          );
      if (backendIntent != null) {
        return backendIntent;
      }
    } catch (e) {
      debugPrint(
        '⚠️ [ApiService] createPendingFixedBookingIntent backend-first falhou; usando fallback legado: $e',
      );
    }

    int? resolvedCategoryId = categoryId;
    int? resolvedProfessionId = professionId;
    String? resolvedProfessionName = professionName?.trim();
    if (professionId != null &&
        (resolvedCategoryId == null ||
            resolvedProfessionName == null ||
            resolvedProfessionName.isEmpty)) {
      try {
        final profession = await supabase
            .from('professions')
            .select('id,name,category_id')
            .eq('id', professionId)
            .maybeSingle();
        if (profession != null) {
          resolvedProfessionId = profession['id'] is num
              ? (profession['id'] as num).toInt()
              : int.tryParse('${profession['id']}');
          resolvedCategoryId ??= profession['category_id'] is num
              ? (profession['category_id'] as num).toInt()
              : int.tryParse('${profession['category_id']}');
          if (resolvedProfessionName == null ||
              resolvedProfessionName.isEmpty) {
            resolvedProfessionName = (profession['name'] ?? '')
                .toString()
                .trim();
          }
        }
      } catch (_) {
        // mantém fallback defensivo abaixo
      }
    }

    String? providerUid;
    try {
      final providerUser = await supabase
          .from('users')
          .select('supabase_uid')
          .eq('id', providerId)
          .maybeSingle();
      providerUid = (providerUser?['supabase_uid'] ?? '').toString().trim();
    } catch (_) {
      providerUid = null;
    }

    final safeDescription = procedureName.trim().isNotEmpty
        ? procedureName.trim()
        : 'Agendamento';
    final safeTotal = totalPrice <= 0 ? 0.0 : totalPrice;
    final safeUpfront = upfrontPrice.clamp(0.0, safeTotal).toDouble();
    final lat = latitude ?? _fixedProviderDefaultLat;
    final lon = longitude ?? _fixedProviderDefaultLon;
    final durationMinutes =
        scheduledEndUtc != null && scheduledEndUtc.isAfter(scheduledStartUtc)
        ? scheduledEndUtc.difference(scheduledStartUtc).inMinutes
        : 60;

    final insertBody = <String, dynamic>{
      'cliente_uid': authUid,
      'prestador_uid': providerUid?.isNotEmpty == true ? providerUid : null,
      'cliente_user_id': _userId,
      'prestador_user_id': providerId,
      'status': 'pending_payment',
      'payment_status': 'pending',
      'description': safeDescription,
      'profession_id': resolvedProfessionId,
      'profession_name': resolvedProfessionName,
      'task_id': taskId,
      'task_name': (taskName ?? safeDescription).trim(),
      'category_id': resolvedCategoryId,
      'scheduled_at': scheduledStartUtc.toUtc().toIso8601String(),
      'duration_minutes': durationMinutes,
      'latitude': lat,
      'longitude': lon,
      'address': (address ?? '').trim().isNotEmpty
          ? address!.trim()
          : _fixedProviderDefaultAddress,
      'price_estimated': double.parse(safeTotal.toStringAsFixed(2)),
      'price_upfront': double.parse(safeUpfront.toStringAsFixed(2)),
      'image_keys': imageKeys,
      'video_key': videoKey,
      'updated_at': DateTime.now().toIso8601String(),
    }..removeWhere((key, value) => value == null);

    Map<String, dynamic>? inserted;
    while (true) {
      try {
        inserted = await supabase
            .from('fixed_booking_pix_intents')
            .insert(insertBody)
            .select(
              'id,status,payment_status,cliente_uid,prestador_uid,'
              'cliente_user_id,prestador_user_id,description,profession_id,'
              'profession_name,task_id,task_name,category_id,scheduled_at,'
              'duration_minutes,latitude,longitude,address,price_estimated,'
              'price_upfront,image_keys,video_key,created_service_id,'
              'created_at,updated_at',
            )
            .single();
        break;
      } on PostgrestException catch (e) {
        final missingColumnMatch = RegExp(
          r"Could not find the '([^']+)' column",
        ).firstMatch(e.message);
        final missingColumn = missingColumnMatch?.group(1);
        final canRetry =
            e.code == 'PGRST204' &&
            missingColumn != null &&
            insertBody.containsKey(missingColumn);
        if (!canRetry) rethrow;
        insertBody.remove(missingColumn);
      }
    }

    final intent = Map<String, dynamic>.from(inserted);
    final intentId = (intent['id'] ?? '').toString().trim();
    if (intentId.isEmpty) {
      throw ApiException(
        message: 'Falha ao criar intenção de pagamento do agendamento.',
        statusCode: 500,
      );
    }

    final resolvedScheduledEndUtc = scheduledStartUtc.toUtc().add(
      Duration(minutes: durationMinutes),
    );
    try {
      await _createFixedBookingSlotHold(
        pixIntentId: intentId,
        providerId: providerId,
        providerUid: providerUid,
        clientUid: authUid,
        clientUserId: _userId,
        scheduledStartUtc: scheduledStartUtc.toUtc(),
        scheduledEndUtc: resolvedScheduledEndUtc,
        durationMinutes: durationMinutes,
      );
    } catch (e) {
      await supabase
          .from('fixed_booking_pix_intents')
          .update({
            'status': 'failed',
            'payment_status': 'failed',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', intentId);
      rethrow;
    }

    return intent;
  }

  Future<void> _createFixedBookingSlotHold({
    required String pixIntentId,
    required int providerId,
    required String? providerUid,
    required String clientUid,
    required int? clientUserId,
    required DateTime scheduledStartUtc,
    required DateTime scheduledEndUtc,
    required int durationMinutes,
  }) async {
    try {
      await _backendApiClient.postJson(
        '/api/v1/bookings/slot-holds',
        body: {
          'pix_intent_id': pixIntentId,
          'cliente_uid': clientUid,
          'prestador_uid': (providerUid ?? '').trim().isEmpty
              ? null
              : providerUid,
          'cliente_user_id': clientUserId,
          'prestador_user_id': providerId,
          'scheduled_at': scheduledStartUtc.toIso8601String(),
          'scheduled_end_at': scheduledEndUtc.toIso8601String(),
          'duration_minutes': durationMinutes,
          'expires_at': DateTime.now()
              .toUtc()
              .add(fixedBookingPixHoldDuration)
              .toIso8601String(),
          'status': 'active',
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
    } on PostgrestException catch (e) {
      final message = e.message.toLowerCase();
      if (e.code == '23P01' ||
          message.contains('no_overlap') ||
          message.contains('conflicting key value')) {
        throw ApiException(
          message:
              'Esse horário acabou de ser reservado por outro cliente. Escolha o próximo horário disponível.',
          statusCode: 409,
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _createFixedBookingRecord({
    required int providerId,
    required String procedureName,
    required DateTime scheduledStartUtc,
    DateTime? scheduledEndUtc,
    required double totalPrice,
    required double upfrontPrice,
    int? professionId,
    String? professionName,
    int? taskId,
    int? categoryId,
    String? address,
    double? latitude,
    double? longitude,
    List<String> imageKeys = const [],
    String? videoKey,
  }) async {
    if (_userId == null) {
      throw ApiException(message: 'Not authenticated', statusCode: 401);
    }
    final supabase = Supabase.instance.client;
    int? resolvedCategoryId = categoryId;
    String? resolvedProfessionName = professionName?.trim();
    if (professionId != null &&
        (resolvedCategoryId == null ||
            resolvedProfessionName == null ||
            resolvedProfessionName.isEmpty)) {
      try {
        final profession = await supabase
            .from('professions')
            .select('id,name,category_id')
            .eq('id', professionId)
            .maybeSingle();
        if (profession != null) {
          resolvedCategoryId ??= profession['category_id'] is num
              ? (profession['category_id'] as num).toInt()
              : int.tryParse('${profession['category_id']}');
          if (resolvedProfessionName == null ||
              resolvedProfessionName.isEmpty) {
            resolvedProfessionName = (profession['name'] ?? '')
                .toString()
                .trim();
          }
        }
      } catch (_) {
        // keep fallback payload below
      }
    }

    final safeTotal = totalPrice <= 0 ? 0.0 : totalPrice;
    final safeUpfront = upfrontPrice.clamp(0.0, safeTotal).toDouble();
    final authUid = supabase.auth.currentUser?.id;
    if (authUid == null || authUid.trim().isEmpty) {
      throw ApiException(
        message: 'Sessão inválida para agendamento.',
        statusCode: 401,
      );
    }

    String? providerUid;
    try {
      final providerUser = await supabase
          .from('users')
          .select('supabase_uid')
          .eq('id', providerId)
          .maybeSingle();
      providerUid = (providerUser?['supabase_uid'] ?? '').toString().trim();
    } catch (_) {
      providerUid = null;
    }

    final lat = latitude ?? _fixedProviderDefaultLat;
    final lon = longitude ?? _fixedProviderDefaultLon;
    final durationMinutes =
        scheduledEndUtc != null && scheduledEndUtc.isAfter(scheduledStartUtc)
        ? scheduledEndUtc.difference(scheduledStartUtc).inMinutes
        : 60;

    final model = AgendamentoModel(
      clienteUid: authUid,
      prestadorUid: providerUid?.isNotEmpty == true ? providerUid : null,
      clienteUserId: _userId,
      prestadorUserId: providerId,
      tipoFluxo: TipoFluxo.fixed,
      status: StatusAgendamento.pending,
      dataAgendada: scheduledStartUtc,
      duracaoEstimadaMinutos: durationMinutes,
      latitude: lat,
      longitude: lon,
      enderecoCompleto: (address ?? '').trim().isNotEmpty
          ? address!.trim()
          : _fixedProviderDefaultAddress,
      tarefaId: taskId,
      precoTotal: double.parse(safeTotal.toStringAsFixed(2)),
      valorEntrada: double.parse(safeUpfront.toStringAsFixed(2)),
      imageKeys: imageKeys,
      videoKey: videoKey,
      legacyServiceRequestId: null,
    );

    final insertBody = Map<String, dynamic>.from(model.toMap())
      ..removeWhere((key, value) => value == null)
      ..['updated_at'] = DateTime.now().toIso8601String();
    final created = await _backendApiClient.postJson(
      '/api/v1/bookings/fixed',
      body: insertBody,
    );
    final inserted = created?['data'] is Map
        ? Map<String, dynamic>.from(created!['data'] as Map)
        : Map<String, dynamic>.from(created ?? const <String, dynamic>{});

    final bookingId = (inserted['id'] ?? '').toString().trim();
    if (bookingId.isEmpty) {
      throw ApiException(
        message: 'Falha ao criar serviço de agendamento para o PIX',
        statusCode: 500,
      );
    }

    return await _enrichFixedBooking(
      _normalizeNewService(Map<String, dynamic>.from(inserted), isFixed: true),
    );
  }

  Future<Map<String, dynamic>> loadPixPayload({
    String? serviceId,
    String? pendingFixedBookingId,
  }) async {
    return sm.SecurityMiddleware.secureCall(() async {
      final normalizedServiceId = serviceId?.trim() ?? '';
      final normalizedPendingId = pendingFixedBookingId?.trim() ?? '';
      if (normalizedServiceId.isEmpty == normalizedPendingId.isEmpty) {
        throw Exception(
          'Informe exatamente um identificador para gerar o PIX.',
        );
      }

      final body = <String, dynamic>{'payment_stage': 'deposit'};
      if (normalizedPendingId.isNotEmpty) {
        body['pending_fixed_booking_id'] = normalizedPendingId;
        body['entity_type'] = 'fixed_booking_pix_intent';
      } else {
        body['service_id'] = normalizedServiceId;
        body['entity_type'] = 'service';
      }

      final result = await invokeEdgeFunction('mp-get-pix-data', body);
      if (result is Map && result['pix'] is Map) {
        final pix = Map<String, dynamic>.from(result['pix'] as Map);
        if (result['amount'] != null) {
          pix['amount'] = result['amount'];
        }
        return pix;
      }
      throw Exception('Falha ao obter dados do PIX');
    });
  }

  Future<Map<String, dynamic>?> getPendingFixedBookingIntent(
    String intentId,
  ) async {
    final normalizedId = intentId.trim();
    if (normalizedId.isEmpty) return null;
    final payload = await _backendApiClient.getJson(
      '/api/v1/bookings/fixed/intents/$normalizedId',
    );
    final dynamic payloadData = payload?['data'];
    final response = payloadData is Map
        ? payloadData
        : (payload is Map<String, dynamic> ? payload : null);
    if (response == null) return null;
    final intent = Map<String, dynamic>.from(response);
    final holdRes = await _backendApiClient.getJson(
      '/api/v1/bookings/fixed/intents/$normalizedId/slot-hold',
    );
    final dynamic holdData = holdRes?['data'];
    final hold = holdData is Map ? holdData : null;
    if (hold != null) {
      intent['slot_hold'] = Map<String, dynamic>.from(hold);
      intent['hold_status'] = hold['status'];
      intent['hold_expires_at'] = hold['expires_at'];
    }
    return intent;
  }

  Future<Map<String, dynamic>?>
  getLatestPendingFixedBookingIntentForCurrentClient() async {
    final payload = await _backendApiClient.getJson(
      '/api/v1/bookings/fixed/intents/latest-pending',
    );
    final dynamic payloadData = payload?['data'];
    final response = payloadData is Map
        ? payloadData
        : (payload is Map<String, dynamic> ? payload : null);

    if (response == null) return null;
    final intent = Map<String, dynamic>.from(response);
    final intentId = '${intent['id'] ?? ''}'.trim();
    final holdRes = intentId.isEmpty
        ? null
        : await _backendApiClient.getJson(
            '/api/v1/bookings/fixed/intents/$intentId/slot-hold',
          );
    final dynamic holdData = holdRes?['data'];
    final hold = holdData is Map ? holdData : null;
    if (hold != null) {
      intent['slot_hold'] = Map<String, dynamic>.from(hold);
      intent['hold_status'] = hold['status'];
      intent['hold_expires_at'] = hold['expires_at'];
    }
    return intent;
  }

  Future<void> cancelPendingFixedBookingIntent(String intentId) async {
    final normalizedId = intentId.trim();
    if (normalizedId.isEmpty) return;

    final backendCancelled = await _backendHomeApi
        .cancelPendingFixedBookingIntent(normalizedId);
    if (backendCancelled) {
      return;
    }

    final currentIntentPayload = await _backendApiClient.getJson(
      '/api/v1/bookings/fixed/intents/$normalizedId',
    );
    final dynamic currentIntentData = currentIntentPayload?['data'];
    final currentIntent = currentIntentData is Map
        ? currentIntentData
        : (currentIntentPayload is Map<String, dynamic>
              ? currentIntentPayload
              : null);
    if (currentIntent == null) return;

    final paymentStatus = (currentIntent['payment_status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final status = (currentIntent['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final createdServiceId = (currentIntent['created_service_id'] ?? '')
        .toString()
        .trim();
    final isAlreadyPaid =
        {'paid', 'approved', 'paid_manual'}.contains(paymentStatus) ||
        status == 'paid' ||
        createdServiceId.isNotEmpty;
    if (isAlreadyPaid) {
      throw ApiException(
        message:
            'Esse horário já foi confirmado no pagamento e não pode mais ser cancelado por aqui.',
        statusCode: 409,
      );
    }

    await _backendApiClient.postJson(
      '/api/v1/bookings/fixed/intents/$normalizedId/cancel',
      body: {'status': 'cancelled'},
    );
  }

  Future<void> createManualAppointment({
    required int providerId,
    required DateTime startTime,
    required DateTime endTime,
    required String clientName,
    required String procedureName,
    String? notes,
  }) async {
    final ok = await _backendSchedulingApi.createManualAppointment(
      providerId: providerId,
      startTime: startTime,
      endTime: endTime,
      clientName: clientName,
      procedureName: procedureName,
      notes: notes,
    );
    if (!ok) {
      throw Exception(
        'Falha ao criar agendamento manual via /api/v1/providers/:id/appointments/manual',
      );
    }
  }

  Future<int?> _resolveBookingUserId({
    required dynamic explicitId,
    required dynamic uidValue,
  }) async {
    final parsedExplicit = explicitId is num
        ? explicitId.toInt()
        : int.tryParse('${explicitId ?? ''}');
    if (parsedExplicit != null) return parsedExplicit;

    final uid = (uidValue ?? '').toString().trim();
    if (uid.isEmpty) return null;

    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('supabase_uid', uid)
          .maybeSingle();
      final resolved = row?['id'];
      return resolved is num ? resolved.toInt() : int.tryParse('$resolved');
    } catch (e) {
      debugPrint('⚠️ [ApiService] Falha ao resolver user_id por uid=$uid: $e');
      return null;
    }
  }

  Future<void> confirmSchedule(
    String serviceId,
    DateTime time, {
    ServiceDataScope scope = ServiceDataScope.auto,
  }) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) {
      throw ApiException(
        message: 'Serviço inválido para confirmar agenda.',
        statusCode: 400,
      );
    }
    final currentUserId =
        _userId ??
        await _resolveBookingUserId(
          explicitId: _userId,
          uidValue: Supabase.instance.client.auth.currentUser?.id,
        );
    if (currentUserId != null && currentUserId > 0) {
      final details = await getServiceDetails(
        normalizedServiceId,
        scope: scope,
        forceRefresh: true,
      );
      final proposedByRaw =
          details['schedule_proposed_by_user_id'] ??
          details['schedule_proposed_by'];
      final proposedBy = proposedByRaw is num
          ? proposedByRaw.toInt()
          : int.tryParse('$proposedByRaw');
      if (proposedBy != null && proposedBy == currentUserId) {
        throw ApiException(
          message:
              'Quem propôs o horário não pode confirmar a própria proposta. Aguarde a outra pessoa ou altere o agendamento.',
          statusCode: 409,
        );
      }
    }
    final backendConfirmed = await _backendTrackingApi.confirmSchedule(
      normalizedServiceId,
      scheduledAt: time,
    );
    if (!backendConfirmed) {
      throw ApiException(
        message:
            'Falha ao confirmar agenda via /api/v1/tracking/services/:id/confirm-schedule',
        statusCode: 502,
      );
    }
  }

  Future<void> markClientDeparting(String serviceId) async {
    debugPrint(
      '📍 [ApiService] Marking client departing for service: $serviceId',
    );
    final nowIso = DateTime.now().toIso8601String();
    await _backendApiClient.putJson(
      '/api/v1/bookings/fixed/$serviceId',
      body: {
        'status': 'EM_DESLOCAMENTO',
        'client_departing_at': nowIso,
        'updated_at': nowIso,
      },
    );
  }

  Future<void> updateServiceClientLocation(
    String serviceId, {
    required double latitude,
    required double longitude,
  }) async {
    await _backendApiClient.putJson(
      '/api/v1/bookings/fixed/$serviceId',
      body: {
        'client_latitude': double.parse(latitude.toStringAsFixed(8)),
        'client_longitude': double.parse(longitude.toStringAsFixed(8)),
        'updated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> updateClientTrackingState(
    String serviceId, {
    required bool isActive,
    required String status,
    String source = 'client_tracking',
  }) async {
    await _backendApiClient.putJson(
      '/api/v1/bookings/fixed/$serviceId',
      body: {
        'client_tracking_active': isActive,
        'client_tracking_status': status,
        'client_tracking_source': source,
        'client_tracking_updated_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> upsertClientTrackingLocation(
    String serviceId, {
    required double latitude,
    required double longitude,
    String trackingStatus = 'tracking_active',
    String source = 'client_tracking',
    int? clientUserId,
    String? clientUid,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final normalizedClientUserId =
        clientUserId ??
        _userId ??
        await _resolveBookingUserId(
          explicitId: _userId,
          uidValue: clientUid ?? Supabase.instance.client.auth.currentUser?.id,
        );
    final normalizedClientUid =
        (clientUid ?? Supabase.instance.client.auth.currentUser?.id ?? '')
            .toString()
            .trim();

    await _backendApiClient.putJson(
      '/api/v1/client-locations/$serviceId',
      body: {
        'service_id': serviceId,
        'client_user_id': normalizedClientUserId,
        'client_uid': normalizedClientUid.isEmpty ? null : normalizedClientUid,
        'latitude': double.parse(latitude.toStringAsFixed(8)),
        'longitude': double.parse(longitude.toStringAsFixed(8)),
        'tracking_status': trackingStatus,
        'source': source,
        'updated_at': nowIso,
      },
    );

    await _backendApiClient.putJson(
      '/api/v1/bookings/fixed/$serviceId',
      body: {
        'client_latitude': double.parse(latitude.toStringAsFixed(8)),
        'client_longitude': double.parse(longitude.toStringAsFixed(8)),
        'client_tracking_active': true,
        'client_tracking_status': trackingStatus,
        'client_tracking_source': source,
        'client_tracking_updated_at': nowIso,
        'updated_at': nowIso,
      },
    );
  }

  Future<void> markClientArrived(String serviceId) async {
    debugPrint(
      '📍 [ApiService] Marking client arrived for service: $serviceId',
    );
    final nowIso = DateTime.now().toIso8601String();
    await _backendApiClient.putJson(
      '/api/v1/bookings/fixed/$serviceId',
      body: {
        'status': 'EM_DESLOCAMENTO',
        'arrived_at': nowIso,
        'updated_at': nowIso,
      },
    );
  }

  Future<void> confirmPaymentManual(String serviceId) async {
    // ⛔ BLOQUEADO NO CLIENTE. Mantido apenas para logs/UX.
    throw sm.SecurityException(
      'Confirmação de pagamento manual só é permitida via Webhook Seguro.',
    );
  }

  Future<void> deleteAppointment(String appointmentId) async {
    final ok = await _backendSchedulingApi.deleteAppointment(appointmentId);
    if (!ok) {
      throw Exception(
        'Falha ao remover agendamento via /api/v1/providers/appointments/:id',
      );
    }
  }

  Future<ProviderScheduleConfigResult> getScheduleConfigResultForProvider(
    int providerId,
  ) async {
    if (providerId <= 0) {
      debugPrint(
        '🗓️ [ApiService] getScheduleConfigResultForProvider invalid providerId=$providerId',
      );
      return const ProviderScheduleConfigResult(
        providerId: 0,
        providerUid: null,
        configs: <Map<String, dynamic>>[],
        usedLegacyFallback: false,
        foundProviderSchedules: false,
      );
    }

    final backend = await _backendSchedulingApi.fetchProviderSchedule(
      providerId,
    );
    final configsRaw = backend?['configs'];
    final normalizedRows = configsRaw is List
        ? configsRaw
              .whereType<Map>()
              .map(
                (raw) => _mapScheduleRowToConfig(raw.cast<String, dynamic>()),
              )
              .toList()
        : const <Map<String, dynamic>>[];
    if (kDebugMode) {
      debugPrint(
        '🐞 [ApiService.getScheduleConfigResultForProvider] providerId=$providerId normalized=${normalizedRows.length}',
      );
    }

    if (normalizedRows.isNotEmpty) {
      debugPrint(
        '🗓️ [ApiService] schedule_config_result provider=$providerId provider_schedules=${normalizedRows.length} legacy_fallback=false',
      );
      return ProviderScheduleConfigResult(
        providerId: providerId,
        providerUid: null,
        configs: normalizedRows,
        usedLegacyFallback: false,
        foundProviderSchedules: true,
      );
    }

    return ProviderScheduleConfigResult(
      providerId: providerId,
      providerUid: null,
      configs: const <Map<String, dynamic>>[],
      usedLegacyFallback: false,
      foundProviderSchedules: false,
    );
  }

  Future<List<Map<String, dynamic>>> getScheduleConfigForProvider(
    int providerId,
  ) async {
    final result = await getScheduleConfigResultForProvider(providerId);
    return result.configs;
  }

  Future<List<Map<String, dynamic>>> getScheduleConfig() async {
    if (_userId == null) return [];
    return getScheduleConfigForProvider(_userId!);
  }

  Future<void> saveScheduleConfig(List<Map<String, dynamic>> configs) async {
    if (_userId == null) throw Exception('Not authenticated');
    final saved = await _backendSchedulingApi.saveProviderSchedule(
      _userId!,
      configs,
    );
    if (saved == null) {
      throw Exception(
        'Falha ao salvar agenda via /api/v1/providers/:id/schedule',
      );
    }

    await _ensureFixedProviderSearchContract(
      client: Supabase.instance.client,
      providerUserId: _userId!,
    );
  }

  Future<List<Map<String, dynamic>>> getScheduleExceptions() async {
    if (_userId == null) return [];
    final rows = await _backendSchedulingApi.fetchProviderScheduleExceptions(
      _userId!,
    );
    return rows ?? const <Map<String, dynamic>>[];
  }

  Future<void> saveScheduleExceptions(List<dynamic> exceptions) async {
    if (_userId == null) throw Exception('Not authenticated');
    final rows = exceptions
        .map(
          (e) => {
            'provider_id': _userId,
            'date': e['date'],
            'is_available': e['is_available'] ?? false,
            'reason': e['reason'],
          },
        )
        .toList();
    final saved = await _backendSchedulingApi.saveProviderScheduleExceptions(
      _userId!,
      rows,
    );
    if (saved == null) {
      throw Exception(
        'Falha ao salvar exceções via /api/v1/providers/:id/schedule/exceptions',
      );
    }
  }

  // Auto-detect desativado: URL base vem de SUPABASE_URL via SupabaseConfig
  Future<void> autoDetectBaseUrl() async {}

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', url);
  }

  String? get currentToken => _token;

  String? get userEmail => _currentUserData?['email']?.toString().toLowerCase();

  // loadConfig desativado: URL base vem de SUPABASE_URL via SupabaseConfig
  Future<void> loadConfig() async {}

  Future<void> loadToken() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('⚠️ [ApiService] Falha ao abrir SharedPreferences: $e');
    }
    final snapshot = await ApiSessionBootstrap.loadStoredSession(
      prefs: prefs,
      secureStorage: _secureStorage,
      supabaseInitialized: SupabaseConfig.isInitialized,
    );
    _token = snapshot.token;
    _applyIdentitySnapshot(snapshot.identity);
    debugPrint(
      '🪪 [ApiService.loadToken] token=${(_token?.isNotEmpty ?? false) ? "present" : "missing"} '
      'userId=${snapshot.identity.userId?.toString() ?? "-"} '
      'role=${snapshot.identity.role ?? "-"} '
      'isFixedLocation=${snapshot.identity.isFixedLocation} '
      'isMedical=${snapshot.identity.isMedical}',
    );
  }

  // Fuel price cache
  final Map<String, _FuelCacheItem> _fuelCache = {};
  static const Duration _fuelCacheTTL = Duration(hours: 6);

  Future<Map<String, dynamic>> _getCachedFuel(
    String key,
    Future<Map<String, dynamic>> Function() fetcher,
  ) async {
    final now = DateTime.now();
    if (_fuelCache.containsKey(key)) {
      final item = _fuelCache[key]!;
      if (now.isBefore(item.expiry)) {
        return item.data;
      }
    }
    final data = await fetcher();
    if (data.isNotEmpty) {
      _fuelCache[key] = _FuelCacheItem(
        data: data,
        expiry: now.add(_fuelCacheTTL),
      );
    }
    return data;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
    } catch (e) {
      debugPrint('⚠️ [ApiService] Falha ao salvar token no storage seguro: $e');
    }
  }

  void setUserId(int id) {
    _userId = id;
  }

  Future<void> clearToken() async {
    AnalyticsService().logEvent('APP_LOGGED_OUT');
    await AnalyticsService().clearSession();

    // Remove token do FCM do banco antes do logout
    try {
      final token = ApiService.isLocalWebEnvironment
          ? null
          : await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await unregisterDeviceToken(token);
      }
      await NotificationService().deleteToken();
    } catch (e) {
      debugPrint('ApiService: Error unregistering token before logout: $e');
    }

    _token = null;
    _userId = null;
    _role = null;
    _isMedical = false;
    _isFixedLocation = false;

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (_) {}
    await prefs.remove('user_id');
    await _secureStorage.delete(key: 'user_role');
    await _secureStorage.delete(key: 'is_medical');
    await _secureStorage.delete(key: 'is_fixed_location');
  }

  void dispose() {
    _client.close();
  }

  bool get isLoggedIn {
    if (!SupabaseConfig.isInitialized) return false;
    return Supabase.instance.client.auth.currentUser != null;
  }

  Future<List<Map<String, dynamic>>> fetchActiveTaskCatalog({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _taskCatalogCache != null &&
        _taskCatalogCacheAt != null &&
        DateTime.now().difference(_taskCatalogCacheAt!).inMinutes < 60) {
      return _taskCatalogCache!;
    }

    final res = await _backendApiClient.getJson(
      '/api/v1/tasks?active_eq=true&limit=2000',
    );

    final list = ((res?['data'] as List?) ?? const []).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final prof = m['professions'] is Map
          ? Map<String, dynamic>.from(m['professions'] as Map)
          : <String, dynamic>{};
      m['profession_name'] = (prof['name'] ?? '').toString();
      m['service_type'] = prof['service_type'];
      m['profession_keywords'] = prof['keywords'];
      for (final key in const [
        'popularity_score',
        'completed_services_count',
        'services_completed_count',
        'service_count',
        'completed_count',
        'total_completed',
        'bookings_count',
        'requests_count',
      ]) {
        if (m[key] == null && prof.containsKey(key)) {
          m[key] = prof[key];
        }
      }
      return m;
    }).toList();

    _taskCatalogCache = list;
    _taskCatalogCacheAt = DateTime.now();
    return list;
  }

  Future<List<Map<String, dynamic>>> semanticTaskSearch({
    required String query,
    required String context,
    String? serviceTypeHint,
    int limit = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    // Busca semântica é endpoint público/optional auth.
    // Forçamos anonKey para evitar loop com JWT stale no Web ("Invalid JWT").
    final uri = Uri.parse('$baseUrl/tasks-semantic-search');
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'apikey': SupabaseConfig.anonKey,
            'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
          },
          body: jsonEncode({
            'query': trimmed,
            'context': context,
            'limit': limit,
            if (serviceTypeHint != null && serviceTypeHint.trim().isNotEmpty)
              'service_type_hint': serviceTypeHint.trim(),
          }),
        )
        .timeout(const Duration(seconds: 30));

    final result = _handleResponse(response);
    final results = result['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _normalizeSearchText(String input) {
    return TaskAutocomplete.normalizePt(input);
  }

  double _safePrice(dynamic value) {
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  bool _textContainsNormalized(String haystack, String needle) {
    final h = _normalizeSearchText(haystack);
    final n = _normalizeSearchText(needle);
    if (h.isEmpty || n.isEmpty) return false;
    return h.contains(n) || n.contains(h);
  }

  Future<Map<String, dynamic>?> _resolveProfessionByName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    try {
      final rowsRes = await _backendApiClient.getJson(
        '/api/v1/professions?name_ilike=${Uri.encodeQueryComponent(trimmed)}&limit=10',
      );
      final rows = (rowsRes?['data'] as List? ?? const []);
      if (rows.isEmpty) return null;
      final scored =
          rows.map((raw) => Map<String, dynamic>.from(raw as Map)).toList()
            ..sort((a, b) {
              final aName = (a['name'] ?? '').toString();
              final bName = (b['name'] ?? '').toString();
              final aExact =
                  _normalizeSearchText(aName) == _normalizeSearchText(trimmed)
                  ? 1
                  : 0;
              final bExact =
                  _normalizeSearchText(bName) == _normalizeSearchText(trimmed)
                  ? 1
                  : 0;
              if (aExact != bExact) return bExact.compareTo(aExact);
              return aName.length.compareTo(bName.length);
            });
      return scored.first;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> classifyService(String text) async {
    final query = text.trim();
    if (query.length < 2) {
      return {
        'encontrado': false,
        'ambiguous': false,
        'task_id': null,
        'task_name': null,
        'profissao': null,
        'profession_id': null,
        'category_id': null,
        'service_type': null,
        'price': null,
        'candidates': <dynamic>[],
        'engine': 'catalog',
        'cache_hit': false,
      };
    }

    final catalog = await fetchActiveTaskCatalog();
    final localSuggestions = TaskAutocomplete.suggestTasks(
      query,
      catalog.map((row) {
        final mapped = Map<String, dynamic>.from(row);
        mapped['task_name'] = mapped['name'];
        return mapped;
      }).toList(),
      limit: 8,
    );

    List<Map<String, dynamic>> semanticSuggestions = const [];
    try {
      semanticSuggestions = await semanticTaskSearch(
        query: query,
        context: 'fixed_booking',
        serviceTypeHint: 'at_provider',
        limit: 8,
      );
    } catch (_) {
      semanticSuggestions = const [];
    }

    final merged = <String, Map<String, dynamic>>{};
    for (final source in [...semanticSuggestions, ...localSuggestions]) {
      final row = Map<String, dynamic>.from(source);
      final taskId = (row['task_id'] ?? row['id'] ?? '').toString();
      final key = taskId.isNotEmpty
          ? 'task:$taskId'
          : 'name:${_normalizeSearchText((row['task_name'] ?? row['name'] ?? '').toString())}';
      merged.putIfAbsent(key, () => row);
    }

    final ordered = merged.values.toList()
      ..sort((a, b) {
        final aScore = double.tryParse('${a['score'] ?? ''}') ?? 0.0;
        final bScore = double.tryParse('${b['score'] ?? ''}') ?? 0.0;
        return bScore.compareTo(aScore);
      });

    if (ordered.isNotEmpty) {
      final best = ordered.first;
      final professionName =
          (best['profession_name'] ??
                  best['profissao'] ??
                  best['profession'] ??
                  '')
              .toString()
              .trim();
      int? professionId = int.tryParse(
        '${best['profession_id'] ?? best['professionId'] ?? ''}',
      );
      int? categoryId = int.tryParse('${best['category_id'] ?? ''}');
      if ((professionId == null || categoryId == null) &&
          professionName.isNotEmpty) {
        final profession = await _resolveProfessionByName(professionName);
        professionId ??= int.tryParse('${profession?['id'] ?? ''}');
        categoryId ??= int.tryParse('${profession?['category_id'] ?? ''}');
      }

      return {
        'encontrado': true,
        'ambiguous': ordered.length > 1,
        'task_id': int.tryParse('${best['task_id'] ?? best['id'] ?? ''}'),
        'task_name': (best['task_name'] ?? best['name'] ?? query).toString(),
        'profissao': professionName.isNotEmpty ? professionName : null,
        'profession_id': professionId,
        'category_id': categoryId,
        'service_type': (best['service_type'] ?? 'at_provider').toString(),
        'price': _safePrice(best['unit_price'] ?? best['price']),
        'candidates': ordered,
        'engine': semanticSuggestions.isNotEmpty
            ? 'semantic+catalog'
            : 'catalog',
        'cache_hit': false,
      };
    }

    final fallbackProfession = await _resolveProfessionByName(query);
    return {
      'encontrado': fallbackProfession != null,
      'ambiguous': false,
      'task_id': null,
      'task_name': null,
      'profissao': fallbackProfession?['name'],
      'profession_id': int.tryParse('${fallbackProfession?['id'] ?? ''}'),
      'category_id': int.tryParse(
        '${fallbackProfession?['category_id'] ?? ''}',
      ),
      'service_type': (fallbackProfession?['service_type'] ?? 'at_provider')
          .toString(),
      'price': null,
      'candidates': fallbackProfession == null
          ? <dynamic>[]
          : [fallbackProfession],
      'engine': 'profession_fallback',
      'cache_hit': false,
    };
  }

  Future<Map<String, dynamic>> searchFixedProvidersForService({
    required String query,
    double? lat,
    double? lon,
    int horizonDays = 14,
  }) async {
    final available = <Map<String, dynamic>>[];
    final unavailable = <Map<String, dynamic>>[];
    Map<String, dynamic> latestService = await classifyService(query);

    await for (final event in searchFixedProvidersForServiceProgressive(
      query: query,
      lat: lat,
      lon: lon,
      horizonDays: horizonDays,
    )) {
      if (event['service'] is Map) {
        latestService = Map<String, dynamic>.from(event['service'] as Map);
      }
      if (event['type'] == 'chunk') {
        available.addAll(
          (event['available'] as List? ?? const [])
              .cast<Map<String, dynamic>>(),
        );
        unavailable.addAll(
          (event['unavailable'] as List? ?? const [])
              .cast<Map<String, dynamic>>(),
        );
      }
    }

    available.sort((a, b) {
      final aDist = a['distance_km'] is num
          ? (a['distance_km'] as num).toDouble()
          : double.infinity;
      final bDist = b['distance_km'] is num
          ? (b['distance_km'] as num).toDouble()
          : double.infinity;
      final byDistance = aDist.compareTo(bDist);
      if (byDistance != 0) return byDistance;
      final aSlot = DateTime.tryParse('${a['next_available_at'] ?? ''}');
      final bSlot = DateTime.tryParse('${b['next_available_at'] ?? ''}');
      if (aSlot == null && bSlot == null) return 0;
      if (aSlot == null) return 1;
      if (bSlot == null) return -1;
      return aSlot.compareTo(bSlot);
    });

    unavailable.sort((a, b) {
      final aDist = a['distance_km'] is num
          ? (a['distance_km'] as num).toDouble()
          : double.infinity;
      final bDist = b['distance_km'] is num
          ? (b['distance_km'] as num).toDouble()
          : double.infinity;
      return aDist.compareTo(bDist);
    });

    return {
      'service': latestService,
      'available': available,
      'unavailable': unavailable,
    };
  }

  Stream<Map<String, dynamic>> searchFixedProvidersForServiceProgressive({
    required String query,
    double? lat,
    double? lon,
    int horizonDays = 14,
    int chunkSize = 8,
  }) async* {
    yield {
      'type': 'phase',
      'phase': 'classifying_service',
      'message': 'Entendendo o serviço solicitado...',
      'detail': 'Relacionando o pedido ao catálogo de serviços.',
      'processed': 0,
      'total': 0,
    };

    final resolved = await classifyService(query);
    final resolvedProfessionName = (resolved['profissao'] ?? '')
        .toString()
        .trim();
    final resolvedProfessionId = int.tryParse(
      '${resolved['profession_id'] ?? ''}',
    );
    final resolvedTaskId = int.tryParse('${resolved['task_id'] ?? ''}');
    final resolvedTaskName = (resolved['task_name'] ?? query).toString().trim();
    final resolvedPrice = _safePrice(resolved['price']);

    yield {
      'type': 'phase',
      'phase': 'loading_nearby_providers',
      'message': 'Buscando prestadores mais próximos...',
      'detail': 'Localizando salões fixos perto de você.',
      'processed': 0,
      'total': 0,
      'service': resolved,
    };

    var baseProviders = await searchProviders(
      lat: lat,
      lon: lon,
      requiredServiceType: 'at_provider',
    );

    if (baseProviders.isEmpty &&
        (resolvedProfessionName.isNotEmpty || query.trim().isNotEmpty)) {
      baseProviders = await searchProviders(
        term: resolvedProfessionName.isNotEmpty
            ? resolvedProfessionName
            : query,
        lat: lat,
        lon: lon,
        requiredServiceType: 'at_provider',
      );
    }

    final normalizedProviders = baseProviders
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) {
          final providerData = row['providers'] is Map
              ? Map<String, dynamic>.from(row['providers'] as Map)
              : <String, dynamic>{};
          final providerLat = double.tryParse(
            '${providerData['latitude'] ?? row['latitude'] ?? ''}',
          );
          final providerLon = double.tryParse(
            '${providerData['longitude'] ?? row['longitude'] ?? ''}',
          );
          return providerLat != null && providerLon != null;
        })
        .toList();

    yield {
      'type': 'service',
      'service': resolved,
      'total': normalizedProviders.length,
      'processed': 0,
      'message': 'Prestadores encontrados. Consultando agenda...',
      'detail': 'Agora vamos verificar quais têm horário livre.',
    };

    if (normalizedProviders.isEmpty) {
      yield {
        'type': 'done',
        'service': resolved,
        'available': const <Map<String, dynamic>>[],
        'unavailable': const <Map<String, dynamic>>[],
        'total': 0,
        'processed': 0,
      };
      return;
    }

    final today = DateTime.now();
    final dateKeys = List<String>.generate(horizonDays, (index) {
      final d = DateTime(
        today.year,
        today.month,
        today.day,
      ).add(Duration(days: index));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });

    final aggregatedAvailable = <Map<String, dynamic>>[];
    final aggregatedUnavailable = <Map<String, dynamic>>[];
    var processed = 0;
    final allProviderIds = normalizedProviders
        .map((row) => int.tryParse('${row['id'] ?? ''}'))
        .whereType<int>()
        .toList();

    yield {
      'type': 'phase',
      'phase': 'loading_catalog_and_links',
      'message': 'Consultando serviços dos prestadores...',
      'detail': 'Cruzando catálogo, profissões e serviços ativos.',
      'processed': 0,
      'total': normalizedProviders.length,
      'service': resolved,
    };

    final providerProfessionsFuture = (() async {
      if (allProviderIds.isEmpty) return const <dynamic>[];
      final res = await _backendApiClient.getJson(
        '/api/v1/provider-professions?provider_user_id_in=${allProviderIds.join(",")}'
        '${resolvedProfessionId != null ? '&profession_id_eq=$resolvedProfessionId' : ''}'
        '&limit=5000',
      );
      return (res?['data'] as List? ?? const <dynamic>[]);
    })();
    final providerTasksFuture = (() async {
      if (allProviderIds.isEmpty) return const <dynamic>[];
      try {
        final res = await _backendApiClient.getJson(
          '/api/v1/provider-tasks?provider_id_in=${allProviderIds.join(",")}'
          '${resolvedTaskId != null ? '&task_id_eq=$resolvedTaskId' : ''}'
          '&limit=5000',
        );
        return (res?['data'] as List? ?? const <dynamic>[]);
      } catch (_) {
        return const <dynamic>[];
      }
    })();

    final professionRowsRaw = await providerProfessionsFuture;
    final professionIdsByProvider = <int, Set<int>>{};
    for (final raw in professionRowsRaw) {
      final providerId = int.tryParse('${raw['provider_user_id'] ?? ''}');
      final professionId = int.tryParse('${raw['profession_id'] ?? ''}');
      if (providerId == null || professionId == null) continue;
      professionIdsByProvider.putIfAbsent(providerId, () => <int>{});
      professionIdsByProvider[providerId]!.add(professionId);
    }

    final allProfessionIds =
        professionIdsByProvider.values.expand((ids) => ids).toSet().toList()
          ..sort();

    final activeCatalog = await fetchActiveTaskCatalog();
    final catalogRowsRaw = activeCatalog.where((raw) {
      final row = Map<String, dynamic>.from(raw);
      final professionId = int.tryParse('${row['profession_id'] ?? ''}');
      if (professionId == null) return false;
      if (allProfessionIds.isNotEmpty &&
          !allProfessionIds.contains(professionId)) {
        return false;
      }
      if (resolvedTaskId != null) {
        final taskId = int.tryParse('${row['id'] ?? row['task_id'] ?? ''}');
        return taskId == resolvedTaskId;
      }
      if (resolvedProfessionId != null) {
        return professionId == resolvedProfessionId;
      }
      return true;
    }).toList();

    final catalogByProfession = <int, List<Map<String, dynamic>>>{};
    for (final raw in catalogRowsRaw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final professionId = int.tryParse('${row['profession_id'] ?? ''}');
      if (professionId == null) continue;
      catalogByProfession.putIfAbsent(
        professionId,
        () => <Map<String, dynamic>>[],
      );
      catalogByProfession[professionId]!.add(row);
    }

    final providerTasksRaw = await providerTasksFuture;
    final providerTasksByProvider = <int, Map<int, Map<String, dynamic>>>{};
    for (final raw in providerTasksRaw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final providerId = int.tryParse('${row['provider_id'] ?? ''}');
      final taskId = int.tryParse('${row['task_id'] ?? ''}');
      if (providerId == null || taskId == null) continue;
      providerTasksByProvider.putIfAbsent(
        providerId,
        () => <int, Map<String, dynamic>>{},
      );
      providerTasksByProvider[providerId]![taskId] = row;
    }

    final providerServicesById = <int, List<Map<String, dynamic>>>{};
    final candidateProviderIds = <int>{};
    for (final providerId in allProviderIds) {
      final professionIds =
          professionIdsByProvider[providerId] ?? const <int>{};
      final services = <Map<String, dynamic>>[];
      for (final professionId in professionIds) {
        final tasksForProfession =
            catalogByProfession[professionId] ?? const [];
        for (final task in tasksForProfession) {
          final taskMap = Map<String, dynamic>.from(task);
          final taskId = int.tryParse('${taskMap['id'] ?? ''}');
          if (taskId == null) continue;
          final providerTask = providerTasksByProvider[providerId]?[taskId];
          final isActive = providerTask == null
              ? true
              : (providerTask['is_active'] == true ||
                    providerTask['is_active'] == 1);
          if (!isActive) continue;
          taskMap['custom_price'] = providerTask?['custom_price'];
          taskMap['unit_price'] =
              providerTask?['custom_price'] ?? taskMap['unit_price'];
          taskMap['is_active'] = true;
          taskMap['active'] = true;
          services.add(taskMap);
        }
      }
      providerServicesById[providerId] = services;

      final hasResolvedTask =
          resolvedTaskId != null &&
          services.any((service) {
            final taskId = int.tryParse(
              '${service['id'] ?? service['task_id'] ?? ''}',
            );
            return taskId == resolvedTaskId;
          });
      final hasResolvedProfession =
          resolvedProfessionId != null &&
          professionIds.contains(resolvedProfessionId);
      final hasTextMatch = services.any((service) {
        final serviceName = (service['name'] ?? service['task_name'] ?? '')
            .toString();
        final keywords = (service['keywords'] ?? '').toString();
        final serviceProfession = (service['profession_name'] ?? '')
            .toString()
            .trim();
        return _textContainsNormalized(serviceName, resolvedTaskName) ||
            _textContainsNormalized(serviceName, query) ||
            _textContainsNormalized(keywords, resolvedTaskName) ||
            _textContainsNormalized(keywords, query) ||
            (resolvedProfessionName.isNotEmpty &&
                _textContainsNormalized(
                  serviceProfession,
                  resolvedProfessionName,
                ));
      });

      if (services.isNotEmpty &&
          (hasResolvedTask || hasResolvedProfession || hasTextMatch)) {
        candidateProviderIds.add(providerId);
      }
    }

    final providersForAvailability = normalizedProviders.where((provider) {
      final providerId = int.tryParse('${provider['id'] ?? ''}');
      if (providerId == null) return false;
      if (candidateProviderIds.isEmpty) return true;
      return candidateProviderIds.contains(providerId);
    }).toList();

    final scheduleIds = candidateProviderIds.isNotEmpty
        ? (candidateProviderIds.toList()..sort())
        : allProviderIds;
    final schedules = await getProviderSchedules(providerIds: scheduleIds);
    final scheduleCountByProvider = <int, int>{};
    for (final row in schedules) {
      final providerId = int.tryParse('${row['provider_id'] ?? ''}');
      if (providerId == null) continue;
      scheduleCountByProvider[providerId] =
          (scheduleCountByProvider[providerId] ?? 0) + 1;
    }

    for (
      var start = 0;
      start < providersForAvailability.length;
      start += chunkSize
    ) {
      final end = min(start + chunkSize, providersForAvailability.length);
      final providerChunk = providersForAvailability.sublist(start, end);
      final providerIds = providerChunk
          .map((row) => int.tryParse('${row['id'] ?? ''}'))
          .whereType<int>()
          .toList();
      if (providerIds.isEmpty) {
        processed = end;
        continue;
      }

      yield {
        'type': 'phase',
        'phase': 'loading_provider_schedules',
        'message': 'Consultando agenda dos prestadores...',
        'detail':
            'Verificando horários livres de ${processed + 1} até ${end.clamp(1, providersForAvailability.length)} de ${providersForAvailability.length}.',
        'processed': processed,
        'total': providersForAvailability.length,
        'service': resolved,
      };

      final batchSlots = await getProvidersAvailableSlotsBatch(
        providerIds: providerIds,
        dateKeys: dateKeys,
      );

      final availableChunk = <Map<String, dynamic>>[];
      final unavailableChunk = <Map<String, dynamic>>[];

      for (final raw in providerChunk) {
        final provider = Map<String, dynamic>.from(raw);
        final providerData = provider['providers'] is Map
            ? Map<String, dynamic>.from(provider['providers'] as Map)
            : <String, dynamic>{};
        final providerId = int.tryParse('${provider['id'] ?? ''}');
        if (providerId == null) continue;

        final services = providerServicesById[providerId] ?? const [];
        final professionIds =
            professionIdsByProvider[providerId] ?? const <int>{};

        Map<String, dynamic>? matchedTask;
        if (resolvedTaskId != null) {
          for (final service in services) {
            final taskId = int.tryParse(
              '${service['id'] ?? service['task_id'] ?? ''}',
            );
            final isActive =
                service['is_active'] == true ||
                service['active'] == true ||
                service['active'] == null;
            if (isActive && taskId == resolvedTaskId) {
              matchedTask = Map<String, dynamic>.from(service);
              break;
            }
          }
        }

        matchedTask ??= services.cast<Map<String, dynamic>?>().firstWhere((
          service,
        ) {
          if (service == null) return false;
          final isActive =
              service['is_active'] == true ||
              service['active'] == true ||
              service['active'] == null;
          if (!isActive) return false;
          final serviceName = (service['name'] ?? service['task_name'] ?? '')
              .toString();
          return _textContainsNormalized(serviceName, resolvedTaskName);
        }, orElse: () => <String, dynamic>{});
        if (matchedTask != null && matchedTask.isEmpty) {
          matchedTask = null;
        }

        final serviceNameMatch = services.any((service) {
          final name = (service['name'] ?? service['task_name'] ?? '')
              .toString();
          return _textContainsNormalized(name, resolvedTaskName) ||
              _textContainsNormalized(name, query);
        });
        final keywordMatch = services.any((service) {
          final keywords = (service['keywords'] ?? '').toString();
          return _textContainsNormalized(keywords, resolvedTaskName) ||
              _textContainsNormalized(keywords, query);
        });
        final professionNameMatch =
            resolvedProfessionName.isNotEmpty &&
            services.any((service) {
              final serviceProfession = (service['profession_name'] ?? '')
                  .toString()
                  .trim();
              return _textContainsNormalized(
                serviceProfession,
                resolvedProfessionName,
              );
            });
        final professionMatch =
            (resolvedProfessionId != null &&
                professionIds.contains(resolvedProfessionId)) ||
            professionNameMatch;

        if (matchedTask == null &&
            !professionMatch &&
            !serviceNameMatch &&
            !keywordMatch) {
          continue;
        }

        final scheduleCount = scheduleCountByProvider[providerId] ?? 0;
        final minimumStartTime = DateTime.now().add(fixedBookingLeadTime);
        Map<String, dynamic>? nextFreeSlot;
        var blockedOnlyByLeadTimeToday = false;
        for (final dateKey in dateKeys) {
          final slots = batchSlots['$providerId|$dateKey'] ?? const [];
          for (final slot in slots) {
            final slotMap = Map<String, dynamic>.from(slot);
            final slotStart = DateTime.tryParse(
              '${slotMap['start_time'] ?? ''}',
            )?.toLocal();
            final isEligible =
                slotStart != null && !slotStart.isBefore(minimumStartTime);
            final isSelectable = slotMap['is_selectable'] == true;
            final isSameLocalDayAsMinimum =
                slotStart != null &&
                slotStart.year == minimumStartTime.year &&
                slotStart.month == minimumStartTime.month &&
                slotStart.day == minimumStartTime.day;
            if (isSelectable &&
                slotStart != null &&
                slotStart.isBefore(minimumStartTime) &&
                isSameLocalDayAsMinimum) {
              blockedOnlyByLeadTimeToday = true;
            }
            if (isSelectable && isEligible) {
              nextFreeSlot = slotMap;
              break;
            }
          }
          if (nextFreeSlot != null) break;
        }

        final normalized = <String, dynamic>{
          ...providerData,
          ...provider,
          'id': providerId,
          'provider_match_mode': matchedTask != null
              ? 'task'
              : professionMatch
              ? 'profession'
              : 'service_text',
          'matched_service': matchedTask,
          'resolved_service': resolved,
          'display_price': matchedTask != null
              ? _safePrice(
                  matchedTask['custom_price'] ??
                      matchedTask['price'] ??
                      matchedTask['unit_price'],
                )
              : resolvedPrice > 0
              ? resolvedPrice
              : _safePrice(
                  services.isNotEmpty
                      ? services.first['custom_price'] ??
                            services.first['price'] ??
                            services.first['unit_price']
                      : null,
                ),
        };

        final nextAvailableAt = nextFreeSlot?['start_time']?.toString();
        final hasValidNextAvailableAt =
            nextAvailableAt != null && nextAvailableAt.trim().isNotEmpty;

        if (nextFreeSlot != null && hasValidNextAvailableAt) {
          normalized['next_available_slot'] = nextFreeSlot;
          normalized['next_available_at'] = nextAvailableAt;
          availableChunk.add(normalized);
        } else {
          final legacyConfigs = providerData['schedule_configs'];
          final hasLegacySchedule =
              legacyConfigs is List && legacyConfigs.isNotEmpty;
          normalized['unavailability_reason'] = blockedOnlyByLeadTimeToday
              ? (fixedBookingLeadTime.inMinutes > 0
                    ? 'Os horários de hoje exigem ${fixedBookingLeadTime.inMinutes} min de antecedência'
                    : 'Os horários de hoje já passaram')
              : scheduleCount == 0 && !hasLegacySchedule
              ? 'Sem agenda configurada'
              : 'Sem horário livre nos próximos $horizonDays dias';
          unavailableChunk.add(normalized);
        }
      }

      availableChunk.sort((a, b) {
        final aDist = a['distance_km'] is num
            ? (a['distance_km'] as num).toDouble()
            : double.infinity;
        final bDist = b['distance_km'] is num
            ? (b['distance_km'] as num).toDouble()
            : double.infinity;
        final byDistance = aDist.compareTo(bDist);
        if (byDistance != 0) return byDistance;
        final aSlot = DateTime.tryParse('${a['next_available_at'] ?? ''}');
        final bSlot = DateTime.tryParse('${b['next_available_at'] ?? ''}');
        if (aSlot == null && bSlot == null) return 0;
        if (aSlot == null) return 1;
        if (bSlot == null) return -1;
        return aSlot.compareTo(bSlot);
      });

      unavailableChunk.sort((a, b) {
        final aDist = a['distance_km'] is num
            ? (a['distance_km'] as num).toDouble()
            : double.infinity;
        final bDist = b['distance_km'] is num
            ? (b['distance_km'] as num).toDouble()
            : double.infinity;
        return aDist.compareTo(bDist);
      });

      aggregatedAvailable.addAll(availableChunk);
      aggregatedUnavailable.addAll(unavailableChunk);
      processed = end;

      yield {
        'type': 'chunk',
        'service': resolved,
        'available': availableChunk,
        'unavailable': unavailableChunk,
        'processed': processed,
        'total': providersForAvailability.length,
      };
    }

    yield {
      'type': 'done',
      'service': resolved,
      'available': aggregatedAvailable,
      'unavailable': aggregatedUnavailable,
      'processed': processed,
      'total': providersForAvailability.length,
    };
  }

  /// Geocodificação reversa via Edge Function geo (Sprint 2: substitui GET /geo/reverse)
  Future<Map<String, dynamic>> reverseGeocode(double lat, double lon) async {
    return _geoService.reverseGeocode(lat, lon);
  }

  /// Busca de endereços via Edge Function geo (Sprint 2: substitui GET /geo/search)
  Future<List<dynamic>> searchAddress(
    String query, {
    double? lat,
    double? lon,
    double? radiusKm,
  }) async {
    return _geoService.searchAddress(
      query,
      lat: lat,
      lon: lon,
      radiusKm: radiusKm,
    );
  }

  /// Registra um endereço selecionado no banco de dados próprio (Crowdsourcing)
  Future<void> registerAddressInRegistry({
    required String fullAddress,
    String? streetName,
    String? streetNumber,
    String? neighborhood,
    String? city,
    String? stateCode,
    String? poiName,
    required double lat,
    required double lon,
    String? category,
  }) async {
    return _geoService.registerAddressInRegistry(
      fullAddress: fullAddress,
      streetName: streetName,
      streetNumber: streetNumber,
      neighborhood: neighborhood,
      city: city,
      stateCode: stateCode,
      poiName: poiName,
      lat: lat,
      lon: lon,
      category: category,
    );
  }

  Map<String, String> get authHeaders => _headers;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
      headers['apikey'] = SupabaseConfig.anonKey;
    } else {
      // Fallback para endpoints públicos como /geo
      headers['Authorization'] = 'Bearer ${SupabaseConfig.anonKey}';
      headers['apikey'] = SupabaseConfig.anonKey;
    }
    return headers;
  }

  /// Fetches the structured list of Professions -> Services from the Backend
  /// with task-level data (task_catalog) so manual search mostra serviço por
  /// profissão de forma correta.
  /// Returns a `Map<String, List<Map<String, dynamic>>>`
  Future<Map<String, List<Map<String, dynamic>>>> getServicesMap() async {
    try {
      final responseWrapper = await _backendApiClient.getJson(
        '/api/v1/tasks?active_eq=true&limit=5000',
      );
      final response = (responseWrapper?['data'] as List? ?? const []);

      final Map<String, List<Map<String, dynamic>>> result = {};

      for (var item in response) {
        if (item is! Map) continue;
        final professionName =
            item['profession_name']?.toString() ??
            item['professions']?['name']?.toString() ??
            'Geral';

        if (!result.containsKey(professionName)) {
          result[professionName] = [];
        }

        result[professionName]!.add({
          'task_id': item['id'],
          'name': item['name'],
          'unit_price': item['unit_price'],
          'pricing_type': item['pricing_type'],
          'profession_id': item['profession_id'],
        });
      }

      return result;
    } catch (e) {
      debugPrint('Error fetching services map: $e');
      return {};
    }
  }

  Future<List<dynamic>> getServices() async {
    try {
      if (_userId == null) return [];

      final isProviderRole = (_role ?? '').toLowerCase().trim() == 'provider';
      final list = isProviderRole
          ? ((await _backendApiClient.getJson(
                      '/api/v1/services?user_id_eq=$_userId&limit=200&order=created_at.desc',
                    ))?['data']
                    as List? ??
                const [])
          : (((await _backendHomeApi.fetchClientHome())?.services) ?? const []);
      // Para cliente: não mostrar serviços cancelados na listagem principal.
      return list.where((row) {
        final map = row as Map;
        final st = (map['status'] ?? '').toString().toLowerCase().trim();
        return st != 'cancelled' && st != 'canceled';
      }).toList();
    } catch (e) {
      debugPrint('Error fetching services: $e');
      return [];
    }
  }

  /// Invoca uma Supabase Edge Function
  /// [functionName] é o nome da função (ex: 'ai-classify', 'geo')
  /// [body] é o JSON body (para POST)
  /// [queryParams] são parâmetros de query (para GET)
  Future<dynamic> invokeEdgeFunction(
    String functionName, [
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  ]) async {
    Map<String, dynamic>? decodeJwtPayload(String jwt) {
      try {
        final parts = jwt.split('.');
        if (parts.length < 2) return null;
        final payload = parts[1];
        final normalized = base64.normalize(
          payload.replaceAll('-', '+').replaceAll('_', '/'),
        );
        final decoded = utf8.decode(base64.decode(normalized));
        final obj = jsonDecode(decoded);
        final objMap = obj is Map<String, dynamic> ? obj : null;
        return objMap;
      } catch (_) {
        return null;
      }
    }

    Map<String, String> buildHeaders(String? jwt) {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'apikey': SupabaseConfig.anonKey,
      };
      if (jwt != null && jwt.isNotEmpty) {
        headers['Authorization'] = 'Bearer $jwt';
      } else {
        headers['Authorization'] = 'Bearer ${SupabaseConfig.anonKey}';
      }
      return headers;
    }

    Future<dynamic> callHttpFallback(String? jwt, {int attempt = 1}) async {
      final uri = Uri.parse(
        '$baseUrl/$functionName',
      ).replace(queryParameters: queryParams);
      debugPrint(
        '🔁 [EdgeFn][HTTP-Fallback] Chamando $functionName via HTTP explícito (tentativa $attempt)',
      );

      try {
        final response =
            await (body != null
                    ? _client.post(
                        uri,
                        headers: buildHeaders(jwt),
                        body: jsonEncode(body),
                      )
                    : _client.get(uri, headers: buildHeaders(jwt)))
                .timeout(const Duration(seconds: 30));

        if (response.statusCode >= 400) {
          final prefix = response.body.length > 800
              ? response.body.substring(0, 800)
              : response.body;
          debugPrint(
            '🔎 [EdgeFn][HTTP-Fallback] $functionName http=${response.statusCode} url=${response.request?.url} bodyPrefix=$prefix',
          );
        }

        return _handleResponse(response);
      } on TimeoutException catch (e) {
        if (attempt < 3) {
          final delay = Duration(milliseconds: 500 * attempt);
          await Future.delayed(delay);
          return callHttpFallback(jwt, attempt: attempt + 1);
        }
        throw ApiException(
          message: 'A função $functionName demorou muito a responder (Timeout)',
          statusCode: 408,
        );
      } on SocketException catch (e) {
        if (attempt < 3) {
          final delay = Duration(milliseconds: 1000 * attempt);
          await Future.delayed(delay);
          return callHttpFallback(jwt, attempt: attempt + 1);
        }
        throw ApiException(
          message: 'Sem conexão com o servidor. Verifique sua internet.',
          statusCode: 503,
          details: {'error': e.toString()},
        );
      } on FormatException catch (e) {
        throw ApiException(
          message: 'Resposta inválida do servidor (JSON malformado)',
          statusCode: 500,
          details: {'error': e.toString()},
        );
      }
    }

    Future<dynamic> callMethod({int attempt = 1}) async {
      // Endpoint público: evita fluxo JWT no Web para não cair em 401/Invalid JWT.
      if (functionName == 'tasks-semantic-search') {
        return await callHttpFallback(null);
      }

      final client = Supabase.instance.client;

      final jwt = await _getToken();
      if (jwt != null && jwt.length > 50) {
        debugPrint(
          '🔑 [EdgeFn] Chamando $functionName com JWT de Usuário (Len: ${jwt.length})',
        );
      } else {
        debugPrint(
          '⚠️ [EdgeFn] Chamando $functionName SEM JWT de Usuário (usando anonKey do SDK)',
        );
      }

      // IMPORTANTE:
      // Não sobrepor o header Authorization aqui, para evitar enviar JWT "stale"
      // quando o SDK faz refresh automático da sessão. O SDK já injeta o JWT
      // correto quando o usuário está autenticado.
      try {
        final response = await client.functions
            .invoke(
              functionName,
              body: body,
              queryParameters: queryParams,
              method: body != null ? HttpMethod.post : HttpMethod.get,
            )
            .timeout(const Duration(seconds: 30));
        return response.data;
      } on TimeoutException catch (e) {
        if (attempt < 3) {
          final delay = Duration(milliseconds: 1000 * attempt);
          await Future.delayed(delay);
          return callMethod(attempt: attempt + 1);
        }
        throw ApiException(
          message: 'A função $functionName demorou muito a responder (Timeout)',
          statusCode: 408,
        );
      } on SocketException catch (e) {
        if (attempt < 3) {
          final delay = Duration(milliseconds: 1000 * attempt);
          await Future.delayed(delay);
          return callMethod(attempt: attempt + 1);
        }
        // Fallback para HTTP em caso de erro de rede persistente
        debugPrint('⚠️ [EdgeFn] Erro de rede no SDK, fallback para HTTP');
        return await callHttpFallback(jwt);
      }
    }

    try {
      return await callMethod();
    } on TimeoutException {
      throw ApiException(
        message: 'A função $functionName demorou muito a responder (Timeout)',
        statusCode: 408,
      );
    } on FunctionException catch (e) {
      // JWT inválido/expirado: tenta refresh de sessão uma única vez.
      if (e.status == 401) {
        final beforeJwt = await _getToken();
        final payload = beforeJwt != null ? decodeJwtPayload(beforeJwt) : null;
        final iss = (payload?['iss'] ?? '').toString();
        final exp = payload?['exp'];
        final host = Uri.tryParse(SupabaseConfig.url.trim())?.host ?? '';
        debugPrint(
          '🚫 [EdgeFn] 401 em $functionName | host=$host | iss=$iss | exp=$exp',
        );

        try {
          await Supabase.instance.client.auth.refreshSession();
          // Reinvoca após refresh; callMethod busca o token novamente.
          return await callMethod();
        } catch (_) {
          // Tenta fallback HTTP com Authorization explícito.
          try {
            debugPrint('🔁 [EdgeFn][HTTP-Fallback] $functionName status=401');
            final refreshedJwt = await _getToken();
            return await callHttpFallback(refreshedJwt);
          } catch (fallbackErr) {
            // Se o fallback HTTP falhar, propagar o erro real (evita mascarar em "Invalid JWT")
            if (fallbackErr is ApiException) rethrow;
          }
        }
      }

      String friendlyMessage =
          'Não foi possível processar sua solicitação no momento ($functionName).';
      if (e.status == 500) {
        friendlyMessage =
            'O servidor encontrou um problema temporário. Tente novamente em instantes.';
      }
      if (e.status == 403) {
        friendlyMessage = 'Você não tem permissão para realizar esta ação.';
      }

      // Extrair detalhes técnicos se disponíveis para log
      final details = e.details is Map<String, dynamic>
          ? e.details as Map<String, dynamic>
          : <String, dynamic>{'raw': e.details};

      // Caso clássico de mismatch de projeto (token de outro Supabase):
      // a API responde "Invalid JWT". Nesse caso, limpar sessão e pedir login novamente.
      final detailsMsg = (details['message'] ?? details['error'] ?? '')
          .toString()
          .toLowerCase();
      if (e.status == 401 && detailsMsg.contains('invalid jwt')) {
        final currentJwt = await _getToken();
        final payload = currentJwt != null
            ? decodeJwtPayload(currentJwt)
            : null;
        final iss = (payload?['iss'] ?? '').toString().trim();
        final host = Uri.tryParse(SupabaseConfig.url.trim())?.host ?? '';

        // Só considerar "mismatch de projeto" se o issuer não bater com o host atual.
        final mismatch =
            iss.isNotEmpty && host.isNotEmpty && !iss.contains(host);
        debugPrint(
          '🚫 [EdgeFn] Invalid JWT em $functionName; iss=$iss host=$host mismatch=$mismatch',
        );

        if (mismatch) {
          try {
            await _secureStorage.delete(key: _tokenKey);
            _token = null;
            await Supabase.instance.client.auth.signOut();
          } catch (_) {}
          throw ApiException(
            message: 'Sessão inválida. Faça login novamente.',
            statusCode: 401,
            details: details,
          );
        }

        // Se não for mismatch, evitar limpar sessão (isso gera loop de login).
        // Orienta usuário a tentar novamente / reiniciar app e preserva details p/ debug.
        throw ApiException(
          message:
              'Falha de autenticação temporária. Tente novamente em instantes (se persistir, feche e reabra o app).',
          statusCode: 401,
          details: details,
        );
      }

      // Se o backend retornar erro estruturado, preferir a mensagem dele
      // (útil para PIX/MP com trace_id, step, reason_code).
      final backendError = (details['error'] ?? details['message'])?.toString();
      final backendTraceId = (details['trace_id'] ?? '').toString().trim();
      if (backendError != null && backendError.trim().isNotEmpty) {
        friendlyMessage = backendError.trim();
        if (backendTraceId.isNotEmpty &&
            !friendlyMessage.toLowerCase().contains('trace')) {
          friendlyMessage = '$friendlyMessage (trace: $backendTraceId)';
        }
      }

      if (e.status == 401) {
        debugPrint(
          '🚫 [EdgeFn] Erro 401 em $functionName: ${details['error'] ?? details['technicalDetail'] ?? e.details}',
        );
      }

      throw ApiException(
        message: friendlyMessage,
        statusCode: e.status,
        details: details,
      );
    } on SocketException catch (e) {
      throw ApiException(
        message: 'Sem conexão com o servidor. Verifique sua internet.',
        statusCode: 503,
        details: {'error': e.toString()},
      );
    } on FormatException catch (e) {
      throw ApiException(
        message: 'Resposta inválida do servidor (JSON malformado)',
        statusCode: 500,
        details: {'error': e.toString()},
      );
    } catch (e) {
      AppLogger.erro('❌ [EdgeFn] $functionName falhou', e);
      if (e is ApiException) rethrow;

      String message = 'Erro ao processar serviço inteligente ($functionName)';
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        message = 'Sem conexão com o servidor. Verifique sua internet.';
      }

      throw ApiException(message: message, statusCode: 500);
    }
  }

  Future<Map<String, dynamic>> validateFaceRecognition({
    required String serviceId,
    required String cnhImageUrl,
    required String selfieImageUrl,
  }) async {
    try {
      final client = Supabase.instance.client;
      final response = await client.functions
          .invoke(
            'validate-rekognition',
            body: {
              'serviceId': serviceId,
              'cnhImageUrl': cnhImageUrl,
              'selfieImageUrl': selfieImageUrl,
            },
            method: HttpMethod.post,
          )
          .timeout(const Duration(seconds: 45));

      if (response.status < 200 || response.status >= 300) {
        final data = response.data;
        final message = data is Map<String, dynamic>
            ? (data['detail'] ?? data['error'] ?? 'Erro no Rekognition')
                  .toString()
            : 'Erro no Rekognition';
        throw ApiException(message: message, statusCode: response.status);
      }

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'result': data};
    } on TimeoutException {
      throw ApiException(
        message: 'A validação facial demorou muito para responder',
        statusCode: 408,
      );
    } on SocketException catch (e) {
      throw ApiException(
        message: 'Sem conexão com o servidor. Verifique sua internet.',
        statusCode: 503,
        details: {'error': e.toString()},
      );
    } on FormatException catch (e) {
      throw ApiException(
        message: 'Resposta inválida do servidor (JSON malformado)',
        statusCode: 500,
        details: {'error': e.toString()},
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Falha ao validar reconhecimento facial: $e',
        statusCode: 500,
      );
    }
  }

  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      // Ensure token is fresh before request
      await _getToken();

      AppLogger.api('🚀 [POST] $endpoint');
      // debugPrint('🚀 [POST] Body: ${jsonEncode(body)}'); // Apenas se necessário

      final response = await _client
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

      AppLogger.sucesso('✅ [POST] $endpoint (Status: ${response.statusCode})');
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
        message: 'Servidor demorou a responder',
        statusCode: 408,
      );
    } on SocketException catch (e) {
      throw ApiException(
        message: 'Sem conexão com o servidor. Verifique sua internet.',
        statusCode: 503,
        details: {'error': e.toString()},
      );
    } on FormatException catch (e) {
      throw ApiException(
        message: 'Resposta inválida do servidor (JSON malformado)',
        statusCode: 500,
        details: {'error': e.toString()},
      );
    } catch (e) {
      AppLogger.erro('❌ [POST] $endpoint Falhou', e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      // Ensure token is fresh before request
      await _getToken();

      final response = await _client
          .put(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
        message: 'Servidor demorou a responder',
        statusCode: 408,
      );
    } on SocketException catch (e) {
      throw ApiException(
        message: 'Sem conexão com o servidor. Verifique sua internet.',
        statusCode: 503,
        details: {'error': e.toString()},
      );
    } on FormatException catch (e) {
      throw ApiException(
        message: 'Resposta inválida do servidor (JSON malformado)',
        statusCode: 500,
        details: {'error': e.toString()},
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      // Ensure token is fresh before request
      await _getToken();

      final response = await _client
          .get(Uri.parse('$baseUrl$endpoint'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
        message: 'Servidor demorou a responder',
        statusCode: 408,
      );
    } on SocketException catch (e) {
      throw ApiException(
        message: 'Sem conexão com o servidor. Verifique sua internet.',
        statusCode: 503,
        details: {'error': e.toString()},
      );
    } on FormatException catch (e) {
      throw ApiException(
        message: 'Resposta inválida do servidor (JSON malformado)',
        statusCode: 500,
        details: {'error': e.toString()},
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> delete(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    try {
      // Ensure token is fresh before request
      await _getToken();

      final response = await _client
          .delete(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
        message: 'Servidor demorou a responder',
        statusCode: 408,
      );
    } on SocketException catch (e) {
      throw ApiException(
        message: 'Sem conexão com o servidor. Verifique sua internet.',
        statusCode: 503,
        details: {'error': e.toString()},
      );
    } on FormatException catch (e) {
      throw ApiException(
        message: 'Resposta inválida do servidor (JSON malformado)',
        statusCode: 500,
        details: {'error': e.toString()},
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<http.Response> postRaw(
    String endpoint,
    List<Map<String, dynamic>> batchBody,
  ) async {
    await _getToken();
    try {
      return await _client
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: jsonEncode(batchBody),
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException(
        message: 'Servidor demorou a responder',
        statusCode: 408,
      );
    } on SocketException catch (e) {
      throw ApiException(
        message: 'Sem conexão com o servidor. Verifique sua internet.',
        statusCode: 503,
        details: {'error': e.toString()},
      );
    } on FormatException catch (e) {
      throw ApiException(
        message: 'Resposta inválida do servidor (JSON malformado)',
        statusCode: 500,
        details: {'error': e.toString()},
      );
    }
  }

  Future<http.Response> getRaw(
    String endpoint, {
    Map<String, String>? extraHeaders,
  }) async {
    final headers = {..._headers, if (extraHeaders != null) ...extraHeaders};
    try {
      return await http
          .get(Uri.parse('$baseUrl$endpoint'), headers: headers)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException(
        message: 'Servidor demorou a responder',
        statusCode: 408,
      );
    } on SocketException catch (e) {
      throw ApiException(
        message: 'Sem conexão com o servidor. Verifique sua internet.',
        statusCode: 503,
        details: {'error': e.toString()},
      );
    } on FormatException catch (e) {
      throw ApiException(
        message: 'Resposta inválida do servidor (JSON malformado)',
        statusCode: 500,
        details: {'error': e.toString()},
      );
    }
  }

  // --- Media & Storage ---

  // Duplicate methods removed to fix conflict
  // uploadServiceImage, uploadServiceVideo, uploadServiceAudio are defined with more options below

  Future<void> registerDeviceToken(
    String token,
    String platform, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      final client = Supabase.instance.client;

      // Se o user_id ainda não foi sincronizado para SharedPreferences,
      // fazemos fallback por supabase_uid para não perder o token do passageiro.
      if (_userId == null) {
        final uid = client.auth.currentUser?.id;
        if (uid == null || uid.trim().isEmpty) return;
        try {
          final updated = await client
              .from('users')
              .update({
                'fcm_token': token,
                'last_seen_at': DateTime.now().toIso8601String(),
              })
              .eq('supabase_uid', uid)
              .select('id, role')
              .maybeSingle();

          if (updated != null) {
            _userId = updated['id'] as int?;
            _role = updated['role']?.toString();
          }
        } on PostgrestException catch (e) {
          // Janela de consistência eventual: usuário autenticado, mas linha em users
          // ainda não refletida. Não é erro fatal para startup.
          if (e.code == 'PGRST116') return;
          rethrow;
        }
        return;
      }

      await client
          .from('users')
          .update({
            'fcm_token': token,
            'last_seen_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _userId!);

      // Também atualizar a tabela de localização se for prestador (provider)
      // Motoristas (driver) usam a tabela driver_locations via CentralService
      if (_role == 'provider' || _isMedical || _isFixedLocation) {
        final authUid = client.auth.currentUser?.id;
        await client
            .from('provider_locations')
            .upsert(
              _buildProviderLocationUpsertPayload(
                providerId: _userId!,
                providerUid: authUid,
                latitude: latitude,
                longitude: longitude,
              ),
            );
      }
    } catch (e) {
      debugPrint('Error registering device token: $e');
    }
  }

  Map<String, dynamic> _buildProviderLocationUpsertPayload({
    required int providerId,
    String? providerUid,
    double? latitude,
    double? longitude,
  }) {
    final hasCompleteCoords = latitude != null && longitude != null;
    return {
      'provider_id': providerId,
      if (providerUid != null && providerUid.trim().isNotEmpty)
        'provider_uid': providerUid,
      if (hasCompleteCoords) 'latitude': latitude,
      if (hasCompleteCoords) 'longitude': longitude,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<void> unregisterDeviceToken(String token) async {
    try {
      final client = Supabase.instance.client;
      if (_userId != null) {
        await client
            .from('users')
            .update({
              'fcm_token': null,
              'last_seen_at': DateTime.now().toIso8601String(),
            })
            .eq('id', _userId!);
        return;
      }

      final uid = client.auth.currentUser?.id;
      if (uid == null || uid.trim().isEmpty) return;
      await client
          .from('users')
          .update({
            'fcm_token': null,
            'last_seen_at': DateTime.now().toIso8601String(),
          })
          .eq('supabase_uid', uid);
    } catch (e) {
      debugPrint('Error unregistering device token: $e');
    }
  }

  // uploadChatMedia removed (unused)

  Future<void> uploadContestEvidence(
    String serviceId, {
    required String type, // 'photo', 'video', 'audio'
    required List<int> fileBytes,
    required String filename,
    required String mimeType,
  }) async {
    // Fase 7: Usar Supabase Storage + SDK em vez do backend legado
    final url = await uploadToCloud(
      fileBytes,
      filename: filename,
      serviceId: serviceId,
      type: 'contest',
    );

    // Registrar evidência diretamente na tabela service_disputes
    if (_userId != null) {
      try {
        await _backendApiClient.postJson(
          '/api/v1/service-disputes/evidence',
          body: {
            'service_id': serviceId,
            'type': type,
            'evidence_url': url,
            'user_id': _userId,
            'created_at': DateTime.now().toIso8601String(),
          },
        );
        debugPrint(
          '✅ [ApiService] Evidência de contestação registrada no Supabase',
        );
      } catch (e) {
        debugPrint('⚠️ [ApiService] Erro ao salvar evidência no Supabase: $e');
        // Não re-throw: upload já foi feito, salvar é secundário
      }
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (e) {
      final bodyPrefix = response.body.length > 500
          ? response.body.substring(0, 500)
          : response.body;
      // Log reduzido para produção
      debugPrint(
        'ERRO DECODE JSON [${response.request?.url}] (Status ${response.statusCode}): $bodyPrefix',
      );
      throw ApiException(
        message:
            'Resposta inválida do servidor (Status ${response.statusCode})',
        statusCode: response.statusCode,
        details: {
          'error': 'JSON malformado',
          'response_preview': bodyPrefix,
          'format_error': e.toString(),
        },
      );
    }

    Map<String, dynamic> data;

    if (decoded is Map<String, dynamic>) {
      data = decoded;
    } else if (decoded is Map) {
      // Converte Map<dynamic, dynamic> para Map<String, dynamic>
      data = decoded.map((key, value) => MapEntry(key.toString(), value));
    } else {
      data = <String, dynamic>{'raw': decoded};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    final msg =
        (data['message'] ?? data['error'] ?? 'Erro ${response.statusCode}')
            .toString();
    throw ApiException(message: msg, statusCode: response.statusCode);
  }

  // Removed manual check helpers as logic moved to backend

  Future<Map<String, dynamic>> register({
    required String
    token, // Token não mais estritamente necessário se já logado
    required String name,
    required String email,
    String? phone,
    String role = 'client',
    String? documentType,
    String? documentValue,
    String? subRole,
    String? commercialName,
    String? address,
    double? latitude,
    double? longitude,
    List<dynamic>? professions,
    int? vehicleTypeId,
    String? vehicleBrand,
    String? vehicleModel,
    int? vehicleYear,
    String? vehicleColor,
    int? vehicleColorHex,
    String? vehiclePlate,
    String? pixKey,
    String? birthDate,
    Map<String, dynamic>? metadata,
  }) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) throw Exception('Não logado no Supabase');
    final normalizedSubRole = role == 'provider'
        ? _normalizeProviderSubRole(subRole)
        : subRole;
    final isFixedProvider = role == 'provider' && normalizedSubRole == 'fixed';

    try {
      final payload = <String, dynamic>{
        'supabase_uid': currentUser.id,
        'email': email,
        'full_name': name,
        'role': role,
        'phone': phone,
        'birth_date': birthDate,
        'sub_role': normalizedSubRole,
        'is_fixed_location': isFixedProvider,
        'pix_key': pixKey,
        'commercial_name': commercialName,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'professions': professions,
        if (documentType != null && documentType.isNotEmpty)
          'document_type': documentType,
        if (documentValue != null && documentValue.isNotEmpty)
          'document_value': documentValue,
        if (vehicleTypeId != null)
          'vehicle': {
            'type_id': vehicleTypeId,
            'brand': vehicleBrand,
            'model': vehicleModel,
            'year': vehicleYear,
            'color': vehicleColor,
            'color_hex': vehicleColorHex,
            'plate': vehiclePlate,
          },
      };
      payload.removeWhere((_, value) => value == null);
      await _backendApiClient.postJson('/api/v1/auth/register', body: payload);

      Map<String, dynamic>? userRow = await _backendApiClient.getJson(
        '/api/v1/me',
      );
      userRow ??= await _backendApiClient.getJson(
        '/api/v1/users?supabase_uid_eq=${Uri.encodeQueryComponent(currentUser.id)}',
      );
      if (userRow != null && userRow['data'] is List) {
        final rows = userRow['data'] as List;
        userRow = rows.isNotEmpty
            ? Map<String, dynamic>.from(rows.first)
            : null;
      }

      final prefs = await SharedPreferences.getInstance();
      if (userRow != null) {
        final resolvedUserId = userRow['id'] is num
            ? (userRow['id'] as num).toInt()
            : int.tryParse('${userRow['id'] ?? ''}');
        _userId = resolvedUserId;
        _role = userRow['role']?.toString() ?? role;
        _isMedical = _parseBool(userRow['is_medical']);
        _isFixedLocation = _resolveProviderFixedLocation(
          Map<String, dynamic>.from(userRow),
        );
        _currentUserData = Map<String, dynamic>.from(userRow);
      } else {
        _role = role;
        _isFixedLocation = isFixedProvider;
      }

      if (_userId != null) await prefs.setInt('user_id', _userId!);
      await _secureStorage.write(key: 'user_role', value: _role ?? 'client');
      await _secureStorage.write(
        key: 'is_medical',
        value: _isMedical.toString(),
      );
      await _secureStorage.write(
        key: 'is_fixed_location',
        value: _isFixedLocation.toString(),
      );

      return {'success': true, 'user': userRow};
    } catch (e) {
      debugPrint('❌ [ApiService] Erro no registro: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> checkUnique({
    String? email,
    String? phone,
    String? document,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (email != null && email.trim().isNotEmpty) {
        params['email'] = email.trim();
      }
      if (phone != null && phone.trim().isNotEmpty) {
        params['phone'] = phone.trim();
      }
      if (document != null && document.trim().isNotEmpty) {
        params['document'] = document.trim();
      }
      if (params.isEmpty) return {'exists': false};
      final res = await _backendApiClient.postJson(
        '/api/v1/auth/check-unique',
        body: params,
      );
      if (res == null) return {'exists': false};
      return Map<String, dynamic>.from(res);
    } catch (e) {
      debugPrint('Error checking uniqueness: $e');
      return {'exists': false};
    }
  }

  Future<List<dynamic>> getProfessions() async {
    if (!SupabaseConfig.isInitialized) {
      debugPrint(
        '⚠️ [ApiService] getProfessions skipped: Supabase not initialized',
      );
      return [];
    }
    try {
      final res = await _backendApiClient.getJson('/api/v1/professions');
      return (res?['data'] as List? ?? const []);
    } catch (e) {
      debugPrint('Erro ao buscar profissões: $e');
      return [];
    }
  }

  Future<List<dynamic>> getProfessionTasks(
    dynamic professionId, {
    String? professionName,
  }) async {
    Map<String, dynamic> normalizeTask(Map raw) {
      final task = Map<String, dynamic>.from(raw);
      final durationMinutes =
          int.tryParse(
            '${task['estimated_duration_minutes'] ?? task['duration_minutes'] ?? ''}',
          ) ??
          int.tryParse('${task['estimated_duration'] ?? ''}') ??
          30;
      final price =
          double.tryParse(
            '${task['unit_price'] ?? task['base_price'] ?? task['price'] ?? '0'}',
          ) ??
          0.0;

      task['unit_price'] = task['unit_price'] ?? task['base_price'] ?? price;
      task['price'] = task['price'] ?? task['unit_price'] ?? price;
      task['description'] = task['description'] ?? task['name'] ?? '';
      task['estimated_duration_minutes'] =
          task['estimated_duration_minutes'] ?? durationMinutes;
      task['keywords'] = task['keywords'] ?? 'Duração: $durationMinutes min';
      return task;
    }

    try {
      final parsedProfessionId = int.tryParse(professionId.toString());
      List<dynamic> response = const [];
      if (parsedProfessionId != null && parsedProfessionId > 0) {
        final res = await _backendApiClient.getJson(
          '/api/v1/tasks?profession_id_eq=$parsedProfessionId&active_eq=true&limit=2000',
        );
        response = (res?['data'] as List? ?? const []);
      }

      var normalized = response
          .map((raw) => normalizeTask(raw as Map))
          .where((task) => task['active'] != false)
          .toList();

      if (normalized.isNotEmpty) {
        return normalized;
      }

      final trimmedProfessionName = professionName?.trim();
      if (trimmedProfessionName == null || trimmedProfessionName.isEmpty) {
        return normalized;
      }

      final servicesMap = await getServicesMap();
      final normalizedProfessionName = _normalizeSearchText(
        trimmedProfessionName,
      );

      for (final entry in servicesMap.entries) {
        if (_normalizeSearchText(entry.key) != normalizedProfessionName) {
          continue;
        }

        normalized = entry.value
            .map((raw) => normalizeTask(raw))
            .where((task) => task['active'] != false)
            .toList();
        if (normalized.isNotEmpty) {
          debugPrint(
            'ℹ️ [ApiService] getProfessionTasks fallback por nome usado para "$trimmedProfessionName": ${normalized.length} serviços.',
          );
          return normalized;
        }
      }

      return normalized;
    } catch (e) {
      debugPrint('Erro ao buscar tarefas da profissão: $e');
      return [];
    }
  }

  Future<void> saveProviderSchedule(
    List<Map<String, dynamic>> schedules,
  ) async {
    await saveScheduleConfig(schedules);
  }

  Future<void> saveProviderService(Map<String, dynamic> service) async {
    if (_userId == null) throw Exception('Not authenticated');
    final professionsRes = await _backendApiClient.getJson(
      '/api/v1/provider-professions?provider_user_id_eq=${_userId!}&limit=1',
    );
    final professions = (professionsRes?['data'] as List? ?? const []);
    final professionId = professions.isNotEmpty
        ? (professions.first as Map)['profession_id']
        : null;

    await _backendApiClient.postJson(
      '/api/v1/task-catalog',
      body: {
        'profession_id': professionId,
        'name': service['name'],
        'unit_price': service['price'],
        'unit_name': 'unidade',
        'active': true,
        // Outros campos como duration seriam salvos em uma tabela de extensão ou JSON se necessário
      },
    );
  }

  Future<List<Map<String, dynamic>>> getProviderServices({
    dynamic providerId,
  }) async {
    final targetId = providerId != null
        ? int.tryParse(providerId.toString())
        : _userId;

    if (targetId == null) return [];

    try {
      final professionsRes = await _backendApiClient.getJson(
        '/api/v1/provider-professions?provider_user_id_eq=$targetId',
      );
      debugPrint(
        '🔍 [ApiService] Buscando profissões para o provider: $targetId',
      );
      final professionRows = (professionsRes?['data'] as List? ?? const []);

      final professionIds = professionRows
          .map((r) => int.tryParse(r['profession_id']?.toString() ?? '0'))
          .whereType<int>()
          .where((id) => id > 0)
          .toSet() // Use a Set to prevent duplicates
          .toList();

      debugPrint('🔍 [ApiService] Profissões encontradas: $professionIds');
      if (professionIds.isEmpty) {
        debugPrint('⚠️ [ApiService] Provider sem profissões vinculadas.');
        return [];
      }

      final tasksRes = await _backendApiClient.getJson(
        '/api/v1/tasks?profession_id_in=${professionIds.join(",")}&limit=5000',
      );
      final List<dynamic> tasks = (tasksRes?['data'] as List? ?? const []);

      final taskList = tasks.map((raw) {
        final task = Map<String, dynamic>.from(raw as Map);
        task['unit_price'] = task['unit_price'] ?? task['base_price'] ?? 0.0;
        task['price'] = task['price'] ?? task['unit_price'];
        task['description'] = task['description'] ?? task['name'] ?? '';
        task['duration_minutes'] =
            task['duration_minutes'] ??
            task['estimated_duration_minutes'] ??
            task['estimated_duration'] ??
            30;
        return task;
      }).toList();
      debugPrint(
        '🔍 [ApiService] Serviços encontrados no catálogo global: ${taskList.length}',
      );

      // Para prestador fixo, os serviços oferecidos são por prestador (não global).
      // Usa `provider_tasks` (provider_id=user_id) para persistir is_active e custom_price.
      try {
        final providerTasksRes = await _backendApiClient.getJson(
          '/api/v1/provider-tasks?provider_id_eq=$targetId&limit=5000',
        );
        final providerTasksRaw =
            (providerTasksRes?['data'] as List? ?? const []);

        var providerTasks = List<Map<String, dynamic>>.from(providerTasksRaw);

        // Bootstrap: se ainda não existir nenhum vínculo, ativa todos os tasks das profissões do prestador.
        // SOMENTE se for o próprio prestador logado (isSelf). Se for um cliente vendo, apenas retorna a lista completa.
        if (providerTasks.isEmpty && taskList.isNotEmpty) {
          // Cliente visualizando: Simular que todos os serviços estão ativos se o vínculo não existir
          for (final t in taskList) {
            t['is_active'] = true;
            t['active'] = true;
          }
          return taskList;
        }

        final byTaskId = <int, Map<String, dynamic>>{};
        for (final row in providerTasks) {
          final taskId = int.tryParse(row['task_id']?.toString() ?? '');
          if (taskId == null) continue;
          byTaskId[taskId] = row;
        }

        for (final t in taskList) {
          final taskId = int.tryParse(t['id']?.toString() ?? '');
          if (taskId == null) continue;
          final row = byTaskId[taskId];
          final isActive = row == null
              ? true
              : (row['is_active'] == true || row['is_active'] == 1);

          t['is_active'] = isActive;
          // compat com telas antigas que leem `active`
          t['active'] = isActive;

          final customPrice = row?['custom_price'];
          if (customPrice != null) {
            t['unit_price'] = customPrice;
          }
        }
      } catch (e) {
        // Se `provider_tasks` ainda não existir no banco remoto ou RLS bloquear,
        // retorna a lista sem personalização por prestador (somente leitura).
        debugPrint(
          '⚠️ [ApiService] provider_tasks indisponível (usando fallback): $e',
        );
      }

      return taskList;
    } catch (e) {
      debugPrint('⚠️ [ApiService] Erro ao buscar serviços do provider: $e');
      return [];
    }
  }

  Future<void> setProviderServiceActive(int taskId, bool active) async {
    if (_userId == null) throw Exception('Not authenticated');
    final authUid = _currentAuthUid();
    final row = <String, dynamic>{
      'provider_id': _userId,
      if (authUid != null) 'provider_uid': authUid,
      'task_id': taskId,
      'is_active': active,
    };

    // Persistência por prestador: não alterar `task_catalog` global.
    await _backendApiClient.putJson(
      '/api/v1/providers/${_userId!}/tasks/$taskId',
      body: {'is_active': active, ...row},
    );

    // Contrato de busca é sincronizado no backend.
  }

  /// Login legado mantido por compatibilidade, mas agora usa Supabase diretamente.
  /// O fluxo principal já usa loginWithFirebase().
  Future<Map<String, dynamic>> login(String firebaseToken) async {
    // Não chama mais o backend legado (/auth/login)
    // Sinc com Supabase via loginWithFirebase
    debugPrint(
      '⚠️ [ApiService] login() chamado — redirecionando para loginWithFirebase()',
    );
    await loginWithFirebase(firebaseToken);
    return {
      'success': true,
      'user': {
        'id': _userId,
        'role': _role,
        'is_medical': _isMedical,
        'is_fixed_location': _isFixedLocation,
      },
    };
  }

  /// Logger for Dispatch Audit (v11)
  Future<void> logServiceEvent(
    String serviceId,
    String action, [
    String? details,
  ]) async {
    try {
      if (_userId == null) return;

      // Must be authenticated (RLS uses auth.uid()).
      final session = Supabase.instance.client.auth.currentSession;
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (session == null || uid == null || uid.trim().isEmpty) {
        // Background isolates (FCM/Awesome) may not have a restored session.
        // Skip silently to avoid noisy errors.
        return;
      }

      final Map<String, dynamic> payload = {
        'service_id': serviceId,
        'action': action,
      };
      if (details != null && details.trim().isNotEmpty) {
        payload['details'] = details;
      } else {
        payload['details'] = '';
      }

      await _backendApiClient.postJson(
        '/api/v1/services/$serviceId/logs',
        body: payload,
      );
      debugPrint('✅ [ApiService] Logged event $action for service $serviceId');
    } catch (e) {
      if (e is PostgrestException && e.code == '42501') {
        // RLS denied: treat as best-effort (do not spam logs).
        return;
      }
      if (e is PostgrestException &&
          (e.code == '23503' ||
              e.message.toLowerCase().contains('foreign key'))) {
        // FK em service_id inválido: best-effort logging, não bloquear fluxo.
        debugPrint(
          '⚠️ [ApiService] Ignorando logServiceEvent($action): service_id sem referência válida ($serviceId)',
        );
        return;
      }
      if (e is PostgrestException && e.code == 'PGRST204') {
        // Schema mismatch (ex.: cache antigo em local). Não bloquear fluxo crítico.
        debugPrint(
          '⚠️ [ApiService] logServiceEvent schema mismatch (best-effort): ${e.message}',
        );
        return;
      }
      debugPrint('❌ [ApiService] Failed to log event: $e');
    }
  }

  // Alias for getProfile to maintain compatibility
  Future<Map<String, dynamic>> getProfile() async {
    final data = await getUserData();
    if (data == null) throw Exception('Profile not found');
    return data;
  }

  Future<Map<String, dynamic>?> getUserData() async {
    try {
      final me = await _backendApiClient.getJson('/api/v1/me');
      if (me is Map<String, dynamic> && me['id'] != null) {
        return Map<String, dynamic>.from(me);
      }
      final data = me?['data'];
      if (data is List && data.isNotEmpty) {
        return Map<String, dynamic>.from(data.first as Map);
      }
      if (_userId != null) {
        return await _selectUserRowMaybeSingleBy('id', _userId);
      }
      return null;
    } catch (e) {
      debugPrint('Erro ao buscar dados do usuário: $e');
      return null;
    }
  }

  Future<void> loginWithFirebase(
    String idToken, {
    String? role,
    String? phone,
    String? name,
  }) async {
    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;

    if (currentUser == null) throw Exception('Não logado no Supabase');

    try {
      // 1. Buscar usuário existente pelo supabase_uid para preservar o role
      var userRow = await _selectUserRowMaybeSingleBy(
        'supabase_uid',
        currentUser.id,
      );

      if (userRow == null) {
        // 1.1 Tentar buscar por e-mail caso o usuário tenha um registro legado sem UID vinculado
        final email = currentUser.email;
        if (email != null && email.isNotEmpty) {
          userRow = await _selectUserRowMaybeSingleBy('email', email);

          if (userRow != null) {
            debugPrint(
              '🔗 [ApiService] Vinculando registro existente ao supabase_uid: ${currentUser.id}',
            );
            await _backendApiClient.putJson(
              '/api/v1/users/${userRow['id']}',
              body: {'supabase_uid': currentUser.id},
            );
            userRow['supabase_uid'] = currentUser.id;
          }
        }
      }

      if (userRow == null) {
        // Usuário novo — criar com role padrão
        final email = currentUser.email;
        final fullName =
            name ??
            currentUser.userMetadata?['full_name'] ??
            email?.split('@')[0] ??
            'Usuário';

        await _backendApiClient.postJson(
          '/api/v1/auth/sync',
          body: {
            'supabase_uid': currentUser.id,
            'email': email,
            'full_name': fullName,
            'role': role ?? 'client',
            'phone': phone,
          },
        );
        // Pode haver pequeno atraso entre sync e visibilidade na leitura.
        for (var attempt = 0; attempt < 6 && userRow == null; attempt++) {
          if (attempt > 0) {
            await Future.delayed(Duration(milliseconds: 200 * attempt));
          }
          userRow = await _selectUserRowMaybeSingleBy(
            'supabase_uid',
            currentUser.id,
          );
          if (userRow != null) break;
          userRow = await _getUserRowByAuthUid(currentUser.id);
        }

        if (userRow == null) {
          final me = await _backendApiClient.getJson('/api/v1/me');
          if (me != null) {
            if (me['data'] is List && (me['data'] as List).isNotEmpty) {
              userRow = Map<String, dynamic>.from(
                (me['data'] as List).first as Map,
              );
            } else if (me['id'] != null) {
              userRow = Map<String, dynamic>.from(me);
            }
          }
        }

        if (userRow == null) {
          // Consistência eventual: mantém fallback local mínimo para não quebrar startup.
          _role = role ?? 'client';
          _currentUserData = <String, dynamic>{
            'supabase_uid': currentUser.id,
            'email': currentUser.email,
            'role': _role,
          };
          debugPrint(
            '⚠️ [ApiService] syncUserProfile: usuário ainda não refletido no backend; usando fallback temporário local.',
          );
          return;
        }
      } else {
        // Usuário existente — atualizar apenas nome/email, NÃO sobrescrever o role
        final updates = <String, dynamic>{};
        if (name != null) updates['full_name'] = name;
        if (phone != null) updates['phone'] = phone;

        if (updates.isNotEmpty) {
          await client
              .from('users')
              .update(updates)
              .eq('supabase_uid', currentUser.id);
        }
      }

      // 3. Atualizar estado local com o role do BANCO (preserva driver/provider)
      _role = userRow['role'];
      _userId = userRow['id'];
      _currentUserData = userRow; // Cache full user data
      _isMedical = userRow['is_medical'] == true;
      _isFixedLocation = _resolveProviderFixedLocation(
        Map<String, dynamic>.from(userRow),
      );

      final prefs = await SharedPreferences.getInstance();
      if (_userId != null) await prefs.setInt('user_id', _userId!);
      await _secureStorage.write(key: 'user_role', value: _role ?? 'client');
      await _secureStorage.write(
        key: 'is_medical',
        value: _isMedical.toString(),
      );
      await _secureStorage.write(
        key: 'is_fixed_location',
        value: _isFixedLocation.toString(),
      );

      if (kDebugMode) {
        final savedRole = await _secureStorage.read(key: 'user_role');
        if (savedRole != _role) {
          debugPrint(
            '🚨 [ApiService.loginWithFirebase] Role não salvo corretamente! Expected: $_role, Got: $savedRole',
          );
        }
      }

      // Authenticate Realtime Service
      if (_userId != null) {
        RealtimeService().authenticate(_userId!.toString());
      }

      // Update FCM Token se disponível
      if (_fcmToken != null) {
        await registerDeviceToken(_fcmToken!, Platform.operatingSystem);
      }
    } catch (e) {
      debugPrint('❌ [ApiService] Erro ao sincronizar usuário: $e');
      rethrow;
    }
  }

  Future<void> updateProfile({
    String? name,
    String? email,
    String? phone,
    Map<String, dynamic>? customFields,
  }) async {
    if (_userId == null) return;

    final body = <String, dynamic>{};
    if (name != null) body['full_name'] = name;
    if (email != null) body['email'] = email;
    if (phone != null) body['phone'] = phone;
    if (customFields != null) body.addAll(customFields);

    if (body.isNotEmpty) {
      try {
        await _backendApiClient.putJson(
          '/api/v1/users/${_userId!}',
          body: body,
        );
        final updatedRow = await _selectUserRowMaybeSingleBy('id', _userId);
        if (updatedRow == null) return;
        _currentUserData = updatedRow;
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST204' &&
            body.containsKey('document_type') &&
            (e.message.contains("'document_type'") ||
                e.message.contains('document_type'))) {
          final fallbackBody = Map<String, dynamic>.from(body)
            ..remove('document_type');
          await _backendApiClient.putJson(
            '/api/v1/users/${_userId!}',
            body: fallbackBody,
          );
          final updatedRow = await _selectUserRowMaybeSingleBy('id', _userId);
          if (updatedRow == null) return;
          _currentUserData = updatedRow;
        } else {
          rethrow;
        }
      }
    }
  }

  /// Verifica se o perfil do usuário está completo com os campos obrigatórios.
  bool isProfileComplete() {
    final data = _currentUserData;
    if (data == null) return false;

    final fullName = data['full_name'] as String?;
    final phone = data['phone'] as String?;
    final documentValue = data['document_value'] as String?;
    final birthDate = data['birth_date'] as String?;

    return fullName != null &&
        fullName.trim().isNotEmpty &&
        phone != null &&
        phone.trim().isNotEmpty &&
        documentValue != null &&
        documentValue.trim().isNotEmpty &&
        birthDate != null &&
        birthDate.trim().isNotEmpty;
  }

  /// Força o recarregamento dos dados do usuário do Supabase.
  Future<void> refreshUserData() async {
    final userRow = await getUserData();

    if (userRow != null) {
      _currentUserData = userRow;
      _role = userRow['role'];
      _userId = userRow['id'];
      _isMedical = userRow['is_medical'] == true;
      _isFixedLocation = _resolveProviderFixedLocation(
        Map<String, dynamic>.from(userRow),
      );

      await _secureStorage.write(key: 'user_role', value: _role ?? 'client');
      await _secureStorage.write(
        key: 'is_medical',
        value: _isMedical.toString(),
      );
      await _secureStorage.write(
        key: 'is_fixed_location',
        value: _isFixedLocation.toString(),
      );
    }
  }

  Future<void> updateProviderProfile({
    String? documentType,
    String? documentValue,
    String? commercialName,
    String? address,
    List<String>? professions,
  }) async {
    if (_userId == null) return;

    final body = <String, dynamic>{};
    if (documentType != null) body['document_type'] = documentType;
    if (documentValue != null) body['document_value'] = documentValue;
    if (commercialName != null) body['commercial_name'] = commercialName;
    if (address != null) body['address'] = address;

    if (body.isNotEmpty) {
      await _backendApiClient.putJson(
        '/api/v1/providers/${_userId!}/profile',
        body: body,
      );
    }

    // Professions logic (opcional: pode precisar de lógica de delete/insert no provider_professions)
  }

  Future<int?> getMyUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value == 1; // 1 is true, 0 is false
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return false;
  }

  void _applyIdentitySnapshot(ApiIdentitySnapshot snapshot) {
    _userId = snapshot.userId;
    _role = snapshot.role;
    _isMedical = snapshot.isMedical;
    _isFixedLocation = snapshot.isFixedLocation;
  }

  Future<void> persistBootstrapIdentity({
    String? role,
    bool? isMedical,
    bool? isFixedLocation,
    int? registerStep,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (role != null && role.trim().isNotEmpty) {
      _role = role.trim();
      await _secureStorage.write(key: 'user_role', value: _role!);
    }
    if (isMedical != null) {
      _isMedical = isMedical;
      await _secureStorage.write(
        key: 'is_medical',
        value: _isMedical.toString(),
      );
    }
    if (isFixedLocation != null) {
      _isFixedLocation = isFixedLocation;
      await _secureStorage.write(
        key: 'is_fixed_location',
        value: _isFixedLocation.toString(),
      );
    }
    if (registerStep != null) {
      await prefs.setInt('register_step', registerStep);
    }
  }

  Future<void> applyBackendProfileSnapshot(Map<String, dynamic> user) async {
    _currentUserData = Map<String, dynamic>.from(user);

    final resolvedUserId = user['id'] is num
        ? (user['id'] as num).toInt()
        : int.tryParse('${user['id'] ?? ''}');
    if (resolvedUserId != null) {
      _userId = resolvedUserId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('user_id', resolvedUserId);
    }

    _isMedical = _parseBool(user['is_medical']);
    _isFixedLocation = _resolveProviderFixedLocation(_currentUserData!);
    _currentUserData!['is_fixed_location'] = _isFixedLocation;
    _role = user['role']?.toString();

    if (_role != null && _role!.trim().isNotEmpty) {
      await _secureStorage.write(key: 'user_role', value: _role!);
    }
    await _secureStorage.write(key: 'is_medical', value: _isMedical.toString());
    await _secureStorage.write(
      key: 'is_fixed_location',
      value: _isFixedLocation.toString(),
    );
  }

  String _normalizeProviderSubRole(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value == 'fixed' || value == 'mobile') return value;
    return 'mobile';
  }

  bool _isFixedServiceType(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'at_provider' ||
        normalized == 'fixed' ||
        normalized == 'provider';
  }

  bool _isMobileServiceType(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'on_site' ||
        normalized == 'mobile' ||
        normalized == 'client';
  }

  Map<String, dynamic>? _extractProviderRecord(dynamic providersRelation) {
    if (providersRelation is Map<String, dynamic>) {
      return Map<String, dynamic>.from(providersRelation);
    }
    if (providersRelation is List && providersRelation.isNotEmpty) {
      final first = providersRelation.first;
      if (first is Map) {
        return Map<String, dynamic>.from(first);
      }
    }
    return null;
  }

  bool _resolveProviderFixedLocation(Map<String, dynamic> userRow) {
    if (_parseBool(userRow['is_fixed_location'])) return true;

    final subRole = (userRow['sub_role'] ?? '').toString().trim().toLowerCase();
    if (subRole == 'fixed') return true;
    if (subRole == 'mobile') return false;

    final provider = _extractProviderRecord(userRow['providers']);
    if (provider == null) return false;

    if (_parseBool(provider['is_fixed_location'])) return true;

    final providerServiceType = (provider['service_type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (_isFixedServiceType(providerServiceType)) return true;
    if (_isMobileServiceType(providerServiceType)) return false;

    return false;
  }

  double _calculateDistanceKm(
    double fromLat,
    double fromLon,
    double toLat,
    double toLon,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(toLat - fromLat);
    final dLon = _degreesToRadians(toLon - fromLon);
    final a =
        pow(sin(dLat / 2), 2) +
        cos(_degreesToRadians(fromLat)) *
            cos(_degreesToRadians(toLat)) *
            pow(sin(dLon / 2), 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) => degrees * (pi / 180);

  Future<Map<String, dynamic>> getMyProfile() async {
    if (!SupabaseConfig.isInitialized) {
      throw StateError('Supabase não inicializado');
    }
    if ((_token == null || _token!.trim().isEmpty) && !hasHydratedIdentity) {
      await loadToken();
    }
    final client = _supa;
    User? currentUser = client.auth.currentUser;
    if (currentUser == null) {
      // On web reload, auth session restoration can be asynchronous.
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        currentUser = client.auth.currentUser;
        if (currentUser != null) break;
      }
    }

    Map<String, dynamic> user;
    String resolutionSource = 'unknown';
    if (currentUser != null) {
      final userByAuth = await _getUserRowByAuthUid(currentUser.id);
      if (userByAuth != null) {
        user = userByAuth;
        resolutionSource = 'auth_uid';
      } else if (_userId != null) {
        final userByCachedId = await _getUserRowById(_userId!);
        if (userByCachedId != null) {
          user = userByCachedId;
          resolutionSource = 'cached_user_id_after_auth_miss';
          debugPrint(
            '⚠️ [ApiService.getMyProfile] Auth UID ${currentUser.id} sem linha em users; usando fallback por user_id=$_userId',
          );
        } else {
          throw Exception(
            'Usuário autenticado sem correspondência em users para supabase_uid=${currentUser.id}',
          );
        }
      } else {
        debugPrint(
          '⚠️ [ApiService.getMyProfile] profile_query_failed reason=auth_uid_missing_user_row '
          'authUid=${currentUser.id} cachedUserId=${_userId ?? "-"} role=${_role ?? "-"} '
          'isFixedLocation=$_isFixedLocation',
        );
        throw Exception(
          'Usuário autenticado sem correspondência em users para supabase_uid=${currentUser.id}',
        );
      }
    } else if (_userId != null) {
      debugPrint(
        'ℹ️ [ApiService.getMyProfile] bootstrap_identity_pending source=cached_user_id '
        'authUid=- cachedUserId=$_userId role=${_role ?? "-"} isFixedLocation=$_isFixedLocation',
      );
      // Fallback to cached local id when Supabase auth takes longer to hydrate.
      final userByCachedId = await _getUserRowById(_userId!);
      if (userByCachedId == null) {
        debugPrint(
          '⚠️ [ApiService.getMyProfile] profile_query_failed reason=cached_user_id_missing_user_row '
          'cachedUserId=$_userId role=${_role ?? "-"} isFixedLocation=$_isFixedLocation',
        );
        throw Exception(
          'Não foi possível reidratar o usuário local id=$_userId',
        );
      }
      user = userByCachedId;
      resolutionSource = 'cached_user_id';
    } else {
      final cachedRole = _role?.trim() ?? '';
      if (cachedRole.isNotEmpty || _isFixedLocation) {
        debugPrint(
          'ℹ️ [ApiService.getMyProfile] bootstrap_identity_pending source=cached_role_only '
          'authUid=- cachedUserId=- role=${cachedRole.isEmpty ? "-" : cachedRole} '
          'isFixedLocation=$_isFixedLocation',
        );
      } else {
        debugPrint(
          '⚠️ [ApiService.getMyProfile] profile_query_failed reason=no_identity_snapshot '
          'authUid=- cachedUserId=- role=- isFixedLocation=$_isFixedLocation',
        );
      }
      throw Exception('Não autenticado');
    }

    _currentUserData = Map<String, dynamic>.from(user);
    final resolvedUserId = user['id'] is num
        ? (user['id'] as num).toInt()
        : int.tryParse('${user['id'] ?? ''}');
    if (resolvedUserId != null && _userId != resolvedUserId) {
      debugPrint(
        '🪪 [ApiService.getMyProfile] Ajustando _userId de ${_userId ?? "-"} para $resolvedUserId',
      );
      _userId = resolvedUserId;
    }

    double? parseWalletFromProviders(dynamic providersRel) {
      if (providersRel == null) return null;
      if (providersRel is Map) {
        final raw = providersRel['wallet_balance'];
        if (raw is num) return raw.toDouble();
        return double.tryParse(raw?.toString() ?? '');
      }
      if (providersRel is List && providersRel.isNotEmpty) {
        final first = providersRel.first;
        if (first is Map) {
          final raw = first['wallet_balance'];
          if (raw is num) return raw.toDouble();
          return double.tryParse(raw?.toString() ?? '');
        }
      }
      return null;
    }

    final providerWallet = parseWalletFromProviders(user['providers']);
    final legacyBalance = () {
      final raw = user['balance'];
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw?.toString() ?? '');
    }();
    final effectiveWallet = providerWallet ?? legacyBalance ?? 0.0;

    user['provider_wallet_balance'] = providerWallet;
    user['wallet_balance_effective'] = effectiveWallet;
    user['wallet_balance'] = effectiveWallet;

    // Compatibilidade: telas legadas continuam lendo `balance`.
    user['balance'] = effectiveWallet;

    debugPrint(
      '🪪 [ApiService.getMyProfile] source=$resolutionSource authUid=${currentUser?.id ?? "-"} '
      'resolvedUserId=${_userId ?? "-"} rowSupabaseUid=${user['supabase_uid'] ?? "-"} '
      'role=${user['role'] ?? "-"} subRole=${user['sub_role'] ?? "-"}',
    );
    debugPrint('DEBUG: getMyProfile fetched user: ${jsonEncode(user)}');

    // Update local state based on fresh profile data
    _isMedical = _parseBool(user['is_medical']);
    _isFixedLocation = _resolveProviderFixedLocation(user);
    user['is_fixed_location'] = _isFixedLocation;
    _role = user['role']?.toString();

    await _secureStorage.write(key: 'is_medical', value: _isMedical.toString());
    await _secureStorage.write(
      key: 'is_fixed_location',
      value: _isFixedLocation.toString(),
    );
    if (_role != null)
      await _secureStorage.write(key: 'user_role', value: _role!);

    return user;
  }

  Future<Map<String, dynamic>> updateMyProfileViaApi({
    required String name,
    required String email,
    required String phone,
  }) async {
    final payload = <String, dynamic>{
      'full_name': name.trim(),
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
    };

    Map<String, dynamic>? res;
    try {
      res = await _backendApiClient.putJson(
        '/api/v1/profile/me',
        body: payload,
      );
    } catch (_) {
      res = await _backendApiClient.putJson('/api/v1/me', body: payload);
    }

    final data = res?['data'];
    if (data is Map) {
      _currentUserData = Map<String, dynamic>.from(data);
      final resolvedUserId = data['id'] is num
          ? (data['id'] as num).toInt()
          : int.tryParse('${data['id'] ?? ''}');
      if (resolvedUserId != null) _userId = resolvedUserId;
      return Map<String, dynamic>.from(data);
    }

    return await getMyProfile();
  }

  Future<List<String>> getProviderSpecialties() async {
    if (!SupabaseConfig.isInitialized || _userId == null) return [];
    final response = await _backendApiClient.getJson(
      '/api/v1/providers/${_userId!}/specialties',
    );
    final rows = (response?['data'] as List? ?? const []);
    return rows
        .map((e) => ((e as Map)['name'] ?? '').toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> getProviderProfile(int providerId) async {
    debugPrint(
      '🚀 [ApiService] getProviderProfile: Instando busca para ID $providerId',
    );
    // 1. Basic user and provider data (backend-first para evitar 404 no PostgREST web)
    final profileRes = await _backendApiClient.getJson(
      '/api/v1/providers/$providerId/profile',
    );
    final data = profileRes?['data'] is Map
        ? Map<String, dynamic>.from(profileRes!['data'] as Map)
        : <String, dynamic>{};
    if (data.isEmpty) {
      debugPrint(
        '❌ [ApiService] Perfil do prestador $providerId não encontrado.',
      );
      return {};
    }
    debugPrint(
      '✅ [ApiService] Dados básicos carregados. Nome: ${data['name']}',
    );

    List<dynamic> toList(dynamic val) {
      if (val == null) return [];
      if (val is List) return val;
      if (val is Map) return [val];
      return [];
    }

    // 2. Schedules
    try {
      final schedsRes = await _backendApiClient.getJson(
        '/api/v1/providers/$providerId/schedules',
      );
      final scheds = (schedsRes?['data'] as List? ?? const []);
      data['schedules'] = scheds;
      debugPrint(
        '📅 [ApiService] Horários: ${(data['schedules'] as List).length} registros.',
      );
    } catch (e) {
      debugPrint('⚠️ [ApiService] Erro horários: $e');
      data['schedules'] = [];
    }

    // 3. Specialties
    try {
      final profsRes = await _backendApiClient.getJson(
        '/api/v1/providers/$providerId/specialties',
      );
      final profs = (profsRes?['data'] as List? ?? const []);

      data['specialties'] = profs
          .map((p) => ((p as Map)['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
      debugPrint('🛠️ [ApiService] Especialidades: ${data['specialties']}');
    } catch (e) {
      debugPrint('⚠️ [ApiService] Erro especialidades: $e');
      data['specialties'] = [];
    }

    // 4. Services (Using the robust getProviderServices logic with bootstrap)
    try {
      final servicesList = await getProviderServices(providerId: providerId);

      data['services'] = servicesList.map((s) {
        final service = Map<String, dynamic>.from(s);
        // Ensure standard fields expected by ProviderProfileScreen
        service['price'] =
            service['unit_price'] ?? service['custom_price'] ?? 0.0;
        service['name'] = service['name'] ?? 'Serviço';
        return service;
      }).toList();

      debugPrint(
        '🛒 [ApiService] Serviços (via getProviderServices): ${(data['services'] as List).length} registros.',
      );
    } catch (e) {
      debugPrint('⚠️ [ApiService] Erro serviços: $e');
      data['services'] = [];
    }

    // 5. Reviews
    try {
      final reviewsRes = await Supabase.instance.client
          .from('reviews')
          .select(_providerProfileReviewsProjection)
          .eq('reviewee_id', providerId)
          .order('created_at', ascending: false)
          .limit(10);

      final reviewsList = (reviewsRes as List? ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      final reviewerIds = reviewsList
          .map((r) => r['reviewer_id'])
          .whereType<int>()
          .toSet()
          .toList();
      if (reviewerIds.isNotEmpty) {
        final usersRes = await Supabase.instance.client
            .from('users')
            .select('id, name, avatar_url')
            .inFilter('id', reviewerIds);

        final Map usersMap = {for (var u in (usersRes as List)) u['id']: u};
        for (var r in reviewsList) {
          final rid = r['reviewer_id'];
          if (rid != null && usersMap.containsKey(rid)) {
            r['client'] = usersMap[rid];
          }
        }
      }
      data['reviews'] = reviewsList;
      debugPrint(
        '⭐ [ApiService] Avaliações: ${(data['reviews'] as List).length} registros.',
      );
    } catch (e) {
      debugPrint('⚠️ [ApiService] Erro reviews: $e');
      data['reviews'] = [];
    }

    // Address and coordinate unification
    final providersList = toList(data['providers']);
    final providerData = providersList.isNotEmpty
        ? Map<String, dynamic>.from(providersList.first as Map)
        : null;

    if (providerData != null) {
      data['commercial_name'] =
          providerData['commercial_name'] ?? data['commercial_name'];
      data['name'] = providerData['commercial_name'] ?? data['name'];
      data['address'] = data['address'] ?? providerData['address'];
      data['latitude'] = data['latitude'] ?? providerData['latitude'];
      data['longitude'] = data['longitude'] ?? providerData['longitude'];
      data['provider_data'] = providerData;
    }

    // Compat: só usa relações embutidas se realmente vierem no select.
    final embeddedSchedules = toList(data['provider_schedules']);
    if (embeddedSchedules.isNotEmpty) {
      data['schedules'] = embeddedSchedules;
    }

    final embeddedProfessions = toList(data['provider_professions']);
    if (embeddedProfessions.isNotEmpty) {
      data['specialties'] = embeddedProfessions
          .map((p) {
            final prof = (p as Map)['professions'];
            if (prof is Map) return (prof['name'] ?? '').toString();
            return '';
          })
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final embeddedTasks = toList(data['provider_tasks']);
    if (embeddedTasks.isNotEmpty) {
      data['services'] = embeddedTasks.map((t) {
        final task = Map<String, dynamic>.from(t as Map);
        final catalog = task['task_catalog'] as Map<String, dynamic>?;
        if (catalog != null) {
          task['name'] = catalog['name'];
          task['description'] = catalog['description'];
          task['unit_name'] = catalog['unit_name'];
          task['price'] = task['custom_price'] ?? catalog['unit_price'];
          task['duration'] =
              catalog['duration'] ??
              catalog['duration_minutes'] ??
              catalog['estimated_duration'];
        }
        return task;
      }).toList();
    }

    final normalizedServices = (data['services'] as List? ?? [])
        .map((raw) {
          final service = Map<String, dynamic>.from(raw as Map);
          service['name'] = (service['name'] ?? 'Serviço').toString();
          service['price'] =
              service['price'] ??
              service['unit_price'] ??
              service['custom_price'] ??
              0;
          service['duration'] =
              service['duration'] ??
              service['duration_minutes'] ??
              service['estimated_duration'] ??
              30;
          service['active'] = service['active'] ?? service['is_active'] ?? true;
          return service;
        })
        .where((service) {
          final active = service['active'];
          return active == true || active == 1 || active == null;
        })
        .toList();
    data['services'] = normalizedServices;
    data['specialties'] = const <String>[];

    return data;
  }

  Future<List<Map<String, dynamic>>> searchProviders({
    String? term,
    double? lat,
    double? lon,
    String? requiredServiceType,
  }) async {
    final client = Supabase.instance.client;

    final response = await client
        .from('users')
        .select('*, providers(*)')
        .eq('role', 'provider');

    var providers = (response as List)
        .map((p) => Map<String, dynamic>.from(p as Map<String, dynamic>))
        .toList();

    // Fixed-location providers (e.g., salão/barbearia) should appear for at_provider flows
    if (requiredServiceType == 'at_provider') {
      providers = providers.where((p) {
        final providerData = p['providers'] as Map<String, dynamic>?;
        // Prefer explicit flags/columns. Address alone is not a reliable signal.
        final userSubRole = (p['sub_role']?.toString() ?? '').toLowerCase();
        final isFixedByUser = userSubRole == 'fixed';
        final providerServiceType =
            (providerData?['service_type']?.toString() ?? '').toLowerCase();
        final isFixedByProvider = providerServiceType == 'at_provider';
        final isFixedByFlag = providerData?['is_fixed_location'] == true;
        final scheduleConfigs = providerData?['schedule_configs'];
        final hasLegacyScheduleConfigs =
            scheduleConfigs is List && scheduleConfigs.isNotEmpty;
        return isFixedByUser ||
            isFixedByProvider ||
            isFixedByFlag ||
            hasLegacyScheduleConfigs;
      }).toList();

      providers = providers
          .where((p) => !_shouldSuppressFixedProvider(p))
          .toList();
    }

    // Search by term in provider name/address/profession
    if (term != null && term.trim().isNotEmpty) {
      final lowerTerm = term.toLowerCase();

      // profissão -> prestadores (pode falhar por RLS/perm; nesse caso, seguimos com match por nome/endereço)
      List<dynamic> professionMatches = const [];
      try {
        professionMatches = await client
            .from('professions')
            .select('id')
            .ilike('name', '%$term%');
      } catch (e) {
        debugPrint('⚠️ [searchProviders] professions lookup failed: $e');
        professionMatches = const [];
      }

      final professionIds = professionMatches
          .map((e) => e['id'])
          .whereType<num>()
          .map((v) => v.toInt())
          .toList();

      final matchingProviderIds = <int>{};
      if (professionIds.isNotEmpty) {
        try {
          final ppRes = await _backendApiClient.getJson(
            '/api/v1/provider-professions?profession_id_in=${professionIds.join(",")}&limit=5000',
          );
          final ppMatches = (ppRes?['data'] as List? ?? const []);

          final missingUids = <String>{};

          for (var item in ppMatches) {
            final providerId = item['provider_user_id'];
            if (providerId != null) {
              final id = int.tryParse(providerId.toString());
              if (id != null) matchingProviderIds.add(id);
            }
            final providerUid = (item['provider_uid'] ?? '').toString().trim();
            if (providerUid.isNotEmpty) missingUids.add(providerUid);
          }

          if (missingUids.isNotEmpty) {
            final uidRows = await client
                .from('users')
                .select('id,supabase_uid')
                .inFilter('supabase_uid', missingUids.toList());
            for (final raw in (uidRows as List)) {
              final id = int.tryParse('${raw['id']}');
              if (id != null) matchingProviderIds.add(id);
            }
          }
        } catch (e) {
          debugPrint(
            '⚠️ [searchProviders] provider_professions lookup failed: $e',
          );
        }
      }

      providers = providers.where((p) {
        final fullName = (p['full_name']?.toString() ?? '').toLowerCase();
        final providerData = p['providers'] as Map<String, dynamic>?;
        final commercialName =
            (providerData?['commercial_name']?.toString() ?? '').toLowerCase();
        final providerAddress = (providerData?['address']?.toString() ?? '')
            .toLowerCase();
        final userId = int.tryParse(p['id']?.toString() ?? '');

        final nameMatch =
            fullName.contains(lowerTerm) ||
            commercialName.contains(lowerTerm) ||
            providerAddress.contains(lowerTerm);
        final professionMatch =
            userId != null && matchingProviderIds.contains(userId);

        return nameMatch || professionMatch;
      }).toList();
    }

    // Add computed distance and open status to make UI cards more informative
    if (lat != null && lon != null) {
      for (var p in providers) {
        final providerData = p['providers'] as Map<String, dynamic>?;
        final providerLat = providerData != null
            ? double.tryParse(providerData['latitude']?.toString() ?? '')
            : null;
        final providerLon = providerData != null
            ? double.tryParse(providerData['longitude']?.toString() ?? '')
            : null;

        if (providerLat != null && providerLon != null) {
          final distance = _calculateDistanceKm(
            lat,
            lon,
            providerLat,
            providerLon,
          );
          p['distance_km'] = double.parse(distance.toStringAsFixed(1));
        }

        p['is_open'] = providerData?['is_online'] == true;
      }

      providers.sort((a, b) {
        final aDist = a['distance_km'] is num
            ? (a['distance_km'] as num).toDouble()
            : double.infinity;
        final bDist = b['distance_km'] is num
            ? (b['distance_km'] as num).toDouble()
            : double.infinity;
        return aDist.compareTo(bDist);
      });
    }

    return providers;
  }

  Future<List<Map<String, dynamic>>> getProviderSchedules({
    required List<int> providerIds,
  }) async {
    if (providerIds.isEmpty) return [];
    final allRows = <Map<String, dynamic>>[];
    for (final providerId in providerIds.toSet()) {
      final schedule = await _backendSchedulingApi.fetchProviderSchedule(
        providerId,
      );
      final configs = schedule?['configs'];
      if (configs is! List) continue;
      for (final raw in configs.whereType<Map>()) {
        allRows.add({
          ...raw.cast<String, dynamic>(),
          'provider_id': providerId,
        });
      }
    }
    return allRows;
  }

  Future<void> addProviderSpecialty(String name) async {
    if (_userId == null) {
      throw ApiException(
        message: 'Usuário não autenticado para adicionar profissão.',
        statusCode: 401,
      );
    }
    final authUid = _currentAuthUid();
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ApiException(message: 'Profissão inválida.', statusCode: 400);
    }

    final matchesResponse = await _backendApiClient.getJson(
      '/api/v1/professions?name_ilike=${Uri.encodeQueryComponent('%$normalized%')}&limit=10',
    );
    final matches = (matchesResponse?['data'] as List? ?? const []);

    if (matches.isEmpty) {
      throw ApiException(
        message: 'Profissão "$normalized" não encontrada no catálogo.',
        statusCode: 404,
      );
    }

    Map<String, dynamic> selected = Map<String, dynamic>.from(matches.first);
    for (final raw in matches) {
      final row = Map<String, dynamic>.from(raw as Map);
      if ((row['name'] ?? '').toString().trim().toLowerCase() ==
          normalized.toLowerCase()) {
        selected = row;
        break;
      }
    }

    await _backendApiClient.postJson(
      '/api/v1/providers/${_userId!}/specialties',
      body: {
        'provider_user_id': _userId,
        if (authUid != null) 'provider_uid': authUid,
        'profession_id': selected['id'],
      },
    );

    // Contratos de busca ficam a cargo do backend nesta migração REST-first.
  }

  Future<void> removeProviderSpecialty(String name) async {
    if (_userId == null) return;
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    final matchesResponse = await _backendApiClient.getJson(
      '/api/v1/professions?name_ilike=${Uri.encodeQueryComponent(normalized)}&limit=1',
    );
    final prof = (matchesResponse?['data'] as List? ?? const []).isNotEmpty
        ? (matchesResponse?['data'] as List).first
        : null;
    if (prof is Map && prof['id'] != null) {
      await _backendApiClient.deleteJson(
        '/api/v1/providers/${_userId!}/specialties/${prof['id']}',
      );
    }
  }

  /// Fetch professions filtered by service_type.
  /// serviceType: 'at_provider' (fixo) | 'on_site' (móvel)
  Future<List<Map<String, dynamic>>> fetchProfessionsByServiceType(
    String serviceType, {
    int limit = 50,
  }) async {
    try {
      final res = await _backendApiClient.getJson(
        '/api/v1/professions?service_type_eq=$serviceType&limit=$limit',
      );
      return (res?['data'] as List? ?? const [])
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    } catch (e) {
      debugPrint('Erro ao carregar profissões ($serviceType): $e');
      return [];
    }
  }

  Future<bool> deleteAccount() async {
    if (_userId == null) return false;
    await _backendApiClient.deleteJson('/api/v1/users/$_userId');
    await clearToken();
    return true;
  }

  Future<void> requestWithdrawal(String pixKey, double amount) async {
    throw UnsupportedError(
      'ApiService.requestWithdrawal desativado. Use PaymentRepository/BackendPaymentApi.',
    );
  }

  Future<int?> resolveProfessionIdForServiceCreation({
    required int? professionId,
    required int? taskId,
    required String? professionName,
  }) async {
    if (professionId != null && professionId > 0) return professionId;

    try {
      if (taskId != null && taskId > 0) {
        final taskRes = await _backendApiClient.getJson(
          '/api/v1/tasks?id_eq=$taskId&limit=1',
        );
        final taskRow =
            taskRes?['data'] is List && (taskRes?['data'] as List).isNotEmpty
            ? (taskRes?['data'] as List).first
            : null;
        final taskProfessionId = int.tryParse(
          '${taskRow is Map ? taskRow['profession_id'] : ''}',
        );
        if (taskProfessionId != null && taskProfessionId > 0) {
          return taskProfessionId;
        }
      }

      final normalizedName = (professionName ?? '').trim();
      if (normalizedName.isNotEmpty) {
        final profRes = await _backendApiClient.getJson(
          '/api/v1/professions?name_ilike=${Uri.encodeQueryComponent(normalizedName)}&limit=1',
        );
        final profRow =
            profRes?['data'] is List && (profRes?['data'] as List).isNotEmpty
            ? (profRes?['data'] as List).first
            : null;
        final nameProfessionId = int.tryParse(
          '${profRow is Map ? profRow['id'] : ''}',
        );
        if (nameProfessionId != null && nameProfessionId > 0) {
          return nameProfessionId;
        }
      }
    } catch (e) {
      debugPrint(
        '⚠️ [ApiService] Falha ao resolver profession_id para criação do serviço: $e',
      );
    }

    return null;
  }

  // ========== SERVICES ==========
  Future<Map<String, dynamic>> createService({
    required int categoryId,
    required String description,
    required dynamic latitude,
    required dynamic longitude,
    required String address,
    required dynamic priceEstimated,
    required dynamic priceUpfront,
    double? feeAdminRate,
    double? feeAdminAmount,
    double? amountPayableOnSite,
    List<String> imageKeys = const [],
    String? videoKey,
    List<String> audioKeys = const [],
    String? profession,
    dynamic professionId,
    String locationType = 'client',
    dynamic providerId,
    DateTime? scheduledAt,
    dynamic taskId,
    int? totalDurationMinutes,
  }) async {
    int? localUserId = _userId;
    String? localAuthUid = _supa.auth.currentUser?.id;
    if (localUserId == null || (localAuthUid == null || localAuthUid.isEmpty)) {
      final me = await _backendApiClient.getJson('/api/v1/me');
      final row = me?['data'] is List
          ? ((me?['data'] as List).isNotEmpty
                ? (me?['data'] as List).first
                : null)
          : me?['data'] ?? me;
      if (row is Map) {
        localUserId =
            (row['id'] as num?)?.toInt() ?? int.tryParse('${row['id'] ?? ''}');
        localAuthUid = (row['supabase_uid'] ?? '').toString().trim();
        _userId = localUserId;
      }
    }
    if (localUserId == null || localAuthUid == null || localAuthUid.isEmpty) {
      throw ApiException(message: 'Usuário não autenticado', statusCode: 401);
    }

    final blockingDispute = await getBlockingDisputeForCurrentClient();
    if (blockingDispute != null) {
      throw ApiException(
        message:
            'Você possui um serviço sob contestação. Consulte os detalhes antes de contratar outro serviço.',
        statusCode: 409,
      );
    }

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) {
        return double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
      }
      return 0.0;
    }

    final double lat = parseDouble(latitude);
    final double lon = parseDouble(longitude);
    final double pEst = parseDouble(priceEstimated);
    final double pUpRaw = parseDouble(priceUpfront);
    // Garantia financeira: entrada + restante = 100% do serviço.
    // - limita entrada entre 0 e total
    // - recalcula restante a partir do total
    final double pUp = pUpRaw.clamp(0.0, pEst).toDouble();
    final double normalizedFeeAdminRate = (feeAdminRate ?? 0.30)
        .clamp(0.0, 1.0)
        .toDouble();
    final double normalizedFeeAdminAmount =
        feeAdminAmount ??
        double.parse((pEst * normalizedFeeAdminRate).toStringAsFixed(2));
    final double normalizedAmountPayableOnSite =
        amountPayableOnSite ?? double.parse((pEst - pUp).toStringAsFixed(2));
    final int? professionIdInt = professionId == null
        ? null
        : int.tryParse(professionId.toString());
    final int? providerIdInt = providerId == null
        ? null
        : int.tryParse(providerId.toString());
    final int? taskIdInt = taskId == null
        ? null
        : int.tryParse(taskId.toString());
    final int? resolvedProfessionId =
        await resolveProfessionIdForServiceCreation(
          professionId: professionIdInt,
          taskId: taskIdInt,
          professionName: profession,
        );
    if (resolvedProfessionId == null) {
      final auditPayload = {
        'category_id': categoryId,
        'task_id': taskIdInt,
        'profession_name': profession,
        'location_type': locationType,
        'provider_id': providerIdInt,
      };
      debugPrint(
        '🚨 [AUDIT][CREATE_SERVICE] profession_id não resolvido. Dispatch pode buscar prestadores sem filtro de profissão. payload=${jsonEncode(auditPayload)}',
      );
      AppLogger.notificacao(
        'AUDIT create_service profession_id_unresolved payload=${jsonEncode(auditPayload)}',
      );
    }

    // Gerar ID UUID v4 do serviço baseado num UUID.
    // Como o SDK Supabase pode não gerar UUID client-side fácil sem pacote extra, deixamos o BD gerar se possível, ou usamos o gen_random_uuid().
    // O SDK tem .insert() que retorna o item inserido.

    final body = <String, dynamic>{
      'client_id': localUserId, // Inteiro
      'client_uid':
          localAuthUid, // UUID do auth user (necessário para autorizações em Edge/RLS)
      'category_id': categoryId,
      'description': description,
      'latitude': double.parse(lat.toStringAsFixed(8)),
      'longitude': double.parse(lon.toStringAsFixed(8)),
      'address': address,
      'price_estimated': double.parse(pEst.toStringAsFixed(2)),
      'price_upfront': double.parse(pUp.toStringAsFixed(2)),
      'status': 'waiting_payment', // Padrão
      'profession': profession,
      'profession_id': resolvedProfessionId,
      'location_type': locationType,
      'provider_id': providerIdInt,
      'scheduled_at': scheduledAt?.toIso8601String(),
      'fee_admin_rate': normalizedFeeAdminRate,
      'fee_admin_amount': normalizedFeeAdminAmount,
      'amount_payable_on_site': normalizedAmountPayableOnSite,
      'task_id': taskIdInt,
    };

    debugPrint('📤 [CREATE SERVICE SUPABASE SDK] Body: ${jsonEncode(body)}');

    try {
      final tipoFluxo = (scheduledAt != null || locationType == 'provider')
          ? TipoFluxo.fixed
          : TipoFluxo.mobile;

      if (tipoFluxo == TipoFluxo.fixed) {
        if (providerIdInt == null || providerIdInt <= 0) {
          throw ApiException(
            message: 'Prestador fixo inválido para criar agendamento.',
            statusCode: 400,
          );
        }
        if (scheduledAt == null) {
          throw ApiException(
            message: 'Horário inválido para criar agendamento fixo.',
            statusCode: 400,
          );
        }
        final fixedBooking = await _createFixedBookingRecord(
          providerId: providerIdInt,
          procedureName: description.trim(),
          scheduledStartUtc: scheduledAt.toUtc(),
          scheduledEndUtc: scheduledAt.toUtc().add(
            Duration(minutes: totalDurationMinutes ?? 60),
          ),
          totalPrice: pEst,
          upfrontPrice: pUp,
          professionId: resolvedProfessionId,
          professionName: profession,
          taskId: taskIdInt,
          categoryId: categoryId,
          address: address,
          latitude: lat,
          longitude: lon,
          imageKeys: imageKeys,
          videoKey: videoKey,
        );
        return {
          'success': true,
          'serviceId': fixedBooking['id'],
          'service': fixedBooking,
        };
      }

      final insertBody = Map<String, dynamic>.from(body);
      final created = await _backendApiClient.postJson(
        '/api/v1/services',
        body: insertBody,
      );
      if (created == null) {
        throw ApiException(
          message: 'Falha ao criar serviço via /api/v1/services',
          statusCode: 502,
        );
      }
      final response = created['data'] is Map
          ? Map<String, dynamic>.from(created['data'] as Map)
          : Map<String, dynamic>.from(created);

      final serviceId = response['id'];

      // Se for presencial/agendado e já tiver provider, cria o bloqueio via API canônica.
      if (scheduledAt != null && providerIdInt != null) {
        final duration = totalDurationMinutes ?? 60;
        final ok = await _backendSchedulingApi.bookProviderSlot(
          providerIdInt,
          clientId: _userId ?? 0,
          serviceRequestId: '$serviceId',
          startTime: scheduledAt,
          endTime: scheduledAt.add(Duration(minutes: duration)),
        );
        if (!ok) {
          throw ApiException(
            message:
                'Falha ao reservar slot via /api/v1/providers/:id/slots/book',
            statusCode: 502,
          );
        }
      }

      return {'success': true, 'serviceId': serviceId, 'service': response};
    } catch (e) {
      debugPrint('❌ [CREATE SERVICE SUPABASE SDK] Erro: $e');
      throw ApiException(
        message: 'Falha ao criar serviço: $e',
        statusCode: 500,
      );
    }
  }

  // Helper to map Supabase relation objects into flattened keys as expected by UI
  Map<String, dynamic> _mapServiceData(Map<String, dynamic> raw) {
    final nestedService = raw['service'] is Map
        ? Map<String, dynamic>.from(raw['service'] as Map)
        : const <String, dynamic>{};
    final Map<String, dynamic> mapped = {
      ...nestedService,
      ...Map<String, dynamic>.from(raw),
    };

    final normalizedServiceId =
        raw['service_id']?.toString().trim().isNotEmpty == true
        ? raw['service_id']
        : nestedService['id'] ?? raw['id'];
    final dispatchRowId = raw['service_id'] != null ? raw['id'] : null;

    if (raw['users'] is Map) {
      final users = Map<String, dynamic>.from(raw['users'] as Map);
      mapped['client_name'] = users['full_name'];
      mapped['client_avatar'] = users['avatar_url'];
    } else if (nestedService['users'] is Map) {
      final users = Map<String, dynamic>.from(nestedService['users'] as Map);
      mapped['client_name'] = users['full_name'];
      mapped['client_avatar'] = users['avatar_url'];
    }

    if (raw['providers'] is Map && (raw['providers'] as Map)['users'] is Map) {
      final providerUsers = Map<String, dynamic>.from(
        (raw['providers'] as Map)['users'] as Map,
      );
      mapped['provider_name'] = providerUsers['full_name'];
      mapped['provider_avatar'] = providerUsers['avatar_url'];
    } else if (nestedService['providers'] is Map &&
        (nestedService['providers'] as Map)['users'] is Map) {
      final providerUsers = Map<String, dynamic>.from(
        (nestedService['providers'] as Map)['users'] as Map,
      );
      mapped['provider_name'] = providerUsers['full_name'];
      mapped['provider_avatar'] = providerUsers['avatar_url'];
    }

    mapped['client_name'] =
        (mapped['client_name'] ?? '').toString().trim().isNotEmpty
        ? mapped['client_name']
        : 'Cliente';
    mapped['provider_name'] =
        (mapped['provider_name'] ?? '').toString().trim().isNotEmpty
        ? mapped['provider_name']
        : 'Prestador';

    mapped['client'] = {
      'id': raw['client_id'],
      'name': mapped['client_name'],
      'avatar': mapped['client_avatar'],
      'photo': mapped['client_avatar'],
    };
    mapped['provider'] = {
      'id': raw['provider_id'],
      'name': mapped['provider_name'],
      'avatar': mapped['provider_avatar'],
      'photo': mapped['provider_avatar'],
    };

    if (raw['service_categories'] is Map) {
      mapped['category_name'] = (raw['service_categories'] as Map)['name'];
    } else if (nestedService['service_categories'] is Map) {
      mapped['category_name'] =
          (nestedService['service_categories'] as Map)['name'];
    }

    final double price =
        double.tryParse(
          (mapped['price_estimated'] ??
                  raw['price_total'] ??
                  raw['price'] ??
                  raw['total_price'] ??
                  0)
              .toString(),
        ) ??
        0.0;
    final double providerAmount =
        double.tryParse(
          (raw['price_provider'] ?? mapped['provider_amount'] ?? '').toString(),
        ) ??
        double.parse((price * 0.85).toStringAsFixed(2));

    mapped['id'] = normalizedServiceId;
    mapped['service_id'] = normalizedServiceId;
    mapped['dispatch_row_id'] = dispatchRowId;
    mapped['status'] =
        nestedService['status'] ?? mapped['status'] ?? 'open_for_schedule';
    mapped['description'] =
        mapped['description'] ??
        raw['service_name'] ??
        nestedService['description'];
    mapped['latitude'] =
        mapped['latitude'] ??
        raw['service_latitude'] ??
        nestedService['latitude'];
    mapped['longitude'] =
        mapped['longitude'] ??
        raw['service_longitude'] ??
        nestedService['longitude'];
    mapped['provider_id'] =
        mapped['provider_id'] ??
        raw['provider_user_id'] ??
        nestedService['provider_id'];
    mapped['price_estimated'] = price;
    mapped['provider_amount'] = providerAmount;

    return mapped;
  }

  String _normalizeFixedStatusForUi(Map<String, dynamic> data) {
    final rawStatus = (data['status'] ?? '').toString().trim();
    final upper = rawStatus.toUpperCase();
    final lower = rawStatus.toLowerCase();

    final arrivedAt = data['arrived_at'];
    final clientArrived =
        data['client_arrived'] == true || data['client_arrived'] == 'true';
    if (arrivedAt != null || clientArrived) {
      return 'client_arrived';
    }

    switch (upper) {
      case 'PENDENTE':
        return 'waiting_payment';
      case 'CONFIRMADO':
      case 'CONFIRMED':
      case 'SCHEDULED':
      case 'ACCEPTED':
        return 'accepted';
      case 'EM_DESLOCAMENTO':
        return 'client_departing';
      case 'EM_EXECUCAO':
        return 'in_progress';
      case 'CONCLUIDO':
        return 'completed';
      case 'CANCELADO':
        return 'cancelled';
      default:
        if (lower == 'arrived' || lower == 'client_departing') {
          return 'client_departing';
        }
        if (lower == 'client_arrived') {
          return 'client_arrived';
        }
        if (data['client_departing_at'] != null) {
          return 'client_departing';
        }
        return lower.isEmpty ? 'waiting_payment' : lower;
    }
  }

  String _generateSixDigitCompletionCode() {
    final value = Random().nextInt(900000) + 100000;
    return value.toString();
  }

  String? _extractCompletionCodeFromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    for (final key in const [
      'completion_code',
      'verification_code',
      'proof_code',
      'codigo_validacao',
    ]) {
      final value = (row[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadFixedCompletionArtifacts(
    String serviceId,
  ) async {
    final payload = await _backendApiClient.getJson(
      '/api/v1/bookings/fixed/$serviceId/artifacts',
    );
    final data = payload?['data'];
    if (data is Map<String, dynamic>) return Map<String, dynamic>.from(data);
    if (payload is Map<String, dynamic> && payload['id'] != null) {
      return Map<String, dynamic>.from(payload);
    }
    return <String, dynamic>{'id': serviceId};
  }

  Future<String?> _ensureFixedCompletionCode(String serviceId) async {
    final existing = await _loadFixedCompletionArtifacts(serviceId);
    final existingCode = _extractCompletionCodeFromRow(existing);
    if (existingCode != null && existingCode.isNotEmpty) {
      return existingCode;
    }

    final generated = _generateSixDigitCompletionCode();
    await _backendApiClient.putJson(
      '/api/v1/bookings/fixed/$serviceId/artifacts',
      body: {
        'completion_code': generated,
        'verification_code': generated,
        'proof_code': generated,
        'codigo_validacao': generated,
        'updated_at': DateTime.now().toIso8601String(),
      },
    );

    final refreshed = await _loadFixedCompletionArtifacts(serviceId);
    return _extractCompletionCodeFromRow(refreshed) ?? generated;
  }

  Map<String, dynamic> normalizeFixedServiceForUi(Map<String, dynamic> data) {
    return _normalizeNewService(Map<String, dynamic>.from(data), isFixed: true);
  }

  Future<Map<String, dynamic>> _enrichFixedBooking(
    Map<String, dynamic> data,
  ) async {
    final normalized = Map<String, dynamic>.from(data);

    final scheduledAt =
        normalized['data_agendada'] ?? normalized['scheduled_at'];
    normalized['scheduled_at'] = scheduledAt;
    normalized['price_estimated'] =
        normalized['preco_total'] ?? normalized['price_estimated'];
    normalized['price_upfront'] =
        normalized['valor_entrada'] ?? normalized['price_upfront'];
    normalized['task_id'] = normalized['tarefa_id'] ?? normalized['task_id'];
    normalized['provider_uid'] =
        normalized['prestador_uid'] ?? normalized['provider_uid'];
    normalized['client_uid'] =
        normalized['cliente_uid'] ?? normalized['client_uid'];
    normalized['provider_id'] =
        normalized['prestador_user_id'] ?? normalized['provider_id'];
    normalized['client_id'] =
        normalized['cliente_user_id'] ?? normalized['client_id'];
    normalized['address'] =
        normalized['endereco_completo'] ?? normalized['address'];
    normalized['provider_lat'] = normalized['latitude'];
    normalized['provider_lon'] = normalized['longitude'];
    normalized['status'] = _normalizeFixedStatusForUi(normalized);
    normalized['at_provider'] = true;
    normalized['service_type'] = 'at_provider';
    normalized['location_type'] = 'provider';
    normalized['is_new_flow'] = true;
    normalized['is_fixed'] = true;
    normalized['is_mobile'] = false;

    final taskCatalog = normalized['task_catalog'];
    if (taskCatalog is Map) {
      normalized['task_name'] = taskCatalog['name'] ?? normalized['task_name'];
      normalized['profession_id'] =
          taskCatalog['profession_id'] ?? normalized['profession_id'];
      normalized['description'] =
          normalized['description'] ?? taskCatalog['name'];
    }

    final providerId = normalized['provider_id'] is num
        ? (normalized['provider_id'] as num).toInt()
        : int.tryParse('${normalized['provider_id'] ?? ''}');
    if (providerId == null) {
      normalized['provider_id'] = await _resolveBookingUserId(
        explicitId: null,
        uidValue: normalized['provider_uid'],
      );
    }

    final resolvedProviderId = normalized['provider_id'] is num
        ? (normalized['provider_id'] as num).toInt()
        : int.tryParse('${normalized['provider_id'] ?? ''}');
    if (resolvedProviderId != null) {
      try {
        final providerUser = await _supa
            .from('users')
            .select('id,full_name,avatar_url,phone')
            .eq('id', resolvedProviderId)
            .maybeSingle();
        final provider = await _supa
            .from('providers')
            .select('commercial_name,address,latitude,longitude')
            .eq('user_id', resolvedProviderId)
            .maybeSingle();
        if (provider != null) {
          normalized['provider_name'] =
              provider['commercial_name'] ??
              providerUser?['full_name'] ??
              normalized['provider_name'] ??
              'Prestador';
          normalized['provider_lat'] =
              provider['latitude'] ?? normalized['provider_lat'];
          normalized['provider_lon'] =
              provider['longitude'] ?? normalized['provider_lon'];
          normalized['provider_address'] =
              provider['address'] ??
              normalized['provider_address'] ??
              normalized['address'];
        }
        if (providerUser != null) {
          normalized['provider_avatar'] =
              providerUser['avatar_url'] ?? normalized['provider_avatar'];
          normalized['provider'] = {
            'id': providerUser['id'],
            'name':
                normalized['provider_name'] ??
                providerUser['full_name'] ??
                'Prestador',
            'avatar':
                providerUser['avatar_url'] ?? normalized['provider_avatar'],
            'photo':
                providerUser['avatar_url'] ?? normalized['provider_avatar'],
          };
        }
      } catch (_) {}
    }

    final clientId = normalized['client_id'] is num
        ? (normalized['client_id'] as num).toInt()
        : int.tryParse('${normalized['client_id'] ?? ''}');
    if (clientId == null) {
      normalized['client_id'] = await _resolveBookingUserId(
        explicitId: null,
        uidValue: normalized['client_uid'],
      );
    }

    final resolvedClientId = normalized['client_id'] is num
        ? (normalized['client_id'] as num).toInt()
        : int.tryParse('${normalized['client_id'] ?? ''}');
    if (resolvedClientId != null) {
      try {
        final clientUser = await _supa
            .from('users')
            .select('id,full_name,avatar_url,phone')
            .eq('id', resolvedClientId)
            .maybeSingle();
        if (clientUser != null) {
          normalized['client_name'] =
              clientUser['full_name'] ?? normalized['client_name'] ?? 'Cliente';
          normalized['client_phone'] =
              clientUser['phone'] ?? normalized['client_phone'];
          normalized['client_avatar'] =
              clientUser['avatar_url'] ?? normalized['client_avatar'];
          normalized['client'] = {
            'id': clientUser['id'],
            'name':
                normalized['client_name'] ??
                clientUser['full_name'] ??
                'Cliente',
            'phone': clientUser['phone'] ?? normalized['client_phone'],
            'avatar': clientUser['avatar_url'] ?? normalized['client_avatar'],
            'photo': clientUser['avatar_url'] ?? normalized['client_avatar'],
          };
        }
      } catch (_) {}
    }

    if ((normalized['provider_name'] ?? '').toString().trim().isEmpty) {
      normalized['provider_name'] = 'Prestador';
    }
    if ((normalized['client_name'] ?? '').toString().trim().isEmpty) {
      normalized['client_name'] = 'Cliente';
    }

    return normalized;
  }

  Future<List<dynamic>> getMyServices() async {
    throw UnsupportedError(
      'ApiService.getMyServices desativado. Use DataGateway.loadMyServices().',
    );
  }

  Future<Map<String, dynamic>?> findActiveService() async {
    try {
      final backendActive = await _backendTrackingApi.fetchActiveService();
      final backendService = backendActive?.service;
      if (backendService != null) {
        primeActiveServiceSnapshot(backendService);
        return backendService;
      }
      clearActiveServiceSnapshot();
      return null;
    } catch (e) {
      debugPrint('⚠️ [ApiService] Erro ao buscar serviço ativo (REST): $e');
      return null;
    }
  }

  Map<String, dynamic>? get activeServiceSnapshot =>
      _activeServiceSnapshot == null
      ? null
      : Map<String, dynamic>.from(_activeServiceSnapshot!);

  ServiceStatusView? get activeServiceStatusView {
    final snapshot = activeServiceSnapshot;
    if (snapshot == null) return null;
    return ServiceStatusView.fromMap(
      snapshot,
      serviceScope: getServiceScopeTag(snapshot),
    );
  }

  String? getServiceScopeTag(Map<String, dynamic>? service) {
    if (service == null) return null;
    final kind = classifyServiceFlow(service);
    return kind == ServiceFlowKind.unknown ? null : serviceFlowKindTag(kind);
  }

  bool hasFreshActiveServiceSnapshot({
    Duration ttl = _activeServiceSnapshotTtl,
  }) {
    final at = _activeServiceSnapshotAt;
    if (at == null) return false;
    return DateTime.now().difference(at) <= ttl;
  }

  void primeActiveServiceSnapshot(Map<String, dynamic>? service) {
    _activeServiceSnapshot = service == null
        ? null
        : Map<String, dynamic>.from(service);
    _activeServiceSnapshotAt = DateTime.now();
  }

  void clearActiveServiceSnapshot() {
    _activeServiceSnapshot = null;
    _activeServiceSnapshotAt = DateTime.now();
  }

  Future<Map<String, dynamic>?> getActiveServiceSnapshot({
    bool forceRefresh = false,
    Duration ttl = _activeServiceSnapshotTtl,
  }) async {
    if (!forceRefresh && hasFreshActiveServiceSnapshot(ttl: ttl)) {
      return activeServiceSnapshot;
    }
    return findActiveService();
  }

  Future<ServiceStatusView?> getActiveServiceStatusView({
    bool forceRefresh = false,
    Duration ttl = _activeServiceSnapshotTtl,
  }) async {
    final snapshot = await getActiveServiceSnapshot(
      forceRefresh: forceRefresh,
      ttl: ttl,
    );
    if (snapshot == null) return null;
    return ServiceStatusView.fromMap(
      snapshot,
      serviceScope: getServiceScopeTag(snapshot),
    );
  }

  /// Converte o formato da nova tabela para o formato esperado pela UI legado
  Map<String, dynamic> _normalizeNewService(
    Map<String, dynamic> data, {
    required bool isFixed,
  }) {
    if (isFixed) {
      final scheduledAt = data['data_agendada'] ?? data['scheduled_at'];
      final providerUid = data['prestador_uid'] ?? data['provider_uid'];
      final clientUid = data['cliente_uid'] ?? data['client_uid'];
      final providerId = data['prestador_user_id'] ?? data['provider_id'];
      final clientId = data['cliente_user_id'] ?? data['client_id'];
      final priceEstimated = data['preco_total'] ?? data['price_estimated'];
      final priceUpfront = data['valor_entrada'] ?? data['price_upfront'];
      final address = data['endereco_completo'] ?? data['address'];
      final providerLat = data['latitude'] ?? data['provider_lat'];
      final providerLon = data['longitude'] ?? data['provider_lon'];

      return {
        ...data,
        'id': data['id'],
        'status': _normalizeFixedStatusForUi(data),
        'service_scope': 'fixed',
        'service_kind': 'fixed',
        'at_provider': true,
        'service_type': 'at_provider',
        'location_type': 'provider',
        'provider_uid': providerUid,
        'client_uid': clientUid,
        'provider_id': providerId,
        'client_id': clientId,
        'scheduled_at': scheduledAt,
        'price_estimated': priceEstimated,
        'price_upfront': priceUpfront,
        'task_id': data['tarefa_id'] ?? data['task_id'],
        'address': address,
        'provider_lat': providerLat,
        'provider_lon': providerLon,
        'completion_code':
            data['completion_code'] ??
            data['verification_code'] ??
            data['proof_code'] ??
            data['codigo_validacao'],
        'verification_code':
            data['verification_code'] ??
            data['completion_code'] ??
            data['proof_code'] ??
            data['codigo_validacao'],
        'proof_code':
            data['proof_code'] ??
            data['completion_code'] ??
            data['verification_code'] ??
            data['codigo_validacao'],
        'proof_video': data['proof_video'] ?? data['video'],
        'proof_photo': data['proof_photo'] ?? data['photo'],
        'client_arrived':
            data['arrived_at'] != null ||
            data['client_arrived'] == true ||
            data['client_arrived'] == 'true',
        'client_tracking_active': data['client_tracking_active'] == true,
        'client_tracking_status':
            data['client_tracking_status'] ?? 'tracking_inactive',
        'client_tracking_updated_at': data['client_tracking_updated_at'],
        'is_new_flow': true,
        'is_fixed': true,
        'is_mobile': false,
      };
    } else {
      // Normalização para Móvel (service_requests_new)
      return {
        ..._mapServiceData(data),
        'service_scope': 'mobile',
        'service_kind': 'mobile',
        'is_new_flow': true,
        'is_fixed': false,
        'is_mobile': true,
      };
    }
  }

  Future<List<dynamic>> getAvailableServices() async {
    try {
      dynamic response;
      try {
        final payload = await _backendApiClient.getJson(
          '/api/v1/services/available',
        );
        response = payload?['data'];
      } catch (_) {
        // Fallback para contrato backend-first atual.
        final payload = await _backendApiClient.getJson(
          '/api/v1/dispatch/offers/active',
        );
        response = payload?['data'] ?? payload?['services'];
      }
      if (response is! List) return [];

      return response
          .map(
            (s) => _normalizeNewService(s, isFixed: s['tipo_fluxo'] == 'FIXO'),
          )
          .toList();
    } catch (e) {
      debugPrint(
        '⚠️ [ApiService] Erro no getAvailableServices (Build 101): $e',
      );
      return [];
    }
  }

  Future<Map<String, dynamic>> getServiceDetails(
    String serviceId, {
    ServiceDataScope scope = ServiceDataScope.auto,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${scope.name}::$serviceId';
    if (!forceRefresh) {
      final cached = _serviceDetailsCache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) <=
              _serviceDetailsCacheTtl) {
        return Map<String, dynamic>.from(cached.data);
      }
      final inFlight = _serviceDetailsInFlight[cacheKey];
      if (inFlight != null) {
        return Map<String, dynamic>.from(await inFlight);
      }
    }

    late final Future<Map<String, dynamic>> request;
    request = () async {
      try {
        final backendBaseUrl = _backendApiClient.resolveBaseUrl();
        if (backendBaseUrl == null || backendBaseUrl.trim().isEmpty) {
          throw StateError(
            'BACKEND_API_URL é obrigatório para getServiceDetails. '
            'Fallback direto no Supabase foi desativado.',
          );
        }
        final backendDetails = await _backendTrackingApi.fetchServiceDetails(
          serviceId,
          scope: scope.name,
        );
        if (backendDetails != null) {
          _serviceDetailsCache[cacheKey] = (
            fetchedAt: DateTime.now(),
            data: Map<String, dynamic>.from(backendDetails),
          );
          return backendDetails;
        }

        final notFound = {
          'id': serviceId,
          'status': 'deleted',
          'not_found': true,
        };
        _serviceDetailsCache[cacheKey] = (
          fetchedAt: DateTime.now(),
          data: Map<String, dynamic>.from(notFound),
        );
        return notFound;
      } catch (e) {
        debugPrint(
          '⚠️ [ApiService] Erro no getServiceDetails (scope=$scope): $e',
        );
        rethrow;
      } finally {
        _serviceDetailsInFlight.remove(cacheKey);
      }
    }();

    _serviceDetailsInFlight[cacheKey] = request;
    return Map<String, dynamic>.from(await request);
  }

  Future<int?> _resolveCurrentProviderUserId() async {
    if (_userId != null && _userId! > 0) return _userId;

    final me = await _backendApiClient.getJson('/api/v1/me');
    final row = me?['data'] is List
        ? ((me?['data'] as List).isNotEmpty
              ? (me?['data'] as List).first
              : null)
        : me;
    final providerId = row is Map && row['id'] is num
        ? (row['id'] as num).toInt()
        : int.tryParse('${row is Map ? row['id'] : null}');
    if (providerId != null && providerId > 0) {
      _userId = providerId;
      return providerId;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getActiveProviderOfferState(
    String serviceId,
  ) async {
    final providerUserId = await _resolveCurrentProviderUserId();
    if (providerUserId == null || providerUserId <= 0) return null;

    final response = await _backendApiClient.getJson(
      '/api/v1/dispatch/$serviceId/offer-state',
    );
    final row = response?['data'] is List
        ? ((response?['data'] as List).isNotEmpty
              ? (response?['data'] as List).first
              : null)
        : response?['data'];

    if (row == null) return null;

    return {
      'id': row['id'],
      'provider_user_id': providerUserId,
      'status': (row['status'] ?? '').toString().toLowerCase().trim(),
      'response_deadline_at': row['response_deadline_at'],
      'notification_count': row['notification_count'],
      'attempt_no': row['attempt_no'],
      'max_attempts': row['max_attempts'],
      'queue_order': row['queue_order'],
      'ciclo_atual': row['ciclo_atual'],
      'last_notified_at': row['last_notified_at'],
      'answered_at': row['answered_at'],
      'skip_reason': row['skip_reason'],
    };
  }

  Future<ServiceOfferState?> getActiveProviderOfferStateView(
    String serviceId,
  ) async {
    final row = await getActiveProviderOfferState(serviceId);
    if (row == null) return null;
    return ServiceOfferState.fromMap(serviceId, row);
  }

  Never _throwMobileFlowRpcError(String code, {String? fallbackMessage}) {
    switch (code) {
      case 'already_accepted':
        throw ApiException(
          message: 'Serviço já foi aceito por outro prestador.',
          statusCode: 409,
        );
      case 'offer_not_active':
        throw ApiException(
          message: 'Oferta expirada por tempo.',
          statusCode: 410,
        );
      case 'not_authenticated':
      case 'provider_not_found':
      case 'client_not_found':
      case 'user_not_found':
        throw ApiException(
          message: 'Não autenticado. Faça login novamente.',
          statusCode: 401,
        );
      case 'service_not_found':
        throw ApiException(message: 'Serviço não encontrado.', statusCode: 404);
      case 'deposit_not_paid':
        throw ApiException(
          message: 'A entrada do serviço ainda não foi confirmada.',
          statusCode: 409,
        );
      case 'payment_remaining_not_paid':
        throw ApiException(
          message:
              'O pagamento restante ainda não foi confirmado para este serviço.',
          statusCode: 409,
        );
      case 'service_not_ready':
      case 'completion_code_not_available':
        throw ApiException(
          message: 'O código de conclusão ainda não está disponível.',
          statusCode: 409,
        );
      case 'invalid_completion_code':
        throw ApiException(
          message: 'Código inválido. Confira e tente novamente.',
          statusCode: 422,
        );
      case 'missing_proof_video':
        throw ApiException(
          message: 'Envie o vídeo do serviço antes de finalizar.',
          statusCode: 422,
        );
      case 'invalid_status':
        throw ApiException(
          message:
              fallbackMessage ??
              'Esta ação não está disponível no status atual do serviço.',
          statusCode: 409,
        );
      case 'fixed_service_not_supported':
        throw ApiException(
          message: 'Esta operação é exclusiva do fluxo móvel.',
          statusCode: 400,
        );
      default:
        throw ApiException(
          message: fallbackMessage ?? 'Não foi possível concluir esta ação.',
          statusCode: 400,
        );
    }
  }

  Future<Map<String, dynamic>> acceptService(String serviceId) async {
    try {
      final response = await _backendApiClient.postJson(
        '/api/v1/dispatch/$serviceId/accept',
      );
      final updated = response?['service'] is Map
          ? Map<String, dynamic>.from(response!['service'] as Map)
          : <String, dynamic>{'id': serviceId, 'status': 'accepted'};

      final providerIdRaw = updated['provider_id'];
      final providerId = providerIdRaw is num
          ? providerIdRaw.toInt()
          : int.tryParse('${providerIdRaw ?? ''}');

      final providerUid = _currentAuthUid();
      final providerEmail =
          (_currentUserData?['email']?.toString().toLowerCase().trim() ?? '');
      if (providerEmail == 'demo.provider@play101.app' && providerId != null) {
        try {
          await _backendApiClient.putJson(
            '/api/v1/providers/$providerId/location',
            body: {
              'provider_id': providerId,
              if (providerUid != null && providerUid.trim().isNotEmpty)
                'provider_uid': providerUid,
              'latitude': _mixBacuriLat,
              'longitude': _mixBacuriLon,
              'updated_at': DateTime.now().toIso8601String(),
            },
          );
          await _backendApiClient.putJson(
            '/api/v1/providers/$providerId/profile',
            body: {
              'latitude': _mixBacuriLat,
              'longitude': _mixBacuriLon,
              'address': _mixBacuriAddress,
            },
          );
        } catch (_) {
          // ignore demo error
        }
      }

      debugPrint('✅ [acceptService] updated=$updated');
      return updated;
    } catch (e) {
      debugPrint('❌ [acceptService] error=$e');
      if (e is ApiException || e is sm.SecurityException) rethrow;
      throw ApiException(message: 'Erro ao aceitar: $e', statusCode: 500);
    }
  }

  Future<void> rejectService(String serviceId) async {
    try {
      final providerUid = _currentAuthUid();
      if (providerUid == null || providerUid.trim().isEmpty) {
        throw ApiException(
          message: 'Não autenticado. Faça login novamente.',
          statusCode: 401,
        );
      }

      final res = await _backendApiClient.postJson(
        '/api/v1/dispatch/$serviceId/reject',
      );
      if (res == null) {
        throw ApiException(
          message: 'Oferta não pôde ser recusada a tempo.',
          statusCode: 409,
        );
      }

      // Some PostgREST configs return `null` for void functions; treat non-false as OK.
      debugPrint('✅ [rejectService] rpc result=$res');
    } catch (e) {
      debugPrint('❌ [rejectService] error=$e');
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Erro ao rejeitar: $e', statusCode: 500);
    }
  }

  Future<void> updateServiceStatus(
    String serviceId,
    String status, {
    ServiceDataScope scope = ServiceDataScope.auto,
  }) async {
    if (status == 'in_progress') {
      await startService(serviceId);
      return;
    }
    if (status == 'completed') {
      await completeService(serviceId);
      return;
    }

    try {
      final backendUpdated = await _backendTrackingApi.updateServiceStatus(
        serviceId,
        status: status,
        scope: scope.name,
      );
      if (!backendUpdated) {
        throw ApiException(
          message:
              'Falha ao atualizar status via /api/v1/tracking/services/:id/status',
          statusCode: 502,
        );
      }
    } catch (e) {
      debugPrint('⚠️ [ApiService] Erro ao atualizar status (scope=$scope): $e');
      rethrow;
    }
  }

  Future<void> startService(String serviceId) async {
    try {
      await _backendApiClient.postJson('/api/v1/services/$serviceId/start');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Erro ao iniciar: $e', statusCode: 500);
    }
  }

  Future<bool> verifyServiceCode(String serviceId, String code) async {
    try {
      final fixedRow = await _loadFixedCompletionArtifacts(serviceId);
      final fixedCode = _extractCompletionCodeFromRow(fixedRow);
      if (fixedCode != null && fixedCode.isNotEmpty) {
        return fixedCode == code.trim();
      }

      final service = await _backendTrackingApi.fetchServiceDetails(
        serviceId,
        scope: ServiceDataScope.auto.name,
      );
      if (service == null) return false;

      final storedCode =
          (service['completion_code'] ?? service['verification_code'] ?? '')
              .toString()
              .trim();
      return storedCode.isNotEmpty && storedCode == code.trim();
    } catch (e) {
      debugPrint('Error verifying code: $e');
      return false;
    }
  }

  /// Confirma conclusão de serviço.
  /// Com código de verificação: chama a RPC rpc_confirm_completion que atualiza
  /// o saldo do provider + wallet_transactions.
  /// Sem código: update direto (compatibilidade com client-flow).
  Future<dynamic> confirmServiceCompletion(
    String serviceId, {
    String? code,
    String? proofVideo,
  }) async {
    try {
      final fixedService = await _backendApiClient.getJson(
        '/api/v1/bookings/fixed/$serviceId',
      );

      if (fixedService != null) {
        if (code != null && code.isNotEmpty) {
          final result = await _backendApiClient.postJson(
            '/api/v1/services/$serviceId/confirm-completion',
            body: {
              'code': code,
              if (proofVideo != null) 'proof_video': proofVideo,
            },
          );

          await logServiceEvent(
            serviceId,
            'COMPLETED',
            'Service confirmed completed via RPC (wallet updated)',
          );

          return result;
        }

        await logServiceEvent(
          serviceId,
          'AWAITING_CONFIRMATION',
          'Service aguardando confirmação do cliente (janela de 12h)',
        );
        return null;
      }

      final payload =
          await _backendApiClient.postJson(
            '/api/v1/services/$serviceId/complete',
            body: {
              'code': (code ?? '').trim().isEmpty ? null : code!.trim(),
              if (proofVideo != null && proofVideo.trim().isNotEmpty)
                'proof_video': proofVideo.trim(),
            },
          ) ??
          <String, dynamic>{'ok': false, 'code': 'unknown'};
      if (payload['ok'] != true) {
        final codeValue = (payload['code'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        _throwMobileFlowRpcError(
          codeValue,
          fallbackMessage: 'Não foi possível finalizar este serviço.',
        );
      }

      await logServiceEvent(
        serviceId,
        payload['requires_client_confirmation'] == true
            ? 'AWAITING_CONFIRMATION'
            : 'COMPLETED',
        payload['requires_client_confirmation'] == true
            ? 'Service aguardando confirmação do cliente (janela de 12h)'
            : 'Service completed via mobile canonical flow',
      );

      return payload;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Erro ao concluir: $e', statusCode: 500);
    }
  }

  Future<bool> autoConfirmServiceAfterGraceIfEligible(
    String serviceId, {
    int graceMinutes = 720,
  }) async {
    try {
      final result = await _backendApiClient.postJson(
        '/api/v1/services/$serviceId/auto-confirm-after-grace',
        body: {'grace_minutes': graceMinutes},
      );
      final map = result == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(result);
      final ok = map['ok'] == true;
      if (ok) {
        await logServiceEvent(
          serviceId,
          'AUTO_CONFIRMED_AFTER_GRACE',
          'Auto confirmado após ${graceMinutes}min sem disputa',
        );
      } else if ((map['reason'] ?? '').toString() == 'has_open_dispute') {
        await logServiceEvent(
          serviceId,
          'AUTO_CONFIRM_BLOCKED',
          'Auto confirmação bloqueada por disputa aberta',
        );
      }
      return ok;
    } catch (e) {
      debugPrint('⚠️ [ApiService] autoConfirmServiceAfterGraceIfEligible: $e');
      return false;
    }
  }

  Future<void> confirmFinalService(
    String serviceId, {
    int? rating,
    String? comment,
  }) async {
    try {
      final backendConfirmed = await _backendTrackingApi.confirmFinalService(
        serviceId,
        rating: rating,
        comment: comment,
      );
      if (!backendConfirmed) {
        throw ApiException(
          message:
              'Falha ao confirmar conclusão final via /api/v1/tracking/services/:id/confirm-final',
          statusCode: 502,
        );
      }
      return;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Erro ao finalizar serviço: $e',
        statusCode: 500,
      );
    }
  }

  // --- Novos Métodos para Migração 100% Online ---

  /// Busca configurações globais da tabela app_configs
  Future<Map<String, dynamic>> getAppConfig() async {
    try {
      final res = await _backendApiClient.getJson('/api/v1/app-configs');
      final List<dynamic> data = (res?['data'] as List? ?? const []);

      final Map<String, dynamic> configMap = {};
      for (var item in data) {
        configMap[item['key']] = item['value'];
      }
      return configMap;
    } catch (e) {
      debugPrint('Error fetching app config: $e');
      return {};
    }
  }

  /// Classifica serviço via Edge Function
  Future<Map<String, dynamic>> classifyServiceAi(String text) async {
    // IA desativada no projeto: retorno determinístico.
    return {
      'encontrado': false,
      'ambiguous': true,
      'ambiguity_reason': 'ai_disabled',
      'task_id': null,
      'task_name': null,
      'profissao': null,
      'candidates': <dynamic>[],
      'engine': 'disabled',
      'cache_hit': false,
    };
  }

  /// Calcula tarifa Uber via Edge Function geo
  Future<dynamic> calculateUberFare({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required int vehicleTypeId,
  }) async {
    final response = await invokeEdgeFunction('geo/calculate-fare', {
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
      'vehicle_type_id': vehicleTypeId,
    });

    debugPrint('📊 [EdgeFn] Dados completos da API de tarifa: $response');
    return response['fare'];
  }

  Future<void> completeService(
    String serviceId, {
    String? proofCode,
    String? proofPhoto,
    String? proofVideo,
  }) async {
    final fixedService = await _backendApiClient.getJson(
      '/api/v1/bookings/fixed/$serviceId',
    );

    if (fixedService != null) {
      final nowIso = DateTime.now().toIso8601String();
      final normalizedProofCode = (proofCode ?? '').trim();

      Future<void> safeUpdate(
        String table,
        Map<String, dynamic> payload, {
        String? orFilter,
      }) async {
        final mutable = Map<String, dynamic>.from(payload);
        while (true) {
          try {
            await _backendApiClient.putJson(
              '/api/v1/tables/$table/$serviceId',
              body: {
                ...mutable,
                if (orFilter != null && orFilter.trim().isNotEmpty)
                  '_or_filter': orFilter,
              },
            );
            return;
          } on PostgrestException catch (e) {
            final missingColumnMatch = RegExp(
              r"Could not find the '([^']+)' column",
            ).firstMatch(e.message);
            final missingColumn = missingColumnMatch?.group(1);
            final canRetry =
                e.code == 'PGRST204' &&
                missingColumn != null &&
                mutable.containsKey(missingColumn);
            if (!canRetry) rethrow;
            mutable.remove(missingColumn);
          }
        }
      }

      await safeUpdate('fixed-booking', {
        'status': 'CONCLUIDO',
        'updated_at': nowIso,
        'completed_at': nowIso,
        'finished_at': nowIso,
        if (normalizedProofCode.isNotEmpty)
          'completion_code': normalizedProofCode,
        if (normalizedProofCode.isNotEmpty)
          'verification_code': normalizedProofCode,
        if (normalizedProofCode.isNotEmpty) 'proof_code': normalizedProofCode,
        if (proofPhoto != null) 'proof_photo': proofPhoto,
        if (proofVideo != null) 'proof_video': proofVideo,
      });

      await safeUpdate('appointments', {
        'status': 'completed',
        'updated_at': nowIso,
        'completed_at': nowIso,
      }, orFilter: 'service_request_id.eq.$serviceId');

      await logServiceEvent(
        serviceId,
        'COMPLETED',
        'Serviço fixo concluído manualmente pelo prestador.',
      );
      return;
    }

    await confirmServiceCompletion(
      serviceId,
      code: proofCode,
      proofVideo: proofVideo,
    );
  }

  Future<void> requestServiceCompletion(String serviceId) async {
    try {
      final fixedService = await _backendApiClient.getJson(
        '/api/v1/bookings/fixed/$serviceId',
      );
      if (fixedService != null) {
        await _ensureFixedCompletionCode(serviceId);
        await logServiceEvent(
          serviceId,
          'COMPLETION_CODE_REQUESTED',
          'Código de conclusão disponibilizado para serviço fixo.',
        );
        return;
      }

      final payload =
          await _backendApiClient.postJson(
            '/api/v1/services/$serviceId/ensure-completion-code',
          ) ??
          <String, dynamic>{'ok': false, 'code': 'unknown'};
      if (payload['ok'] != true) {
        final code = (payload['code'] ?? '').toString().trim().toLowerCase();
        _throwMobileFlowRpcError(
          code,
          fallbackMessage:
              'Não foi possível disponibilizar o código de conclusão.',
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Erro ao solicitar a conclusão: $e',
        statusCode: 500,
      );
    }
  }

  Future<void> submitReview({
    required String serviceId,
    required int rating,
    String? comment,
  }) async {
    if (_userId == null) throw Exception('Não autenticado');

    try {
      final service = await _backendTrackingApi.fetchServiceDetails(
        serviceId,
        scope: ServiceDataScope.auto.name,
      );
      if (service == null) {
        throw Exception('Serviço não encontrado para avaliação');
      }
      final providerId = service['provider_id'];
      final clientId = service['client_id'];

      // Determinar quem está avaliando quem (Assume-se que cliente avalia prestador se _role == 'client')
      final revieweeId = (_role == 'client') ? providerId : clientId;

      if (revieweeId == null) {
        throw Exception('Não foi possível identificar o avaliado');
      }

      // 2. Inserir a avaliação
      await _backendApiClient.postJson(
        '/api/v1/reviews',
        body: {
          'service_id': serviceId,
          'reviewer_id': _userId,
          'reviewee_id': revieweeId,
          'rating': rating,
          'comment': comment,
        },
      );

      debugPrint('✅ [ApiService] Avaliação enviada com sucesso!');
    } catch (e) {
      debugPrint('❌ [ApiService] Erro ao enviar avaliação: $e');
      rethrow;
    }
  }

  Future<void> arriveService(
    String serviceId, {
    ServiceDataScope scope = ServiceDataScope.auto,
  }) async {
    try {
      if (scope == ServiceDataScope.fixedOnly ||
          scope == ServiceDataScope.auto) {
        final fixedService = await _backendApiClient.getJson(
          '/api/v1/bookings/fixed/$serviceId',
        );
        if (fixedService != null) {
          throw ApiException(
            message:
                'A ação "cheguei" do prestador não se aplica ao fluxo fixo. Nesse fluxo, a chegada é confirmada pelo cliente.',
            statusCode: 400,
          );
        }
        if (scope == ServiceDataScope.fixedOnly) {
          throw ApiException(
            message: 'Agendamento fixo não encontrado para este serviço.',
            statusCode: 404,
          );
        }
      }

      if (scope == ServiceDataScope.tripOnly) {
        throw ApiException(
          message:
              'Ação de chegada não suportada para corridas por este método.',
          statusCode: 400,
        );
      }

      final payload =
          await _backendApiClient.postJson(
            '/api/v1/services/$serviceId/arrive',
          ) ??
          <String, dynamic>{'ok': false, 'code': 'unknown'};
      if (payload['ok'] != true) {
        final code = (payload['code'] ?? '').toString().trim().toLowerCase();
        _throwMobileFlowRpcError(
          code,
          fallbackMessage: 'Não foi possível registrar a chegada.',
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Erro ao registrar chegada: $e',
        statusCode: 500,
      );
    }
  }

  Future<void> contestService(String serviceId, String reason) async {
    await _backendApiClient.postJson(
      '/api/v1/services/$serviceId/contest',
      body: {'reason': reason},
    );
  }

  Future<void> submitServiceComplaint({
    required String serviceId,
    required String claimType,
    required String reason,
    List<Map<String, String>> attachments = const [],
  }) async {
    final backendSubmitted = await _backendTrackingApi.submitComplaint(
      serviceId,
      claimType: claimType,
      reason: reason,
      attachments: attachments,
    );
    if (backendSubmitted) {
      return;
    }

    int? localUserId = _userId;
    if (localUserId == null) {
      final me = await _backendApiClient.getJson('/api/v1/me');
      final row = me?['data'] is List
          ? ((me?['data'] as List).isNotEmpty
                ? (me?['data'] as List).first
                : null)
          : me;
      if (row is Map) {
        localUserId =
            (row['id'] as num?)?.toInt() ?? int.tryParse('${row['id']}');
        _userId = localUserId;
      }
    }

    if (localUserId == null) {
      throw ApiException(
        message: 'Usuário não autenticado para abrir reclamação.',
        statusCode: 401,
      );
    }

    final normalizedClaimType = claimType.trim().toLowerCase().isEmpty
        ? 'complaint'
        : claimType.trim().toLowerCase();
    final normalizedReason =
        '[claim_type:$normalizedClaimType] ${reason.trim()}'.trim();

    await _backendApiClient.postJson(
      '/api/v1/service-disputes',
      body: {
        'service_id': serviceId,
        'user_id': localUserId,
        'type': normalizedClaimType,
        'reason': normalizedReason,
        'status': 'open',
        'created_at': DateTime.now().toIso8601String(),
      },
    );

    for (final attachment in attachments) {
      final url = (attachment['url'] ?? '').trim();
      if (url.isEmpty) continue;
      final type = (attachment['type'] ?? 'photo').trim().toLowerCase();
      await _backendApiClient.postJson(
        '/api/v1/service-disputes',
        body: {
          'service_id': serviceId,
          'user_id': localUserId,
          'type': type,
          'evidence_url': url,
          'reason': normalizedReason,
          'status': 'open',
          'created_at': DateTime.now().toIso8601String(),
        },
      );
    }

    await _backendApiClient.postJson(
      '/api/v1/services/$serviceId/contest',
      body: {'reason': normalizedReason, 'claim_type': normalizedClaimType},
    );

    await logServiceEvent(
      serviceId,
      'DISPUTE_OPENED',
      'Disputa aberta pelo cliente. claim_type=$normalizedClaimType',
    );
  }

  Future<Map<String, dynamic>?> getOpenDisputeForService(
    String serviceId,
  ) async {
    final response = await _backendApiClient.getJson(
      '/api/v1/service-disputes?service_id_eq=$serviceId&type_eq=complaint&status_eq=open&limit=1&order=created_at.desc',
    );
    final row =
        response?['data'] is List && (response?['data'] as List).isNotEmpty
        ? (response?['data'] as List).first
        : null;
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>?> getLatestPrimaryDisputeForService(
    String serviceId,
  ) async {
    final response = await _backendApiClient.getJson(
      '/api/v1/service-disputes?service_id_eq=$serviceId&type_eq=complaint&limit=1&order=created_at.desc',
    );
    final row =
        response?['data'] is List && (response?['data'] as List).isNotEmpty
        ? (response?['data'] as List).first
        : null;
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<void> acceptPlatformDisputeDecision(String serviceId) async {
    final dispute = await getLatestPrimaryDisputeForService(serviceId);
    if (dispute == null) {
      throw ApiException(
        message: 'Nenhuma contestação principal encontrada para este serviço.',
        statusCode: 404,
      );
    }

    final disputeId = dispute['id'];
    final disputeStatus = (dispute['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final decision = (dispute['platform_decision'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    await _backendApiClient.putJson(
      '/api/v1/service-disputes/$disputeId',
      body: {'client_acknowledged_at': DateTime.now().toIso8601String()},
    );
    final service = await _backendApiClient.getJson(
      '/api/v1/services/$serviceId',
    );

    final serviceStatus = (service?['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    if (decision == 'rejected' &&
        disputeStatus == 'dismissed' &&
        serviceStatus == 'contested') {
      await _backendApiClient.putJson(
        '/api/v1/services/$serviceId',
        body: {
          'status': 'completed',
          'status_updated_at': DateTime.now().toIso8601String(),
          'completed_at':
              service?['completed_at'] ?? DateTime.now().toIso8601String(),
          'finished_at':
              service?['finished_at'] ?? DateTime.now().toIso8601String(),
        },
      );
    }
  }

  Future<Map<String, dynamic>?> getBlockingDisputeForCurrentClient() async {
    int? localUserId = _userId;
    if (localUserId == null) {
      final me = await _backendApiClient.getJson('/api/v1/me');
      final row = me?['data'] is List
          ? ((me?['data'] as List).isNotEmpty
                ? (me?['data'] as List).first
                : null)
          : me;
      if (row is Map) {
        localUserId =
            (row['id'] as num?)?.toInt() ?? int.tryParse('${row['id']}');
        _userId = localUserId;
      }
    }

    if (localUserId == null) return null;

    final response = await _backendApiClient.getJson(
      '/api/v1/service-disputes?user_id_eq=$localUserId&type_eq=complaint&status_eq=open&limit=1&order=created_at.desc',
    );
    final row =
        response?['data'] is List && (response?['data'] as List).isNotEmpty
        ? (response?['data'] as List).first
        : null;

    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<void> cancelService(
    String serviceId, {
    ServiceDataScope scope = ServiceDataScope.auto,
  }) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) {
      throw ApiException(
        message: 'Serviço inválido para cancelamento.',
        statusCode: 400,
      );
    }
    final backendCancelled = await _backendTrackingApi.cancelService(
      normalizedServiceId,
      scope: scope.name,
    );
    if (!backendCancelled) {
      throw ApiException(
        message:
            'Falha ao cancelar serviço via /api/v1/tracking/services/:id/cancel',
        statusCode: 502,
      );
    }

    // Confirmação defensiva: evita "falso sucesso" seguido de reabertura da tela.
    try {
      final resolvedScope = scope == ServiceDataScope.auto
          ? 'auto'
          : scope.name;
      final updatedService = await _backendTrackingApi.fetchServiceDetails(
        normalizedServiceId,
        scope: resolvedScope,
      );
      final normalizedStatus = (updatedService?['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final isCancelled =
          normalizedStatus == 'cancelled' || normalizedStatus == 'canceled';
      if (!isCancelled) {
        throw ApiException(
          message:
              'Cancelamento ainda não confirmado pelo servidor. Tente novamente em instantes.',
          statusCode: 409,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Falha ao confirmar cancelamento no servidor.',
        statusCode: 502,
      );
    }
  }

  Future<void> requestServiceEdit({
    required String serviceId,
    required String newDescription,
    required double newPrice,
  }) async {
    // This could also be a direct update if allowed by RLS,
    // but usually needs review. We'll use a transaction/RPC or just update status to 'edit_requested'
    await _backendApiClient.putJson(
      '/api/v1/services/$serviceId',
      body: {
        'description': newDescription,
        'price_estimated': newPrice,
        'status': 'edit_requested',
        'status_updated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> fetchFuelPricesByState(String state) async {
    return _getCachedFuel('state_$state', () async {
      try {
        return await get('/geo/fuel?state=$state');
      } catch (_) {
        return {};
      }
    });
  }

  Future<Map<String, dynamic>> fetchFuelPriceByCityState(
    String city,
    String state,
  ) async {
    return _getCachedFuel('city_${city}_$state', () async {
      try {
        return await get('/geo/fuel?city=$city&state=$state');
      } catch (_) {
        return {};
      }
    });
  }

  Future<Map<String, dynamic>> reverseCityStateFromCoords(
    double lat,
    double lon,
  ) async {
    try {
      return await get('/geo/reverse?lat=$lat&lon=$lon');
    } catch (_) {
      return {'city': 'Unknown', 'state': 'XX'};
    }
  }

  Future<String> reverseStateFromCoords(double lat, double lon) async {
    final res = await reverseCityStateFromCoords(lat, lon);
    return (res['state'] ?? '').toString();
  }

  Future<Map<String, dynamic>> getRouteMetrics({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    try {
      return await post('/geo/route', {
        'from': {'lat': fromLat, 'lon': fromLon},
        'to': {'lat': toLat, 'lon': toLon},
      });
    } catch (_) {
      return {'distance_km': 0.0, 'duration_min': 0.0};
    }
  }

  // ========== MEDIA ==========

  Future<String> uploadServiceImage(
    List<int> bytes, {
    String filename = 'image.jpg',
    String mimeType = 'image/jpeg',
  }) async {
    return _mediaStorage.uploadServiceImage(
      bytes,
      filename: filename,
      mimeType: mimeType,
    );
  }

  Future<String> uploadServiceVideo(
    List<int> bytes, {
    String filename = 'video.mp4',
    String? mimeType,
    void Function(double)? onProgress,
  }) async {
    return _mediaStorage.uploadServiceVideo(
      bytes,
      filename: filename,
      mimeType: mimeType,
    );
  }

  Future<String> uploadServiceAudio(
    List<int> bytes, {
    String filename = 'audio.m4a',
  }) async {
    return _mediaStorage.uploadServiceAudio(bytes, filename: filename);
  }

  Future<String> uploadChatImage(
    String serviceId,
    List<int> bytes, {
    String filename = 'chat.jpg',
  }) async {
    return _mediaStorage.uploadChatImage(serviceId, bytes, filename: filename);
  }

  Future<String> uploadChatAudio(
    String serviceId,
    List<int> bytes, {
    String filename = 'audio.m4a',
    String mimeType = 'audio/mp4',
  }) async {
    return _mediaStorage.uploadChatAudio(
      serviceId,
      bytes,
      filename: filename,
      mimeType: mimeType,
    );
  }

  Future<String> uploadChatVideo(
    String serviceId,
    List<int> bytes, {
    String filename = 'video.mp4',
    String? mimeType,
  }) async {
    return _mediaStorage.uploadChatVideo(
      serviceId,
      bytes,
      filename: filename,
      mimeType: mimeType,
    );
  }

  Future<String> uploadMediaFromPath(
    String path, {
    required String filename,
    String? serviceId,
    String type = 'image',
    String? mimeType,
    void Function(double)? onProgress,
  }) async {
    return _mediaStorage.uploadMediaFromPath(
      path,
      filename: filename,
      serviceId: serviceId,
      type: type,
      mimeType: mimeType,
    );
  }

  Future<String> uploadServiceVideoFromPath(
    String path, {
    String filename = 'video.mp4',
    String? mimeType,
    void Function(double)? onProgress,
  }) async {
    return uploadMediaFromPath(
      path,
      filename: filename,
      type: 'service',
      mimeType: mimeType,
      onProgress: onProgress,
    );
  }

  Future<String> uploadToCloud(
    List<int> bytes, {
    required String filename,
    String? serviceId,
    String type = 'image',
  }) async {
    return _mediaStorage.uploadToCloud(
      bytes,
      filename: filename,
      serviceId: serviceId,
      type: type,
    );
  }

  Future<String> getMediaViewUrl(String key) async {
    return _mediaStorage.getMediaViewUrl(key);
  }

  String getMediaUrl(String key) {
    return _mediaStorage.getMediaUrl(key);
  }

  Future<Uint8List> getMediaBytes(String key) {
    return _mediaStorage.getMediaBytes(key);
  }

  void invalidateMediaBytesCache([String? key]) {
    _mediaStorage.invalidateMediaBytesCache(key);
  }

  Future<void> payRemainingService(String serviceId) async {
    throw sm.SecurityException(
      'Confirmação de pagamento síncrona proibida. Aguarde Webhooks seguros.',
    );
  }

  // --- Scheduling Flow ---

  Future<List<dynamic>> getAvailableForSchedule() async {
    try {
      List<dynamic> mapped = const [];
      dynamic backendPayload;
      try {
        backendPayload = await _backendApiClient.getJson(
          '/api/v1/providers/schedule/available',
        );
      } catch (_) {
        final uid = '${_userId ?? ''}'.trim();
        if (uid.isEmpty) {
          return [];
        }
        backendPayload = await _backendApiClient.getJson(
          '/api/v1/providers/$uid/availability',
        );
      }
      final dynamic dataPayload = backendPayload is Map<String, dynamic>
          ? backendPayload['data']
          : null;
      final backendServices = backendPayload is List
          ? backendPayload
          : dataPayload is List
          ? dataPayload
          : dataPayload is Map
          ? (dataPayload['services'] as List?)
          : (backendPayload?['services'] as List?);
      if (backendServices != null && backendServices.isNotEmpty) {
        mapped = backendServices
            .whereType<Map>()
            .map((s) => _mapServiceData(Map<String, dynamic>.from(s)))
            .toList();
      } else {
        mapped = const [];
      }
      final withoutRejected = await _filterRejectedDispatchOffers(mapped);
      return await _filterActiveDispatchOffers(withoutRejected);
    } catch (e) {
      debugPrint('Erro no getAvailableForSchedule: $e');
      return [];
    }
  }

  Future<List<dynamic>> _filterRejectedDispatchOffers(
    List<dynamic> services,
  ) async {
    if (services.isEmpty || _userId == null) return services;

    final serviceIds = services
        .map((service) => service['id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (serviceIds.isEmpty) return services;

    try {
      final rejectedRes = await _backendApiClient.getJson(
        '/api/v1/dispatch/offers/rejected?provider_user_id_eq=${_userId!}&service_id_in=${serviceIds.join(",")}',
      );
      final rejectedRows = (rejectedRes?['data'] as List? ?? const []);

      final rejectedIds = rejectedRows
          .map((row) => (row as Map)['service_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      if (rejectedIds.isEmpty) return services;

      final filtered = services.where((service) {
        final id = service['id']?.toString().trim() ?? '';
        return id.isNotEmpty && !rejectedIds.contains(id);
      }).toList();

      debugPrint(
        '🚫 [ApiService] Serviços removidos da vitrine por recusa explícita do prestador: ${rejectedIds.length}',
      );
      return filtered;
    } catch (e) {
      debugPrint(
        '⚠️ [ApiService] Falha ao filtrar serviços rejeitados do dispatch: $e',
      );
      return services;
    }
  }

  Future<List<dynamic>> _filterActiveDispatchOffers(
    List<dynamic> services,
  ) async {
    if (services.isEmpty) return services;

    final serviceIds = services
        .map((service) => service['id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (serviceIds.isEmpty) return services;

    try {
      final queueRes = await _backendApiClient.getJson(
        '/api/v1/dispatch/queue/active?service_id_in=${serviceIds.join(",")}',
      );
      final queueRows = (queueRes?['data'] as List? ?? const []);

      final activeQueueIds = queueRows
          .map((row) => (row as Map)['service_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final offersRes = await _backendApiClient.getJson(
        '/api/v1/dispatch/offers/active?service_id_in=${serviceIds.join(",")}',
      );
      final offerRows = (offersRes?['data'] as List? ?? const []);

      final activeOfferIds = offerRows
          .map((row) => (row as Map)['service_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final blockedIds = {...activeQueueIds, ...activeOfferIds};
      if (blockedIds.isEmpty) return services;

      final filtered = services.where((service) {
        final id = service['id']?.toString().trim() ?? '';
        return id.isNotEmpty && !blockedIds.contains(id);
      }).toList();

      debugPrint(
        '🔒 [ApiService] Serviços ocultados da vitrine por ciclo ativo de notificação: ${blockedIds.length}',
      );
      return filtered;
    } catch (e) {
      debugPrint(
        '⚠️ [ApiService] Falha ao filtrar serviços em ciclo ativo de notificação: $e',
      );
      return services;
    }
  }

  Future<void> proposeSchedule(
    String serviceId,
    DateTime scheduledAt, {
    ServiceDataScope scope = ServiceDataScope.auto,
  }) async {
    final backendProposed = await _backendTrackingApi.proposeSchedule(
      serviceId,
      scheduledAt: scheduledAt,
    );
    if (!backendProposed) {
      throw ApiException(
        message:
            'Falha ao propor remarcação via /api/v1/tracking/services/:id/propose-schedule',
        statusCode: 502,
      );
    }
  }

  // confirmSchedule already defined above

  // --- Test & Dev Helpers ---

  Future<void> testApprovePayment(String serviceId) async {
    await _backendApiClient.postJson(
      '/api/v1/services/$serviceId/test-approve-payment',
      body: {
        'status': 'accepted',
        'payment_remaining_status': 'paid_manual',
        'status_updated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  // --- Location Search (Mapbox) ---

  Future<List<dynamic>> searchLocation(
    String query, {
    double? lat,
    double? lon,
  }) async {
    try {
      String url = '/geo/search?q=${Uri.encodeComponent(query)}';

      // Adicionar raio de busca do app_configs
      final radius = RemoteConfigService.searchRadiusKm;
      url += '&radius=$radius';

      if (lat != null && lon != null) {
        url += '&proximity=$lat,$lon';
      }
      final dynamic res = await get(url);
      if (res is List) return res;
      if (res is Map && res['raw'] is List) return res['raw'];
      return [];
    } catch (e) {
      debugPrint('SearchLocation error: $e');
      return [];
    }
  }

  Future<List<String>> fetchServiceAutocompleteHints(
    String query, {
    int limit = 8,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];
    try {
      final response = await _backendApiClient.getJson(
        '/api/v1/tasks/autocomplete?q=${Uri.encodeQueryComponent(trimmed)}&limit=$limit',
      );
      final results = response?['results'] ?? response?['data'];
      if (results is! List) return [];
      final names = <String>{};
      for (final row in results) {
        if (row is! Map) continue;
        final name =
            (row['task_name'] ??
                    row['taskName'] ??
                    row['nome'] ??
                    row['name'] ??
                    row['title'] ??
                    row['titulo'] ??
                    '')
                .toString()
                .trim();
        if (name.isNotEmpty) names.add(name);
      }
      if (names.isNotEmpty) return names.take(limit).toList();
      final catalog = await fetchActiveTaskCatalog();
      return TaskAutocomplete.suggestTasks(trimmed, catalog, limit: limit)
          .map((t) => (t['task_name'] ?? t['name'] ?? '').toString().trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .take(limit)
          .toList();
    } catch (e) {
      debugPrint('⚠️ [ApiService] fetchServiceAutocompleteHints: $e');
      try {
        final catalog = await fetchActiveTaskCatalog();
        return TaskAutocomplete.suggestTasks(trimmed, catalog, limit: limit)
            .map((t) => (t['task_name'] ?? t['name'] ?? '').toString().trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .take(limit)
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  // --- Notifications ---

  Future<void> markNotificationRead(int id) async {
    return _userPreferences.markNotificationRead(id);
  }

  Future<void> markAllNotificationsRead() async {
    return _userPreferences.markAllNotificationsRead(_userId);
  }

  // Locais Salvos
  Future<List<Map<String, dynamic>>> getSavedPlaces() async {
    return _userPreferences.getSavedPlaces(_userId);
  }

  Future<void> saveSavedPlace(Map<String, dynamic> place) async {
    return _userPreferences.saveSavedPlace(_userId, place);
  }

  // -------- Compatibilidade (assinaturas esperadas pelo app) --------
  Future<void> syncUserProfile(
    String token, {
    String? role,
    String? phone,
    String? name,
  }) async {
    // token param kept for signature compat; loginWithFirebase reads session internally
    await loginWithFirebase('', role: role, phone: phone, name: name);
  }

  Future<bool?> inferFixedFromProfessions(String userId) async {
    final parsed = int.tryParse(userId);
    if (parsed == null) return null;
    try {
      final linksRes = await _backendApiClient.getJson(
        '/api/v1/provider-professions?provider_user_id_eq=$parsed',
      );
      final rows = (linksRes?['data'] as List? ?? const []);
      final ids = rows
          .map((e) => int.tryParse((e['profession_id'] ?? '').toString()))
          .whereType<int>()
          .toList();
      if (ids.isEmpty) return null;
      final profsRes = await _backendApiClient.getJson(
        '/api/v1/professions?id_in=${ids.join(',')}',
      );
      final profs = (profsRes?['data'] as List? ?? const []);
      final names = profs
          .map((e) => (e['name'] ?? '').toString().toLowerCase())
          .toList();
      final fixedHints = ['barbeiro', 'salão', 'clinica', 'consultório'];
      return names.any((n) => fixedHints.any((h) => n.contains(h)));
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getTripDetail(String tripId) async {
    throw ApiException(
      message: 'Fluxo legado de corridas desativado neste build.',
      statusCode: 410,
      details: const {'reason_code': 'TRIP_RUNTIME_DISABLED'},
    );
  }

  Future<bool> hasSavedCard() async {
    if (_userId == null) return false;
    final response = await _backendApiClient.getJson(
      '/api/v1/payment-methods?user_id_eq=${_userId!}&limit=1',
    );
    final data = response?['data'];
    return data is List && data.isNotEmpty;
  }

  Future<Map<String, dynamic>> getWalletData() async {
    throw UnsupportedError(
      'ApiService.getWalletData desativado. Use BackendPaymentApi.fetchWallet.',
    );
  }

  Future<List<Map<String, dynamic>>> getWalletTransactions() async {
    final edge = await invokeEdgeFunction('mp-driver-statement', {
      'limit': 100,
      'offset': 0,
    });
    final tx = (edge?['transactions'] as List?) ?? const [];
    return tx.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getTripEarnings() async {
    return [];
  }

  Future<Map<String, dynamic>> requestPayout(double amount) async {
    final edge = await invokeEdgeFunction('mp-request-payout', {
      'amount': amount,
    });
    return Map<String, dynamic>.from(edge as Map? ?? const {});
  }

  Future<Map<String, dynamic>> changePasswordWithBiometrics({
    String? currentPassword,
    required String newPassword,
    String? selfiePath,
  }) async {
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
    return {'success': true};
  }

  Future<Map<String, dynamic>> lookupPlate(String plate) async {
    final edge = await invokeEdgeFunction('lookup-plate', {'plate': plate});
    return Map<String, dynamic>.from(edge as Map? ?? const {});
  }

  Future<String> uploadAvatarImage(
    List<int> bytes, {
    String? filename,
    String? mimeType,
  }) async {
    if (_userId == null) throw Exception('Não autenticado');

    final resolvedMime = (mimeType != null && mimeType.trim().isNotEmpty)
        ? mimeType.trim()
        : 'image/jpeg';
    final ext = (filename != null && filename.contains('.'))
        ? filename.split('.').last.toLowerCase()
        : (resolvedMime == 'image/png' ? 'png' : 'jpg');
    final path =
        'avatars/${_userId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    debugPrint(
      '🖼️ [AvatarUpload] Iniciando upload | userId=$_userId | bytes=${bytes.length} | mime=$resolvedMime | path=$path',
    );

    final upload = await _backendApiClient.postJson(
      '/api/v1/media/upload',
      body: {
        'path': path,
        'content_type': resolvedMime,
        'base64': base64Encode(bytes),
        'visibility': 'public',
        'category': 'avatar',
      },
    );
    final publicUrl =
        upload?['url']?.toString() ??
        upload?['public_url']?.toString() ??
        upload?['data']?['url']?.toString() ??
        upload?['data']?['public_url']?.toString();
    if (publicUrl == null || publicUrl.trim().isEmpty) {
      throw Exception('Falha ao fazer upload de avatar via backend media API.');
    }

    debugPrint('🔗 [AvatarUpload] URL pública gerada | url=$publicUrl');
    await _logAvatarUrlProbe(publicUrl);

    try {
      await _backendApiClient.putJson(
        '/api/v1/users/${_userId!}',
        body: {'avatar_url': publicUrl},
      );
      final updatedUserRow = await _selectUserRowMaybeSingleBy('id', _userId);

      if (updatedUserRow == null) {
        debugPrint(
          '⚠️ [AvatarUpload] Upload feito, mas não consegui reler a linha do usuário após salvar avatar_url. Verifique RLS/filtro do update.',
        );
        throw Exception(
          'Upload do avatar concluído, mas avatar_url não pôde ser relido em users.',
        );
      } else {
        debugPrint(
          '💾 [AvatarUpload] avatar_url persistido no users | row=${jsonEncode(updatedUserRow)}',
        );
      }

      if (_currentUserData != null) {
        _currentUserData = {
          ..._currentUserData!,
          'avatar_url': publicUrl,
          if (_currentUserData!.containsKey('photo')) 'photo': publicUrl,
        };
      }

      try {
        final reloadedProfile = await getMyProfile();
        final persistedAvatar = reloadedProfile['avatar_url']?.toString();
        debugPrint(
          '🔄 [AvatarUpload] Perfil recarregado após salvar | avatar_url=$persistedAvatar',
        );
        if (persistedAvatar == null || persistedAvatar.isEmpty) {
          debugPrint(
            '⚠️ [AvatarUpload] O perfil recarregado veio sem avatar_url, apesar do upload ter concluído.',
          );
          throw Exception(
            'Upload do avatar concluído, mas o perfil recarregado voltou sem avatar_url.',
          );
        } else if (persistedAvatar != publicUrl) {
          debugPrint(
            '⚠️ [AvatarUpload] avatar_url salvo difere da URL recém-gerada | esperado=$publicUrl | atual=$persistedAvatar',
          );
          throw Exception(
            'Upload do avatar concluído, mas o avatar_url persistido diverge da URL gerada.',
          );
        }
      } catch (reloadError) {
        debugPrint(
          '⚠️ [AvatarUpload] Falha ao reler o perfil após salvar avatar_url: $reloadError',
        );
        rethrow;
      }
    } catch (e) {
      debugPrint('⚠️ [ApiService] Falha ao persistir avatar_url no perfil: $e');
      rethrow;
    }

    return publicUrl;
  }

  Future<void> _logAvatarUrlProbe(String publicUrl) async {
    try {
      final uri = Uri.parse(publicUrl);
      final response = await http.get(
        uri,
        headers: const {'Range': 'bytes=0-0'},
      );
      final contentType = response.headers['content-type'] ?? 'desconhecido';
      final contentLength =
          response.headers['content-length'] ?? 'desconhecido';
      debugPrint(
        '🌍 [AvatarUpload] Teste da URL pública | status=${response.statusCode} | content-type=$contentType | content-length=$contentLength | url=$publicUrl',
      );
      if (response.statusCode >= 400) {
        debugPrint(
          '⚠️ [AvatarUpload] A URL foi gerada, mas a leitura HTTP falhou. Isso aponta para bucket/política/URL pública.',
        );
      }
    } catch (e) {
      debugPrint(
        '⚠️ [AvatarUpload] Erro ao testar acessibilidade da URL pública: $e | url=$publicUrl',
      );
    }
  }

  Future<String> uploadVerificationImage(
    List<int> bytes, {
    String? filename,
  }) async {
    final ext = (filename ?? 'image.jpg').split('.').last;
    final path =
        'id-verification/anonymous/${DateTime.now().millisecondsSinceEpoch}_$ext';
    final upload = await _backendApiClient.postJson(
      '/api/v1/media/upload',
      body: {
        'path': path,
        'content_type': 'image/$ext',
        'base64': base64Encode(bytes),
        'visibility': 'private',
        'category': 'verification',
      },
    );
    final mediaPath =
        upload?['path']?.toString() ?? upload?['data']?['path']?.toString();
    return mediaPath?.isNotEmpty == true ? mediaPath! : path;
  }

  Future<String> uploadIdDocument(List<int> bytes, String filename) async {
    return uploadVerificationImage(bytes, filename: filename);
  }

  Future<void> saveDriverDocumentPaths({
    String? cnhPath,
    String? documentPath,
    required String selfiePath,
  }) async {
    if (_userId == null) throw Exception('Não autenticado');
    await _backendApiClient.putJson(
      '/api/v1/users/${_userId!}',
      body: {
        'document_path': cnhPath ?? documentPath,
        'selfie_path': selfiePath,
      },
    );
  }

  Future<Map<String, dynamic>> verifyFace({
    required String selfiePath,
    String? cnhPath,
  }) async {
    final edge = await invokeEdgeFunction('verify-face', {
      'selfiePath': selfiePath,
      'cnhPath': ?cnhPath,
    });
    return Map<String, dynamic>.from(edge as Map? ?? const {});
  }

  Future<Map<String, dynamic>> verifyCardFace({
    required String selfiePath,
  }) async {
    final edge = await invokeEdgeFunction('verify-card-face', {
      'selfiePath': selfiePath,
    });
    return Map<String, dynamic>.from(edge as Map? ?? const {});
  }

  Future<Map<String, dynamic>> provisionMercadoPagoAccount(
    dynamic userId,
  ) async {
    final parsed = int.tryParse(userId.toString());
    final edge = await invokeEdgeFunction('mp-customer-manager', {
      'driver_id': parsed,
    });
    return Map<String, dynamic>.from(edge as Map? ?? const {});
  }

  Future<void> disconnectDriverMercadoPago() async {
    final uid = _userId;
    if (uid == null) {
      debugPrint('⚠️ [ApiService] User ID nulo ao tentar desconectar MP');
      return;
    }

    debugPrint(
      '🔄 [ApiService] Desconectando Mercado Pago para motorista: $uid',
    );

    try {
      await invokeEdgeFunction('mp-disconnect-account', {'role': 'driver'});
    } catch (e) {
      // Fallback: remove localmente mesmo se a revogação falhar.
      await Supabase.instance.client
          .from('driver_mercadopago_accounts')
          .delete()
          .eq('user_id', uid);
    }

    debugPrint('✅ [ApiService] Mercado Pago (Driver) desconectado');
  }

  Future<void> disconnectPassengerMercadoPago() async {
    final uid = _userId;
    if (uid == null) {
      debugPrint(
        '⚠️ [ApiService] User ID nulo ao tentar desconectar MP (Passenger)',
      );
      return;
    }

    debugPrint(
      '🔄 [ApiService] Desconectando Mercado Pago para passageiro: $uid',
    );

    try {
      await invokeEdgeFunction('mp-disconnect-account', {'role': 'passenger'});
    } catch (e) {
      // Fallback: remove localmente mesmo se a revogação falhar.
      await _backendApiClient.deleteJson(
        '/api/v1/passenger-mercadopago-accounts/$uid',
      );
    }

    debugPrint('✅ [ApiService] Mercado Pago (Passenger) desconectado');
  }

  /// Chama uma Edge Function do Supabase
  Future<Map<String, dynamic>> callEdgeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await invokeEdgeFunction(functionName, body);
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'data': response};
    } catch (e) {
      debugPrint(
        '⚠️ [ApiService] Erro ao chamar Edge Function $functionName: $e',
      );
      rethrow;
    }
  }
}

class _FuelCacheItem {
  final Map<String, dynamic> data;
  final DateTime expiry;
  _FuelCacheItem({required this.data, required this.expiry});
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final Map<String, dynamic>? details;
  ApiException({required this.message, required this.statusCode, this.details});
  @override
  String toString() => '$message (Status: $statusCode)';
}
