import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:device_info_plus/device_info_plus.dart';

class SecurityMiddleware {
  static bool? _isSecure;
  static DateTime? _lastCheck;
  static const _checkInterval = Duration(hours: 1);

  /// Verifica integridade do ambiente. Cache de 1h para performance.
  /// ATENÇÃO: este cache pode ser burlado se o ambiente mudar durante a execução.
  /// Para operações críticas, force uma nova checagem passando forceRefresh=true.
  static Future<bool> checkEnvironment({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _isSecure != null && 
        _lastCheck != null && 
        DateTime.now().difference(_lastCheck!) < _checkInterval) {
      return _isSecure!;
    }

    bool isRooted = false;
    bool isEmulator = false;

    try {
      if (Platform.isAndroid) {
        isRooted = await FlutterJailbreakDetection.jailbroken;
        isEmulator = !(await DeviceInfoPlugin().androidInfo).isPhysicalDevice;
      } else if (Platform.isIOS) {
        isRooted = await FlutterJailbreakDetection.jailbroken;
        isEmulator = !(await DeviceInfoPlugin().iosInfo).isPhysicalDevice;
      }
    } catch (_) {
      // Falha na detecção = ambiente inseguro por princípio
      isRooted = true; 
    }

    final newSecureState = !kDebugMode && !isRooted && !isEmulator;
    
    // Se o estado mudou de seguro para inseguro, invalida cache imediatamente
    // para evitar que operações críticas usem cache desatualizado
    if (_isSecure != null && _isSecure! && !newSecureState) {
      _isSecure = null;
      _lastCheck = null;
      debugPrint('🚨 [Security] ALERTA: ambiente tornou-se INSEGURO. Cache invalidado.');
      return await checkEnvironment(forceRefresh: true);
    }
    
    _isSecure = newSecureState;
    _lastCheck = DateTime.now();

    if (!_isSecure!) {
      debugPrint('🚨 [Security] Ambiente comprometido: debug=$kDebugMode root=$isRooted emulator=$isEmulator');
    }
    return _isSecure!;
  }

  /// Wrapper seguro para chamadas críticas (ex: PIX, login, perfil)
  static Future<T> secureCall<T>(Future<T> Function() apiCall) async {
    final safe = await checkEnvironment();
    if (!safe && !kDebugMode) {
      debugPrint('⚠️ [Security] Operação bloqueada: ambiente não seguro.');
      throw SecurityException('Operação bloqueada: dispositivo não confiável.');
    }
    if (!safe && kDebugMode) {
      debugPrint('⚠️ [Security] AVISO: ambiente não seguro, mas em modo debug. Prosseguindo com cautela.');
    }
    return apiCall();
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  @override String toString() => message;
}
