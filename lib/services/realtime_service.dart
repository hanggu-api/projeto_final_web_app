import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:service_101/services/notification_service.dart';
import 'package:service_101/services/api_service.dart';
import '../core/utils/logger.dart';

class RealtimeService {
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
  void init(int userId) {
    if (_initialized && _currentUserId == userId) {
      return;
    }

    _initialized = true;
    _currentUserId = userId;
    AppLogger.sistema('RealtimeService inicializado para o usuário $userId');

    // Setup Presence via Supabase Realtime
    try {
      final channel = Supabase.instance.client.channel('public:presence_status');
      
      channel.onPresenceSync((payload) {
        // AppLogger.sistema('Presence Sync event!');
      });

      channel.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.track({
            'user_id': userId,
            'state': 'online',
            'last_changed': DateTime.now().toIso8601String()
          });
        }
      });
      
    } catch (e) {
      AppLogger.erro('Erro ao configurar presença no Supabase', e);
    }

    _listenToUserEvents(userId);
  }

  @visibleForTesting
  RealtimeService.testing();

  static bool mockMode = false;

  final StreamController<Map<String, dynamic>> _allEventsController = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream global de todos os eventos recebidos (Supabase Realtime ou FCM)
  Stream<Map<String, dynamic>> get eventsStream => _allEventsController.stream;

  // Timer? _locationTimer; // Replaced by StreamSubscription
  DateTime? _lastLocationUpdate;
  int? _currentUserId;
  final Map<String, List<Function(dynamic)>> _eventListeners = {};
  RealtimeChannel? _userEventsSub;

  /// Conecta ao serviço (Mantido para compatibilidade)
  void connect() {
    debugPrint(
      '🔥 Firebase RealtimeService connect() called (use init(userId) for full setup)',
    );
  }

  void authenticate(int userId) {
    // Redireciona para init que agora é Singleton-safe
    init(userId);
  }

  /// Retorna stream de localização do prestador (Ainda não migrado para stream Postgres)
  Stream<dynamic>? getProviderLocationStream(int providerId) {
    AppLogger.viagem('Supabase Realtime Location Stream não completamente migrado ainda.');
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
    final Map<String, dynamic> normalizedPayload = payload is Map ? Map<String, dynamic>.from(payload) : {};
    
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

  void _listenToUserEvents(int userId) {
    if (mockMode) return;
    
    if (_userEventsSub != null) {
      Supabase.instance.client.removeChannel(_userEventsSub!);
    }
    
    AppLogger.sistema('Ouvindo eventos Broadcast do Supabase para o usuário $userId');

    _userEventsSub = Supabase.instance.client.channel('user_events_$userId');
    
    _userEventsSub!.onBroadcast(event: 'custom_event', callback: (payload) {
       final val = payload;
       if (val.isNotEmpty) {
            final type = val['type'];
            final eventPayload = val['payload'];
            final timestampRaw = val['timestamp'];

            AppLogger.notificacao('Evento Supabase Broadcast detectado: $type');

            final Map<String, dynamic> normalizedPayload = eventPayload is Map ? Map<String, dynamic>.from(eventPayload) : {};

            _allEventsController.add({
              'type': type,
              'payload': normalizedPayload,
              'source': 'supabase_broadcast',
              'timestamp': timestampRaw ?? DateTime.now().millisecondsSinceEpoch,
            });

            if (type == 'service.scheduled_started') {
              AppLogger.notificacao('⚡ Interceptando START agendado -> NotificationService');
              NotificationService().handleNotificationTap({
                'type': 'scheduled_started',
                'id': normalizedPayload['service_id'] ?? normalizedPayload['id'],
                ...normalizedPayload
              });
            }

            if (type != null && _eventListeners.containsKey(type)) {
              AppLogger.sistema('Executando handlers para o evento: $type');
              for (final h in _eventListeners[type]!) {
                try {
                  h(normalizedPayload);
                } catch (e) {
                  AppLogger.erro('Erro no handler do evento $type: $e');
                }
              }
            } else if (type != 'service.scheduled_started' && 
                       type != 'client.arrived' && 
                       type != 'client.departed') { 
              AppLogger.alerta('Nenhum handler registrado para o tipo de evento: $type');
            }
       }
    }).subscribe();
  }

  // --- Lógica de Localização ---

  void startLocationUpdates(int userId) {
    _locationSub?.cancel();
    _currentUserId = userId;

    // Configuração de Stream com filtro de distância
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Mínimo 10 metros para notificar
    );

    AppLogger.viagem('Iniciando atualizações de localização via Stream (GPS)');

    Position? lastRegistryPosition;

    _locationSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((position) {
          final now = DateTime.now();
          // Debounce/Throttle manual de 10 segundos para RTDB
          if (_lastLocationUpdate == null ||
              now.difference(_lastLocationUpdate!).inSeconds >= 10) {
            _lastLocationUpdate = now;
            _updateLocationInFirebase(position);
            
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
                   position.longitude
                 );
                 if (distance > 500) {
                   AppLogger.viagem('Movimento significativo detectado ($distance m). Sincronizando cadastro FCM.');
                   lastRegistryPosition = position;
                   NotificationService().syncToken();
                 }
              }
            }
          }
        });
  }

  void stopLocationUpdates() {
    _locationSub?.cancel();
    _locationSub = null;
    AppLogger.viagem('Atualizações de localização encerradas');
  }

  Future<void> _updateLocationInFirebase(Position position) async {
    if (_currentUserId == null) return;
    try {
      // TODO: Usar Supabase Location Table ou Presence State para syncar GPS do Provider
      // Supabase.instance.client.from('provider_locations').upsert(...)
    } catch (e) {
      AppLogger.erro('Erro ao enviar localização para o Supabase', e);
    }
  }

  // Método antigo removido (_sendLocationUpdate) pois agora usamos stream

  // --- Presença ---

  void checkStatus(int userId, void Function(bool isOnline) callback) {
    // Verificação simples via API ou Presence
    callback(false);
  }

  void onPresenceUpdate(void Function(int userId, bool isOnline) handler) {
    // Escutar mudanças globais de status seria custoso aqui.
    // Idealmente, escutar status de usuários específicos.
  }

  void dispose() {
    stopLocationUpdates();
  }
}
