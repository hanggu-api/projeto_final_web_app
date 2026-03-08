import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serviço singleton que carrega configurações do app da tabela `app_configs`.
/// As configs são cacheadas em memória após a primeira carga.
class AppConfigService {
  static final AppConfigService _instance = AppConfigService._internal();
  factory AppConfigService() => _instance;
  AppConfigService._internal();

  final Map<String, dynamic> _cache = {};
  bool _loaded = false;

  /// Pré-carrega todas as configs do banco. Deve ser chamado uma vez no startup.
  Future<void> preload() async {
    try {
      final rows = await Supabase.instance.client
          .from('app_configs')
          .select('key, value')
          .timeout(const Duration(seconds: 8));

      _cache.clear();
      for (final row in rows) {
        _cache[row['key'] as String] = row['value'];
      }
      _loaded = true;
      debugPrint(
        '✅ [AppConfig] ${_cache.length} configurações carregadas: ${_cache.keys.toList()}',
      );
    } catch (e) {
      debugPrint(
        '⚠️ [AppConfig] Falha ao carregar configs (usando defaults): $e',
      );
    }
  }

  /// Recarrega configs do banco.
  Future<void> reload() async {
    _loaded = false;
    await preload();
  }

  bool get isLoaded => _loaded;

  // ──────────────────────────────────────────
  // Getters tipados com valores padrão seguros
  // ──────────────────────────────────────────

  /// Taxa de cancelamento em R$ cobrada ao passageiro quando cancela
  /// após o motorista ter chegado ao local.
  double get cancellationFee {
    final val = _cache['cancellation_fee']?['value'];
    return (val as num?)?.toDouble() ?? 5.0;
  }

  /// Tempo de espera gratuita em minutos antes de liberar cancelamento com taxa.
  int get waitTimeMinutes {
    final val = _cache['wait_time_minutes']?['value'];
    return (val as num?)?.toInt() ?? 2;
  }

  // ──────────────────────────────────────────
  // Lógica de Tributação Flexível
  // ──────────────────────────────────────────

  Map<String, dynamic> get _taxation => _cache['taxation_config'] ?? {};
  Map<String, dynamic> get _motoFare => _cache['moto_fare_config'] ?? {};

  String get taxationModel => _taxation['model']?.toString() ?? 'percentage';

  double get taxationPercentage =>
      (_taxation['percentage_value'] as num?)?.toDouble() ?? 15.0;

  double get taxationFixedAmount =>
      (_taxation['fixed_value'] as num?)?.toDouble() ?? 2.50;

  double get additionalFee =>
      (_taxation['additional_fee'] as num?)?.toDouble() ?? 1.00;

  // ──────────────────────────────────────────
  // Configurações de Tarifa Moto
  // ──────────────────────────────────────────

  double get motoBaseFare =>
      (_motoFare['base_fare'] as num?)?.toDouble() ?? 3.00;
  double get motoPerKm => (_motoFare['per_km'] as num?)?.toDouble() ?? 1.00;
  double get motoPerMinute =>
      (_motoFare['per_minute'] as num?)?.toDouble() ?? 0.10;
  double get motoMinimumFare =>
      (_motoFare['minimum_fare'] as num?)?.toDouble() ?? 5.00;

  /// Calcula o ganho líquido do motorista baseado no modelo de tributação.
  double calculateNetGain(double fare) {
    double deduction = 0;

    if (taxationModel == 'percentage') {
      deduction = fare * (taxationPercentage / 100);
    } else {
      deduction = taxationFixedAmount;
    }

    return fare - deduction - additionalFee;
  }

  /// Retorna apenas o valor descontado (Comissão + Taxa Adicional)
  double calculateDeduction(double fare) {
    if (taxationModel == 'percentage') {
      return (fare * (taxationPercentage / 100)) + additionalFee;
    }
    return taxationFixedAmount + additionalFee;
  }
}
