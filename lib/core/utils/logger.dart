import 'package:flutter/foundation.dart';

class AppLogger {
  static bool showDebugLogs = kDebugMode;

  static void _print(String icon, String category, String message) {
    if (showDebugLogs) {
      final timestamp = DateTime.now()
          .toIso8601String()
          .split('T')
          .last
          .substring(0, 8);
      // ignore: avoid_print
      print('$icon [$timestamp] [$category] $message');
    }
  }

  static void sistema(String message) => _print('⚙️', 'SISTEMA', message);
  static void api(String message) => _print('🌐', 'API', message);
  static void erro(String message, [dynamic details]) => _print(
    '❌',
    'ERRO',
    details != null ? '$message | Detalhe: $details' : message,
  );
  static void sucesso(String message) => _print('✅', 'SUCESSO', message);
  static void info(String message) => _print('ℹ️', 'INFO', message);
  static void alerta(String message) => _print('⚠️', 'ALERTA', message);
  static void debug(String message) => _print('🐛', 'DEBUG', message);
  static void despacho(String message) => _print('🚚', 'DESPACHO', message);
  static void notificacao(String message) =>
      _print('🔔', 'NOTIFICAÇÃO', message);
  static void viagem(String message) => _print('🚦', 'VIAGEM', message);

  // Mantido para compatibilidade temporária
  static void log(String message, {bool important = false}) {
    if (important || showDebugLogs) {
      // ignore: avoid_print
      print(message);
    }
  }
}

void customDebugPrint(String? message, {int? wrapWidth}) {
  if (message == null) return;
  if (AppLogger.showDebugLogs) {
    debugPrintThrottled(message, wrapWidth: wrapWidth);
  }
}
