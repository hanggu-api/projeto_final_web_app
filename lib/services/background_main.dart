import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/config/supabase_config.dart';
import '../firebase_options.dart';
import 'client_tracking_service.dart';
import 'network_status_service.dart';
import 'provider_keepalive_service.dart';

bool _backgroundServiceConfigured = false;

// Entry point for the background service
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter_background_service_android
  DartPluginRegistrant.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Firebase init error in background: $e');
  }

  try {
    await SupabaseConfig.initialize(
      disableAuthAutoRefresh: true,
      detectSessionInUri: false,
    );
  } catch (e) {
    debugPrint('Supabase init error in background: $e');
  }

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final networkStatus = NetworkStatusService();
  await networkStatus.ensureInitialized();

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

  final providerOnline = await ProviderKeepaliveService.isOnlineForDispatch();
  final clientTrackingActive = await ClientTrackingService.isTrackingEnabled();
  if (!providerOnline && !clientTrackingActive) {
    await service.stopSelf();
    return;
  }

  if (service is AndroidServiceInstance) {
    if (clientTrackingActive) {
      await ClientTrackingService.refreshServiceNotification(service);
    } else {
      await ProviderKeepaliveService.refreshServiceNotification(service);
    }
  }

  service.on('refreshContext').listen((event) async {
    final providerOnline = await ProviderKeepaliveService.isOnlineForDispatch();
    final clientTrackingActive = await ClientTrackingService.isTrackingEnabled();
    if (!providerOnline && !clientTrackingActive) {
      await service.stopSelf();
      return;
    }
    if (clientTrackingActive) {
      await ClientTrackingService.refreshServiceNotification(service);
    } else {
      await ProviderKeepaliveService.refreshServiceNotification(service);
    }
  });

  if (clientTrackingActive) {
    await ClientTrackingService.sendTrackingTick(source: 'background_start');
  } else {
    await ProviderKeepaliveService.sendHeartbeatTick(source: 'background_start');
  }

  Timer.periodic(ProviderKeepaliveService.heartbeatInterval, (timer) async {
    final providerOnline = await ProviderKeepaliveService.isOnlineForDispatch();
    final clientTrackingActive = await ClientTrackingService.isTrackingEnabled();
    if (!providerOnline && !clientTrackingActive) {
      timer.cancel();
      await service.stopSelf();
      return;
    }

    if (service is AndroidServiceInstance &&
        !await service.isForegroundService()) {
      if (clientTrackingActive) {
        await ClientTrackingService.refreshServiceNotification(service);
      } else {
        await ProviderKeepaliveService.refreshServiceNotification(service);
      }
    }

    await networkStatus.refreshConnectivity();
    if (clientTrackingActive) {
      await ClientTrackingService.sendTrackingTick(source: 'background');
    } else {
      await ProviderKeepaliveService.sendHeartbeatTick(source: 'background');
    }
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

Future<void> initializeBackgroundService() async {
  if (_backgroundServiceConfigured) return;

  if (!ProviderKeepaliveService.supportsBackgroundService) {
    debugPrint(
      'ℹ️ [BackgroundService] Ignorado em ${kIsWeb ? "web" : defaultTargetPlatform.name}',
    );
    return;
  }

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
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // Mantendo false para segurança no boot
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: 'foreground_service_channel',
      initialNotificationTitle: '101 Service',
      initialNotificationContent: 'Online para receber pedidos',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [
        AndroidForegroundType.dataSync,
        AndroidForegroundType.location,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  // await service.startService(); // Disabled to prevent crash on launch. Start manually after permissions.
  _backgroundServiceConfigured = true;
}
