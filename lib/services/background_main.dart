import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';

// Entry point for the background service
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter_background_service_android
  DartPluginRegistrant.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init error in background: $e');
  }

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          'foreground_service_channel',
          'Online Service',
          description: 'Mantendo o app ativo para receber pedidos',
          importance: Importance.low,
        ),
      );

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  /*
  // Initial notification
  if (service is AndroidServiceInstance) {
    if (await service.isForegroundService()) {
      flutterLocalNotificationsPlugin.show(
        888,
        '101 Service',
        'Você está online e pronto para receber pedidos',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'foreground_service_channel',
            'Online Service',
            icon: '@mipmap/launcher_icon',
            ongoing: true,
          ),
        ),
      );
    }
  }

  // Timer for Heartbeat / Keep Alive
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        flutterLocalNotificationsPlugin.show(
          888,
          '101 Service',
          'Você está online e pronto para receber pedidos',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'foreground_service_channel',
              'Online Service',
              icon: '@mipmap/launcher_icon',
              ongoing: true,
            ),
          ),
        );

        await _sendHeartbeat();
      }
    }
  });
  */
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Create the notification channel on the main isolate as well
  // This ensures it exists before the service tries to use it
  // É CRÍTICO criar um canal de notificação para o Android 12+ ANTES de configurar o serviço
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'foreground_service_channel',
    'Serviço em Segundo Plano',
    description: 'Este canal é usado para manter o app ativo.',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // Mantendo false para segurança no boot
      isForegroundMode: true,
      notificationChannelId: 'foreground_service_channel',
      initialNotificationTitle: 'App Ativo',
      initialNotificationContent: 'Otimizando processos...',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.specialUse, AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  // await service.startService(); // Disabled to prevent crash on launch. Start manually after permissions.
}
