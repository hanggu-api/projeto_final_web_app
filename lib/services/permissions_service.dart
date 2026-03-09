import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class PermissionsService {
  static final PermissionsService _instance = PermissionsService._internal();
  factory PermissionsService() => _instance;
  PermissionsService._internal();

  /// Mapa de status de permissões
  Map<String, String> _permissionsStatus = {};

  /// Dados de telemetria do dispositivo
  Map<String, String> _deviceTelemetry = {};

  /// Verifica todas as permissões relevantes
  Future<Map<String, String>> checkAllPermissions() async {
    final permissions = <String, String>{};

    // Permissão de Localização
    final locationStatus = await _checkLocationPermission();
    permissions['location_permission'] = locationStatus;

    // Permissão de Notificação
    final notificationStatus = await _checkNotificationPermission();
    permissions['notification_permission'] = notificationStatus;

    _permissionsStatus = permissions;
    return permissions;
  }

  Future<String> _checkLocationPermission() async {
    final always = await Permission.locationAlways.status;
    final whenInUse = await Permission.locationWhenInUse.status;

    if (always.isGranted) return 'Always';
    if (whenInUse.isGranted) return 'WhileInUse';
    return 'Denied';
  }

  Future<String> _checkNotificationPermission() async {
    final status = await Permission.notification.status;
    return status.isGranted ? 'Granted' : 'Denied';
  }

  /// Coleta telemetria completa do dispositivo
  Future<Map<String, String>> collectDeviceTelemetry() async {
    final telemetry = <String, String>{};
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        telemetry['device_name'] = androidInfo.model;
        telemetry['device_model'] = androidInfo.model;
        telemetry['os_version'] = 'Android ${androidInfo.version.release}';
        telemetry['device_platform'] = 'android';
        telemetry['device_id'] = androidInfo.id; // Android ID
        telemetry['manufacturer'] = androidInfo.manufacturer;
        telemetry['app_version'] = androidInfo.version.sdkInt.toString();
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        telemetry['device_name'] = iosInfo.name;
        telemetry['device_model'] = iosInfo.model;
        telemetry['os_version'] = iosInfo.systemVersion;
        telemetry['device_platform'] = 'ios';
        telemetry['device_id'] = iosInfo.identifierForVendor ?? 'Unknown';
        telemetry['app_version'] = iosInfo.utsname.version;
      }

      // Campos comuns
      telemetry['timestamp'] = DateTime.now().toIso8601String();
    } catch (e) {
      debugPrint('❌ Erro ao coletar telemetria: $e');
      telemetry['error'] = e.toString();
    }

    _deviceTelemetry = telemetry;
    return telemetry;
  }

  /// Payload completo para envio ao backend
  Future<Map<String, dynamic>> buildRegistrationPayload({
    required String fcmToken,
    double? latitude,
    double? longitude,
  }) async {
    final permissions = await checkAllPermissions();
    final telemetry = await collectDeviceTelemetry();

    return {
      'token': fcmToken,
      'platform':
          telemetry['device_platform'] ?? (Platform.isIOS ? 'ios' : 'android'),
      'latitude': latitude,
      'longitude': longitude,
      ...permissions,
      ...telemetry,
    };
  }

  Map<String, String> get permissionsStatus =>
      Map.unmodifiable(_permissionsStatus);
  Map<String, String> get deviceTelemetry => Map.unmodifiable(_deviceTelemetry);
}
