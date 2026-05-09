import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:awesome_notifications_fcm/awesome_notifications_fcm.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/logger.dart';
import 'data_gateway.dart';

typedef AwesomeNotificationActionHandler =
    Future<void> Function(Map<String, dynamic> data);

/// Camada paralela de migracao para Awesome Notifications.
/// Ainda nao substitui o fluxo atual; serve para introduzir canais e setup
/// sem quebrar firebase_messaging + flutter_local_notifications.
@pragma('vm:entry-point')
class AwesomeNotificationService {
  static const bool _tripRuntimeEnabled = false;
  @pragma('vm:entry-point')
  AwesomeNotificationService._();

  @pragma('vm:entry-point')
  static final AwesomeNotificationService instance =
      AwesomeNotificationService._();

  static const String urgentChannelKey = 'high_importance_channel_v3';
  // Mantemos as channel keys legadas por compatibilidade com instalações já existentes.
  static const String serviceOfferChannelKey = 'central_trip_offers_channel';
  static const String serviceStatusChannelKey = 'central_trip_updates_channel';
  static const String chatChannelKey = 'chat_messages_channel';
  static const String _actionPortName = 'awesome_notification_action_port';

  bool _initialized = false;
  bool _listenersRegistered = false;
  bool _fcmInitialized = false;
  ReceivePort? _receivePort;
  AwesomeNotificationActionHandler? _actionHandler;

  bool get isInitialized => _initialized;

  void setActionHandler(AwesomeNotificationActionHandler handler) {
    _actionHandler = handler;
  }

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    await AwesomeNotifications().initialize(
      'resource://drawable/ic_notification_small',
      [
      NotificationChannel(
        channelKey: urgentChannelKey,
        channelName: 'Alertas Urgentes',
        channelDescription: 'Canal para alertas urgentes do aplicativo.',
        defaultColor: const Color(0xFFFDE500),
        ledColor: const Color(0xFFFDE500),
        importance: NotificationImportance.Max,
        channelShowBadge: true,
        playSound: true,
        criticalAlerts: true,
        defaultPrivacy: NotificationPrivacy.Public,
      ),
      NotificationChannel(
        channelKey: serviceOfferChannelKey,
        channelName: 'Ofertas de atendimento',
        channelDescription: 'Ofertas urgentes de atendimento para parceiros.',
        defaultColor: const Color(0xFFFDE500),
        ledColor: const Color(0xFFFDE500),
        importance: NotificationImportance.Max,
        channelShowBadge: true,
        playSound: true,
        criticalAlerts: true,
        defaultPrivacy: NotificationPrivacy.Public,
      ),
      NotificationChannel(
        channelKey: serviceStatusChannelKey,
        channelName: 'Atualizacoes de atendimento',
        channelDescription: 'Atualizacoes de status dos atendimentos.',
        defaultColor: const Color(0xFFFDE500),
        ledColor: const Color(0xFFFDE500),
        importance: NotificationImportance.High,
        channelShowBadge: true,
        playSound: true,
        defaultPrivacy: NotificationPrivacy.Public,
      ),
      NotificationChannel(
        channelKey: chatChannelKey,
        channelName: 'Mensagens de Chat',
        channelDescription: 'Mensagens e respostas rapidas do chat.',
        defaultColor: const Color(0xFFFDE500),
        ledColor: const Color(0xFFFDE500),
        importance: NotificationImportance.High,
        channelShowBadge: true,
        playSound: true,
        defaultPrivacy: NotificationPrivacy.Public,
      ),
    ]);

    _initializeActionBridge();
    if (!_listenersRegistered) {
      await AwesomeNotifications().setListeners(
        onActionReceivedMethod:
            AwesomeNotificationService.onActionReceivedMethod,
      );
      _listenersRegistered = true;
    }

    if (!_fcmInitialized) {
      await AwesomeNotificationsFcm().initialize(
        onFcmTokenHandle: AwesomeNotificationService.onFcmTokenHandle,
        onFcmSilentDataHandle: AwesomeNotificationService.onFcmSilentDataHandle,
        onNativeTokenHandle: AwesomeNotificationService.onNativeTokenHandle,
        debug: kDebugMode,
      );
      _fcmInitialized = true;
    }

    _initialized = true;
  }

  void _initializeActionBridge() {
    if (_receivePort != null) return;

    _receivePort = ReceivePort(_actionPortName)
      ..listen((dynamic serializedData) async {
        try {
          final action = ReceivedAction().fromMap(
            Map<String, dynamic>.from(serializedData as Map),
          );
          await _handleAction(action);
        } catch (error) {
          AppLogger.erro('Erro ao processar acao do Awesome', error);
        }
      });

    IsolateNameServer.removePortNameMapping(_actionPortName);
    IsolateNameServer.registerPortWithName(
      _receivePort!.sendPort,
      _actionPortName,
    );
  }

  @pragma('vm:entry-point')
  static Future<void> onActionReceivedMethod(ReceivedAction action) async {
    final SendPort? sendPort = IsolateNameServer.lookupPortByName(
      _actionPortName,
    );

    if (sendPort != null) {
      sendPort.send(action.toMap());
      return;
    }

    await instance._handleAction(action);
  }

  @pragma('vm:entry-point')
  static Future<void> onFcmTokenHandle(String token) async {
    AppLogger.notificacao('Awesome FCM token recebido');
  }

  @pragma('vm:entry-point')
  static Future<void> onNativeTokenHandle(String token) async {
    AppLogger.notificacao('Awesome native token recebido');
  }

  @pragma('vm:entry-point')
  static Future<void> onFcmSilentDataHandle(FcmSilentData silentData) async {
    AppLogger.notificacao('Awesome silent push recebido');
  }

  Future<void> _handleAction(ReceivedAction action) async {
    final payload = Map<String, String>.from(action.payload ?? const {});
    final tripId =
        payload['trip_id'] ?? payload['service_id'] ?? payload['id'] ?? '';

    if (!_tripRuntimeEnabled &&
        (payload.containsKey('trip_id') ||
            action.buttonKeyPressed == 'reply_trip' ||
            action.buttonKeyPressed == 'open_trip')) {
      return;
    }

    if (action.buttonKeyPressed == 'service_accept' ||
        action.buttonKeyPressed == 'service_reject') {
      if (tripId.isNotEmpty) {
        final data = <String, dynamic>{
          'type': payload['type'] ?? 'service_offer',
          'service_id': tripId,
          'id': tripId,
          'notification_action': action.buttonKeyPressed,
          ...payload,
        };
        await _actionHandler?.call(data);
      }
      return;
    }

    if (action.buttonKeyPressed == 'reply_trip') {
      final text = action.buttonKeyInput.trim();
      if (tripId.isNotEmpty && text.isNotEmpty) {
        await DataGateway().sendChatMessage(tripId, text, 'text');
      }
      return;
    }

    if (action.buttonKeyPressed.isEmpty ||
        action.buttonKeyPressed == 'open_trip') {
      if (tripId.isNotEmpty) {
        final data = <String, dynamic>{
          'type': payload['type'] ?? 'central_trip_arrived',
          'trip_id': tripId,
          'id': tripId,
          ...payload,
        };
        await _actionHandler?.call(data);
      }
      return;
    }

    AppLogger.notificacao(
      'Acao Awesome recebida: ${action.buttonKeyPressed} para $tripId',
    );
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;

    return await AwesomeNotifications().requestPermissionToSendNotifications();
  }

  Future<void> showLocalSmokeTest() async {
    if (!_initialized || kIsWeb) return;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        channelKey: serviceStatusChannelKey,
        title: 'Teste Awesome Notifications',
        body: 'Base pronta para migracao premium das notificacoes do app.',
        notificationLayout: NotificationLayout.BigText,
        wakeUpScreen: false,
        category: NotificationCategory.Status,
        backgroundColor: const Color(0xFFF5F7F5),
        color: const Color(0xFFFDE500),
      ),
    );
  }

  Future<void> showPremiumDriverArrivedPreview() async {
    if (!_tripRuntimeEnabled) return;
    if (!_initialized || kIsWeb) return;

    await _showPremiumDriverArrived(
      tripId: 'awesome-preview-trip',
      driverName: 'Ricardo Silva',
      vehicleModel: 'Toyota Corolla',
      vehicleColor: 'Branco',
      vehiclePlate: 'ABC-1234',
      title: 'Motorista chegou',
      body:
          'Seu prestador Toyota Corolla (ABC-1234) esta aguardando no local combinado.\n\nApos 2 minutos de espera, taxas adicionais podem ser cobradas.',
      largeIconUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuBcavrlYSiTqH7RhmYDrt0tAenIEvUl4Wm0fJef-rUgM2XxD3dNzBMFxSMQiuH8fcHAaiEmK63ribmKEQoEekv9B2wSxsq6VdNbH1rTKJZ00bwv7Xkh0nud7X3TKxow8opJyUj8dsuqNHSy9bP9ZrH5phA1DSzCP2_PmE1-m9uSNc4p4FdaqYxi5lGG7NHDpUS5Zp7r9GEAYmZ561fsZlu5nEmb1EH8aKxVbEleBO6u_1LaKbeFgz1-lCw0R-wZDr6PsUq3AYUIrC8',
    );
  }

  Future<void> showPremiumDriverArrived({
    required String tripId,
    required String title,
    required String body,
    String? driverName,
    String? vehicleModel,
    String? vehicleColor,
    String? vehiclePlate,
    String? largeIconUrl,
  }) async {
    if (!_tripRuntimeEnabled) return;
    if (!_initialized || kIsWeb) return;

    await _showPremiumDriverArrived(
      tripId: tripId,
      driverName: driverName,
      vehicleModel: vehicleModel,
      vehicleColor: vehicleColor,
      vehiclePlate: vehiclePlate,
      title: title,
      body: body,
      largeIconUrl: largeIconUrl,
    );
  }

  Future<void> showServiceOfferFullScreen({
    required String serviceId,
    required String title,
    required String body,
    Map<String, String>? payload,
  }) async {
    if (!_initialized || kIsWeb) return;

    final resolvedPayload = <String, String>{
      'type': 'service_offer',
      'service_id': serviceId,
      'id': serviceId,
      ...?payload,
    };

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: serviceId.hashCode,
        channelKey: urgentChannelKey,
        icon: 'resource://drawable/ic_notification_small',
        largeIcon: 'resource://drawable/ic_notification_badge',
        roundedLargeIcon: true,
        title: title,
        body: body,
        summary: '101 Service',
        notificationLayout: NotificationLayout.BigText,
        wakeUpScreen: true,
        fullScreenIntent: true,
        autoDismissible: false,
        locked: true,
        category: NotificationCategory.Call,
        backgroundColor: const Color(0xFFF5F7F5),
        color: const Color(0xFFFDE500),
        displayOnForeground: true,
        displayOnBackground: true,
        payload: resolvedPayload,
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'service_reject',
          label: 'Recusar',
          color: const Color(0xFFFFFFFF),
          autoDismissible: false,
          showInCompactView: true,
        ),
        NotificationActionButton(
          key: 'service_accept',
          label: 'Aceitar',
          color: const Color(0xFFFDE500),
          autoDismissible: true,
          showInCompactView: true,
        ),
      ],
    );
  }

  Future<void> _showPremiumDriverArrived({
    required String tripId,
    required String title,
    required String body,
    String? driverName,
    String? vehicleModel,
    String? vehicleColor,
    String? vehiclePlate,
    String? largeIconUrl,
  }) async {
    if (!_tripRuntimeEnabled) return;
    final hasDriverName = (driverName ?? '').isNotEmpty;
    final vehicleLabel = [
      if ((vehicleModel ?? '').isNotEmpty) vehicleModel,
      if ((vehicleColor ?? '').isNotEmpty) vehicleColor,
      if ((vehiclePlate ?? '').isNotEmpty) vehiclePlate,
    ].join(' • ');
    final hasVehicleLabel = vehicleLabel.isNotEmpty;
    final headline = hasDriverName ? driverName! : 'Prestador chegou';
    final shortBody = hasVehicleLabel
        ? '$vehicleLabel\nNo local de embarque agora.'
        : body;

    final detailLines = <String>[
      shortBody,
      'Apos 2 min de espera, taxas podem ser cobradas.',
    ];

    final richBody = detailLines.join('\n');
    final summary = [
      '101 Service',
      if (hasVehicleLabel) vehicleLabel,
    ].join(' • ');

    final payload = <String, String>{
      'type': 'central_trip_arrived',
      'trip_id': tripId,
    };
    if (driverName != null) payload['driver_name'] = driverName;
    if (vehicleModel != null) payload['vehicle_model'] = vehicleModel;
    if (vehicleColor != null) payload['vehicle_color'] = vehicleColor;
    if (vehiclePlate != null) payload['vehicle_plate'] = vehiclePlate;

    AppLogger.notificacao(
      'Awesome arrived payload => ${jsonEncode({
        'trip_id': tripId,
        'title': headline,
        'body': richBody,
        'summary': summary,
        'payload': payload,
        'large_icon_url': largeIconUrl ?? '',
      })}',
    );

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: tripId.hashCode,
        channelKey: serviceStatusChannelKey,
        icon: 'resource://drawable/ic_notification_small',
        title: headline,
        body: richBody,
        summary: summary,
        notificationLayout: NotificationLayout.BigText,
        wakeUpScreen: true,
        fullScreenIntent: false,
        autoDismissible: false,
        locked: true,
        category: NotificationCategory.Message,
        backgroundColor: const Color(0xFFF5F7F5),
        color: const Color(0xFFFDE500),
        largeIcon:
            (largeIconUrl ?? '').trim().isNotEmpty
                ? largeIconUrl!.trim()
                : 'resource://drawable/ic_logo_colored',
        roundedLargeIcon: (largeIconUrl ?? '').trim().isNotEmpty,
        displayOnForeground: true,
        displayOnBackground: true,
        payload: payload,
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'open_trip',
          label: 'Ver atendimento',
          color: const Color(0xFFFF184C),
          autoDismissible: true,
          showInCompactView: true,
        ),
        NotificationActionButton(
          key: 'reply_trip',
          label: 'Avisar prestador',
          requireInputText: true,
          autoDismissible: false,
          showInCompactView: true,
        ),
      ],
    );
  }
}
