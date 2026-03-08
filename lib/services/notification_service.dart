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
import 'data_gateway.dart';
import 'realtime_service.dart';
import '../core/utils/logger.dart';

/// Handler for background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  AppLogger.notificacao(
    'Notificação recebida em BACKGROUND (Isolate separada)',
  );

  final type = message.data['type'];
  final serviceId =
      message.data['id']?.toString() ?? message.data['service_id']?.toString();

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
      type == 'service.offered') {
    debugPrint(
      '🚀 [BACKGROUND DEBUG] Oferta Urgente Detectada. Disparando canais de alta prioridade.',
    );

    final FlutterLocalNotificationsPlugin localNotifications =
        FlutterLocalNotificationsPlugin();

    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidInit);
    await localNotifications.initialize(settings: initSettings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel_v3',
      'Alertas Urgentes',
      description: 'Canal para alertas urgentes de novos serviços.',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
    );

    await localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    final NotificationDetails details = NotificationDetails(
      android: NotificationService.getUrgentAndroidDetails(),
    );

    final String title =
        message.notification?.title ??
        message.data['title']?.toString() ??
        '🔔 Novo Serviço Disponível';

    final String body =
        message.notification?.body ??
        message.data['body']?.toString() ??
        'Você tem uma nova oportunidade de serviço próxima!';

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
void _onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  NotificationService().handleNotificationResponse(response);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

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
          const AndroidNotificationChannel channel = AndroidNotificationChannel(
            'high_importance_channel_v3',
            'Notificações Importantes',
            description:
                'Este canal é usado para notificações urgentes do serviço.',
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
          );

          await _localNotifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.createNotificationChannel(channel);
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
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
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
            final role = ApiService().role;
            debugPrint(
              '🔔🔔🔔 [FOREGROUND] new_service recebido! role=$role, serviceId=$serviceId, _isDialogOpen=$_isDialogOpen',
            );
            if (role != 'provider') {
              debugPrint(
                '⏩ [FOREGROUND] Ignorando new_service — role não é provider ($role)',
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

            // 3. Forçar abertura do modal (resetar bloqueio se necessário)
            _isDialogOpen = false;
            handleNotificationTap(message.data);
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
          'chat_messages_channel',
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
              inputs: [AndroidNotificationActionInput(label: 'Digite sua resposta')],
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

      if (role != null && role != 'provider') return;

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

  void handleNotificationTap(Map<String, dynamic> data) {
    debugPrint('🔔 [NOTIFICATION DEBUG] Handling tap with data: $data');

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (navigatorKey?.currentContext == null) {
        await _getValidContext();
      }

      if (navigatorKey?.currentContext != null) {
        _processNotificationData(data);
      }
    });
  }

  void _processNotificationData(Map<String, dynamic> data) {
    final String? type = data['type']?.toString();
    debugPrint('🔀 [NOTIFICATION TAP] Type detected: $type');

    if (type == 'chat_message' || type == 'chat') {
      final String? serviceId =
          data['id']?.toString() ?? data['service_id']?.toString();
      if (serviceId != null && navigatorKey?.currentContext != null) {
        GoRouter.of(navigatorKey!.currentContext!).push('/chat/$serviceId');
        return;
      }
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
      final role = ApiService().role;
      if (role != 'provider') return;

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
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel_v3',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.max,
          icon: 'ic_notification_101',
          playSound: true,
          largeIcon: DrawableResourceAndroidBitmap('ic_logo_colored'),
          color: Colors.black,
          sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
        ),
      ),
    );
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
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
          android: AndroidNotificationDetails(
            'high_importance_channel_v3',
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            icon: '@mipmap/launcher_icon',
            color: Colors.black,
            largeIcon: largeIcon,
            sound: const RawResourceAndroidNotificationSound(
              'iphone_notificacao',
            ),
            fullScreenIntent: true,
            category: AndroidNotificationCategory.call,
            timeoutAfter: 30000,
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
      'high_importance_channel_v3',
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
