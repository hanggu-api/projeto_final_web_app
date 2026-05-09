import 'package:flutter/foundation.dart';

class AppLogger {
  static const String _logMode = String.fromEnvironment(
    'APP_LOG_MODE',
    defaultValue: 'critical',
  ); // critical | important | verbose | silent

  static bool showDebugLogs = kDebugMode && _logMode != 'silent';
  static bool compactRidePaymentLogsOnly = _logMode != 'verbose';

  static bool _containsAny(String source, List<String> needles) {
    for (final needle in needles) {
      if (source.contains(needle)) return true;
    }
    return false;
  }

  static bool _shouldEmit({required String category, required String message}) {
    if (!showDebugLogs) return false;
    final lower = message.toLowerCase();

    // Sempre manter erros críticos
    const errorNeedles = [
      'erro',
      'error',
      'exception',
      'falha',
      'failed',
      'invalid',
      'unauthorized',
      'forbidden',
      'timeout',
      'stack trace',
    ];
    if (category == 'ERRO' || _containsAny(lower, errorNeedles)) {
      return true;
    }

    if (_logMode == 'verbose') return true;

    const criticalNeedles = [
      'status mudou',
      'status change',
      'pagamento confirmado',
      'payment confirmed',
      'webhook',
      'awaiting_confirmation',
      'serviço concluído',
      'servico concluido',
      'service completed',
      'crédito',
      'credito',
      'wallet',
      'carteira',
      'dispatch',
    ];

    const criticalCategories = ['SUCESSO', 'ALERTA', 'SISTEMA'];
    if (_logMode == 'critical') {
      return criticalCategories.contains(category) &&
          _containsAny(lower, criticalNeedles);
    }

    if (!compactRidePaymentLogsOnly) return true;

    // Em modo "important", mostrar apenas sinais de negócio relevantes
    // para acompanhar fluxo crítico sem poluir terminal.
    const importantNeedles = [
      'serviço concluído',
      'servico concluido',
      'finalizar serviço',
      'finalizar servico',
      'confirm_completion',
      'awaiting_confirmation',
      'wallet',
      'carteira',
      'saldo',
      'pix',
      'pagamento',
      'crédito',
      'credito',
      'rpc_confirm_completion',
      'service completed',
    ];

    // Logs de alto nível com categorias mais úteis
    const importantCategories = ['SUCESSO', 'ALERTA', 'API'];
    if (importantCategories.contains(category) &&
        _containsAny(lower, importantNeedles)) {
      return true;
    }

    // Também aceita linhas de debugPrint com esses sinais
    return _containsAny(lower, importantNeedles);
  }

  static bool shouldEmitRaw(String message, {String category = 'RAW'}) {
    return _shouldEmit(category: category, message: message);
  }

  static void _print(String icon, String category, String message) {
    if (_shouldEmit(category: category, message: message)) {
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
    if (important || _shouldEmit(category: 'LOG', message: message)) {
      // ignore: avoid_print
      print(message);
    }
  }
}

void customDebugPrint(String? message, {int? wrapWidth}) {
  if (message == null) return;
  if (AppLogger._shouldEmit(category: 'DEBUG_PRINT', message: message)) {
    debugPrintThrottled(message, wrapWidth: wrapWidth);
  }
}
