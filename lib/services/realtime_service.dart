import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/widgets.dart';
import 'package:service_101/services/notification_service.dart';
import 'package:service_101/services/api_service.dart';
import '../core/utils/logger.dart';
import 'network_status_service.dart';
import 'provider_keepalive_service.dart';

class RealtimeService with WidgetsBindingObserver {
  static RealtimeService? _mockInstance;
  static set mockInstance(RealtimeService? mock) => _mockInstance = mock;

  static final RealtimeService _instance = RealtimeService._internal();
  factory RealtimeService() => _mockInstance ?? _instance;

  bool _initialized = false;
  StreamSubscription? _locationSub;

  RealtimeService._internal() {
    // Initialized without firebase
  }

  /// Inicializa o serviço (Singleton/Idempotente)
  void init(String userId) {
    if (_initialized && _currentUserId == userId) {
      return;
    }

    final previousUserId = _currentUserId;
    if (previousUserId != null && previousUserId != userId) {
      _disposeUserScopedChannels();
    }

    _initialized = true;
    _currentUserId = userId;
    AppLogger.sistema('RealtimeService inicializado para o usuário $userId');
    unawaited(_networkStatus.ensureInitialized());
    _registerLifecycleObserver();

    if (mockMode) {
      return;
    }

    // Realtime agora vem de relay backend / eventos externos (FCM etc).
    _userEventsDegraded = false;

    unawaited(_listenToUserEvents(userId));
  }

  @visibleForTesting
  RealtimeService.testing();

  static bool mockMode = false;

  final StreamController<Map<String, dynamic>> _allEventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream global de todos os eventos recebidos (Supabase Realtime ou FCM)
  Stream<Map<String, dynamic>> get eventsStream => _allEventsController.stream;

  // Timer? _locationTimer; // Replaced by StreamSubscription
  DateTime? _lastLocationUpdate;
  String? _currentUserId;
  Timer? _providerHeartbeatTimer;
  final Map<String, List<Function(dynamic)>> _eventListeners = {};
  Timer? _userEventsRetryTimer;
  int _userEventsRetryAttempt = 0;
  bool _isReconnectingRealtime = false;
  bool _userEventsDegraded = false;
  DateTime? _lastUserEventsRetryLogAt;
  String? _lastUserEventsRetrySignature;
  bool _isAppInBackground = false;
  bool _isObservingLifecycle = false;
  bool get isUserEventsDegraded => _userEventsDegraded;
  final NetworkStatusService _networkStatus = NetworkStatusService();

  /// Conecta ao serviço (Mantido para compatibilidade)
  void connect() {
    debugPrint(
      '🔥 Firebase RealtimeService connect() called (use init(userId) for full setup)',
    );
  }

  void authenticate(String userId) {
    // Redireciona para init que agora é Singleton-safe
    init(userId);
  }

  /// Retorna stream de localização do prestador (Ainda não migrado para stream Postgres)
  Stream<dynamic>? getProviderLocationStream(String providerId) {
    AppLogger.viagem(
      'Location stream dedicado será provido pelo relay backend.',
    );
    return null;
  }

  // --- Métodos de Compatibilidade (Depreciados/Adaptados) ---

  void joinService(String serviceId) {
    // No Firebase não precisamos dar "join", apenas ouvir o stream.
    // Mantido para não quebrar chamadas existentes imediatamente.
  }

  void leaveService() {}

  void onEvent(String event, Function(dynamic) handler) {
    _eventListeners.putIfAbsent(event, () => []).add(handler);
  }

  void offEvent(String event, Function(dynamic) handler) {
    if (_eventListeners.containsKey(event)) {
      _eventListeners[event]!.remove(handler);
    }
  }

  void on(String event, Function(dynamic) handler) => onEvent(event, handler);
  void off(String event, Function(dynamic) handler) => offEvent(event, handler);

  /// Permite injetar eventos externos (pl. ex: via FCM)
  void handleExternalEvent(String type, dynamic payload) {
    AppLogger.notificacao('Evento externo injetado: $type');

    // Normalização básica do payload para garantir que campos id/service_id existam
    final Map<String, dynamic> normalizedPayload = payload is Map
        ? Map<String, dynamic>.from(payload)
        : {};

    // Broadcast global
    _allEventsController.add({
      'type': type,
      'payload': normalizedPayload,
      'source': 'external',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    if (_eventListeners.containsKey(type)) {
      for (final h in _eventListeners[type]!) {
        try {
          h(normalizedPayload);
        } catch (e) {
          debugPrint('❌ Error in handler for injected event $type: $e');
        }
      }
    }
  }

  Future<void> _listenToUserEvents(String userId) async {
    if (mockMode) return;
    if (_networkStatus.isOffline) {
      _userEventsDegraded = true;
      AppLogger.info(
        'ℹ️ [Realtime] user_events aguardando rede para religar userId=$userId',
      );
      _scheduleUserEventsResubscribe(userId, error: 'offline_dns_or_network');
      return;
    }

    _userEventsRetryTimer?.cancel();
    _userEventsRetryTimer = null;
    _removeUserEventsChannel();

    AppLogger.sistema(
      '🔌 [Realtime] relay backend ativo (sem canal direto Supabase) userId=$userId',
    );
    _userEventsRetryAttempt = 0;
    _userEventsDegraded = false;
    _networkStatus.markBackendRecovered();
  }

  Future<void> _reconnectRealtimeSocket() async {
    if (_isReconnectingRealtime) return;
    _isReconnectingRealtime = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      AppLogger.sistema('🔌 [Realtime] reconnect via relay backend');
    } catch (e) {
      AppLogger.alerta('⚠️ [Realtime] falha ao reconectar socket: $e');
    } finally {
      _isReconnectingRealtime = false;
    }
  }

  Future<void> requestSocketReconnect() => _reconnectRealtimeSocket();

  void _scheduleUserEventsResubscribe(String userId, {String? error}) {
    if (mockMode) return;
    _userEventsRetryTimer?.cancel();
    _userEventsRetryTimer = null;

    if (_networkStatus.isOffline) {
      _userEventsDegraded = true;
      AppLogger.info(
        'ℹ️ [Realtime] user_events offline; retry passivo em 15s userId=$userId',
      );
      _userEventsRetryTimer = Timer(const Duration(seconds: 15), () {
        unawaited(() async {
          await _networkStatus.refreshConnectivity();
          if (_networkStatus.canAttemptSupabase) {
            await _reconnectRealtimeSocket();
          }
          await _listenToUserEvents(userId);
        }());
      });
      return;
    }

    // Exponential backoff capped at 60s.
    _userEventsRetryAttempt = (_userEventsRetryAttempt + 1).clamp(1, 10);
    final seconds = (2 << (_userEventsRetryAttempt - 1)).clamp(2, 60);
    _logUserEventsRetry(userId: userId, seconds: seconds, error: error);

    _userEventsRetryTimer = Timer(Duration(seconds: seconds), () {
      unawaited(() async {
        await _reconnectRealtimeSocket();
        _removeUserEventsChannel();
        await _listenToUserEvents(userId);
      }());
    });
  }

  void _logUserEventsRetry({
    required String userId,
    required int seconds,
    String? error,
  }) {
    final signature = '$userId|$seconds|${error ?? ""}';
    final now = DateTime.now();
    final shouldThrottle =
        _lastUserEventsRetrySignature == signature &&
        _lastUserEventsRetryLogAt != null &&
        now.difference(_lastUserEventsRetryLogAt!) <
            const Duration(seconds: 20);
    if (shouldThrottle) return;
    _lastUserEventsRetrySignature = signature;
    _lastUserEventsRetryLogAt = now;
    AppLogger.sistema(
      '🔁 [Realtime] retry user_events in ${seconds}s attempt=$_userEventsRetryAttempt userId=$userId err=${error ?? ""}',
    );
  }

  void _removeUserEventsChannel() {
    // Sem canal direto no cliente (relay backend).
  }

  void _disposeUserScopedChannels() {
    _removeUserEventsChannel();
  }

  // --- Lógica de Localização ---

  void startLocationUpdates(String userId, {String? userUid}) {
    _locationSub?.cancel();
    _currentUserId = userId;
    _registerLifecycleObserver();
    _persistKeepaliveContext(userId, userUid: userUid);

    if (kIsWeb) {
      AppLogger.info(
        'ℹ️ [Realtime] startLocationUpdates ignorado no web para evitar falhas do geolocator stream.',
      );
      _startProviderHeartbeat(forceImmediate: true);
      return;
    }

    // Configuração de Stream com filtro de distância
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Mínimo 10 metros para notificar
    );

    AppLogger.viagem('Iniciando atualizações de localização via Stream (GPS)');

    Position? lastRegistryPosition;

    _locationSub = Geolocator.getPositionStream(locationSettings: settings).listen((
      position,
    ) {
      unawaited(
        ProviderKeepaliveService.cacheLastKnownCoords(
          position.latitude,
          position.longitude,
        ),
      );
      final now = DateTime.now();
      // Debounce/Throttle manual de 10 segundos para RTDB
      if (_lastLocationUpdate == null ||
          now.difference(_lastLocationUpdate!).inSeconds >= 10) {
        _lastLocationUpdate = now;
        unawaited(_sendProviderPresenceWithCoords(position));

        // Check if we moved significantly (> 500m) to update the D1 Registry
        if (ApiService().isLoggedIn) {
          if (lastRegistryPosition == null) {
            lastRegistryPosition = position;
            NotificationService().syncToken();
          } else {
            final distance = Geolocator.distanceBetween(
              lastRegistryPosition!.latitude,
              lastRegistryPosition!.longitude,
              position.latitude,
              position.longitude,
            );
            if (distance > 500) {
              AppLogger.viagem(
                'Movimento significativo detectado ($distance m). Sincronizando cadastro FCM.',
              );
              lastRegistryPosition = position;
              NotificationService().syncToken();
            }
          }
        }
      }
    });

    _startProviderHeartbeat(forceImmediate: true);
  }

  void stopLocationUpdates() {
    _locationSub?.cancel();
    _locationSub = null;
    _providerHeartbeatTimer?.cancel();
    _providerHeartbeatTimer = null;
    _userEventsRetryTimer?.cancel();
    _userEventsRetryTimer = null;
    _disposeUserScopedChannels();
    _unregisterLifecycleObserver();
    _isAppInBackground = false;
    unawaited(ProviderKeepaliveService.clearKeepaliveContext());
    AppLogger.viagem('Atualizações de localização encerradas');
  }

  void _startProviderHeartbeat({bool forceImmediate = false}) {
    _providerHeartbeatTimer?.cancel();
    _providerHeartbeatTimer = null;

    if (!_isProviderSession()) {
      return;
    }

    if (_isAppInBackground) {
      return;
    }

    Future<void> tick() async {
      final result = await ProviderKeepaliveService.sendHeartbeatTick(
        source: 'foreground',
      );
      AppLogger.viagem(
        '🫀 [Heartbeat] provider presence tick result=${result.name}',
      );
    }

    if (forceImmediate) {
      unawaited(tick());
    }

    _providerHeartbeatTimer = Timer.periodic(
      ProviderKeepaliveService.heartbeatInterval,
      (_) => unawaited(tick()),
    );
  }

  Future<void> _sendProviderPresenceWithCoords(Position position) async {
    final result = await ProviderKeepaliveService.sendHeartbeatWithCoords(
      lat: position.latitude,
      lon: position.longitude,
      source: 'location_stream',
    );
    AppLogger.viagem(
      '🛰️ [Heartbeat] location stream presence result=${result.name}',
    );
  }

  bool _isProviderSession() {
    final api = ApiService();
    return api.role == 'provider';
  }

  void _registerLifecycleObserver() {
    if (_isObservingLifecycle) return;
    WidgetsBinding.instance.addObserver(this);
    _isObservingLifecycle = true;
  }

  void _unregisterLifecycleObserver() {
    if (!_isObservingLifecycle) return;
    WidgetsBinding.instance.removeObserver(this);
    _isObservingLifecycle = false;
  }

  Future<void> _persistKeepaliveContext(
    String userId, {
    String? userUid,
  }) async {
    final api = ApiService();
    await ProviderKeepaliveService.persistKeepaliveContext(
      onlineForDispatch: true,
      userId: userId,
      userUid: userUid ?? ApiService().userData?['supabase_uid']?.toString(),
      isFixedLocation: api.isFixedLocation,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _isAppInBackground = true;
      if (!_isProviderSession()) return;
      _providerHeartbeatTimer?.cancel();
      _providerHeartbeatTimer = null;
      unawaited(ProviderKeepaliveService.startBackgroundService());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _isAppInBackground = false;
      final userId = _currentUserId?.trim();
      if (userId != null && userId.isNotEmpty && !mockMode) {
        unawaited(() async {
          await _networkStatus.refreshConnectivity();
          if (_networkStatus.canAttemptSupabase) {
            await _reconnectRealtimeSocket();
            await _listenToUserEvents(userId);
          }
        }());
      }
      if (!_isProviderSession()) return;
      unawaited(ProviderKeepaliveService.stopBackgroundService());
      _startProviderHeartbeat(forceImmediate: true);
    }
  }

  // Método antigo removido (_sendLocationUpdate) pois agora usamos stream

  // --- Presença ---

  void checkStatus(String userId, void Function(bool isOnline) callback) {
    // Verificação simples via API ou Presence
    callback(false);
  }

  void onPresenceUpdate(void Function(String userId, bool isOnline) handler) {
    // Escutar mudanças globais de status seria custoso aqui.
    // Idealmente, escutar status de usuários específicos.
  }

  void dispose() {
    stopLocationUpdates();
  }
}
