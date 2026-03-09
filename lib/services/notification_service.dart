import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:service_101/features/notifications/widgets/time_to_leave_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/client/widgets/provider_arrived_modal.dart';
import '../features/client/widgets/client_wake_up_modal.dart';
import '../features/provider/widgets/scheduled_notification_modal.dart';
import '../features/provider/widgets/service_offer_modal.dart';
import '../firebase_options.dart';
import 'api_service.dart';
import 'awesome_notification_service.dart';
import 'data_gateway.dart';
import 'realtime_service.dart';
import '../core/utils/logger.dart';

const String _urgentChannelIdBg = 'high_importance_channel_v3';
const String _uberOffersChannelIdBg = 'uber_trip_offers_channel';
const String _uberUpdatesChannelIdBg = 'uber_trip_updates_channel';
const String _chatChannelIdBg = 'chat_messages_channel';

bool _isUberTripType(String? type) => type?.startsWith('uber_trip_') == true;

int _tripReminderNotificationId(String tripId) => tripId.hashCode ^ 0x2F2F;

String _defaultUberTitle(String? type) {
  switch (type) {
    case 'uber_trip_offer':
      return 'Nova corrida Uber disponivel';
    case 'uber_trip_accepted':
      return 'Motorista a caminho';
    case 'uber_trip_arrived':
      return 'Motorista chegou';
    case 'uber_trip_started':
      return 'Corrida iniciada';
    case 'uber_trip_completed':
      return 'Corrida concluida';
    case 'uber_trip_cancelled':
      return 'Corrida cancelada';
    case 'uber_trip_wait_2m':
      return 'Tempo de espera iniciado';
    default:
      return 'Atualizacao da corrida';
  }
}

String _defaultUberBody(String? type) {
  switch (type) {
    case 'uber_trip_offer':
      return 'Toque para revisar a oferta e decidir agora.';
    case 'uber_trip_accepted':
      return 'Seu motorista aceitou a corrida e esta indo ate voce.';
    case 'uber_trip_arrived':
      return 'Seu motorista ja esta no local de embarque.';
    case 'uber_trip_started':
      return 'Sua viagem comecou.';
    case 'uber_trip_completed':
      return 'Sua viagem foi finalizada.';
    case 'uber_trip_cancelled':
      return 'A corrida foi cancelada.';
    case 'uber_trip_wait_2m':
      return 'Ja se passaram 2 minutos de espera. Se precisar, responda ao motorista pelo chat.';
    default:
      return 'Voce recebeu uma atualizacao importante da sua corrida.';
  }
}

AndroidNotificationDetails _buildBackgroundUberArrivedDetails() {
  return const AndroidNotificationDetails(
    _uberUpdatesChannelIdBg,
    'Uber: Atualizacoes de Corrida',
    channelDescription: 'Atualizacoes de status das corridas do modulo Uber.',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    icon: 'ic_notification_101',
    largeIcon: DrawableResourceAndroidBitmap('ic_logo_colored'),
    color: Color(0xFFFDE500),
    colorized: true,
    category: AndroidNotificationCategory.message,
    sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
    visibility: NotificationVisibility.public,
    actions: [
      AndroidNotificationAction('open_trip', 'Abrir corrida'),
      AndroidNotificationAction(
        'trip_reply',
        'Responder',
        inputs: [AndroidNotificationActionInput(label: 'Digite uma resposta')],
      ),
    ],
  );
}

AndroidNotificationDetails _buildBackgroundUberStatusDetails({
  required String type,
  required String title,
  required String body,
}) {
  return AndroidNotificationDetails(
    type == 'uber_trip_offer'
        ? _uberOffersChannelIdBg
        : _uberUpdatesChannelIdBg,
    type == 'uber_trip_offer'
        ? 'Uber: Ofertas de Corrida'
        : 'Uber: Atualizacoes de Corrida',
    channelDescription: 'Notificacoes premium do modulo Uber.',
    importance: type == 'uber_trip_offer' ? Importance.max : Importance.high,
    priority: type == 'uber_trip_offer' ? Priority.max : Priority.high,
    playSound: true,
    icon: 'ic_notification_101',
    largeIcon: const DrawableResourceAndroidBitmap('ic_logo_colored'),
    color: const Color(0xFFFDE500),
    colorized: true,
    category: type == 'uber_trip_offer'
        ? AndroidNotificationCategory.call
        : AndroidNotificationCategory.status,
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: title,
      summaryText: '101 Service',
    ),
    sound: const RawResourceAndroidNotificationSound('iphone_notificacao'),
    visibility: NotificationVisibility.public,
    fullScreenIntent: type == 'uber_trip_offer',
    timeoutAfter: type == 'uber_trip_offer' ? 30000 : null,
  );
}

Future<void> _scheduleTripWaitReminderBackground(
  FlutterLocalNotificationsPlugin localNotifications,
  String tripId,
) async {
  tz.initializeTimeZones();
  final scheduledAt = tz.TZDateTime.now(
    tz.local,
  ).add(const Duration(minutes: 2));

  await localNotifications.zonedSchedule(
    id: _tripReminderNotificationId(tripId),
    title: 'Tempo de espera iniciado',
    body:
        'Ja se passaram 2 minutos de espera. Se precisar, responda ao motorista pelo chat.',
    scheduledDate: scheduledAt,
    notificationDetails: NotificationDetails(
      android: _buildBackgroundUberArrivedDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: jsonEncode({
      'type': 'uber_trip_wait_2m',
      'trip_id': tripId,
      'id': tripId,
    }),
  );
}

/// Handler for background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  AppLogger.notificacao(
    'Notificação recebida em BACKGROUND (Isolate separada)',
  );

  final type = message.data['type'];
  final serviceId =
      message.data['id']?.toString() ??
      message.data['service_id']?.toString() ??
      message.data['trip_id']?.toString();

  // ✅ SALVAR PAYLOAD PARA PROCESSAMENTO NA ISOLATE PRINCIPAL (Foreground)
  if (serviceId != null) {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'data': message.data,
        'received_at': DateTime.now().toIso8601String(),
        'service_id': serviceId,
        'type': type,
      });
      await prefs.setString('bg_pending_offer', payload);
      await prefs.setInt(
        'bg_pending_version',
        2,
      ); // Versão 2: Processamento Robusto
      AppLogger.notificacao(
        'Payload de background salvo para processamento posterior',
      );
    } catch (e) {
      AppLogger.erro('Erro ao salvar payload em background', e);
    }
  }

  // ✅ GERAR NOTIFICAÇÃO LOCAL URGENTE (Para acordar o dispositivo)
  if (type == 'new_service' ||
      type == 'offer' ||
      type == 'service_offered' ||
      type == 'service.offered' ||
      _isUberTripType(type)) {
    debugPrint(
      '🚀 [BACKGROUND DEBUG] Oferta Urgente Detectada. Disparando canais de alta prioridade.',
    );

    final FlutterLocalNotificationsPlugin localNotifications =
        FlutterLocalNotificationsPlugin();

    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidInit);
    await localNotifications.initialize(settings: initSettings);

    const channels = [
      AndroidNotificationChannel(
        _urgentChannelIdBg,
        'Alertas Urgentes',
        description: 'Canal para alertas urgentes de novos serviços.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
      ),
      AndroidNotificationChannel(
        _uberOffersChannelIdBg,
        'Uber: Ofertas de Corrida',
        description: 'Ofertas urgentes para motoristas do modulo Uber.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
      ),
      AndroidNotificationChannel(
        _uberUpdatesChannelIdBg,
        'Uber: Atualizacoes de Corrida',
        description: 'Atualizacoes de status das corridas do modulo Uber.',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
      ),
      AndroidNotificationChannel(
        _chatChannelIdBg,
        'Mensagens de Chat',
        description: 'Mensagens de chat em tempo real.',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
      ),
    ];

    final androidPlugin = localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final channel in channels) {
      await androidPlugin?.createNotificationChannel(channel);
    }

    final String title =
        message.notification?.title ??
        message.data['title']?.toString() ??
        (_isUberTripType(type)
            ? _defaultUberTitle(type?.toString())
            : 'Novo Servico Disponivel');

    final String body =
        message.notification?.body ??
        message.data['body']?.toString() ??
        (_isUberTripType(type)
            ? _defaultUberBody(type?.toString())
            : 'Voce tem uma nova oportunidade de servico proxima!');

    if (type == 'uber_trip_arrived' && serviceId != null) {
      await localNotifications.show(
        id: serviceId.hashCode,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: _buildBackgroundUberArrivedDetails(),
        ),
        payload: jsonEncode({
          ...message.data,
          'trip_id': serviceId,
          'id': serviceId,
        }),
      );
      await _scheduleTripWaitReminderBackground(localNotifications, serviceId);
      return;
    }

    if (_isUberTripType(type) && serviceId != null) {
      if (type == 'uber_trip_started' ||
          type == 'uber_trip_completed' ||
          type == 'uber_trip_cancelled') {
        await localNotifications.cancel(
          id: _tripReminderNotificationId(serviceId),
        );
      }

      await localNotifications.show(
        id: serviceId.hashCode,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: _buildBackgroundUberStatusDetails(
            type: type.toString(),
            title: title,
            body: body,
          ),
        ),
        payload: jsonEncode({
          ...message.data,
          'trip_id': serviceId,
          'id': serviceId,
        }),
      );
      return;
    }

    final NotificationDetails details = NotificationDetails(
      android: NotificationService.getUrgentAndroidDetails(),
    );

    await localNotifications.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: details,
      payload: jsonEncode(message.data),
    );
  }
}

@pragma('vm:entry-point')
void _onDidReceiveBackgroundNotificationResponse(
  NotificationResponse response,
) {
  NotificationService().handleNotificationResponse(response);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _urgentChannelId = 'high_importance_channel_v3';
  static const String _uberOffersChannelId = 'uber_trip_offers_channel';
  static const String _uberUpdatesChannelId = 'uber_trip_updates_channel';
  static const String _chatChannelId = 'chat_messages_channel';

  static const String _vapidKey =
      'BDAlbsqCz9yQNX88yXTKmxPVCxWixZ1Zl9naFpB1Js_RP1t7jYbyO7VLGYN_cGw_d4apRlyhP253pACFJgixUEQ';

  FirebaseMessaging? get _fcm {
    try {
      if (Firebase.apps.isNotEmpty) return FirebaseMessaging.instance;
    } catch (_) {}
    return null;
  }

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool _isInitializing = false; // Evita inicialização duplicada
  GlobalKey<NavigatorState>? navigatorKey;
  bool _isDialogOpen = false;

  // Persistent notifications management
  final Set<String> _activeServiceNotifications = {};
  Timer? _persistentNotificationTimer;
  int _notificationCount = 0;

  // Subscription management
  final List<StreamSubscription> _subscriptions = [];

  Future<void> init(GlobalKey<NavigatorState> navKey) async {
    navigatorKey = navKey;
    try {
      await initialize();
    } catch (e) {
      AppLogger.erro('Falha ao inicializar notificações', e);
    }
    _processBackgroundOffers(); // ✅ Check for background offers immediately on init

    // Listen to lifecycle changes to check when app resumes from background
    WidgetsBinding.instance.addObserver(_LifecycleObserver(this));
  }

  /// Request permissions specifically for providers (Overlay, etc)
  Future<void> requestProviderPermissions() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        AppLogger.sistema(
          'Solicitando permissão de sobreposição (Overlay) para Prestador...',
        );
        await requestOverlayPermission().then((granted) {
          AppLogger.sistema(
            'Permissão de sobreposição: ${granted ? "CONCEDIDA" : "NEGADA"}',
          );
        });
      } catch (e) {
        AppLogger.erro('Erro ao solicitar permissão de sobreposição', e);
      }
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_isInitializing) {
      debugPrint('NotificationService: Already initializing, skipping...');
      return;
    }
    _isInitializing = true;

    // Inicializar fuso horário para agendamentos locais
    tz.initializeTimeZones();

    // 1. Setup Initial Message
    if (_fcm != null) {
      _fcm!
          .getInitialMessage()
          .then((RemoteMessage? message) {
            if (message != null) {
              AppLogger.notificacao(
                'App aberto via notificação (Terminated state)',
              );
              handleNotificationTap(message.data);
            }
          })
          .catchError((e) {
            AppLogger.erro('Erro ao verificar initial message', e);
            return null;
          });
    }

    // 2. Setup onMessageOpenedApp
    if (_fcm != null) {
      _subscriptions.add(
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          if (kDebugMode) {
            debugPrint(
              'App opened from background state via notification: ${message.data}',
            );
          }
          handleNotificationTap(message.data);
        }),
      );
    }

    // Solicitar permissão
    if (_fcm != null) {
      try {
        NotificationSettings settings = await _fcm!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          String? token = await getToken();
          if (kDebugMode) debugPrint("FCM Token: $token");
        }
      } catch (e) {
        debugPrint('Permission request error: $e');
      }
    }

    // 2. Setup Local Notifications (Note: repeated number in original, but kept as is)
    if (!kIsWeb) {
      try {
        const androidSettings = AndroidInitializationSettings(
          '@mipmap/launcher_icon',
        );
        const iosSettings = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

        const initSettings = InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        );

        final bool? initialized = await _localNotifications.initialize(
          settings: initSettings,
          onDidReceiveNotificationResponse: handleNotificationResponse,
          onDidReceiveBackgroundNotificationResponse:
              _onDidReceiveBackgroundNotificationResponse,
        );

        if (initialized == true) {
          final androidPlugin = _localNotifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

          const channels = [
            AndroidNotificationChannel(
              _urgentChannelId,
              'Notificações Importantes',
              description:
                  'Este canal é usado para notificações urgentes do serviço.',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
            ),
            AndroidNotificationChannel(
              _uberOffersChannelId,
              'Uber: Ofertas de Corrida',
              description: 'Ofertas urgentes para motoristas do modulo Uber.',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
            ),
            AndroidNotificationChannel(
              _uberUpdatesChannelId,
              'Uber: Atualizações de Corrida',
              description:
                  'Atualizações de status das corridas do modulo Uber.',
              importance: Importance.high,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
            ),
            AndroidNotificationChannel(
              _chatChannelId,
              'Mensagens de Chat',
              description: 'Mensagens de chat em tempo real.',
              importance: Importance.high,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
            ),
          ];

          for (final channel in channels) {
            await androidPlugin?.createNotificationChannel(channel);
          }
        } else {
          AppLogger.erro(
            'Falha ao inicializar LocalNotifications (retornou false)',
          );
        }
      } catch (e) {
        AppLogger.erro('Erro fatal ao configurar LocalNotifications', e);
      }
    }

    // 3. Setup FCM Handlers
    if (_fcm != null) {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      _subscriptions.add(
        FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
          AppLogger.notificacao('Notificação recebida em FOREGROUND');

          final type = message.data['type'];
          final serviceId =
              message.data['id']?.toString() ??
              message.data['service_id']?.toString();

          if (serviceId != null) {
            ApiService().logServiceEvent(serviceId, 'DELIVERED');
          }

          if (type != null) {
            AppLogger.debug(
              '⚡ Encaminhando evento FCM para RealtimeService: $type',
            );
            final cleanData = Map<String, dynamic>.from(message.data);
            if (serviceId != null) cleanData['id'] = serviceId;
            RealtimeService().handleExternalEvent(type, cleanData);
          }

          if (type == 'new_service' ||
              type == 'offer' ||
              type == 'service_offered' ||
              type == 'service.offered') {
            final prefs = await SharedPreferences.getInstance();
            final role = ApiService().role ?? prefs.getString('user_role');
            debugPrint(
              '🔔🔔🔔 [FOREGROUND] new_service recebido! role=$role, serviceId=$serviceId, _isDialogOpen=$_isDialogOpen',
            );
            if (!_isProviderLikeRole(role)) {
              debugPrint(
                '⏩ [FOREGROUND] Ignorando new_service — role não é provider/driver ($role)',
              );
              return;
            }

            AppLogger.notificacao(
              '🚀 Abrindo modal de oferta automaticamente (FOREGROUND)',
            );

            // 1. Tocar alerta sonoro IMEDIATAMENTE
            _playNotificationAlert();
            _showLocalNotification(message);

            // 2. Iniciar notificações persistentes (repetição)
            if (serviceId != null) {
              _startPersistentNotification(serviceId, message);
            }

            // 3. Direcionar o motorista para a home de corridas.
            // Provider legado continua abrindo o modal diretamente.
            _isDialogOpen = false;
            if (_isDriverRole(role)) {
              unawaited(_openDriverHomeForTripOffer(message.data));
            } else {
              handleNotificationTap(message.data);
            }
            return;
          }

          if (type == 'force_logout') {
            _handleForceLogout();
            return;
          }

          if (type == 'provider_arrived') {
            final role = ApiService().role;
            if (role == 'provider') return;
          }

          if (message.notification != null) {
            _showLocalNotification(message);
          }
        }),
      );
    }

    // 4. Token Sync
    String? token = await getToken();
    if (token != null) {
      await _sendTokenToBackend(token);
    }

    _subscriptions.add(
      _fcm?.onTokenRefresh.listen((newToken) {
            _sendTokenToBackend(newToken);
          }) ??
          const Stream.empty().listen((_) {}),
    );

    _processBackgroundOffers();

    _isInitialized = true;
  }

  void handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(payload));
    } catch (_) {
      return;
    }

    final actionId = response.actionId;
    if (actionId == 'chat_mark_read') {
      final msgId = int.tryParse('${data['message_id']}');
      if (msgId != null) {
        DataGateway().markChatMessageRead(msgId);
      }
      return;
    }

    if (actionId == 'chat_reply') {
      final serviceId = data['service_id']?.toString();
      final text = response.input?.trim() ?? '';
      final msgId = int.tryParse('${data['message_id']}');
      if (serviceId != null && text.isNotEmpty) {
        DataGateway().sendChatMessage(serviceId, text, 'text');
        if (msgId != null) {
          DataGateway().markChatMessageRead(msgId);
        }
      }
      return;
    }

    if (actionId == 'trip_reply') {
      final tripId =
          data['trip_id']?.toString() ??
          data['service_id']?.toString() ??
          data['id']?.toString();
      final text = response.input?.trim() ?? '';
      if (tripId != null && text.isNotEmpty) {
        DataGateway().sendChatMessage(tripId, text, 'text');
      }
      return;
    }

    if (actionId == 'open_trip') {
      handleNotificationTap(data);
      return;
    }

    handleNotificationTap(data);
  }

  Future<void> showChatMessageNotification({
    required String serviceId,
    required int messageId,
    required String senderName,
    required String message,
  }) async {
    if (kIsWeb) return;

    await _localNotifications.show(
      id: messageId,
      title: senderName,
      body: message,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _chatChannelId,
          'Mensagens de Chat',
          channelDescription: 'Mensagens de chat em tempo real',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          icon: '@mipmap/launcher_icon',
          sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
          actions: [
            AndroidNotificationAction('chat_mark_read', 'Marcar como lida'),
            AndroidNotificationAction(
              'chat_reply',
              'Responder rapido',
              inputs: [
                AndroidNotificationActionInput(label: 'Digite sua resposta'),
              ],
            ),
          ],
        ),
      ),
      payload: jsonEncode({
        'type': 'chat_message',
        'service_id': serviceId,
        'message_id': messageId,
      }),
    );
  }

  Future<bool> hasOverlayPermission() async {
    if (!Platform.isAndroid) return true;
    return await Permission.systemAlertWindow.isGranted;
  }

  Future<bool> requestOverlayPermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final status = await Permission.systemAlertWindow.request();
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check and request overlay with explanation
  Future<void> showOverlayExplanationAndRequest(BuildContext context) async {
    if (!Platform.isAndroid) return;

    final granted = await hasOverlayPermission();
    if (!context.mounted) return;
    if (granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permissão de sobreposição já concedida!'),
        ),
      );
      return;
    }

    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sobreposição de Tela'),
        content: const Text(
          'Para que você possa receber alertas de novos serviços mesmo com o app fechado ou em outro aplicativo, precisamos da permissão de "Sobrepor a outros apps".\n\nIsso abrirá os Ajustes do seu Android.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('AGORA NÃO'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('CONFIGURAR'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      final result = await requestOverlayPermission();
      if (!result && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Habilite a permissão na tela que abriu.'),
          ),
        );
      }
    }
  }

  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _isInitialized = false;
  }

  Future<String?> getToken() async {
    try {
      if (kIsWeb) {
        return await _fcm?.getToken(vapidKey: _vapidKey);
      }
      return await _fcm?.getToken();
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteToken() async {
    try {
      await _fcm?.deleteToken();
    } catch (e) {
      debugPrint('❌ [FCM] Erro ao deletar token: $e');
    }
  }

  Future<void> syncToken() async {
    String? token = await getToken();
    if (token != null) {
      await _sendTokenToBackend(token);
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final api = ApiService();
      if (!api.isLoggedIn) return;

      String? role = api.role;
      if (role == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          role = prefs.getString('user_role');
        } catch (_) {}
      }

      if (role == null) return;

      double? lat;
      double? lon;

      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();

          if (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse) {
            Position? position = await Geolocator.getLastKnownPosition();
            position ??= await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.low,
                timeLimit: Duration(seconds: 3),
              ),
            );
            lat = position.latitude;
            lon = position.longitude;
          }
        }
      } catch (e) {
        debugPrint(
          '⚠️ [NotificationService] Could not get location for token registration: $e',
        );
      }

      final platform = kIsWeb ? 'web' : Platform.operatingSystem;
      await api.registerDeviceToken(
        token,
        platform,
        latitude: lat,
        longitude: lon,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [FCM] Erro ao registrar token no backend: $e');
      }
    }
  }

  Future<BuildContext?> _getValidContext() async {
    int attempts = 0;
    while (navigatorKey?.currentContext == null && attempts < 20) {
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }
    return navigatorKey?.currentContext;
  }

  bool _isDriverRole(String? role) => role == 'driver';
  bool _isProviderLikeRole(String? role) =>
      role == 'provider' || role == 'driver';

  Future<void> _openDriverHomeForTripOffer(Map<String, dynamic> data) async {
    if (navigatorKey?.currentContext == null) {
      await _getValidContext();
    }
    if (navigatorKey?.currentContext == null) return;

    GoRouter.of(
      navigatorKey!.currentContext!,
    ).go('/uber-driver', extra: {'initialTripOffer': data});
  }

  void handleNotificationTap(Map<String, dynamic> data) {
    debugPrint('🔔 [NOTIFICATION DEBUG] Handling tap with data: $data');

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (navigatorKey?.currentContext == null) {
        await _getValidContext();
      }

      if (navigatorKey?.currentContext != null) {
        await _processNotificationData(data);
      }
    });
  }

  Future<void> _processNotificationData(Map<String, dynamic> data) async {
    final String? type = data['type']?.toString();
    final prefs = await SharedPreferences.getInstance();
    final role = ApiService().role ?? prefs.getString('user_role');
    debugPrint('🔀 [NOTIFICATION TAP] Type detected: $type');

    if (type == 'chat_message' || type == 'chat') {
      final String? serviceId =
          data['id']?.toString() ?? data['service_id']?.toString();
      if (serviceId != null && navigatorKey?.currentContext != null) {
        GoRouter.of(navigatorKey!.currentContext!).push('/chat/$serviceId');
        return;
      }
    }

    if (type == 'uber_trip_offer') {
      if (_isDriverRole(role)) {
        await _openDriverHomeForTripOffer(data);
      }
      return;
    }

    if (type == 'uber_trip_accepted' ||
        type == 'uber_trip_arrived' ||
        type == 'uber_trip_started') {
      final String? tripId =
          data['trip_id']?.toString() ?? data['id']?.toString();
      if (tripId != null && navigatorKey?.currentContext != null) {
        GoRouter.of(navigatorKey!.currentContext!).go('/uber-tracking/$tripId');
      }
      return;
    }

    if (type == 'uber_trip_completed' || type == 'uber_trip_cancelled') {
      final String? tripId =
          data['trip_id']?.toString() ?? data['id']?.toString();

      if (tripId != null &&
          role == 'driver' &&
          navigatorKey?.currentContext != null) {
        GoRouter.of(navigatorKey!.currentContext!).go('/uber-driver');
        return;
      }

      if (navigatorKey?.currentContext != null) {
        GoRouter.of(navigatorKey!.currentContext!).go('/home');
      }
      return;
    }

    if (type == 'schedule_proposal') {
      if (navigatorKey?.currentContext != null) {
        GoRouter.of(navigatorKey!.currentContext!).go('/home');
        return;
      }
    }

    if (type == 'provider_arrived') {
      final String? serviceId =
          data['id']?.toString() ?? data['service_id']?.toString();
      if (serviceId != null) {
        _showDialogSafe(
          ProviderArrivedModal(serviceId: serviceId, initialData: data),
        );
        return;
      }
    }

    if (type == 'time_to_leave') {
      _showDialogSafe(TimeToLeaveModal(data: data));
      return;
    }

    if (type == 'new_service' ||
        type == 'offer' ||
        type == 'service_offered' ||
        type == 'service.offered') {
      if (!_isProviderLikeRole(role)) return;

      if (_isDriverRole(role)) {
        unawaited(_openDriverHomeForTripOffer(data));
        return;
      }

      final String? serviceId =
          data['id']?.toString() ?? data['service_id']?.toString();
      if (serviceId != null) {
        _showDialogSafe(
          ServiceOfferModal(serviceId: serviceId, initialData: data),
          barrierDismissible: false,
        );
        return;
      }
    }

    if (type == 'scheduled_started') {
      final role = ApiService().role;
      final String? serviceId =
          data['id']?.toString() ?? data['service_id']?.toString();

      if (serviceId != null) {
        if (role == 'provider') {
          _showDialogSafe(
            ScheduledNotificationModal(serviceId: serviceId, initialData: data),
            barrierDismissible: false,
          );
        } else {
          // Client Logic: Show Wake Up Modal
          _showDialogSafe(
            ClientWakeUpModal(serviceId: serviceId, initialData: data),
            barrierDismissible: false,
          );
        }
        return;
      }
    }

    if (type == 'service_started' ||
        type == 'service_completed' ||
        type == 'status_update' ||
        type == 'payment_approved') {
      final String? serviceId =
          data['id']?.toString() ?? data['service_id']?.toString();
      if (serviceId != null) {
        final locationType = data['location_type'];

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (navigatorKey?.currentContext == null) return;

          if (locationType == 'provider') {
            GoRouter.of(
              navigatorKey!.currentContext!,
            ).push('/scheduled-service/$serviceId');
          } else {
            GoRouter.of(
              navigatorKey!.currentContext!,
            ).push('/tracking/$serviceId');
          }
        });
        return;
      }
    }
  }

  Future<void> _showDialogSafe(
    Widget child, {
    bool barrierDismissible = true,
  }) async {
    if (_isDialogOpen) return;
    if (navigatorKey?.currentContext == null) return;

    if (child is ServiceOfferModal) {
      final String sid = child.serviceId;
      final prefs = await SharedPreferences.getInstance();
      final lastProcessed = prefs.getString('last_processed_sid');
      final lastTime = prefs.getInt('last_processed_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (lastProcessed == sid && (now - lastTime) < 5000) return;

      await prefs.setString('last_processed_sid', sid);
      await prefs.setInt('last_processed_time', now);
    }

    _isDialogOpen = true;
    try {
      await showDialog(
        context: navigatorKey!.currentContext!,
        barrierDismissible: barrierDismissible,
        builder: (context) => child,
      );
    } finally {
      _isDialogOpen = false;
    }
  }

  Future<void> showFromService(
    Map<String, dynamic> payload, {
    String? event,
  }) async {
    await _localNotifications.show(
      id: DateTime.now().millisecond,
      title: 'Atualização de Serviço',
      body: payload['message'] ?? event ?? 'Nova atualização',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'service_updates',
          'Service Updates',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          largeIcon: DrawableResourceAndroidBitmap('ic_logo_colored'),
          sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
        ),
      ),
      payload: jsonEncode(payload),
    );
  }

  Future<void> showAccepted() async {
    await _localNotifications.show(
      id: DateTime.now().millisecond,
      title: 'Serviço Aceito!',
      body: 'Um prestador aceitou seu serviço.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'service_updates',
          'Service Updates',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          largeIcon: DrawableResourceAndroidBitmap('ic_logo_colored'),
          sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
        ),
      ),
    );
  }

  Future<void> showNotification(String title, String body) async {
    await _localNotifications.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: _buildPremiumAndroidDetails(
          channelId: _urgentChannelId,
          channelName: 'High Importance Notifications',
          title: title,
          body: body,
          category: AndroidNotificationCategory.alarm,
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
        ),
        iOS: _buildPremiumDarwinDetails(
          subtitle: '101 Service',
          threadIdentifier: 'urgent-alerts',
        ),
      ),
    );
  }

  Future<void> showUberTripOfferNotification(Map<String, dynamic> trip) async {
    if (kIsWeb) return;

    final tripId = trip['id']?.toString() ?? '';
    final pickup = trip['pickup_address']?.toString() ?? 'Origem';
    final dropoff = trip['dropoff_address']?.toString() ?? 'Destino';
    final fare = trip['fare_estimated']?.toString() ?? '0,00';
    final body =
        '$pickup -> $dropoff\nGanhos estimados: R\$ $fare\nToque para revisar e aceitar a corrida.';

    await _localNotifications.show(
      id: tripId.hashCode,
      title: 'Nova corrida Uber disponível',
      body: body,
      notificationDetails: NotificationDetails(
        android: _buildPremiumAndroidDetails(
          channelId: _uberOffersChannelId,
          channelName: 'Uber: Ofertas de Corrida',
          title: 'Nova corrida Uber disponível',
          body: body,
          category: AndroidNotificationCategory.call,
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          timeoutAfter: 30000,
          subText: 'Oferta premium',
          summaryText: 'Corrida pronta para analise',
        ),
        iOS: _buildPremiumDarwinDetails(
          subtitle: 'Nova oferta de corrida',
          threadIdentifier: 'uber-trip-offers',
        ),
      ),
      payload: jsonEncode({
        'type': 'uber_trip_offer',
        'trip_id': tripId,
        'id': tripId,
        ...trip,
      }),
    );
  }

  Future<void> showUberTripStatusNotification({
    required String tripId,
    required String title,
    required String body,
    required String type,
  }) async {
    if (kIsWeb) return;

    if (type == 'uber_trip_arrived') {
      await AwesomeNotificationService.instance.showPremiumDriverArrived(
        tripId: tripId,
        title: title,
        body: body,
      );
      await _scheduleTripWaitReminder(tripId);
      return;
    }

    if (type == 'uber_trip_started' ||
        type == 'uber_trip_completed' ||
        type == 'uber_trip_cancelled') {
      await _cancelTripWaitReminder(tripId);
    }

    await _localNotifications.show(
      id: tripId.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: _buildPremiumAndroidDetails(
          channelId: _uberUpdatesChannelId,
          channelName: 'Uber: Atualizações de Corrida',
          title: title,
          body: body,
          category: AndroidNotificationCategory.status,
          importance: Importance.high,
          priority: Priority.high,
          subText: 'Sua corrida',
          summaryText: _resolveStatusSummary(type),
        ),
        iOS: _buildPremiumDarwinDetails(
          subtitle: _resolveStatusSummary(type),
          threadIdentifier: 'uber-trip-updates',
        ),
      ),
      payload: jsonEncode({'type': type, 'trip_id': tripId, 'id': tripId}),
    );
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final type = message.data['type']?.toString();

    if (_isUberTripType(type)) {
      final tripId =
          message.data['trip_id']?.toString() ?? message.data['id']?.toString();
      if (tripId == null || tripId.isEmpty) return;

      final title =
          notification?.title ??
          message.data['title']?.toString() ??
          _defaultUberTitle(type);
      final body =
          notification?.body ??
          message.data['body']?.toString() ??
          _defaultUberBody(type);

      await showUberTripStatusNotification(
        tripId: tripId,
        title: title,
        body: body,
        type: type ?? 'uber_trip_accepted',
      );
      return;
    }

    final android = message.notification?.android;

    if (notification != null && android != null) {
      AndroidBitmap<Object>? largeIcon;

      final String? imageUrl = message.data['image'] ?? android.imageUrl;

      if (imageUrl != null &&
          imageUrl.trim().isNotEmpty &&
          imageUrl.startsWith('http') &&
          imageUrl != 'null') {
        try {
          final response = await http
              .get(Uri.parse(imageUrl.trim()))
              .timeout(const Duration(seconds: 4));
          if (response.statusCode == 200) {
            largeIcon = ByteArrayAndroidBitmap(response.bodyBytes);
          }
        } catch (e) {
          debugPrint('⚠️ [NotificationService] Falha ao baixar imagem: $e');
        }
      }

      largeIcon ??= const DrawableResourceAndroidBitmap('ic_logo_colored');

      await _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: _buildPremiumAndroidDetails(
            channelId: _resolveAndroidChannelId(
              message.data['type']?.toString(),
            ),
            channelName: _resolveAndroidChannelName(
              message.data['type']?.toString(),
            ),
            title: notification.title ?? '',
            body: notification.body ?? '',
            category: _resolveAndroidCategory(message.data['type']?.toString()),
            importance: _resolveAndroidImportance(
              message.data['type']?.toString(),
            ),
            priority: _resolveAndroidPriority(message.data['type']?.toString()),
            fullScreenIntent: _shouldUseFullScreenIntent(
              message.data['type']?.toString(),
            ),
            timeoutAfter: _resolveTimeout(message.data['type']?.toString()),
            largeIcon: largeIcon,
            subText: _resolveSubText(message.data['type']?.toString()),
            summaryText: _resolveStatusSummary(
              message.data['type']?.toString(),
            ),
          ),
          iOS: _buildPremiumDarwinDetails(
            subtitle: _resolveSubText(message.data['type']?.toString()),
            threadIdentifier: _resolveIosThreadId(
              message.data['type']?.toString(),
            ),
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  void _startPersistentNotification(String serviceId, RemoteMessage message) {
    debugPrint(
      '🔔 [PERSISTENT] Starting persistent notifications for service $serviceId',
    );
    _activeServiceNotifications.add(serviceId);
    _updateBadgeCount();

    _persistentNotificationTimer?.cancel();

    int repeatCount = 0;
    const maxRepeats = 3;

    _persistentNotificationTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      if (!_activeServiceNotifications.contains(serviceId)) {
        timer.cancel();
        return;
      }

      repeatCount++;

      if (repeatCount >= maxRepeats) {
        timer.cancel();
        _activeServiceNotifications.remove(serviceId);
        _updateBadgeCount();
        return;
      }

      await _playNotificationAlert();
      await _showLocalNotification(message);
    });
  }

  void stopPersistentNotification(String serviceId) {
    debugPrint('🛑 [PERSISTENT] Stopping notifications for service $serviceId');
    _activeServiceNotifications.remove(serviceId);
    _updateBadgeCount();

    if (_activeServiceNotifications.isEmpty) {
      _persistentNotificationTimer?.cancel();
      _persistentNotificationTimer = null;
    }
  }

  void _updateBadgeCount() {
    _notificationCount = _activeServiceNotifications.length;

    if (!kIsWeb && _notificationCount > 0) {
      _localNotifications.show(
        id: 9998,
        title: null,
        body: null,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'badge_channel',
            'Badge Channel',
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            onlyAlertOnce: true,
            number: 0,
          ),
        ),
      );
    }
  }

  Future<void> _playNotificationAlert() async {
    if (!kIsWeb) {
      HapticFeedback.heavyImpact();
      await _localNotifications.show(
        id: 9999,
        title: null,
        body: null,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'alert_sound_channel',
            'Alert Sounds',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
            onlyAlertOnce: false,
            visibility: NotificationVisibility.secret,
          ),
        ),
      );
    }
  }

  void _handleForceLogout() {
    ApiService().clearToken();
    navigatorKey?.currentState?.pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
    _showDialogSafe(
      AlertDialog(
        title: const Text('Sessão Encerrada'),
        content: const Text(
          'Você conectou em outro dispositivo. Por segurança, esta sessão foi finalizada.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (navigatorKey?.currentContext != null) {
                Navigator.of(navigatorKey!.currentContext!).pop();
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  Future<void> _processBackgroundOffers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final String? payloadStr = prefs.getString('bg_pending_offer');
      final version = prefs.getInt('bg_pending_version') ?? 0;

      if (payloadStr != null && version >= 2) {
        final payload = jsonDecode(payloadStr);
        final data = Map<String, dynamic>.from(payload['data']);
        final serviceId = payload['service_id']?.toString();

        if (serviceId != null) {
          ApiService().logServiceEvent(
            serviceId,
            'DELIVERED',
            'Processado via Foreground (Sync)',
          );
          RealtimeService().handleExternalEvent('new_service', data);
          handleNotificationTap(data);
        }

        await prefs.remove('bg_pending_offer');
        await prefs.remove('bg_pending_version');
      }
    } catch (e) {
      debugPrint(
        '🚨 [NotificationService] Erro ao processar oferta de background: $e',
      );
    }
  }

  /// Cancels all pending notifications
  Future<void> cancelAll() async {
    debugPrint('🗑️ [NOTIFICATION] Clearing all notifications');
    await _localNotifications.cancelAll();
  }

  static AndroidNotificationDetails getUrgentAndroidDetails() {
    return const AndroidNotificationDetails(
      _urgentChannelId,
      'Urgent Alerts',
      channelDescription: 'Canal para novos serviços.',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
      playSound: true,
      visibility: NotificationVisibility.public,
      timeoutAfter: 30000,
    );
  }

  AndroidNotificationDetails _buildPremiumAndroidDetails({
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    required AndroidNotificationCategory category,
    required Importance importance,
    required Priority priority,
    bool fullScreenIntent = false,
    int? timeoutAfter,
    String? subText,
    String? summaryText,
    AndroidBitmap<Object>? largeIcon,
    List<AndroidNotificationAction>? actions,
  }) {
    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: '$channelName com apresentacao premium.',
      importance: importance,
      priority: priority,
      playSound: true,
      icon: 'ic_notification_101',
      largeIcon:
          largeIcon ?? const DrawableResourceAndroidBitmap('ic_logo_colored'),
      color: const Color(0xFFFDE500),
      colorized: true,
      category: category,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: summaryText,
      ),
      subText: subText,
      ticker: title,
      sound: const RawResourceAndroidNotificationSound('iphone_notificacao'),
      visibility: NotificationVisibility.public,
      fullScreenIntent: fullScreenIntent,
      timeoutAfter: timeoutAfter,
      actions: actions,
    );
  }

  DarwinNotificationDetails _buildPremiumDarwinDetails({
    String? subtitle,
    String? threadIdentifier,
  }) {
    return DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      subtitle: subtitle,
      threadIdentifier: threadIdentifier,
    );
  }

  String _resolveAndroidChannelId(String? type) {
    switch (type) {
      case 'uber_trip_offer':
        return _uberOffersChannelId;
      case 'uber_trip_accepted':
      case 'uber_trip_arrived':
      case 'uber_trip_started':
      case 'uber_trip_completed':
      case 'uber_trip_cancelled':
        return _uberUpdatesChannelId;
      case 'chat_message':
        return _chatChannelId;
      default:
        return _urgentChannelId;
    }
  }

  String _resolveAndroidChannelName(String? type) {
    switch (type) {
      case 'uber_trip_offer':
        return 'Uber: Ofertas de Corrida';
      case 'uber_trip_accepted':
      case 'uber_trip_arrived':
      case 'uber_trip_started':
      case 'uber_trip_completed':
      case 'uber_trip_cancelled':
        return 'Uber: Atualizações de Corrida';
      case 'chat_message':
        return 'Mensagens de Chat';
      default:
        return 'High Importance Notifications';
    }
  }

  AndroidNotificationCategory _resolveAndroidCategory(String? type) {
    switch (type) {
      case 'uber_trip_offer':
        return AndroidNotificationCategory.call;
      case 'chat_message':
        return AndroidNotificationCategory.message;
      default:
        return AndroidNotificationCategory.status;
    }
  }

  Importance _resolveAndroidImportance(String? type) {
    switch (type) {
      case 'uber_trip_offer':
        return Importance.max;
      default:
        return Importance.high;
    }
  }

  Priority _resolveAndroidPriority(String? type) {
    switch (type) {
      case 'uber_trip_offer':
        return Priority.max;
      default:
        return Priority.high;
    }
  }

  bool _shouldUseFullScreenIntent(String? type) {
    return type == 'uber_trip_offer';
  }

  int? _resolveTimeout(String? type) {
    return type == 'uber_trip_offer' ? 30000 : null;
  }

  String? _resolveSubText(String? type) {
    switch (type) {
      case 'uber_trip_offer':
        return 'Oferta premium';
      case 'uber_trip_accepted':
      case 'uber_trip_arrived':
      case 'uber_trip_started':
      case 'uber_trip_completed':
      case 'uber_trip_cancelled':
        return 'Sua corrida';
      case 'chat_message':
        return 'Chat em tempo real';
      default:
        return '101 Service';
    }
  }

  String? _resolveIosThreadId(String? type) {
    switch (type) {
      case 'uber_trip_offer':
        return 'uber-trip-offers';
      case 'uber_trip_accepted':
      case 'uber_trip_arrived':
      case 'uber_trip_started':
      case 'uber_trip_completed':
      case 'uber_trip_cancelled':
        return 'uber-trip-updates';
      case 'chat_message':
        return 'chat-messages';
      default:
        return 'service-101';
    }
  }

  String? _resolveStatusSummary(String? type) {
    switch (type) {
      case 'uber_trip_offer':
        return 'Oferta disponivel agora';
      case 'uber_trip_accepted':
        return 'Motorista a caminho';
      case 'uber_trip_arrived':
        return 'Motorista chegou';
      case 'uber_trip_started':
        return 'Corrida em andamento';
      case 'uber_trip_completed':
        return 'Corrida finalizada';
      case 'uber_trip_cancelled':
        return 'Corrida cancelada';
      case 'uber_trip_wait_2m':
        return '2 minutos de espera';
      case 'chat_message':
        return 'Nova mensagem';
      default:
        return null;
    }
  }

  Future<void> _scheduleTripWaitReminder(String tripId) async {
    final scheduledAt = tz.TZDateTime.now(
      tz.local,
    ).add(const Duration(minutes: 2));

    await _localNotifications.zonedSchedule(
      id: _tripReminderNotificationId(tripId),
      title: 'Tempo de espera iniciado',
      body:
          'Ja se passaram 2 minutos de espera. Se precisar, responda ao motorista pelo chat.',
      scheduledDate: scheduledAt,
      notificationDetails: NotificationDetails(
        android: _buildPremiumAndroidDetails(
          channelId: _uberUpdatesChannelId,
          channelName: 'Uber: Atualizações de Corrida',
          title: 'Tempo de espera iniciado',
          body:
              'Ja se passaram 2 minutos de espera. Se precisar, responda ao motorista pelo chat.',
          category: AndroidNotificationCategory.message,
          importance: Importance.high,
          priority: Priority.high,
          subText: 'Atencao',
          summaryText: '2 minutos de espera',
          actions: const [
            AndroidNotificationAction('open_trip', 'Abrir corrida'),
            AndroidNotificationAction(
              'trip_reply',
              'Responder',
              inputs: [
                AndroidNotificationActionInput(label: 'Digite uma resposta'),
              ],
            ),
          ],
        ),
        iOS: _buildPremiumDarwinDetails(
          subtitle: '2 minutos de espera',
          threadIdentifier: 'uber-trip-updates',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: jsonEncode({
        'type': 'uber_trip_wait_2m',
        'trip_id': tripId,
        'id': tripId,
      }),
    );
  }

  Future<void> _cancelTripWaitReminder(String tripId) async {
    await _localNotifications.cancel(id: _tripReminderNotificationId(tripId));
  }

  /// Agendamento legado (mantido como fallback para background)
  Future<void> scheduleTimeToLeave({
    required String serviceId,
    required DateTime leaveAtAt,
    required int travelTimeMin,
    double? lat,
    double? lng,
  }) async {
    if (kIsWeb) return;

    // Evita agendar para o passado
    if (leaveAtAt.isBefore(DateTime.now())) {
      debugPrint(
        '⚠️ [NotificationService] Ignorando agendamento para o passado: $leaveAtAt',
      );
      return;
    }

    final id = serviceId.hashCode;

    await _localNotifications.zonedSchedule(
      id: id,
      title: '🎒 HORA DE SAIR!',
      body:
          'Saia agora para chegar com 3 min de antecedência. Viagem estimada: $travelTimeMin min.',
      scheduledDate: tz.TZDateTime.from(leaveAtAt, tz.local),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'time_to_leave_channel',
          'Alertas de Trânsito',
          channelDescription:
              'Notificações para avisar quando sair para um serviço.',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound(
            'iphone_notificacao',
          ),
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          categoryIdentifier: 'time_to_leave',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: jsonEncode({
        'type': 'time_to_leave',
        'service_id': serviceId,
        'travel_time': travelTimeMin.toString(),
        'lat': lat,
        'lng': lng,
      }),
    );

    AppLogger.notificacao(
      '📅 Alerta de trânsito agendado para $leaveAtAt (ID: $id)',
    );
  }

  /// Dispara o modal de "Hora de Sair" imediatamente (usado pelo polling ativo)
  Future<void> showTimeToLeaveModal(Map<String, dynamic> data) async {
    AppLogger.notificacao('🚀 Disparando Alerta de Saída ATIVO (Polling)');

    // 1. Tocar alerta sonoro
    _playNotificationAlert();

    // 2. Mostrar o modal
    _showDialogSafe(TimeToLeaveModal(data: data), barrierDismissible: false);
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  final NotificationService _service;
  _LifecycleObserver(this._service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _service._processBackgroundOffers();
      _service.syncToken();
    }
  }
}
