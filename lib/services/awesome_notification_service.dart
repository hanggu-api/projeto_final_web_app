import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

/// Camada paralela de migracao para Awesome Notifications.
/// Ainda nao substitui o fluxo atual; serve para introduzir canais e setup
/// sem quebrar firebase_messaging + flutter_local_notifications.
class AwesomeNotificationService {
  AwesomeNotificationService._();

  static final AwesomeNotificationService instance =
      AwesomeNotificationService._();

  static const String urgentChannelKey = 'high_importance_channel_v3';
  static const String uberOffersChannelKey = 'uber_trip_offers_channel';
  static const String uberUpdatesChannelKey = 'uber_trip_updates_channel';
  static const String chatChannelKey = 'chat_messages_channel';

  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    await AwesomeNotifications().initialize('resource://mipmap/launcher_icon', [
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
        channelKey: uberOffersChannelKey,
        channelName: 'Uber: Ofertas de Corrida',
        channelDescription: 'Ofertas de corrida para motoristas.',
        defaultColor: const Color(0xFFFDE500),
        ledColor: const Color(0xFFFDE500),
        importance: NotificationImportance.Max,
        channelShowBadge: true,
        playSound: true,
        criticalAlerts: true,
        defaultPrivacy: NotificationPrivacy.Public,
      ),
      NotificationChannel(
        channelKey: uberUpdatesChannelKey,
        channelName: 'Uber: Atualizacoes de Corrida',
        channelDescription: 'Atualizacoes de status das corridas.',
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

    _initialized = true;
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
        channelKey: uberUpdatesChannelKey,
        title: 'Teste Awesome Notifications',
        body: 'Base pronta para migracao premium das notificacoes Uber.',
        notificationLayout: NotificationLayout.BigText,
        wakeUpScreen: false,
        category: NotificationCategory.Status,
        backgroundColor: const Color(0xFFF5F7F5),
        color: const Color(0xFFFDE500),
      ),
    );
  }

  Future<void> showPremiumDriverArrivedPreview() async {
    if (!_initialized || kIsWeb) return;

    await _showPremiumDriverArrived(
      tripId: 'awesome-preview-trip',
      driverName: 'Ricardo Silva',
      vehicleModel: 'Toyota Corolla',
      vehiclePlate: 'ABC-1234',
      title: 'Motorista chegou',
      body:
          'Seu motorista Toyota Corolla (ABC-1234) esta aguardando no local de embarque.\n\nApos 2 minutos de espera, taxas de espera podem ser cobradas.',
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
    String? vehiclePlate,
    String? largeIconUrl,
  }) async {
    if (!_initialized || kIsWeb) return;

    await _showPremiumDriverArrived(
      tripId: tripId,
      driverName: driverName,
      vehicleModel: vehicleModel,
      vehiclePlate: vehiclePlate,
      title: title,
      body: body,
      largeIconUrl: largeIconUrl,
    );
  }

  Future<void> _showPremiumDriverArrived({
    required String tripId,
    required String title,
    required String body,
    String? driverName,
    String? vehicleModel,
    String? vehiclePlate,
    String? largeIconUrl,
  }) async {
    final richBody = StringBuffer(body);
    if ((driverName ?? '').isNotEmpty ||
        (vehicleModel ?? '').isNotEmpty ||
        (vehiclePlate ?? '').isNotEmpty) {
      richBody.write('\n\n');
      if ((driverName ?? '').isNotEmpty) {
        richBody.write('Motorista: $driverName');
      }
      if ((vehicleModel ?? '').isNotEmpty || (vehiclePlate ?? '').isNotEmpty) {
        if ((driverName ?? '').isNotEmpty) richBody.write('\n');
        final vehicleLabel = [
          if ((vehicleModel ?? '').isNotEmpty) vehicleModel,
          if ((vehiclePlate ?? '').isNotEmpty) vehiclePlate,
        ].join(' • ');
        richBody.write('Veiculo: $vehicleLabel');
      }
    }

    final payload = <String, String>{
      'type': 'uber_trip_arrived',
      'trip_id': tripId,
    };
    if (driverName != null) payload['driver_name'] = driverName;
    if (vehicleModel != null) payload['vehicle_model'] = vehicleModel;
    if (vehiclePlate != null) payload['vehicle_plate'] = vehiclePlate;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: tripId.hashCode,
        channelKey: uberUpdatesChannelKey,
        title: title,
        body: richBody.toString(),
        summary: '101 SERVICE • AGORA',
        notificationLayout: NotificationLayout.BigText,
        wakeUpScreen: true,
        fullScreenIntent: false,
        autoDismissible: false,
        locked: true,
        category: NotificationCategory.Message,
        backgroundColor: const Color(0xFFF5F7F5),
        color: const Color(0xFFFDE500),
        largeIcon: largeIconUrl,
        roundedLargeIcon: true,
        payload: payload,
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'open_trip',
          label: 'Ver detalhes',
          color: const Color(0xFFFF184C),
          autoDismissible: true,
          showInCompactView: true,
        ),
        NotificationActionButton(
          key: 'reply_trip',
          label: 'Responder',
          requireInputText: true,
          autoDismissible: false,
          showInCompactView: true,
        ),
      ],
    );
  }
}
