import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:service_101/features/notifications/widgets/time_to_leave_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_theme.dart';
import '../features/client/widgets/provider_arrived_modal.dart';
import '../features/client/widgets/client_wake_up_modal.dart';
import '../features/provider/widgets/scheduled_notification_modal.dart';
import '../features/provider/widgets/service_offer_modal.dart';
import '../core/navigation/notification_action_resolver.dart';
import '../core/navigation/notification_navigation_resolver.dart';
import '../firebase_options.dart';
import 'api_service.dart';
import 'awesome_notification_service.dart';
import 'data_gateway.dart';
import 'realtime_service.dart';
import 'service_tracking_bus.dart';
import 'models/notification_payload.dart';
import 'models/notification_dispatch_request.dart';
import 'support/notification_dispatcher.dart';
import 'support/service_offer_notification_coordinator.dart';
import 'support/service_offer_notification_handler.dart';
import 'support/service_offer_notification_flow.dart';
import 'support/service_offer_pending_processor.dart';
import 'support/service_offer_notification_presentation.dart';
import '../core/utils/logger.dart';
import '../core/utils/notification_type_helper.dart';
import '../features/shared/chat_screen.dart';

const String _urgentChannelIdBg = 'high_importance_channel_v5';
const String _serviceOfferChannelIdBg = 'central_trip_offers_channel_v3';
const String _serviceStatusChannelIdBg = 'central_trip_updates_channel_v3';
const String _chatChannelIdBg = 'chat_messages_channel_v3';
const String _paymentChannelIdBg = 'payment_updates_channel_v2';
const String _scheduleProposalChannelIdBg = 'schedule_proposals_channel_v1';

const String _androidOrderSoundKey = 'notification_order';
const String _androidMessageSoundKey = 'notification_message';
const String _androidPaymentSoundKey = 'notification_payment';

const String _iosOrderSoundName = 'notification_order.caf';
const String _iosMessageSoundName = 'notification_message.caf';
const String _iosPaymentSoundName = 'notification_payment.caf';
bool _isServiceOfferType(String? type) {
  return isServiceOfferNotificationType(type);
}

bool _isPaymentNotificationType(String? type) {
  if (type == null) return false;
  return type == 'payment_approved' ||
      type == 'payment_received' ||
      type == 'payment_confirmed' ||
      type == 'payment_pending' ||
      type == 'payment_failed' ||
      type == 'payment_released' ||
      type.startsWith('payment_');
}

bool _isScheduleProposalNotificationType(String? type) {
  if (type == null) return false;
  final normalized = type.toLowerCase().trim();
  return normalized == 'schedule_proposal' ||
      normalized == 'schedule_proposal_expired';
}

String _normalizeNotificationType(String? type) {
  if (type == null) return 'unknown';
  // Normaliza o tipo de notificação para um formato padrão
  final normalized = type.toLowerCase().trim();
  // Mapeia tipos antigos para novos
  if (normalized.contains('trip') || normalized.contains('corrid')) {
    return 'central_trip_offer';
  }
  if (normalized.contains('service') || normalized.contains('servico')) {
    return 'service_offer';
  }
  if (normalized.contains('payment') || normalized.contains('pagamento')) {
    return 'payment_status';
  }
  if (normalized.contains('chat') || normalized.contains('message')) {
    return 'chat_message';
  }
  return normalized;
}

bool _isLegacyTripType(String? type) {
  if (type == null) return false;
  final normalized = type.toLowerCase();
  return normalized.contains('trip') ||
      normalized.contains('corrid') ||
      normalized.contains('central_trip') ||
      normalized == 'new_trip' ||
      normalized == 'trip_offer';
}

String _resolveAndroidSoundKey(String? type) {
  type = _normalizeNotificationType(type);
  if (_isPaymentNotificationType(type)) {
    return _androidPaymentSoundKey;
  }
  if (_isScheduleProposalNotificationType(type)) {
    return _androidOrderSoundKey;
  }
  if (_isServiceOfferType(type) || type == 'central_trip_offer') {
    return _androidOrderSoundKey;
  }
  return _androidMessageSoundKey;
}

String _resolveIosSoundName(String? type) {
  type = _normalizeNotificationType(type);
  if (_isPaymentNotificationType(type)) {
    return _iosPaymentSoundName;
  }
  if (_isScheduleProposalNotificationType(type)) {
    return _iosOrderSoundName;
  }
  if (_isServiceOfferType(type) || type == 'central_trip_offer') {
    return _iosOrderSoundName;
  }
  return _iosMessageSoundName;
}

int _tripReminderNotificationId(String tripId) => tripId.hashCode ^ 0x2F2F;

String _defaultLegacyTripTitle(String? type) {
  switch (type) {
    case 'central_trip_offer':
      return 'Nova oferta de atendimento disponivel';
    case 'central_trip_accepted':
      return 'Motorista a caminho';
    case 'central_trip_arrived':
      return 'Motorista chegou';
    case 'central_trip_started':
      return 'Corrida iniciada';
    case 'central_trip_completed':
      return 'Atendimento concluido';
    case 'central_trip_cancelled':
      return 'Atendimento cancelado';
    case 'central_trip_wait_2m':
      return 'Tempo de espera iniciado';
    default:
      return 'Atualizacao do atendimento';
  }
}

String _defaultLegacyTripBody(String? type) {
  switch (type) {
    case 'central_trip_offer':
      return 'Toque para revisar a oferta e decidir agora.';
    case 'central_trip_accepted':
      return 'Seu parceiro aceitou a solicitacao e esta indo ate voce.';
    case 'central_trip_arrived':
      return 'Seu prestador ja esta no local combinado.';
    case 'central_trip_started':
      return 'Sua viagem comecou.';
    case 'central_trip_completed':
      return 'Seu atendimento foi finalizado.';
    case 'central_trip_cancelled':
      return 'O atendimento foi cancelado.';
    case 'central_trip_wait_2m':
      return 'Ja se passaram 2 minutos de espera. Se precisar, responda ao prestador pelo chat.';
    default:
      return 'Voce recebeu uma atualizacao importante do seu atendimento.';
  }
}

String _composeArrivedNotificationBody(
  String baseBody, {
  String? driverName,
  String? vehicleModel,
  String? vehicleColor,
  String? vehiclePlate,
}) {
  // Se o baseBody parece ser apenas info do carro enviada pelo servidor, ignoramos para evitar duplicidade
  final isRedundant = baseBody.contains('•') || baseBody.contains('Placa:');
  final buffer = StringBuffer(isRedundant ? '' : baseBody);

  final hasDriverName = (driverName ?? '').trim().isNotEmpty;
  final hasVehicleModel = (vehicleModel ?? '').trim().isNotEmpty;
  final hasVehicleColor = (vehicleColor ?? '').trim().isNotEmpty;
  final hasVehiclePlate = (vehiclePlate ?? '').trim().isNotEmpty;

  if (hasDriverName || hasVehicleModel || hasVehicleColor || hasVehiclePlate) {
    buffer.write('\n\n');

    if (hasDriverName) {
      buffer.write('Motorista: ${driverName!.trim()}');
    }

    if (hasVehicleModel || hasVehicleColor || hasVehiclePlate) {
      if (hasDriverName) buffer.write('\n');
      final vehicleLabel = [
        if (hasVehicleModel) vehicleModel!.trim(),
        if (hasVehicleColor) vehicleColor!.trim(),
        if (hasVehiclePlate) vehiclePlate!.trim(),
      ].join(' • ');
      buffer.write('Veiculo: $vehicleLabel');
    }
  }

  buffer.write(
    '\n\nApos 2 minutos de espera, taxas de espera podem ser cobradas.',
  );

  return buffer.toString();
}

String _composeAcceptedNotificationBody(
  String baseBody, {
  String? driverName,
  String? vehicleModel,
  String? vehicleColor,
  String? vehiclePlate,
}) {
  // Se o baseBody parece ser apenas info do carro enviada pelo servidor, ignoramos para evitar duplicidade
  final isRedundant = baseBody.contains('•') || baseBody.contains('Placa:');
  final buffer = StringBuffer(isRedundant ? '' : baseBody);

  final hasDriverName = (driverName ?? '').trim().isNotEmpty;

  final vehicleLabel = [
    if ((vehicleModel ?? '').trim().isNotEmpty) vehicleModel!.trim(),
    if ((vehicleColor ?? '').trim().isNotEmpty) vehicleColor!.trim(),
  ].join(' • ');
  final plate = (vehiclePlate ?? '').trim();

  if (hasDriverName || vehicleLabel.isNotEmpty || plate.isNotEmpty) {
    buffer.write('\n\n');

    if (hasDriverName) {
      buffer.write('Motorista: ${driverName!.trim()}');
    }

    if (vehicleLabel.isNotEmpty) {
      if (hasDriverName) buffer.write('\n');
      buffer.write(vehicleLabel);
    }

    if (plate.isNotEmpty) {
      if (hasDriverName || vehicleLabel.isNotEmpty) buffer.write('\n');
      buffer.write('Placa: $plate');
    }
  }

  return buffer.toString();
}

AndroidNotificationDetails _buildBackgroundArrivedDetails() {
  return const AndroidNotificationDetails(
    _serviceStatusChannelIdBg,
    'Atualizacoes de atendimento',
    channelDescription: 'Atualizacoes de status dos atendimentos do app.',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    icon: 'ic_notification_small',
    largeIcon: DrawableResourceAndroidBitmap('ic_logo_colored'),
    color: Color(0xFFFDE500),
    colorized: true,
    category: AndroidNotificationCategory.message,
    sound: RawResourceAndroidNotificationSound(_androidMessageSoundKey),
    visibility: NotificationVisibility.public,
    actions: [
      AndroidNotificationAction('open_trip', 'Abrir atendimento'),
      AndroidNotificationAction(
        'trip_reply',
        'Responder',
        inputs: [AndroidNotificationActionInput(label: 'Digite uma resposta')],
      ),
    ],
  );
}

AndroidNotificationDetails _buildBackgroundLegacyTripStatusDetails({
  required String type,
  required String title,
  required String body,
}) {
  return AndroidNotificationDetails(
    type == 'central_trip_offer'
        ? _serviceOfferChannelIdBg
        : _serviceStatusChannelIdBg,
    type == 'central_trip_offer'
        ? 'Ofertas de atendimento'
        : 'Atualizacoes de atendimento',
    channelDescription: 'Notificacoes premium do fluxo legado de atendimento.',
    importance: type == 'central_trip_offer' ? Importance.max : Importance.high,
    priority: type == 'central_trip_offer' ? Priority.max : Priority.high,
    playSound: true,
    icon: 'ic_notification_small',
    largeIcon: const DrawableResourceAndroidBitmap('ic_logo_colored'),
    color: const Color(0xFFFDE500),
    colorized: true,
    category: type == 'central_trip_offer'
        ? AndroidNotificationCategory.call
        : AndroidNotificationCategory.status,
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: title,
      summaryText: '101 Service',
    ),
    sound: const RawResourceAndroidNotificationSound(_androidMessageSoundKey),
    visibility: NotificationVisibility.public,
    fullScreenIntent: type == 'central_trip_offer',
    timeoutAfter: type == 'central_trip_offer' ? 30000 : null,
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
      android: _buildBackgroundArrivedDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: jsonEncode({
      'type': 'central_trip_wait_2m',
      'trip_id': tripId,
      'id': tripId,
    }),
  );
}

/// Handler for background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Required so plugins (ex: shared_preferences) work in background isolate.
  // Without this, you'll see MissingPluginException on Android.
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  AppLogger.notificacao(
    'Notificação recebida em BACKGROUND (Isolate separada)',
  );

  final type = message.data['type'];
  // IMPORTANTE:
  // `service_logs` tem FK para `service_requests_new`. Não usar `trip_id` aqui.
  final serviceId =
      message.data['id']?.toString() ?? message.data['service_id']?.toString();
  final tripId = message.data['trip_id']?.toString();

  // ✅ SALVAR PAYLOAD PARA PROCESSAMENTO NA ISOLATE PRINCIPAL (Foreground)
  if (serviceId != null || tripId != null) {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'data': message.data,
        'received_at': DateTime.now().toIso8601String(),
        'service_id': serviceId,
        'trip_id': tripId,
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
    } on MissingPluginException catch (e) {
      // Some Flutter versions/builds do not register shared_preferences in background isolates.
      // In that case, we still show the urgent notification and rely on the tap payload.
      AppLogger.erro('SharedPreferences indisponível em background isolate', e);
    } catch (e) {
      AppLogger.erro('Erro ao salvar payload em background', e);
    }
  }

  // ✅ GERAR NOTIFICAÇÃO LOCAL URGENTE (Para acordar o dispositivo)
  final normalizedType = _normalizeNotificationType(type?.toString());
  if (_isServiceOfferType(normalizedType) ||
      isLegacyTripNotificationType(normalizedType)) {
    debugPrint(
      '🚀 [BACKGROUND DEBUG] Oferta Urgente Detectada. Disparando canais de alta prioridade.',
    );

    final FlutterLocalNotificationsPlugin localNotifications =
        FlutterLocalNotificationsPlugin();

    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_notification_small',
    );
    const initSettings = InitializationSettings(android: androidInit);
    await localNotifications.initialize(settings: initSettings);

    const channels = [
      AndroidNotificationChannel(
        _urgentChannelIdBg,
        'Alertas Urgentes',
        description: 'Canal para alertas urgentes de novos serviços.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_androidMessageSoundKey),
      ),
      AndroidNotificationChannel(
        _serviceOfferChannelIdBg,
        'Ofertas de atendimento',
        description: 'Ofertas urgentes de atendimento do fluxo legado.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_androidOrderSoundKey),
      ),
      AndroidNotificationChannel(
        _serviceStatusChannelIdBg,
        'Atualizacoes de atendimento',
        description: 'Atualizacoes de status do fluxo legado de atendimento.',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_androidMessageSoundKey),
      ),
      AndroidNotificationChannel(
        _chatChannelIdBg,
        'Mensagens de Chat',
        description: 'Mensagens de chat em tempo real.',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_androidMessageSoundKey),
      ),
      AndroidNotificationChannel(
        _paymentChannelIdBg,
        'Pagamentos',
        description: 'Atualizacoes e confirmacoes de pagamento.',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_androidPaymentSoundKey),
      ),
      AndroidNotificationChannel(
        _scheduleProposalChannelIdBg,
        'Propostas de agendamento',
        description:
            'Alertas de negociacao de horario entre cliente e prestador.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_androidOrderSoundKey),
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
        (isLegacyTripNotificationType(type)
            ? _defaultLegacyTripTitle(type?.toString())
            : 'Novo Servico Disponivel');

    final String body =
        message.notification?.body ??
        message.data['body']?.toString() ??
        (isLegacyTripNotificationType(type)
            ? _defaultLegacyTripBody(type?.toString())
            : 'Voce tem uma nova oportunidade de servico proxima!');

    if (_isServiceOfferType(normalizedType) && serviceId != null) {
      try {
        await AwesomeNotificationService.instance.initialize();
        await AwesomeNotificationService.instance.showServiceOfferFullScreen(
          serviceId: serviceId,
          title: title,
          body: body,
          payload: message.data.map(
            (key, value) => MapEntry(key, value.toString()),
          ),
        );
        debugPrint(
          '🚀 [BACKGROUND DEBUG] Awesome full-screen offer disparado para serviceId=$serviceId',
        );
        return;
      } catch (e) {
        debugPrint(
          '⚠️ [BACKGROUND DEBUG] Falha ao usar Awesome full-screen offer: $e',
        );
      }
    }

    if ((type == 'central_trip_arrived' || type == 'central_trip_accepted') &&
        (tripId ?? serviceId) != null) {
      final uberTripId = (tripId ?? serviceId)!;
      final richBody = type == 'central_trip_arrived'
          ? _composeArrivedNotificationBody(
              body,
              driverName: message.data['driver_name']?.toString(),
              vehicleModel: message.data['vehicle_model']?.toString(),
              vehicleColor: message.data['vehicle_color']?.toString(),
              vehiclePlate: message.data['vehicle_plate']?.toString(),
            )
          : _composeAcceptedNotificationBody(
              body,
              driverName: message.data['driver_name']?.toString(),
              vehicleModel: message.data['vehicle_model']?.toString(),
              vehicleColor: message.data['vehicle_color']?.toString(),
              vehiclePlate: message.data['vehicle_plate']?.toString(),
            );

      await localNotifications.show(
        id: uberTripId.hashCode,
        title: title,
        body: richBody,
        notificationDetails: NotificationDetails(
          android: type == 'central_trip_arrived'
              ? _buildBackgroundArrivedDetails()
              : _buildBackgroundLegacyTripStatusDetails(
                  type: type?.toString() ?? 'central_trip_accepted',
                  title: title,
                  body: richBody,
                ),
        ),
        payload: jsonEncode({
          ...message.data,
          'trip_id': uberTripId,
          'id': uberTripId,
        }),
      );

      if (type == 'central_trip_arrived') {
        await _scheduleTripWaitReminderBackground(
          localNotifications,
          uberTripId,
        );
      }
      return;
    }

    if (_isLegacyTripType(type) && (tripId ?? serviceId) != null) {
      final uberTripId = (tripId ?? serviceId)!;
      if (type == 'central_trip_started' ||
          type == 'central_trip_completed' ||
          type == 'central_trip_cancelled') {
        await localNotifications.cancel(
          id: _tripReminderNotificationId(uberTripId),
        );
      }

      await localNotifications.show(
        id: uberTripId.hashCode,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: _buildBackgroundLegacyTripStatusDetails(
            type: type.toString(),
            title: title,
            body: body,
          ),
        ),
        payload: jsonEncode({
          ...message.data,
          'trip_id': uberTripId,
          'id': uberTripId,
        }),
      );
      return;
    }

    // ✅ CALCULAR ID DINÂMICO PARA EVITAR SOBRESCRITA
    final int notificationId = (serviceId ?? tripId ?? type ?? '0').hashCode;

    final NotificationDetails details = NotificationDetails(
      android: type == 'chat_message'
          ? const AndroidNotificationDetails(
              _chatChannelIdBg,
              'Mensagens de Chat',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('iphone_notificacao'),
            )
          : NotificationService.getUrgentAndroidDetails(),
    );

    // ✅ LOG DE ENTREGA PARA CHAT
    if (type == 'chat_message' && serviceId != null) {
      ApiService().logServiceEvent(serviceId, 'DELIVERED', 'Background (Sync)');
    }

    final notificationService = NotificationService();

    await localNotifications.show(
      id: notificationId,
      title: _isServiceOfferType(type?.toString())
          ? notificationService._composeServiceOfferTitle(message.data, title)
          : title,
      body: _isServiceOfferType(type?.toString())
          ? notificationService._composeServiceOfferBody(message.data, body)
          : body,
      notificationDetails: _isServiceOfferType(type?.toString())
          ? NotificationDetails(
              android: notificationService._buildPremiumAndroidDetails(
                channelId: notificationService._resolveAndroidChannelId(
                  type?.toString(),
                ),
                channelName: notificationService._resolveAndroidChannelName(
                  type?.toString(),
                ),
                title: notificationService._composeServiceOfferTitle(
                  message.data,
                  title,
                ),
                body: notificationService._composeServiceOfferBody(
                  message.data,
                  body,
                ),
                category: notificationService._resolveAndroidCategory(
                  type?.toString(),
                ),
                importance: notificationService._resolveAndroidImportance(
                  type?.toString(),
                ),
                priority: notificationService._resolveAndroidPriority(
                  type?.toString(),
                ),
                fullScreenIntent: notificationService
                    ._shouldUseFullScreenIntent(type?.toString()),
                timeoutAfter: notificationService._resolveTimeout(
                  type?.toString(),
                ),
                subText: 'Responder rapido',
                summaryText: 'Nova oportunidade perto de voce',
                actions: notificationService._buildServiceOfferActions(),
              ),
            )
          : details,
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
  static const bool _tripRuntimeEnabled = false;
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _urgentChannelId = 'high_importance_channel_v5';
  static const String _serviceOfferChannelId = 'central_trip_offers_channel_v3';
  static const String _serviceStatusChannelId =
      'central_trip_updates_channel_v3';
  static const String _chatChannelId = 'chat_messages_channel_v3';
  static const String _paymentChannelId = 'payment_updates_channel_v2';
  static const String _scheduleProposalChannelId =
      'schedule_proposals_channel_v1';

  // VAPID key via --dart-define=VAPID_KEY=... em produção
  // ou via .env em desenvolvimento (lida pelo SupabaseConfig)
  static const String _vapidKey = String.fromEnvironment('VAPID_KEY');

  FirebaseMessaging? get _fcm {
    try {
      if (Firebase.apps.isNotEmpty) return FirebaseMessaging.instance;
    } catch (_) {}
    return null;
  }

  bool get _shouldSkipWebPushOnCurrentHost {
    if (!kIsWeb) return false;
    final host = Uri.base.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  bool get _shouldSkipWebPush {
    if (!kIsWeb) return false;
    return _shouldSkipWebPushOnCurrentHost || _vapidKey.trim().isEmpty;
  }

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  late final NotificationDispatcher _dispatcher = NotificationDispatcher(
    localNotifications: _localNotifications,
  );
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isInitialized = false;
  bool _isInitializing = false; // Evita inicialização duplicada
  bool _notificationsEnabled =
      false; // Track se notificações locais estão disponíveis
  GlobalKey<NavigatorState>? navigatorKey;
  bool _isDialogOpen = false;
  String? _activeDialogKey;
  DateTime? _activeDialogOpenedAt;
  String? _activeSheetKey;
  DateTime? _activeSheetOpenedAt;

  // Persistent notifications management
  final Set<String> _activeServiceNotifications = {};
  Timer? _persistentNotificationTimer;
  Timer? _pendingOfferRetryTimer;
  int _notificationCount = 0;
  String? _lastNavigationKey;
  DateTime? _lastNavigationAt;
  String? _lastOfferPresentationKey;
  DateTime? _lastOfferPresentationAt;
  _LifecycleObserver? _lifecycleObserver;
  bool _backgroundOffersProcessed = false;

  // Subscription management
  final List<StreamSubscription> _subscriptions = [];

  Future<void> init(GlobalKey<NavigatorState> navKey) async {
    navigatorKey = navKey;
    AwesomeNotificationService.instance.setActionHandler((data) async {
      handleNotificationTap(data);
    });

    if (_isInitialized) {
      if (_lifecycleObserver == null) {
        _lifecycleObserver = _LifecycleObserver(this);
        WidgetsBinding.instance.addObserver(_lifecycleObserver!);
      }
      if (!_backgroundOffersProcessed) {
        _backgroundOffersProcessed = true;
        _processBackgroundOffers();
      }
      return;
    }

    try {
      await initialize();
    } catch (e) {
      AppLogger.erro('Falha ao inicializar notificações', e);
    }
    if (!_backgroundOffersProcessed) {
      _backgroundOffersProcessed = true;
      _processBackgroundOffers();
    }

    // Listen to lifecycle changes to check when app resumes from background
    _lifecycleObserver ??= _LifecycleObserver(this);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  String _composeServiceOfferTitle(Map<String, dynamic> data, String fallback) {
    bool isGenericOfferTitle(String value) {
      final normalizedLower = value
          .trim()
          .toLowerCase()
          .replaceAll('á', 'a')
          .replaceAll('à', 'a')
          .replaceAll('ã', 'a')
          .replaceAll('â', 'a')
          .replaceAll('é', 'e')
          .replaceAll('ê', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ô', 'o')
          .replaceAll('õ', 'o')
          .replaceAll('ú', 'u');
      return normalizedLower == 'responda rapido' ||
          normalizedLower == 'responda rapido!' ||
          normalizedLower == 'nova oferta de servico';
    }

    final serviceName = data['service_name']?.toString().trim() ?? '';
    if (serviceName.isNotEmpty && !isGenericOfferTitle(serviceName)) {
      return serviceName;
    }

    final payloadTitle = data['title']?.toString().trim() ?? '';
    if (payloadTitle.isNotEmpty && !isGenericOfferTitle(payloadTitle)) {
      return payloadTitle;
    }

    final normalizedFallback = fallback.trim();
    return normalizedFallback.isNotEmpty &&
            !isGenericOfferTitle(normalizedFallback)
        ? normalizedFallback
        : 'Nova solicitação de serviço';
  }

  String _composeServiceOfferBody(Map<String, dynamic> data, String fallback) {
    final gainRaw =
        data['price_provider']?.toString().trim() ??
        data['provider_amount']?.toString().trim() ??
        '';
    final minutesRaw =
        data['estimated_minutes']?.toString().trim() ??
        data['travel_minutes']?.toString().trim() ??
        '';
    final distanceRaw =
        data['distance_km']?.toString().trim() ??
        data['distance']?.toString().trim() ??
        '';

    final lines = <String>[];
    if (gainRaw.isNotEmpty) {
      lines.add('Ganhe R\$ $gainRaw');
    }

    final travelParts = <String>[];
    if (minutesRaw.isNotEmpty) {
      travelParts.add('Chegada em ~$minutesRaw min');
    }
    if (distanceRaw.isNotEmpty) {
      travelParts.add(
        distanceRaw.contains('km') ? distanceRaw : '$distanceRaw km',
      );
    }
    if (travelParts.isNotEmpty) {
      lines.add(travelParts.join(' • '));
    }

    lines.add('Toque para revisar e responder.');

    return lines.length >= 2 && gainRaw.isNotEmpty
        ? lines.join('\n')
        : (fallback.trim().isNotEmpty
              ? fallback
              : 'Voce tem uma nova solicitacao de servico proxima.');
  }

  List<AndroidNotificationAction> _buildServiceOfferActions() {
    return const [
      AndroidNotificationAction(
        'service_reject',
        'Recusar',
        cancelNotification: false,
        showsUserInterface: false,
      ),
      AndroidNotificationAction(
        'service_accept',
        'Aceitar',
        cancelNotification: true,
        showsUserInterface: false,
      ),
    ];
  }

  Future<void> _handleServiceOfferAction(Map<String, dynamic> data) async {
    final action = data['notification_action']?.toString().trim() ?? '';
    final type = data['type']?.toString().trim() ?? '';
    final serviceId =
        data['service_id']?.toString().trim() ??
        data['id']?.toString().trim() ??
        '';
    if (action.isEmpty || serviceId.isEmpty) return;

    try {
      if (type == 'manual_visual_test') {
        await _localNotifications.cancel(id: serviceId.hashCode);
        if (navigatorKey?.currentContext != null) {
          final label = action == 'service_accept' ? 'Aceitar' : 'Recusar';
          ScaffoldMessenger.of(navigatorKey!.currentContext!).showSnackBar(
            SnackBar(
              content: Text('Ação simulada no push de teste: $label'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      if (action == 'service_accept') {
        await ApiService().dispatch.acceptService(serviceId);
        stopPersistentNotification(serviceId);
        await _localNotifications.cancel(id: serviceId.hashCode);
        final ctx = navigatorKey?.currentContext ?? await _getValidContext();
        if (ctx != null) {
          _navigateToNotificationTarget(
            NotificationNavigationResolver.providerAcceptedService(
              serviceId: serviceId,
            ),
          );
        }
        return;
      }

      if (action == 'service_reject') {
        try {
          await ApiService().dispatch.rejectService(serviceId);
        } on ApiException catch (e) {
          if (e.statusCode != 409) rethrow;
          debugPrint(
            'ℹ️ [NotificationService] Oferta $serviceId já não aceitava recusa; limpando notificação local.',
          );
        }
        stopPersistentNotification(serviceId);
        await _localNotifications.cancel(id: serviceId.hashCode);
        if (navigatorKey?.currentContext != null) {
          ScaffoldMessenger.of(navigatorKey!.currentContext!).showSnackBar(
            SnackBar(
              content: Text(
                action == 'service_reject'
                    ? 'Oferta removida da lista.'
                    : 'Oferta recusada com sucesso.',
              ),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint(
        '⚠️ [NotificationService] Falha ao processar ação da oferta ($action) para $serviceId: $e',
      );
      if (navigatorKey?.currentContext != null) {
        ScaffoldMessenger.of(navigatorKey!.currentContext!).showSnackBar(
          SnackBar(
            content: Text('Nao foi possivel concluir a acao: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Request permissions specifically for providers (Overlay, etc)
  Future<void> requestProviderPermissions() async {
    if (!kIsWeb && Platform.isAndroid) {
      AppLogger.sistema(
        'Release Play: alertas especiais de overlay/full-screen foram desativados. O app usa notificações padrão do Android.',
      );
    }
  }

  Future<bool> requestFullScreenIntentPermission() async {
    return false;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_isInitializing) {
      debugPrint('NotificationService: Already initializing, skipping...');
      return;
    }
    _isInitializing = true;

    try {
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
      if (_fcm != null && !_shouldSkipWebPush) {
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
      } else if (_shouldSkipWebPush) {
        final reason = _shouldSkipWebPushOnCurrentHost
            ? 'localhost para evitar 403 de referer nas instalacoes do Firebase'
            : 'VAPID_KEY ausente no build web';
        debugPrint('NotificationService: Web Push/FCM desativado em $reason.');
      }

      // 2. Setup Local Notifications
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          const androidSettings = AndroidInitializationSettings(
            '@drawable/ic_notification_small',
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
              sound: RawResourceAndroidNotificationSound(
                _androidMessageSoundKey,
              ),
            ),
            AndroidNotificationChannel(
              _serviceOfferChannelId,
              'Ofertas de atendimento',
              description: 'Ofertas urgentes do fluxo legado de atendimento.',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound(_androidOrderSoundKey),
            ),
            AndroidNotificationChannel(
              _serviceStatusChannelId,
              'Atualizações de atendimento',
              description:
                  'Atualizações de status do fluxo legado de atendimento.',
              importance: Importance.high,
              playSound: true,
              sound: RawResourceAndroidNotificationSound(
                _androidMessageSoundKey,
              ),
            ),
            AndroidNotificationChannel(
              _chatChannelId,
              'Mensagens de Chat',
              description: 'Mensagens de chat em tempo real.',
              importance: Importance.high,
              playSound: true,
              sound: RawResourceAndroidNotificationSound(
                _androidMessageSoundKey,
              ),
            ),
            AndroidNotificationChannel(
              _paymentChannelId,
              'Pagamentos',
              description: 'Atualizações e confirmações de pagamento.',
              importance: Importance.high,
              playSound: true,
              sound: RawResourceAndroidNotificationSound(
                _androidPaymentSoundKey,
              ),
            ),
            AndroidNotificationChannel(
              _scheduleProposalChannelId,
              'Propostas de agendamento',
              description:
                  'Alertas de negociação de horário entre cliente e prestador.',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound(_androidOrderSoundKey),
            ),
            AndroidNotificationChannel(
              'service_offers_channel_v2',
              'Ofertas de Serviço',
              description: 'Canal específico para o som de chamado.',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('chamado'),
            ),
          ];

          for (final channel in channels) {
            await androidPlugin?.createNotificationChannel(channel);
          }

          if (initialized == true) {
            _notificationsEnabled = true;
          } else if (Platform.isAndroid && androidPlugin != null) {
            _notificationsEnabled = true;
            AppLogger.sistema(
              'LocalNotifications retornou false no Android, mas o plugin nativo está disponível; seguindo com fallback compatível.',
            );
          } else {
            _notificationsEnabled = false;
            AppLogger.erro(
              'Falha ao inicializar LocalNotifications (retornou false)',
            );
          }
        } catch (e) {
          _notificationsEnabled = false;
          AppLogger.erro('Erro fatal ao configurar LocalNotifications', e);
        }
      } else {
        _notificationsEnabled = false;
      }

      // 3. Setup FCM Handlers
      if (_fcm != null) {
        _subscriptions.add(
          FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
            AppLogger.notificacao('Notificação recebida em FOREGROUND');

            final type = message.data['type'];
            // Não usar `trip_id` como `serviceId` para `service_logs` (FK).
            final serviceId =
                message.data['id']?.toString() ??
                message.data['service_id']?.toString();
            final tripId = message.data['trip_id']?.toString();

            if (serviceId != null && !_isLegacyTripType(type?.toString())) {
              ApiService().logServiceEvent(serviceId, 'DELIVERED');
            }

            if (type != null) {
              AppLogger.debug(
                '⚡ Encaminhando evento FCM para RealtimeService: $type',
              );
              final cleanData = Map<String, dynamic>.from(message.data);
              if (serviceId != null) cleanData['id'] = serviceId;
              if (tripId != null) cleanData['trip_id'] = tripId;
              RealtimeService().handleExternalEvent(type, cleanData);

              // If the tracking screen for this service is open, refresh it.
              if (type == 'status_update' ||
                  type == 'service_started' ||
                  type == 'service_completed' ||
                  type == 'payment_approved') {
                ServiceTrackingBus().refreshIfActive(serviceId);
              }
            }

            if (_isServiceOfferType(type?.toString())) {
              final role = await _resolveCurrentRole();
              final decision = ServiceOfferNotificationHandler.decideForeground(
                Map<String, dynamic>.from(message.data),
                role: role,
                isProviderLikeRole: _isProviderLikeRole(role),
                isDriverRole: _isDriverRole(role),
              );
              debugPrint(
                '🔔🔔🔔 [FOREGROUND] service_offer recebido! role=$role, serviceId=$serviceId, _isDialogOpen=$_isDialogOpen',
              );
              if (decision == ServiceOfferHandlingDecision.defer ||
                  decision == ServiceOfferHandlingDecision.ignore) {
                if (decision == ServiceOfferHandlingDecision.defer) {
                  await _persistPendingOffer(
                    Map<String, dynamic>.from(message.data),
                    reason: 'foreground_role_not_ready',
                  );
                  _schedulePendingOfferRetry();
                }
                debugPrint(
                  '⏩ [FOREGROUND] Ignorando service_offer — role não é provider/driver ($role)',
                );
                return;
              }

              AppLogger.notificacao(
                '🚀 Abrindo modal de oferta automaticamente (FOREGROUND)',
              );

              // 1. Tocar alerta sonoro IMEDIATAMENTE (somente mobile)
              if (!kIsWeb) {
                _playNotificationAlert('chamado.mp3');
              }
              _showLocalNotification(message);

              // 2. Iniciar notificações persistentes (repetição)
              if (serviceId != null) {
                _startPersistentNotification(serviceId, message);
              }

              // 3. Direcionar o parceiro para a home do fluxo legado ou abrir modal.
              if (decision == ServiceOfferHandlingDecision.openDriverFlow) {
                if (type == 'central_trip_offer') {
                  unawaited(showUberTripOfferNotification(message.data));
                }
                unawaited(_openDriverHomeForTripOffer(message.data));
              } else {
                handleNotificationTap(message.data);
              }
              return;
            }

            if (type == 'central_trip_offer') {
              _playNotificationAlert('chamado.mp3');
              await showUberTripOfferNotification(message.data);

              // Iniciar notificações persistentes (repetição do alerta)
              if (serviceId != null) {
                _startPersistentNotification(serviceId, message);
              }

              // Navegar para a home do motorista para exibir o modal de oferta
              final role = await _resolveCurrentRole();
              AppLogger.notificacao(
                '🚕 [FOREGROUND] central_trip_offer recebido! role=$role',
              );
              if (_isDriverRole(role)) {
                unawaited(_openDriverHomeForTripOffer(message.data));
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
            if (type == 'chat_message' || type == 'chat') {
              final String? sid = serviceId;
              if (sid != null) {
                _playNotificationAlert();
                // Se já estivermos no chat desse serviço, não fazemos nada
                if (ChatScreen.activeChatServiceId == sid) return;

                if (navigatorKey?.currentContext != null) {
                  GoRouter.of(navigatorKey!.currentContext!).push('/chat/$sid');
                } else {
                  await showChatModal(sid, message.data);
                }
                return;
              }
            }

            if (_isLegacyTripType(type?.toString()) ||
                message.notification != null ||
                _shouldShowForegroundLocalNotificationForType(
                  type?.toString(),
                )) {
              if (type == 'central_trip_accepted') {
                _playNotificationAlert('iphone_notificacao.mp3');
              }
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
    } finally {
      _isInitializing = false;
    }
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

    if (actionId == 'service_accept' || actionId == 'service_reject') {
      data['notification_action'] = actionId;
      unawaited(_handleServiceOfferAction(data));
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

    final payload = NotificationPayload(
      type: 'chat_message',
      entityId: serviceId,
      title: senderName,
      body: message,
      channel: NotificationPayloadChannel.chat,
      data: {
        'type': 'chat_message',
        'service_id': serviceId,
        'message_id': messageId,
        'title': senderName,
        'body': message,
      },
    );

    await _dispatcher.dispatchLocal(
      NotificationDispatchRequest(
        id: messageId,
        payload: payload,
        details: const NotificationDetails(
          android: AndroidNotificationDetails(
            _chatChannelId,
            'Mensagens de Chat',
            channelDescription: 'Mensagens de chat em tempo real',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            icon: 'ic_notification_small',
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
      ),
    );
  }

  Future<bool> hasOverlayPermission() async {
    return false;
  }

  Future<bool> requestOverlayPermission() async {
    return false;
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
        title: const Text('Notificações do Android'),
        content: const Text(
          'Para o build de loja, o app usa notificações padrão do Android sem sobreposição de tela. Se quiser reforçar os alertas no aparelho, abra os ajustes do app e revise as permissões e notificações manualmente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('AGORA NÃO'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryYellow,
              foregroundColor: AppTheme.textDark,
            ),
            child: const Text('ABRIR AJUSTES'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      final opened = await openAppSettings();
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nao foi possivel abrir os ajustes do app.'),
          ),
        );
      }
    }
  }

  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _pendingOfferRetryTimer?.cancel();
    _subscriptions.clear();
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
    _isInitialized = false;
    _backgroundOffersProcessed = false;
  }

  Future<String?> getToken() async {
    try {
      if (_shouldSkipWebPush) return null;
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
      if (_shouldSkipWebPush) return;
      await _fcm?.deleteToken();
    } catch (e) {
      debugPrint('❌ [FCM] Erro ao deletar token: $e');
    }
  }

  Future<void> syncToken() async {
    if (kIsWeb) return;
    try {
      final token = await getToken().timeout(const Duration(seconds: 6));
      if (token == null || token.trim().isEmpty) return;
      await _sendTokenToBackend(token).timeout(const Duration(seconds: 6));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [FCM] syncToken timeout/erro: $e');
      }
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

      // Não bloqueia registro de token se role ainda não estiver disponível.
      // O backend usa o supabase_uid como fallback.

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

  bool _shouldSkipDuplicateNavigation(String navigationKey) {
    final now = DateTime.now();
    if (_lastNavigationKey == navigationKey &&
        _lastNavigationAt != null &&
        now.difference(_lastNavigationAt!) < const Duration(seconds: 2)) {
      debugPrint(
        '⚠️ [NotificationService] Navegação duplicada ignorada: $navigationKey',
      );
      return true;
    }
    _lastNavigationKey = navigationKey;
    _lastNavigationAt = now;
    return false;
  }

  bool _shouldSkipDuplicateOfferPresentation(String offerKey) {
    final now = DateTime.now();
    if (_lastOfferPresentationKey == offerKey &&
        _lastOfferPresentationAt != null &&
        now.difference(_lastOfferPresentationAt!) <
            const Duration(seconds: 4)) {
      debugPrint(
        '⚠️ [NotificationService] Apresentação duplicada de oferta ignorada: $offerKey',
      );
      return true;
    }
    _lastOfferPresentationKey = offerKey;
    _lastOfferPresentationAt = now;
    return false;
  }

  String _dialogPresentationKeyFor(Widget child) {
    if (child is ServiceOfferModal) {
      return 'ServiceOfferModal:${child.serviceId}';
    }
    if (child is ProviderArrivedModal) {
      return 'ProviderArrivedModal:${child.serviceId}';
    }
    if (child is ScheduledNotificationModal) {
      return 'ScheduledNotificationModal:${child.serviceId}';
    }
    if (child is ClientWakeUpModal) {
      return 'ClientWakeUpModal:${child.serviceId}';
    }
    if (child is TimeToLeaveModal) {
      final serviceId =
          child.data['service_id']?.toString() ??
          child.data['id']?.toString() ??
          '';
      return 'TimeToLeaveModal:$serviceId';
    }
    return child.runtimeType.toString();
  }

  bool _shouldSkipDialogPresentation(String dialogKey) {
    final now = DateTime.now();
    if (_isDialogOpen &&
        _activeDialogKey == dialogKey &&
        _activeDialogOpenedAt != null &&
        now.difference(_activeDialogOpenedAt!) < const Duration(seconds: 6)) {
      debugPrint(
        '⚠️ [NotificationService] Dialogo duplicado ignorado: $dialogKey',
      );
      return true;
    }
    return false;
  }

  bool _shouldSkipSheetPresentation(String sheetKey) {
    final now = DateTime.now();
    if (_isDialogOpen) {
      debugPrint(
        '⚠️ [NotificationService] Bottom sheet ignorado porque um dialogo já está ativo: $sheetKey',
      );
      return true;
    }
    if (_activeSheetKey == sheetKey &&
        _activeSheetOpenedAt != null &&
        now.difference(_activeSheetOpenedAt!) < const Duration(seconds: 6)) {
      debugPrint(
        '⚠️ [NotificationService] Bottom sheet duplicado ignorado: $sheetKey',
      );
      return true;
    }
    return false;
  }

  String? _offerPresentationKeyFor(Map<String, dynamic> data) {
    return ServiceOfferNotificationFlow.presentationKey(data);
  }

  bool _guardOfferPresentation(Map<String, dynamic> data) {
    final key = _offerPresentationKeyFor(data);
    if (key == null) return false;
    return _shouldSkipDuplicateOfferPresentation(key);
  }

  void _navigateToNotificationTarget(NotificationNavigationTarget target) {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return;
    final navigationKey = '${target.replace ? 'go' : 'push'}:${target.route}';
    if (_shouldSkipDuplicateNavigation(navigationKey)) return;
    if (target.replace) {
      GoRouter.of(ctx).go(target.route);
    } else {
      GoRouter.of(ctx).push(target.route);
    }
  }

  bool _shouldShowForegroundLocalNotificationForType(String? type) {
    final normalized = _normalizeNotificationType(type);
    return normalized == 'status_update' ||
        normalized == 'service_started' ||
        normalized == 'service_completed' ||
        normalized == 'payment_approved' ||
        normalized == 'payment_received' ||
        normalized == 'payment_confirmed' ||
        normalized == 'payment_pending' ||
        normalized == 'payment_failed' ||
        normalized == 'payment_released' ||
        normalized == 'schedule_confirmed' ||
        normalized == 'schedule_30m_reminder' ||
        normalized == 'schedule_proposal' ||
        normalized == 'schedule_proposal_expired' ||
        normalized == 'scheduled_started';
  }

  Future<String?> _resolveCurrentRole() async {
    final apiRole = ApiService().role;
    if (apiRole != null && apiRole.trim().isNotEmpty) return apiRole.trim();

    String? role;
    try {
      final prefs = await SharedPreferences.getInstance();
      role = prefs.getString('user_role')?.trim();
      if (role != null && role.isNotEmpty) return role;
    } catch (_) {}

    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null || uid.trim().isEmpty) return role;
      final row = await Supabase.instance.client
          .from('users')
          .select('role')
          .eq('supabase_uid', uid)
          .maybeSingle();
      final resolved = row?['role']?.toString().trim();
      if (resolved != null && resolved.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', resolved);
        return resolved;
      }
    } catch (_) {}

    return role;
  }

  Future<void> _persistPendingOffer(
    Map<String, dynamic> data, {
    String reason = 'unknown',
  }) async {
    try {
      final type = data['type']?.toString();
      if (!ServiceOfferNotificationFlow.handlesType(type)) return;

      final serviceId = ServiceOfferNotificationFlow.extractServiceId(data);
      if (serviceId == null) return;

      final payload = ServiceOfferNotificationFlow.encodePendingPayload(
        data,
        reason: reason,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bg_pending_offer', payload);
      await prefs.setInt('bg_pending_version', 2);
      debugPrint(
        '💾 [NotificationService] oferta pendente salva (serviceId=$serviceId, reason=$reason)',
      );
    } catch (e) {
      debugPrint(
        '⚠️ [NotificationService] Falha ao salvar oferta pendente: $e',
      );
    }
  }

  void _schedulePendingOfferRetry() {
    _pendingOfferRetryTimer?.cancel();
    _pendingOfferRetryTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_processBackgroundOffers());
    });
  }

  Future<void> _openDriverHomeForTripOffer(Map<String, dynamic> data) async {
    if (!_tripRuntimeEnabled) return;
    if (navigatorKey?.currentContext == null) {
      await _getValidContext();
    }
    if (navigatorKey?.currentContext == null) return;

    await ServiceOfferNotificationCoordinator.openDriverFlow(
      navigatorKey!.currentContext!,
      data: data,
      tripRuntimeEnabled: _tripRuntimeEnabled,
    );
  }

  void handleNotificationTap(Map<String, dynamic> data) {
    debugPrint('🔔 [NOTIFICATION DEBUG] Handling tap with data: $data');
    final type = data['type']?.toString();
    if (_isServiceOfferType(type) && _guardOfferPresentation(data)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (navigatorKey?.currentContext == null) {
        await _getValidContext();
      }

      if (navigatorKey?.currentContext == null) {
        if (_isServiceOfferType(type)) {
          await _persistPendingOffer(data, reason: 'tap_no_context');
          _schedulePendingOfferRetry();
        }
        return;
      }

      await _processNotificationData(data);
    });
  }

  Future<void> _processNotificationData(Map<String, dynamic> data) async {
    final payload = NotificationPayload.fromMap(data);
    final type = payload.type;
    final role = await _resolveCurrentRole();
    debugPrint('🔀 [NOTIFICATION TAP] Type detected: $type');

    final resolution = NotificationActionResolver.resolve(
      payload,
      role: role,
      isProviderLikeRole: _isProviderLikeRole(role),
      isDriverRole: _isDriverRole(role),
    );

    if (resolution.kind == NotificationActionKind.openChat) {
      final serviceId = resolution.entityId;
      if (serviceId != null && navigatorKey?.currentContext != null) {
        GoRouter.of(navigatorKey!.currentContext!).push('/chat/$serviceId');
      }
      return;
    }

    if (resolution.kind == NotificationActionKind.openDriverTripOffer) {
      await _openDriverHomeForTripOffer(data);
      return;
    }

    if (resolution.kind == NotificationActionKind.processServiceOfferAction) {
      await _handleServiceOfferAction(data);
      return;
    }

    if (resolution.kind == NotificationActionKind.navigate &&
        resolution.navigationTarget != null) {
      _navigateToNotificationTarget(resolution.navigationTarget!);
      return;
    }

    if (resolution.kind == NotificationActionKind.openProviderArrivedModal &&
        resolution.entityId != null) {
      _showDialogSafe(
        ProviderArrivedModal(
          serviceId: resolution.entityId!,
          initialData: data,
        ),
      );
      return;
    }

    if (resolution.kind == NotificationActionKind.openTimeToLeaveModal) {
      _showDialogSafe(TimeToLeaveModal(data: data));
      return;
    }

    if (resolution.kind == NotificationActionKind.none &&
        _isServiceOfferType(type)) {
      final decision = ServiceOfferNotificationHandler.decideTapFallback(
        data,
        role: role,
        isProviderLikeRole: _isProviderLikeRole(role),
        isDriverRole: _isDriverRole(role),
      );
      if (_guardOfferPresentation(data)) return;
      if (decision == ServiceOfferHandlingDecision.defer ||
          decision == ServiceOfferHandlingDecision.ignore) {
        if (decision == ServiceOfferHandlingDecision.defer) {
          await _persistPendingOffer(data, reason: 'tap_role_not_ready');
          _schedulePendingOfferRetry();
        }
        return;
      }

      if (decision == ServiceOfferHandlingDecision.openDriverFlow) {
        unawaited(_openDriverHomeForTripOffer(data));
        return;
      }
    }

    if (resolution.kind == NotificationActionKind.openServiceOfferModal &&
        resolution.entityId != null) {
      if (_guardOfferPresentation(data)) return;
      final serviceId = resolution.entityId!;
      final ctx = navigatorKey?.currentContext;
      if (ctx == null) return;
      _showDialogSafe(
        ServiceOfferNotificationCoordinator.buildProviderOfferModal(
          serviceId: serviceId,
          data: data,
          navigateToAcceptedService: () {
            ServiceOfferNotificationCoordinator.navigateProviderAcceptedService(
              ctx,
              serviceId: serviceId,
            );
          },
        ),
        barrierDismissible: false,
      );
      return;
    }

    if (resolution.kind == NotificationActionKind.openScheduledStartedModal) {
      final currentRole = ApiService().role;
      final serviceId = resolution.entityId;

      if (serviceId != null) {
        if (currentRole == 'provider') {
          _showDialogSafe(
            ScheduledNotificationModal(serviceId: serviceId, initialData: data),
            barrierDismissible: false,
          );
        } else {
          _showDialogSafe(
            ClientWakeUpModal(serviceId: serviceId, initialData: data),
            barrierDismissible: false,
          );
        }
      }
      return;
    }

    if (resolution.kind ==
        NotificationActionKind.resolveServiceLifecycleRoute) {
      final serviceId = resolution.entityId;
      if (serviceId != null) {
        unawaited(() async {
          final currentRole = ApiService().role;
          var target = NotificationNavigationResolver.serviceLifecycleFallback(
            role: currentRole,
            serviceId: serviceId,
          );

          try {
            final details = await ApiService().getServiceDetails(serviceId);
            target = NotificationNavigationResolver.serviceLifecycleFromDetails(
              role: currentRole,
              serviceId: serviceId,
              details: details,
            );
          } catch (e) {
            debugPrint(
              '⚠️ [NotificationService] fallback de rota para $type/$serviceId: $e',
            );
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigateToNotificationTarget(target);
          });
        }());
      }
      return;
    }
  }

  Future<void> showChatModal(
    String serviceId,
    Map<String, dynamic> data, {
    bool showComposer = true,
  }) async {
    if (ChatScreen.activeChatServiceId == serviceId) {
      debugPrint(
        '[NotificationService] Chat já está aberto para este serviço.',
      );
      return;
    }

    if (navigatorKey?.currentContext == null) {
      await _getValidContext();
    }
    if (navigatorKey?.currentContext == null) return;
    final sheetKey = 'ChatSheet:$serviceId';
    if (_shouldSkipSheetPresentation(sheetKey)) return;

    final otherName =
        data['sender_name']?.toString() ?? data['title']?.toString();
    final otherAvatar =
        data['sender_avatar']?.toString() ?? data['image']?.toString();

    // Usar bottom sheet para garantir Material ancestor e altura controlada
    _activeSheetKey = sheetKey;
    _activeSheetOpenedAt = DateTime.now();
    try {
      await showModalBottomSheet(
        context: navigatorKey!.currentContext!,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final media = MediaQuery.of(ctx);
          final bottom = media.viewInsets.bottom;
          final availableHeight = media.size.height - bottom;
          final height = (availableHeight * 0.98).clamp(320.0, availableHeight);
          return AnimatedPadding(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: bottom),
            child: Material(
              color: Colors.white,
              borderRadius: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ).borderRadius,
              child: SizedBox(
                height: height,
                child: ChatScreen(
                  serviceId: serviceId,
                  isInline: false,
                  otherName: otherName,
                  otherAvatar: otherAvatar,
                  showComposer: showComposer,
                  onClose: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _activeSheetKey = null;
      _activeSheetOpenedAt = null;
    }
  }

  Future<void> _showDialogSafe(
    Widget child, {
    bool barrierDismissible = true,
  }) async {
    if (navigatorKey?.currentContext == null) return;
    final dialogKey = _dialogPresentationKeyFor(child);
    if (_shouldSkipDialogPresentation(dialogKey)) return;
    if (_activeSheetKey != null) return;
    if (_isDialogOpen && _activeDialogKey != dialogKey) return;

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
    _activeDialogKey = dialogKey;
    _activeDialogOpenedAt = DateTime.now();
    try {
      await showDialog(
        context: navigatorKey!.currentContext!,
        barrierDismissible: barrierDismissible,
        builder: (context) => child,
      );
    } finally {
      _isDialogOpen = false;
      _activeDialogKey = null;
      _activeDialogOpenedAt = null;
    }
  }

  Future<void> showFromService(
    Map<String, dynamic> payload, {
    String? event,
  }) async {
    final notificationPayload = NotificationPayload.fromMap(
      payload,
      fallbackTitle: 'Atualização de Serviço',
      fallbackBody:
          payload['message']?.toString() ?? event ?? 'Nova atualização',
      fallbackChannel: NotificationPayloadChannel.serviceUpdate,
    );
    await _dispatcher.dispatchLocal(
      NotificationDispatchRequest(
        id: DateTime.now().millisecond,
        payload: notificationPayload,
        details: const NotificationDetails(
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
      ),
    );
  }

  Future<void> showAccepted() async {
    final notificationPayload = NotificationPayload(
      type: 'service_accepted',
      title: 'Serviço Aceito!',
      body: 'Um prestador aceitou seu serviço.',
      channel: NotificationPayloadChannel.serviceUpdate,
      data: const {
        'type': 'service_accepted',
        'title': 'Serviço Aceito!',
        'body': 'Um prestador aceitou seu serviço.',
      },
    );
    await _dispatcher.dispatchLocal(
      NotificationDispatchRequest(
        id: DateTime.now().millisecond,
        payload: notificationPayload,
        details: const NotificationDetails(
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
      ),
    );
  }

  Future<void> showNotification(String title, String body) async {
    if (!_notificationsEnabled) {
      debugPrint(
        '[NotificationService] ⚠️ Notificações desabilitadas em ${_getPlatformName()}, skipping showNotification',
      );
      return;
    }

    try {
      final notificationPayload = NotificationPayload(
        type: 'generic',
        title: title,
        body: body,
        channel: NotificationPayloadChannel.generic,
        data: {'type': 'generic', 'title': title, 'body': body},
      );
      await _dispatcher.dispatchLocal(
        NotificationDispatchRequest(
          id: DateTime.now().millisecond,
          payload: notificationPayload,
          details: NotificationDetails(
            android: _buildPremiumAndroidDetails(
              channelId: _urgentChannelId,
              channelName: 'High Importance Notifications',
              title: notificationPayload.title,
              body: notificationPayload.body,
              category: AndroidNotificationCategory.alarm,
              importance: Importance.max,
              priority: Priority.max,
              fullScreenIntent: true,
            ),
            iOS: _buildPremiumDarwinDetails(
              subtitle: '101 Service',
              threadIdentifier: 'urgent-alerts',
              sound: _resolveIosSoundName(notificationPayload.type),
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ [NotificationService] Erro em showNotification: $e');
    }
  }

  Future<void> showUberTripOfferNotification(Map<String, dynamic> trip) async {
    if (!_tripRuntimeEnabled) return;
    if (kIsWeb) return;
    if (!_notificationsEnabled) {
      debugPrint(
        '[NotificationService] ⚠️ Notificações desabilitadas em ${_getPlatformName()}, skipping showUberTripOfferNotification',
      );
      return;
    }

    try {
      final tripId = trip['id']?.toString() ?? '';
      final pickup = trip['pickup_address']?.toString() ?? 'Origem';
      final dropoff = trip['dropoff_address']?.toString() ?? 'Destino';
      final fareFinal = (trip['fare_final'] is num)
          ? (trip['fare_final'] as num).toDouble()
          : double.tryParse(trip['fare_final']?.toString() ?? '') ?? 0.0;
      final fareEstimated = (trip['fare_estimated'] is num)
          ? (trip['fare_estimated'] as num).toDouble()
          : double.tryParse(trip['fare_estimated']?.toString() ?? '') ?? 0.0;
      final fare = (fareFinal > 0 ? fareFinal : fareEstimated).toStringAsFixed(
        2,
      );
      final body =
          '$pickup -> $dropoff\nGanhos estimados: R\$ $fare\nToque para revisar e aceitar a oferta.';
      final notificationPayload = NotificationPayload.fromMap(
        {
          'type': 'central_trip_offer',
          'trip_id': tripId,
          'id': tripId,
          ...trip,
        },
        fallbackTitle: 'Nova oferta de atendimento disponível',
        fallbackBody: body,
        fallbackChannel: NotificationPayloadChannel.tripOffer,
      );

      await _dispatcher.dispatchLocal(
        NotificationDispatchRequest(
          id: tripId.hashCode,
          payload: notificationPayload,
          details: NotificationDetails(
            android: _buildPremiumAndroidDetails(
              channelId: _serviceOfferChannelId,
              channelName: 'Ofertas de atendimento',
              title: notificationPayload.title,
              body: notificationPayload.body,
              category: AndroidNotificationCategory.call,
              importance: Importance.max,
              priority: Priority.max,
              fullScreenIntent: true,
              timeoutAfter: 30000,
              subText: 'Oferta premium',
              summaryText: 'Corrida pronta para analise',
            ),
            iOS: _buildPremiumDarwinDetails(
              subtitle: 'Nova oferta de atendimento',
              threadIdentifier: 'uber-trip-offers',
              sound: _resolveIosSoundName(notificationPayload.type),
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        '❌ [NotificationService] Erro em showUberTripOfferNotification: $e',
      );
    }
  }

  Future<void> showUberTripStatusNotification({
    required String tripId,
    required String title,
    required String body,
    required String type,
    String? driverName,
    String? vehicleModel,
    String? vehicleColor,
    String? vehiclePlate,
    String? driverPhotoUrl,
  }) async {
    if (!_tripRuntimeEnabled) return;
    if (kIsWeb) return;
    if (!_notificationsEnabled) {
      debugPrint(
        '[NotificationService] ⚠️ Notificações desabilitadas em ${_getPlatformName()}, skipping showUberTripStatusNotification',
      );
      return;
    }

    try {
      final resolvedBody = type == 'central_trip_accepted'
          ? _composeAcceptedNotificationBody(
              body,
              driverName: driverName,
              vehicleModel: vehicleModel,
              vehicleColor: vehicleColor,
              vehiclePlate: vehiclePlate,
            )
          : body;
      final notificationPayload = NotificationPayload.fromMap(
        {'type': type, 'trip_id': tripId, 'id': tripId},
        fallbackTitle: title,
        fallbackBody: resolvedBody,
        fallbackChannel: NotificationPayloadChannel.tripUpdate,
      );

      AppLogger.notificacao(
        'showUberTripStatusNotification => ${jsonEncode({'trip_id': tripId, 'type': type, 'title': title, 'body': resolvedBody, 'driver_name': driverName ?? '', 'vehicle_model': vehicleModel ?? '', 'vehicle_color': vehicleColor ?? '', 'vehicle_plate': vehiclePlate ?? '', 'driver_photo_url': driverPhotoUrl ?? ''})}',
      );

      if (type == 'central_trip_arrived') {
        await AwesomeNotificationService.instance.showPremiumDriverArrived(
          tripId: tripId,
          title: title,
          body: body,
          driverName: driverName,
          vehicleModel: vehicleModel,
          vehicleColor: vehicleColor,
          vehiclePlate: vehiclePlate,
          largeIconUrl: driverPhotoUrl,
        );
        await _scheduleTripWaitReminder(tripId);
        return;
      }

      if (type == 'central_trip_started' ||
          type == 'central_trip_completed' ||
          type == 'central_trip_cancelled') {
        await _cancelTripWaitReminder(tripId);
      }

      await _dispatcher.dispatchLocal(
        NotificationDispatchRequest(
          id: tripId.hashCode,
          payload: notificationPayload,
          details: NotificationDetails(
            android: _buildPremiumAndroidDetails(
              channelId: _serviceStatusChannelId,
              channelName: 'Atualizações de atendimento',
              title: notificationPayload.title,
              body: notificationPayload.body,
              category: AndroidNotificationCategory.status,
              importance: Importance.high,
              priority: Priority.high,
              subText: 'Seu atendimento',
              summaryText: _resolveStatusSummary(type),
            ),
            iOS: _buildPremiumDarwinDetails(
              subtitle: _resolveStatusSummary(type),
              threadIdentifier: 'uber-trip-updates',
              sound: _resolveIosSoundName(notificationPayload.type),
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        '❌ [NotificationService] Erro em showUberTripStatusNotification: $e',
      );
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (!_notificationsEnabled) {
      debugPrint(
        '[NotificationService] ⚠️ Notificações desabilitadas em ${_getPlatformName()}, skipping _showLocalNotification',
      );
      return;
    }

    try {
      final notification = message.notification;
      final type = message.data['type']?.toString();
      final isServiceOffer = _isServiceOfferType(type);
      final serviceId =
          message.data['service_id']?.toString() ??
          message.data['id']?.toString() ??
          '';

      AppLogger.notificacao(
        'RemoteMessage recebido => ${jsonEncode({'type': type ?? '', 'notification_title': notification?.title ?? '', 'notification_body': notification?.body ?? '', 'data': message.data})}',
      );

      if (_isLegacyTripType(type)) {
        final tripId =
            message.data['trip_id']?.toString() ??
            message.data['id']?.toString();
        if (tripId == null || tripId.isEmpty) return;

        final title =
            notification?.title ??
            message.data['title']?.toString() ??
            _defaultLegacyTripTitle(type);
        final body =
            notification?.body ??
            message.data['body']?.toString() ??
            _defaultLegacyTripBody(type);

        await showUberTripStatusNotification(
          tripId: tripId,
          title: title,
          body: body,
          type: type ?? 'central_trip_accepted',
          driverName: message.data['driver_name']?.toString(),
          vehicleModel: message.data['vehicle_model']?.toString(),
          vehicleColor: message.data['vehicle_color']?.toString(),
          vehiclePlate: message.data['vehicle_plate']?.toString(),
          driverPhotoUrl: message.data['driver_photo_url']?.toString(),
        );
        return;
      }

      final android = notification?.android;
      final fallbackTitle =
          message.data['title']?.toString() ??
          (isServiceOffer ? 'Novo Servico Disponivel' : '101 Service');
      final fallbackBody =
          message.data['body']?.toString() ??
          (isServiceOffer
              ? 'Voce tem uma nova oportunidade de servico proxima!'
              : 'Nova notificacao recebida.');
      final resolvedTitle = isServiceOffer
          ? _composeServiceOfferTitle(message.data, fallbackTitle)
          : (notification?.title ?? fallbackTitle);
      final resolvedBody = isServiceOffer
          ? _composeServiceOfferBody(message.data, fallbackBody)
          : (notification?.body ?? fallbackBody);

      if (notification != null || isServiceOffer) {
        final notificationPayload = NotificationPayload.fromMap(
          message.data,
          fallbackTitle: resolvedTitle,
          fallbackBody: resolvedBody,
          fallbackChannel: isServiceOffer
              ? NotificationPayloadChannel.serviceOffer
              : NotificationPayloadChannel.generic,
        );
        AndroidBitmap<Object>? largeIcon;

        final String? imageUrl = message.data['image'] ?? android?.imageUrl;

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

        largeIcon ??= isServiceOffer
            ? const DrawableResourceAndroidBitmap('ic_notification_badge')
            : const DrawableResourceAndroidBitmap('ic_logo_colored');

        await _dispatcher.dispatchLocal(
          NotificationDispatchRequest(
            id: serviceId.isNotEmpty
                ? serviceId.hashCode
                : (notification?.hashCode ?? resolvedTitle.hashCode),
            payload: notificationPayload,
            details: NotificationDetails(
              android: _buildPremiumAndroidDetails(
                channelId: _resolveAndroidChannelId(type),
                channelName: _resolveAndroidChannelName(type),
                title: resolvedTitle,
                body: resolvedBody,
                category: _resolveAndroidCategory(type),
                importance: _resolveAndroidImportance(type),
                priority: _resolveAndroidPriority(type),
                fullScreenIntent: _shouldUseFullScreenIntent(type),
                timeoutAfter: _resolveTimeout(type),
                largeIcon: largeIcon,
                subText: _resolveSubText(type),
                summaryText: _resolveStatusSummary(type),
                actions: isServiceOffer ? _buildServiceOfferActions() : null,
                sound: RawResourceAndroidNotificationSound(
                  _resolveAndroidSoundKey(type),
                ),
              ),
              iOS: _buildPremiumDarwinDetails(
                subtitle: _resolveSubText(type),
                threadIdentifier: _resolveIosThreadId(type),
                sound: _resolveIosSoundName(type),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [NotificationService] Erro em _showLocalNotification: $e');
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

  Future<void> _playNotificationAlert([
    String sound = 'iphone_notificacao.mp3',
  ]) async {
    if (!kIsWeb) {
      HapticFeedback.heavyImpact();
      try {
        await _audioPlayer.stop();
        await _audioPlayer.play(AssetSource('sounds/$sound'));
      } catch (e) {
        debugPrint('Erro ao reproduzir som: $e');
      }
      await _localNotifications.show(
        id: 9999,
        title: null,
        body: null,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'alert_sound_channel_v2',
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
        final prepared = ServiceOfferPendingProcessor.prepare(data);

        if (prepared.shouldWaitForContext) {
          if (navigatorKey?.currentContext == null) {
            final ctx = await _getValidContext();
            if (ctx == null) {
              debugPrint(
                '⏳ [NotificationService] contexto indisponível, mantendo oferta pendente.',
              );
              return;
            }
          }
        }

        if (prepared.shouldLogDelivered && prepared.serviceId != null) {
          ApiService().logServiceEvent(
            prepared.serviceId!,
            'DELIVERED',
            'Processado via Foreground (Sync)',
          );
          RealtimeService().handleExternalEvent('service_offer', data);
        }

        if (_guardOfferPresentation(prepared.mappedPayload)) {
          await prefs.remove('bg_pending_offer');
          await prefs.remove('bg_pending_version');
          return;
        }

        handleNotificationTap(prepared.mappedPayload);

        await prefs.remove('bg_pending_offer');
        await prefs.remove('bg_pending_version');
      }
    } on MissingPluginException catch (e) {
      debugPrint(
        '🚨 [NotificationService] SharedPreferences indisponível (skip bg offers): $e',
      );
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
      icon: 'ic_notification_small',
      largeIcon: DrawableResourceAndroidBitmap('ic_logo_colored'),
      color: Color(0xFFFDE500),
      colorized: true,
      sound: RawResourceAndroidNotificationSound(_androidOrderSoundKey),
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
    AndroidNotificationSound? sound,
  }) {
    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: '$channelName com apresentacao premium.',
      importance: importance,
      priority: priority,
      playSound: true,
      icon: 'ic_notification_small',
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
      sound:
          sound ??
          const RawResourceAndroidNotificationSound(_androidMessageSoundKey),
      visibility: NotificationVisibility.public,
      fullScreenIntent: fullScreenIntent,
      timeoutAfter: timeoutAfter,
      actions: actions,
    );
  }

  DarwinNotificationDetails _buildPremiumDarwinDetails({
    String? subtitle,
    String? threadIdentifier,
    String? sound,
  }) {
    return DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      subtitle: subtitle,
      threadIdentifier: threadIdentifier,
      sound: sound,
    );
  }

  String _getPlatformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    return 'Unknown Platform';
  }

  String _resolveAndroidChannelId(String? type) {
    final serviceOfferChannelId =
        ServiceOfferNotificationPresentation.resolveChannelId(
          type,
          serviceOfferChannelId: _serviceOfferChannelId,
        );
    if (serviceOfferChannelId != null) return serviceOfferChannelId;
    type = _normalizeNotificationType(type);
    switch (type) {
      case 'central_trip_offer':
        return _serviceOfferChannelId;
      case 'schedule_proposal':
      case 'schedule_proposal_expired':
        return _scheduleProposalChannelId;
      case 'central_trip_accepted':
      case 'central_trip_arrived':
      case 'central_trip_started':
      case 'central_trip_completed':
      case 'central_trip_cancelled':
        return _serviceStatusChannelId;
      case 'payment_approved':
      case 'payment_received':
      case 'payment_confirmed':
      case 'payment_pending':
      case 'payment_failed':
      case 'payment_released':
        return _paymentChannelId;
      case 'chat_message':
      case 'chat':
        return _chatChannelId;
      default:
        return _urgentChannelId;
    }
  }

  String _resolveAndroidChannelName(String? type) {
    final serviceOfferChannelName =
        ServiceOfferNotificationPresentation.resolveChannelName(type);
    if (serviceOfferChannelName != null) return serviceOfferChannelName;
    type = _normalizeNotificationType(type);
    switch (type) {
      case 'central_trip_offer':
        return 'Ofertas de atendimento';
      case 'schedule_proposal':
      case 'schedule_proposal_expired':
        return 'Propostas de agendamento';
      case 'central_trip_accepted':
      case 'central_trip_arrived':
      case 'central_trip_started':
      case 'central_trip_completed':
      case 'central_trip_cancelled':
        return 'Atualizações de atendimento';
      case 'payment_approved':
      case 'payment_received':
      case 'payment_confirmed':
      case 'payment_pending':
      case 'payment_failed':
      case 'payment_released':
        return 'Pagamentos';
      case 'chat_message':
      case 'chat':
        return 'Mensagens de Chat';
      default:
        return 'High Importance Notifications';
    }
  }

  AndroidNotificationCategory _resolveAndroidCategory(String? type) {
    final serviceOfferCategory =
        ServiceOfferNotificationPresentation.resolveCategory(type);
    if (serviceOfferCategory != null) return serviceOfferCategory;
    type = _normalizeNotificationType(type);
    switch (type) {
      case 'central_trip_offer':
        return AndroidNotificationCategory.call;
      case 'schedule_proposal':
      case 'schedule_proposal_expired':
        return AndroidNotificationCategory.reminder;
      case 'chat_message':
      case 'chat':
        return AndroidNotificationCategory.message;
      default:
        return AndroidNotificationCategory.status;
    }
  }

  Importance _resolveAndroidImportance(String? type) {
    final serviceOfferImportance =
        ServiceOfferNotificationPresentation.resolveImportance(type);
    if (serviceOfferImportance != null) return serviceOfferImportance;
    type = _normalizeNotificationType(type);
    switch (type) {
      case 'central_trip_offer':
      case 'schedule_proposal':
      case 'schedule_proposal_expired':
        return Importance.max;
      default:
        return Importance.high;
    }
  }

  Priority _resolveAndroidPriority(String? type) {
    final serviceOfferPriority =
        ServiceOfferNotificationPresentation.resolvePriority(type);
    if (serviceOfferPriority != null) return serviceOfferPriority;
    type = _normalizeNotificationType(type);
    switch (type) {
      case 'central_trip_offer':
      case 'schedule_proposal':
      case 'schedule_proposal_expired':
        return Priority.max;
      default:
        return Priority.high;
    }
  }

  bool _shouldUseFullScreenIntent(String? type) {
    final serviceOfferFullScreen =
        ServiceOfferNotificationPresentation.resolveFullScreenIntent(type);
    if (serviceOfferFullScreen != null) return serviceOfferFullScreen;
    type = _normalizeNotificationType(type);
    return type == 'central_trip_offer';
  }

  int? _resolveTimeout(String? type) {
    final serviceOfferTimeout =
        ServiceOfferNotificationPresentation.resolveTimeout(type);
    if (serviceOfferTimeout != null ||
        normalizeNotificationType(type) == 'manual_visual_test') {
      return serviceOfferTimeout;
    }
    type = _normalizeNotificationType(type);
    return type == 'central_trip_offer' ? 30000 : null;
  }

  String? _resolveSubText(String? type) {
    final serviceOfferSubText =
        ServiceOfferNotificationPresentation.resolveSubText(type);
    if (serviceOfferSubText != null) return serviceOfferSubText;
    type = _normalizeNotificationType(type);
    switch (type) {
      case 'central_trip_offer':
        return 'Oferta premium';
      case 'schedule_proposal':
      case 'schedule_proposal_expired':
        return 'Negociação de agenda';
      case 'payment_approved':
      case 'payment_received':
      case 'payment_confirmed':
      case 'payment_pending':
      case 'payment_failed':
      case 'payment_released':
        return 'Pagamento';
      case 'central_trip_accepted':
      case 'central_trip_arrived':
      case 'central_trip_started':
      case 'central_trip_completed':
      case 'central_trip_cancelled':
        return 'Seu atendimento';
      case 'chat_message':
      case 'chat':
        return 'Chat em tempo real';
      default:
        return '101 Service';
    }
  }

  String? _resolveIosThreadId(String? type) {
    switch (type) {
      case 'central_trip_offer':
        return 'uber-trip-offers';
      case 'central_trip_accepted':
      case 'central_trip_arrived':
      case 'central_trip_started':
      case 'central_trip_completed':
      case 'central_trip_cancelled':
        return 'uber-trip-updates';
      case 'payment_approved':
      case 'payment_received':
      case 'payment_confirmed':
      case 'payment_pending':
      case 'payment_failed':
      case 'payment_released':
        return 'payment-updates';
      case 'chat_message':
      case 'chat':
        return 'chat-messages';
      default:
        return 'service-101';
    }
  }

  String? _resolveStatusSummary(String? type) {
    final serviceOfferSummary =
        ServiceOfferNotificationPresentation.resolveStatusSummary(type);
    if (serviceOfferSummary != null) return serviceOfferSummary;
    type = _normalizeNotificationType(type);
    switch (type) {
      case 'central_trip_offer':
        return 'Oferta disponivel agora';
      case 'schedule_proposal':
        return 'Novo horario sugerido';
      case 'schedule_proposal_expired':
        return 'Prazo de resposta encerrado';
      case 'central_trip_accepted':
        return 'Prestador a caminho';
      case 'central_trip_arrived':
        return 'Prestador chegou';
      case 'central_trip_started':
        return 'Atendimento em andamento';
      case 'central_trip_completed':
        return 'Atendimento finalizado';
      case 'central_trip_cancelled':
        return 'Atendimento cancelado';
      case 'central_trip_wait_2m':
        return '2 minutos de espera';
      case 'chat_message':
      case 'chat':
        return 'Nova mensagem';
      case 'payment_approved':
        return 'Pagamento aprovado';
      case 'payment_received':
      case 'payment_confirmed':
        return 'Pagamento confirmado';
      case 'payment_pending':
        return 'Pagamento pendente';
      case 'payment_failed':
        return 'Falha no pagamento';
      case 'payment_released':
        return 'Pagamento liberado';
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
          'Ja se passaram 2 minutos de espera. Se precisar, responda ao prestador pelo chat.',
      scheduledDate: scheduledAt,
      notificationDetails: NotificationDetails(
        android: _buildPremiumAndroidDetails(
          channelId: _serviceStatusChannelId,
          channelName: 'Atualizações de atendimento',
          title: 'Tempo de espera iniciado',
          body:
              'Ja se passaram 2 minutos de espera. Se precisar, responda ao prestador pelo chat.',
          category: AndroidNotificationCategory.message,
          importance: Importance.high,
          priority: Priority.high,
          subText: 'Atencao',
          summaryText: '2 minutos de espera',
          actions: const [
            AndroidNotificationAction('open_trip', 'Abrir atendimento'),
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
          threadIdentifier: 'service-status-updates',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: jsonEncode({
        'type': 'central_trip_wait_2m',
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
      title: 'Hora de sair para o serviço',
      body:
          'Saia agora para chegar com 15 min de antecedência. Viagem estimada: $travelTimeMin min.',
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
