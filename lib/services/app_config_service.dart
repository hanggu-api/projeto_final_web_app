import 'package:flutter/foundation.dart';
import '../core/config/supabase_config.dart';
import '../core/network/backend_api_client.dart';
import 'dart:async';
import 'dart:convert';

/// Serviço singleton que carrega configurações do app da tabela `app_configs`.
/// As configs são cacheadas em memória após a primeira carga.
class AppConfigService {
  static final AppConfigService _instance = AppConfigService._internal();
  factory AppConfigService() => _instance;
  AppConfigService._internal();

  final Map<String, dynamic> _cache = {};
  final BackendApiClient _backendApiClient = const BackendApiClient();
  bool _loaded = false;

  /// Pré-carrega todas as configs do banco. Deve ser chamado uma vez no startup.
  Future<void> preload() async {
    if (!SupabaseConfig.isInitialized) {
      debugPrint('⚠️ [AppConfig] Preload skipped: Supabase not initialized');
      return;
    }
    try {
      final response = await _backendApiClient.getJson(
        '/api/v1/app-configs',
        timeout: const Duration(seconds: 15),
      );
      final rows = (response?['data'] as List? ?? const <dynamic>[]);

      _cache.clear();
      for (final row in rows) {
        if (row is! Map) continue;
        final key = row['key']?.toString();
        if (key == null || key.trim().isEmpty) continue;
        _cache[key] = row['value'];
      }
      _loaded = true;
    } on TimeoutException catch (_) {
      debugPrint(
        '⚠️ [AppConfig] Timeout ao carregar configs; mantendo defaults/cache local.',
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

  num? _readNum(String key) {
    final raw = _cache[key];
    if (raw == null) return null;
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw);
    if (raw is Map<String, dynamic>) {
      final inner = raw['value'];
      if (inner is num) return inner;
      if (inner is String) return num.tryParse(inner);
    }
    return null;
  }

  /// Tempo (s) que o prestador tem para aceitar a oferta antes de expirar.
  /// Fonte: `app_configs.dispatch_notify_timeout_seconds`.
  int get dispatchNotifyTimeoutSeconds {
    final val = _readNum('dispatch_notify_timeout_seconds');
    return val?.toInt() ?? 30;
  }

  /// Taxa de cancelamento em R$ cobrada ao passageiro quando cancela
  /// após o motorista ter chegado ao local.
  double get cancellationFee {
    final val = _readNum('cancellation_fee');
    return val?.toDouble() ?? 5.0;
  }

  /// Tempo de espera gratuita em minutos antes de liberar cancelamento com taxa.
  int get waitTimeMinutes {
    final val = _readNum('wait_time_minutes');
    return val?.toInt() ?? 2;
  }

  /// Distância em metros do destino para gerar o PIX (plataforma).
  /// Regra: gerar somente perto do fim para evitar PIX expirado/cancelado.
  int get pixGenerateRadiusMeters {
    final val = _readNum('pix_generate_radius_m');
    return val?.toInt() ?? 500;
  }

  String getString(String key, {String defaultValue = ''}) {
    final raw = _cache[key];
    if (raw == null) return defaultValue;
    if (raw is String) return raw;
    if (raw is num || raw is bool) return raw.toString();
    if (raw is Map<String, dynamic>) {
      final inner = raw['value'];
      if (inner is String) return inner;
      if (inner is num || inner is bool) return inner.toString();
    }
    return defaultValue;
  }

  Map<String, dynamic> getMap(
    String key, {
    Map<String, dynamic> defaultValue = const {},
  }) {
    final raw = _cache[key];
    if (raw == null) return defaultValue;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map(
        (mapKey, mapValue) => MapEntry(mapKey.toString(), mapValue),
      );
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map(
            (mapKey, mapValue) => MapEntry(mapKey.toString(), mapValue),
          );
        }
      } catch (_) {
        return defaultValue;
      }
    }
    return defaultValue;
  }

  List<dynamic> getList(String key, {List<dynamic> defaultValue = const []}) {
    final raw = _cache[key];
    if (raw == null) return defaultValue;
    if (raw is List) return raw;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded;
      } catch (_) {
        return defaultValue;
      }
    }
    return defaultValue;
  }

  double getDouble(String key, {double defaultValue = 0}) {
    final raw = _readNum(key);
    return raw?.toDouble() ?? defaultValue;
  }

  /// URL pública do CRUD para resolver campanha de marketing da home.
  /// Fonte preferida: app_configs.marketing_home_ad_api_url
  String get marketingHomeAdApiUrl {
    return getString('marketing_home_ad_api_url', defaultValue: '');
  }

  /// Altura do banner de marketing da home.
  /// Fonte preferida: app_configs.marketing_home_ad_height
  double get marketingHomeAdHeight {
    return getDouble('marketing_home_ad_height', defaultValue: 0);
  }

  /// URL pública do CRUD para resolver campanha de marketing da tela de tracking.
  String get marketingTrackingAdApiUrl {
    return getString('marketing_tracking_ad_api_url', defaultValue: '');
  }

  /// Altura do banner de marketing do tracking.
  double get marketingTrackingAdHeight {
    return getDouble('marketing_tracking_ad_height', defaultValue: 0);
  }

  /// Inclinação visual do mapa da Home (efeito 3D leve), em radianos.
  /// Exemplo: 0.18 (~10.3 graus)
  double get homeMapTiltRadians {
    return getDouble('home_map_tilt_radians', defaultValue: 0.22).clamp(
      0.16,
      0.28,
    );
  }

  /// Perspectiva 3D do mapa da Home (Matrix4 setEntry(3,2,x)).
  double get homeMapTiltPerspective {
    return getDouble('home_map_tilt_perspective', defaultValue: 0.0018).clamp(
      0.0012,
      0.0028,
    );
  }

  /// Escala horizontal do mapa inclinado.
  double get homeMapTiltScaleX {
    return getDouble('home_map_tilt_scale_x', defaultValue: 1.02).clamp(
      1.00,
      1.08,
    );
  }

  /// Escala vertical do mapa inclinado.
  double get homeMapTiltScaleY {
    return getDouble('home_map_tilt_scale_y', defaultValue: 1.18).clamp(
      1.08,
      1.28,
    );
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
