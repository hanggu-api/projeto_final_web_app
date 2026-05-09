import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import '../core/config/supabase_config.dart';
import '../core/utils/payment_audit_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'app_config_service.dart';
import 'data_gateway.dart';
import 'payment/payment_service.dart';
import 'support/central_payment_policy.dart';
import 'package:synchronized/synchronized.dart';

class _MpInitCacheEntry {
  final DateTime at;
  final Map<String, dynamic> data;

  _MpInitCacheEntry(this.at, this.data);
}

class CentralService {
  final ApiService _api = ApiService();
  static const bool _tripRuntimeEnabled = false;

  static final CentralService _instance = CentralService._internal();
  factory CentralService() => _instance;
  CentralService._internal();

  Timer? _simulationTimer;
  StreamController<int>? _simulationProgressController;
  final Lock _lock = Lock();
  final Map<String, Future<Map<String, dynamic>>> _mpInitInFlight = {};
  final Map<String, _MpInitCacheEntry> _mpInitCache = {};
  static const _pixAutoPayLocalQa = String.fromEnvironment(
    'PIX_AUTO_PAY_LOCAL',
    defaultValue: 'false',
  );

  bool get _allowLocalPixAutoPay {
    // Segurança: simulação automática de PIX desativada por padrão em todos ambientes.
    // Só ativa se explicitamente forçado no build para QA local.
    if (!kDebugMode) return false;
    final flag = _pixAutoPayLocalQa.toLowerCase().trim();
    return flag == 'force';
  }

  bool _isGenericCardSelection(String method) {
    final raw = method.trim();
    final lower = raw.toLowerCase();
    return raw == 'Card' ||
        raw.startsWith('Card_') ||
        lower == 'cartão (plataforma)' ||
        lower == 'cartao (plataforma)' ||
        lower == 'método salvo' ||
        lower == 'metodo salvo';
  }

  bool _looksLikeUuid(String value) {
    final v = value.trim();
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(v);
  }

  bool _looksLikeCardTechnicalIdentifier(String value) {
    final raw = value.trim().toLowerCase();
    if (_looksLikeUuid(raw)) return true;
    if (raw.startsWith('aact_') || raw.startsWith('tok_')) return true;
    return raw.length > 32;
  }

  Future<String> _resolveSpecificOrFallbackCardPaymentMethodId(
    String candidateMethodId,
  ) async {
    final userIdRaw = _api.userId;
    if (userIdRaw == null || userIdRaw.trim().isEmpty) {
      throw ApiException(
        message: 'Usuário inválido para resolver forma de pagamento.',
        statusCode: 400,
      );
    }

    final userIdInt = int.tryParse(userIdRaw.trim());
    if (userIdInt == null) {
      throw ApiException(
        message: 'Usuário inválido para resolver cartão do pagamento.',
        statusCode: 400,
      );
    }

    final response = await Supabase.instance.client
        .from('user_payment_methods')
        .select('id,is_default,mp_card_id,created_at')
        .eq('user_id', userIdInt)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);

    final methods = (response as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final methodsWithToken = methods
        .where((row) => (row['mp_card_id'] ?? '').toString().trim().isNotEmpty)
        .toList();

    final candidateLower = candidateMethodId.trim().toLowerCase();

    Map<String, dynamic>? matched;
    for (final row in methodsWithToken) {
      final id = (row['id'] ?? '').toString().trim().toLowerCase();
      final mpCardId = (row['mp_card_id'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (candidateLower == id || candidateLower == mpCardId) {
        matched = row;
        break;
      }
    }

    if (matched != null) {
      final resolved = matched['id'].toString();
      debugPrint(
        '💳 [CentralService] Cartão do pagamento validado por método específico: $resolved',
      );
      return resolved;
    }

    if (methodsWithToken.isNotEmpty) {
      Map<String, dynamic>? defaultCard;
      for (final row in methodsWithToken) {
        if (row['is_default'] == true) {
          defaultCard = row;
          break;
        }
      }
      final resolved = (defaultCard ?? methodsWithToken.first)['id'].toString();
      debugPrint(
        '⚠️ [CentralService] Método técnico inválido/stale ($candidateMethodId). '
        'Usando cartão válido de fallback: $resolved',
      );
      return resolved;
    }

    throw ApiException(
      message:
          'Nenhum cartão válido encontrado. Recadastre seu cartão para continuar.',
      statusCode: 400,
    );
  }

  Future<String> _resolveCardPaymentMethodIdForTrip() async {
    final userIdRaw = _api.userId;
    if (userIdRaw == null || userIdRaw.trim().isEmpty) {
      throw ApiException(
        message: 'Usuário inválido para resolver forma de pagamento.',
        statusCode: 400,
      );
    }

    final userIdInt = int.tryParse(userIdRaw.trim());
    if (userIdInt == null) {
      throw ApiException(
        message: 'Usuário inválido para resolver cartão do pagamento.',
        statusCode: 400,
      );
    }

    final userRow = await Supabase.instance.client
        .from('users')
        .select('preferred_payment_method')
        .eq('id', userIdInt)
        .maybeSingle();
    final preferredRaw = (userRow?['preferred_payment_method'] ?? '')
        .toString()
        .trim();
    final preferredLower = preferredRaw.toLowerCase();

    final response = await Supabase.instance.client
        .from('user_payment_methods')
        .select('id,is_default,mp_card_id,created_at')
        .eq('user_id', userIdInt)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);

    final methods = (response as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final methodsWithToken = methods
        .where((row) => (row['mp_card_id'] ?? '').toString().trim().isNotEmpty)
        .toList();

    Map<String, dynamic>? preferredCard;
    for (final row in methodsWithToken) {
      if (row['id']?.toString().trim().toLowerCase() == preferredLower) {
        preferredCard = row;
        break;
      }
    }
    if (preferredCard != null) {
      final resolved = preferredCard['id'].toString();
      debugPrint(
        '💳 [CentralService] Cartão do pagamento resolvido por preferência: $resolved',
      );
      return resolved;
    }

    Map<String, dynamic>? defaultCard;
    for (final row in methodsWithToken) {
      if (row['is_default'] == true) {
        defaultCard = row;
        break;
      }
    }
    if (defaultCard != null) {
      final resolved = defaultCard['id'].toString();
      debugPrint(
        '💳 [CentralService] Cartão do pagamento resolvido por default: $resolved',
      );
      return resolved;
    }

    if (methodsWithToken.isNotEmpty) {
      final resolved = methodsWithToken.first['id'].toString();
      debugPrint(
        '💳 [CentralService] Cartão do pagamento resolvido por fallback recente: $resolved',
      );
      return resolved;
    }

    throw ApiException(
      message:
          'Nenhum cartão válido encontrado. Recadastre seu cartão para continuar.',
      statusCode: 400,
    );
  }

  Future<String> resolveTripPaymentMethodId({
    required String selectedPaymentMethod,
  }) async {
    final normalized = selectedPaymentMethod.trim();
    if (normalized.isEmpty) return 'PIX';
    if (_isGenericCardSelection(normalized)) {
      return _resolveCardPaymentMethodIdForTrip();
    }
    if (_looksLikeCardTechnicalIdentifier(normalized)) {
      return _resolveSpecificOrFallbackCardPaymentMethodId(normalized);
    }
    return normalized;
  }

  /// Resolve detalhes completos de um método de pagamento
  Future<Map<String, dynamic>> resolvePaymentMethodDetails(
    String methodId,
  ) async {
    final userIdRaw = _api.userId;
    if (userIdRaw == null) {
      throw ApiException(message: 'Usuário não autenticado', statusCode: 401);
    }
    final userIdInt = int.parse(userIdRaw);

    final normalized = methodId.trim();

    // Se for um ID genérico ou preferência, precisamos descobrir qual é o cartão real
    String targetId = normalized;
    if (_isGenericCardSelection(normalized)) {
      targetId = await _resolveCardPaymentMethodIdForTrip();
    }

    final response = await Supabase.instance.client
        .from('user_payment_methods')
        .select(
          'id,user_id,gateway_name,brand,last_four,expiry_month,expiry_year,'
          'holder_name,is_default,status,created_at,updated_at,mp_card_id',
        )
        .eq('user_id', userIdInt)
        .eq('id', targetId)
        .maybeSingle();

    if (response == null) {
      throw ApiException(
        message: 'Método de pagamento não encontrado',
        statusCode: 404,
      );
    }

    return Map<String, dynamic>.from(response);
  }

  static const Duration _mpInitCacheTtl = Duration(seconds: 20);

  Stream<int>? get simulationProgress => _simulationProgressController?.stream;

  Map<String, dynamic> _errorToMap(Object error) {
    if (error is ApiException) {
      final base = <String, dynamic>{
        'success': false,
        'error': error.message,
        'status_code': error.statusCode,
      };
      if (error.details != null) {
        base.addAll(error.details!);
      }
      return base;
    }
    return {'success': false, 'error': error.toString()};
  }

  ApiException _tripRuntimeDisabledException([String? action]) {
    final label = (action ?? 'Fluxo legado de atendimento')
        .trim()
        .replaceFirstMapped(
          RegExp(r'^[a-z]'),
          (m) => m.group(0)!.toUpperCase(),
        );
    return ApiException(
      message: '$label desativado neste build.',
      statusCode: 410,
      details: const {'reason_code': 'TRIP_RUNTIME_DISABLED'},
    );
  }

  Future<Map<String, dynamic>?> refreshUserStatus() async {
    return await _api.getUserData();
  }

  /// Verifica se o módulo legado de corridas está habilitado nas configurações globais
  Future<bool> isModuleEnabled() async {
    try {
      final config = await _api.getAppConfig();
      return config['central_module_enabled'] == 'true' ||
          config['central_module_enabled'] == true;
    } catch (e) {
      return false;
    }
  }

  // Taxas por tipo de pagamento
  static const double feePixPlataforma = CentralPaymentPolicy.feePixPlataforma;
  static const double feeMercadoPagoPlataforma =
      CentralPaymentPolicy.feeMercadoPagoPlataforma;
  static const double feeCartaoPlataforma =
      CentralPaymentPolicy.feeCartaoPlataforma;
  static const double feeCartaoMaquina = CentralPaymentPolicy.feeCartaoMaquina;

  /// Calcula o preço final com taxas baseado no método de pagamento
  double calculateFareWithFees(double baseFare, String paymentMethod) {
    return CentralPaymentPolicy.calculateFareWithFees(baseFare, paymentMethod);
  }

  /// Calcula o preço estimado do deslocamento legado
  Future<dynamic> calculateFare({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required int vehicleTypeId,
    double? distanceKm,
    double? durationMin,
  }) async {
    try {
      // Tenta calcular via Edge Function (Backend)
      final backendFare = await _api.calculateUberFare(
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropoffLat: dropoffLat,
        dropoffLng: dropoffLng,
        vehicleTypeId: vehicleTypeId,
      );
      return backendFare;
    } catch (e) {
      debugPrint(
        '⚠️ [CentralService] Falha no cálculo via Backend, usando lógica local: $e',
      );

      // Fallback local se o backend falhar ou se for Moto com config específica
      if (vehicleTypeId == 3) {
        // Moto
        final config = AppConfigService();
        final dist = distanceKm ?? 0.0;
        final dur = durationMin ?? 0.0;

        double fare =
            config.motoBaseFare +
            (dist * config.motoPerKm) +
            (dur * config.motoPerMinute);

        if (fare < config.motoMinimumFare) fare = config.motoMinimumFare;

        return {
          'fare': fare,
          'is_local': true,
          'details': 'Calculado localmente (Moto)',
        };
      }

      // Fallback genérico para outros veículos (preservando comportamento)
      rethrow;
    }
  }

  /// Busca taxas de cancelamento pendentes do passageiro logado
  Future<List<Map<String, dynamic>>> getPendingCancellationFees() async {
    return [];
  }

  /// Solicita uma nova viagem
  Future<Map<String, dynamic>> requestTrip({
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double dropoffLat,
    required double dropoffLng,
    required String dropoffAddress,
    required int vehicleTypeId,
    required String paymentMethod,
    double? fare,
    double? feePlatformRate,
    double? feePlatformAmount,
    double? driverNetAmount,
    List<String>? feeIdsToPay, // IDs das multas sendo pagas neste fluxo legado
    String status = 'searching',
  }) async {
    throw _tripRuntimeDisabledException('Solicitação de corrida');
  }

  /// Sincroniza dados do cliente com o Mercado Pago.
  Future<void> syncMercadoPagoCustomer() async {
    final String? userId = _api.userId;
    if (userId == null) return;

    debugPrint('🏦 [MercadoPago] Sincronizando cliente para user: $userId...');
    try {
      final parsedId = int.tryParse(userId);
      if (parsedId != null) {
        final customerId = await PaymentService().ensureCustomerForUser(
          userId: parsedId,
          gatewayName: 'mercado_pago',
        );
        if (customerId == null || customerId.trim().isEmpty) {
          debugPrint(
            'ℹ️ [MercadoPago] Cliente não sincronizado (sem conta conectada ou CPF ausente).',
          );
          return;
        }
      }
      debugPrint('✅ [MercadoPago] Cliente sincronizado');
    } catch (e) {
      debugPrint('❌ [MercadoPago] Erro na sincronização: $e');
      rethrow;
    }
  }

  /// Motorista: Inicializa e verifica status da conta Mercado Pago.
  Future<Map<String, dynamic>> initMercadoPagoDriverAccount(
    String? driverId, {
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final key = (driverId ?? _api.userId ?? '').trim();
    if (key.isEmpty) return {'ready': false, 'error': 'No driver ID'};

    return await _lock.synchronized(() async {
      if (!forceRefresh) {
        final cached = _mpInitCache[key];
        if (cached != null && now.difference(cached.at) <= _mpInitCacheTtl) {
          return cached.data;
        }

        final inFlight = _mpInitInFlight[key];
        if (inFlight != null) {
          debugPrint(
            '⏳ [PaymentAccount] Reutilizando verificação Mercado Pago em andamento para motorista $key',
          );
          return inFlight;
        }
      }

      final future = _initMercadoPagoDriverAccountInternal(key).then((result) {
        _mpInitCache[key] = _MpInitCacheEntry(DateTime.now(), result);
        _mpInitInFlight.remove(key);
        return result;
      });

      _mpInitInFlight[key] = future;
      return future;
    });
  }

  Future<Map<String, dynamic>> _initMercadoPagoDriverAccountInternal(
    String driverId,
  ) async {
    debugPrint(
      '🛡️ [PaymentAccount] Verificando conta Mercado Pago para motorista $driverId...',
    );
    final client = Supabase.instance.client;
    final user = await client
        .from('users')
        .select('driver_payment_mode, mp_account_status, mp_collector_id')
        .eq('id', driverId)
        .maybeSingle();

    final mode = (user?['driver_payment_mode'] ?? 'platform')
        .toString()
        .trim()
        .toLowerCase();
    final mpStatus = (user?['mp_account_status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final collectorId = (user?['mp_collector_id'] ?? '').toString().trim();

    // Modo direct: motorista pode operar sem conta conectada.
    if (mode == 'direct') {
      return {'ready': true, 'mode': 'direct'};
    }

    // Modo fixed: provedor fixo com cobrança de taxa diária, sem split percentual por corrida.
    if (mode == 'fixed') {
      return {
        'ready': true,
        'mode': 'fixed',
        'connected': false,
        'needs_manual_payout': false,
      };
    }

    // Modo platform sem conta conectada continua permitido (repasse manual diário).
    final isConnected = collectorId.isNotEmpty && mpStatus == 'active';
    return {
      'ready': true,
      'mode': 'platform',
      'connected': isConnected,
      'needs_manual_payout': !isConnected,
    };
  }

  /// Mercado Pago OAuth: Obtém a URL de autorização para o motorista vincular sua conta (Split Real).
  Future<String> getMercadoPagoDriverAuthUrl() async {
    try {
      final response = await _api.invokeEdgeFunction('mp-get-auth-url', {
        'role': 'driver',
        'userId': _api.userIdInt,
      });
      final map = Map<String, dynamic>.from(response as Map? ?? const {});
      final url = map['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception(
          map['error'] ?? 'Não foi possível gerar a URL de autorização.',
        );
      }
      return url;
    } catch (e) {
      debugPrint('❌ [CentralService] Erro ao obter URL OAuth (Motorista): $e');
      rethrow;
    }
  }

  /// Verifica se o motorista tem uma conta Mercado Pago vinculada para Split Real.
  Future<Map<String, dynamic>> checkMercadoPagoDriverConnection() async {
    final String? userId = _api.userId;
    if (userId == null) return {'connected': false};

    try {
      final response = await Supabase.instance.client
          .from('driver_mercadopago_accounts')
          .select('id, mp_user_id, updated_at')
          .eq('user_id', userId)
          .maybeSingle();

      return {'connected': response != null, 'data': response};
    } catch (e) {
      debugPrint('❌ [CentralService] Erro ao verificar conexão MP: $e');
      return {'connected': false, 'error': e.toString()};
    }
  }

  /// Gera um link de pagamento (Checkout Pro) para o passageiro pagar com saldo MP/Cartão.
  Future<Map<String, dynamic>> generateMercadoPagoPaymentLink(
    String tripId,
  ) async {
    try {
      final response = await _api.invokeEdgeFunction('mp-create-preference', {
        'trip_id': tripId,
      });
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      debugPrint('❌ [CentralService] Erro ao gerar link MP: $e');
      rethrow;
    }
  }

  /// Provisiona conta de pagamentos no Mercado Pago.
  Future<Map<String, dynamic>> createMercadoPagoDriverAccount() async {
    try {
      final response = await _api.invokeEdgeFunction('mp-customer-manager', {
        'driver_id': _api.userId,
      });
      final key = (_api.userId ?? '').trim();
      if (key.isNotEmpty) {
        _mpInitCache.remove(key);
        _mpInitInFlight.remove(key);
      }
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      debugPrint('❌ [MercadoPago] Erro ao provisionar conta de motorista: $e');
      rethrow;
    }
  }

  /// Motorista: Alterna entre ATIVO e INATIVO
  /// is_active = true → visível no mapa, recebe corridas
  /// is_active = false → invisível, não recebe corridas
  Future<void> toggleDriverStatus({
    required bool isActive,
    required String driverId,
    double? latitude,
    double? longitude,
  }) async =>
      throw _tripRuntimeDisabledException('Disponibilidade de motorista');

  /// Motorista: Atualiza localização em tempo real
  Future<void> updateDriverLocation({
    required String driverId,
    required double latitude,
    required double longitude,
    bool forceHistory = false,
  }) async {}

  /// Motorista: Escuta novas corridas disponíveis para o seu tipo de veículo
  Stream<List<Map<String, dynamic>>> streamAvailableTrips(int vehicleTypeId) {
    return const Stream<List<Map<String, dynamic>>>.empty();
  }

  /// Motorista: Aceita uma corrida
  Future<void> acceptTrip(String tripId, String driverId) async =>
      throw _tripRuntimeDisabledException('Aceite de corrida');

  /// Busca o veículo do motorista para saber o tipo (carro/moto)
  Future<int?> getDriverVehicleTypeId(String driverId) async => null;

  /// Busca as preferências de pagamento do motorista
  Future<Map<String, bool>> getDriverPaymentPreferences(String driverId) async {
    return {'pix_direct': true, 'card_machine': false};
  }

  Future<Map<String, dynamic>?> getTripPartyProfile({
    required String tripId,
    required String partyRole,
  }) async => null;

  Future<double?> getOptionalWalletBalance(String userId) async {
    // Campo legado removido do schema atual.
    // Mantemos assinatura para compatibilidade, sem gerar erro em loop nos logs.
    return null;
  }

  /// Envia uma avaliação de viagem
  Future<void> submitTripReview({
    required String tripId,
    required String revieweeId,
    required int rating,
    String? comment,
  }) async {
    try {
      final revieweeIdAsInt = int.tryParse(revieweeId.trim());
      if (revieweeIdAsInt == null || revieweeIdAsInt <= 0) {
        throw Exception(
          'reviewee_id inválido para avaliação de atendimento legado',
        );
      }

      await _api.invokeEdgeFunction('submit-trip-review', {
        'trip_id': tripId,
        'reviewee_id': revieweeIdAsInt,
        'rating': rating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      });

      debugPrint(
        '✅ [CentralService] Avaliação enviada com sucesso para a viagem $tripId',
      );
    } catch (e) {
      final err = e.toString();
      final isDuplicateReview =
          err.contains('trips_reviews_trip_id_reviewer_id_key') ||
          err.toLowerCase().contains('duplicate key value');
      if (isDuplicateReview) {
        debugPrint(
          'ℹ️ [CentralService] Avaliação já registrada anteriormente para a viagem $tripId (idempotente).',
        );
        return;
      }
      debugPrint('❌ [CentralService] Erro ao enviar avaliação: $e');
      rethrow;
    }
  }

  Future<void> updateTripStatus(
    String tripId,
    String status, {
    String? clientId,
    String? cancellationReason,
    String? paymentMethodId,
    String? paymentMethod,
  }) async {
    try {
      final role =
          ApiService().role ??
          (await SharedPreferences.getInstance()).getString('user_role');

      // Proteção: cancelamento de cliente deve ir para cancel-trip
      if (status == 'cancelled' && role != 'driver') {
        await _api.invokeEdgeFunction('cancel-trip', {
          'trip_id': tripId,
          if (cancellationReason != null &&
              cancellationReason.trim().isNotEmpty)
            'reason': cancellationReason.trim(),
        });
        debugPrint(
          '✅ [Trip] Viagem $tripId cancelada via cancel-trip (role=$role)',
        );
        return;
      }

      // Qualquer outro status exige motorista
      if (role != 'driver') {
        throw ApiException(
          message: 'Apenas motoristas podem atualizar este status',
          statusCode: 403,
        );
      }

      final Map<String, dynamic> payload = {
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (status == 'cancelled') {
        payload['cancellation_reason'] = cancellationReason;
        payload['cancelled_at'] = DateTime.now().toUtc().toIso8601String();
      } else if (status == 'accepted') {
        payload['accepted_at'] = DateTime.now().toUtc().toIso8601String();
      }

      // Captura localização atual para os marcos de embarque e desembarque
      LatLng? currentPos;
      try {
        if (!kIsWeb) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 3),
            ),
          );
          currentPos = LatLng(pos.latitude, pos.longitude);
        }
      } catch (_) {}

      if (status == 'in_progress') {
        payload['started_at'] = DateTime.now().toUtc().toIso8601String();
        if (currentPos != null) {
          payload['boarding_lat'] = currentPos.latitude;
          payload['boarding_lon'] = currentPos.longitude;
        }
      } else if (status == 'completed') {
        payload['completed_at'] = DateTime.now().toUtc().toIso8601String();
        if (currentPos != null) {
          payload['actual_dropoff_lat'] = currentPos.latitude;
          payload['actual_dropoff_lon'] = currentPos.longitude;
        }
      }

      await _api.invokeEdgeFunction('update-trip-status', {
        'trip_id': tripId,
        'status': status,
        if (paymentMethodId != null && paymentMethodId.trim().isNotEmpty)
          'payment_method_id': paymentMethodId.trim(),
        if (paymentMethod != null && paymentMethod.trim().isNotEmpty)
          'payment_method': paymentMethod.trim(),
        'boarding_lat': payload['boarding_lat'],
        'boarding_lon': payload['boarding_lon'],
        'actual_dropoff_lat': payload['actual_dropoff_lat'],
        'actual_dropoff_lon': payload['actual_dropoff_lon'],
        if (cancellationReason != null && cancellationReason.trim().isNotEmpty)
          'cancellation_reason': cancellationReason.trim(),
      });
      debugPrint(
        '✅ [Trip] Status da viagem $tripId atualizado para $status via Edge Function',
      );
    } on ApiException catch (e) {
      debugPrint('❌ [Trip] Erro ao atualizar status da viagem: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ [Trip] Erro ao atualizar status da viagem: $e');
      throw ApiException(
        message: 'Erro ao atualizar status da viagem: $e',
        statusCode: 500,
      );
    }
  }

  Future<void> cancelTripByClient(String tripId, {String? reason}) async {
    try {
      await _api.invokeEdgeFunction('cancel-trip', {
        'trip_id': tripId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
      debugPrint(
        '✅ [Trip] Viagem $tripId cancelada pelo cliente via cancel-trip',
      );
    } on ApiException catch (e) {
      debugPrint('❌ [Trip] Erro ao cancelar viagem: ${e.message}');
      rethrow;
    }
  }

  Future<void> requeueTripAfterDriverWaitCancellation({
    required String tripId,
    required String driverId,
    required double cancellationFee,
    String? driverName,
  }) async =>
      throw _tripRuntimeDisabledException('Reenfileiramento de corrida');

  /// Recupera dados de pagamento PIX (QR Code) via API Gateway
  Future<Map<String, dynamic>> getPixData(
    String id, {
    String entityType = 'trip', // 'trip' | 'service'
    String paymentStage = 'deposit', // 'deposit' | 'remaining'
  }) async {
    try {
      final type = entityType.trim().isEmpty ? 'trip' : entityType.trim();
      if (!_tripRuntimeEnabled && type != 'service') {
        throw _tripRuntimeDisabledException('Pagamento Pix de corrida');
      }
      final stage = paymentStage.trim().isEmpty
          ? 'deposit'
          : paymentStage.trim().toLowerCase();
      debugPrint(
        '🔍 [CentralService] Buscando dados PIX para ${type == 'service' ? 'o serviço' : 'a viagem'}: $id',
      );

      final payload = <String, dynamic>{
        if (type == 'service') 'service_id': id else 'trip_id': id,
        'entity_type': type,
        if (type == 'service') 'payment_stage': stage,
      };
      final response = await _api.invokeEdgeFunction(
        'mp-get-pix-data',
        payload,
      );

      if (response is Map) {
        final map = Map<String, dynamic>.from(response);
        final backendError = (map['error'] ?? '').toString().trim();
        final hasFailureFlag = map['success'] == false;
        if (backendError.isNotEmpty || hasFailureFlag) {
          debugPrint(
            '⚠️ [CentralService] PIX backend error '
            'step=${map['step'] ?? "N/A"} '
            'reason_code=${map['reason_code'] ?? "N/A"} '
            'trace_id=${map['trace_id'] ?? "N/A"} '
            'status=${map['status_code'] ?? "N/A"}',
          );
          throw ApiException(
            message: backendError.isNotEmpty
                ? backendError
                : 'Falha ao buscar dados PIX',
            statusCode: int.tryParse('${map['status_code'] ?? ''}') ?? 400,
            details: map,
          );
        }
      }

      if (response is Map && response['pix'] != null) {
        final pix = Map<String, dynamic>.from(response['pix'] as Map);
        final payloadRaw =
            (pix['copy_and_paste'] ??
                    pix['payload'] ??
                    pix['pix_payload'] ??
                    pix['pix_code'] ??
                    pix['code'])
                ?.toString()
                .trim() ??
            '';
        final qrRaw =
            (pix['encodedImage'] ??
                    pix['image_url'] ??
                    pix['qr_code_base64'] ??
                    pix['qr_code'] ??
                    pix['qrcode_base64'] ??
                    pix['qr'])
                ?.toString()
                .trim() ??
            '';

        final isFakePayload = payloadRaw.toLowerCase().contains(
          'test-key@example.com',
        );
        final isFakeQr = qrRaw.toLowerCase().contains('mock-qr-image-url');
        if (isFakePayload || isFakeQr) {
          throw ApiException(
            message:
                'PIX inválido retornado pelo backend. É necessário QR e copia/cola reais do Mercado Pago.',
            statusCode: 502,
            details: {
              'reason_code': 'fake_pix_payload',
              'has_fake_payload': isFakePayload,
              'has_fake_qr': isFakeQr,
            },
          );
        }

        if (payloadRaw.isNotEmpty) {
          pix['payload'] = payloadRaw;
          pix['copy_and_paste'] = payloadRaw;
        }
        if (qrRaw.isNotEmpty) {
          pix['encodedImage'] = qrRaw;
          pix['qr_code'] = qrRaw;
        }

        if (response['amount'] != null) {
          pix['amount'] = response['amount'];
        }
        if (response['status'] != null) {
          pix['status'] = response['status'];
        }
        if (response['trip_id'] != null) pix['trip_id'] = response['trip_id'];
        if (response['trace_id'] != null) {
          pix['trace_id'] = response['trace_id'];
        }
        final amount = (pix['amount'] as num?)?.toDouble();
        if (type == 'service') {
          PaymentAuditLogger.logServicePaymentEvent(
            serviceId: id,
            event: 'pix_data_loaded',
            amount: amount,
            paymentMethodId: 'pix_app',
            traceId: pix['trace_id']?.toString(),
            extra: {
              'status': pix['status']?.toString(),
              'has_payload':
                  (pix['payload']?.toString().trim().isNotEmpty ?? false),
              'has_qr':
                  (pix['encodedImage']?.toString().trim().isNotEmpty ??
                      false) ||
                  (pix['image_url']?.toString().trim().isNotEmpty ?? false) ||
                  (pix['qr_code']?.toString().trim().isNotEmpty ?? false),
            },
          );
        } else {
          PaymentAuditLogger.logTripPaymentEvent(
            tripId: id,
            event: 'pix_data_loaded',
            amount: amount,
            paymentMethodId: 'pix_app',
            traceId: pix['trace_id']?.toString(),
            extra: {
              'status': pix['status']?.toString(),
              'has_payload':
                  (pix['payload']?.toString().trim().isNotEmpty ?? false),
              'has_qr':
                  (pix['encodedImage']?.toString().trim().isNotEmpty ??
                      false) ||
                  (pix['image_url']?.toString().trim().isNotEmpty ?? false) ||
                  (pix['qr_code']?.toString().trim().isNotEmpty ?? false),
            },
          );
        }
        return pix;
      }

      // Fallback para compatibilidade com respostas antigas
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }

      throw Exception('Dados PIX não disponíveis');
    } catch (e) {
      debugPrint('❌ [CentralService] Erro ao buscar dados PIX: $e');

      if (entityType == 'service') {
        PaymentAuditLogger.logServicePaymentEvent(
          serviceId: id,
          event: 'pix_data_error',
          extra: {'error': e.toString()},
        );
      } else {
        PaymentAuditLogger.logTripPaymentEvent(
          tripId: id,
          event: 'pix_data_error',
          extra: {'error': e.toString()},
        );
      }
      return _errorToMap(e);
    }
  }

  /// Confirma pagamento em dinheiro (cancela PIX e gera dívida de comissão)
  Future<Map<String, dynamic>> confirmCashPayment(
    String tripId, {
    String? manualPaymentMethodId,
  }) async {
    if (!_tripRuntimeEnabled) {
      return _errorToMap(
        _tripRuntimeDisabledException('Pagamento manual de corrida'),
      );
    }
    try {
      final payload = <String, dynamic>{
        'trip_id': tripId,
        if (manualPaymentMethodId != null &&
            manualPaymentMethodId.trim().isNotEmpty)
          'manual_payment_method_id': manualPaymentMethodId,
      };

      PaymentAuditLogger.logTripPaymentEvent(
        tripId: tripId,
        event: 'manual_payment_confirm_start',
        paymentMethodId: manualPaymentMethodId?.trim().isNotEmpty == true
            ? manualPaymentMethodId!.trim()
            : 'cash',
        extra: {'payload': payload},
      );

      final response = await _api.invokeEdgeFunction(
        'mp-confirm-cash-payment',
        payload,
      );
      final map = Map<String, dynamic>.from(response as Map);
      PaymentAuditLogger.logTripPaymentEvent(
        tripId: tripId,
        event: 'manual_payment_confirm_ok',
        paymentMethodId: manualPaymentMethodId?.trim().isNotEmpty == true
            ? manualPaymentMethodId!.trim()
            : 'cash',
        commissionAmount: (map['commission_due_total'] as num?)?.toDouble(),
        traceId: map['trace_id']?.toString(),
        extra: {
          'step': map['step'],
          'commission_due_remaining': map['commission_due_remaining'],
        },
      );
      return map;
    } catch (e) {
      debugPrint('❌ [CentralService] Erro confirmCashPayment: $e');
      PaymentAuditLogger.logTripPaymentEvent(
        tripId: tripId,
        event: 'manual_payment_confirm_error',
        paymentMethodId: manualPaymentMethodId,
        extra: {'error': e.toString()},
      );
      return _errorToMap(e);
    }
  }

  /// Alias para facilitar o entendimento do fluxo de cancelamento de PIX para pagamento direto
  Future<Map<String, dynamic>> cancelPixAndSetDirectPayment(
    String tripId,
  ) async {
    return confirmCashPayment(tripId);
  }

  /// Simula PIX pago (modo teste) e replica efeito de webhook.
  Future<Map<String, dynamic>> simulatePixPaid(String tripId) async {
    if (!_tripRuntimeEnabled) {
      return _errorToMap(
        _tripRuntimeDisabledException('Simulação Pix de corrida'),
      );
    }
    if (!_allowLocalPixAutoPay) {
      return _errorToMap(
        ApiException(
          message: 'Simulação PIX desativada neste build.',
          statusCode: 400,
        ),
      );
    }
    try {
      final response = await _api.invokeEdgeFunction('simulate-pix-paid', {
        'trip_id': tripId,
      });
      final map = Map<String, dynamic>.from(response as Map);
      PaymentAuditLogger.logTripPaymentEvent(
        tripId: tripId,
        event: 'simulate_pix_paid',
        traceId: map['trace_id']?.toString(),
        extra: {'step': map['step'], 'status_code': map['status_code']},
      );
      return map;
    } catch (e) {
      debugPrint('❌ [CentralService] Erro simulatePixPaid: $e');
      PaymentAuditLogger.logTripPaymentEvent(
        tripId: tripId,
        event: 'simulate_pix_paid_error',
        extra: {'error': e.toString()},
      );
      return _errorToMap(e);
    }
  }

  /// Inicia processo de pagamento via Cartão de Crédito
  Future<Map<String, dynamic>> processCardPayment({
    required String tripId,
    String? creditCardToken,
    String? securityCode,
  }) async {
    if (!_tripRuntimeEnabled) {
      return _errorToMap(
        _tripRuntimeDisabledException('Pagamento em cartão de corrida'),
      );
    }
    try {
      final traceId = 'card_${tripId}_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint(
        '💳 [CentralService] Processando pagamento Cartão para a viagem: $tripId | trace_id=$traceId',
      );
      final payload = <String, dynamic>{
        'trip_id': tripId,
        'payment_method': 'credit_card',
        'trace_id': traceId,
      };
      // Quando não informado, o backend usa o cartão padrão salvo do usuário.
      final trimmedSecurityCode = securityCode?.trim();
      if (trimmedSecurityCode != null && trimmedSecurityCode.isNotEmpty) {
        payload['security_code'] = trimmedSecurityCode;
      }

      final trimmedCreditCardToken = creditCardToken?.trim();
      if (trimmedCreditCardToken != null && trimmedCreditCardToken.isNotEmpty) {
        payload['creditCardToken'] = trimmedCreditCardToken;
      }

      final response = await _api.invokeEdgeFunction(
        'mp-process-payment',
        payload,
      );
      final map = Map<String, dynamic>.from(response);
      PaymentAuditLogger.logTripPaymentEvent(
        tripId: tripId,
        event: 'card_payment_response',
        paymentMethodId: 'card_app',
        traceId: map['trace_id']?.toString() ?? traceId,
        extra: {
          'success': map['success'],
          'status_code': map['status_code'],
          'step': map['step'],
          'reason_code': map['reason_code'],
        },
      );
      if (map['trace_id'] != null || map['step'] != null) {
        debugPrint(
          '📡 [CardMonitor] processCardPayment trip=$tripId trace_id=${map['trace_id'] ?? traceId} '
          'step=${map['step']} reason_code=${map['reason_code'] ?? 'N/A'} '
          'status=${map['status']} payment_id=${map['paymentId'] ?? 'N/A'} invoice=${map['invoiceUrl'] ?? 'N/A'} '
          'provider_error=${map['provider_error'] ?? map['details'] ?? 'N/A'}',
        );
      }
      return map;
    } catch (e) {
      debugPrint('❌ [CentralService] Erro ao processar pagamento: $e');
      PaymentAuditLogger.logTripPaymentEvent(
        tripId: tripId,
        event: 'card_payment_error',
        paymentMethodId: 'card_app',
        extra: {'error': e.toString()},
      );
      return _errorToMap(e);
    }
  }

  /// Retorna o rastreio rico do pagamento do fluxo legado (timeline de logs).
  Future<Map<String, dynamic>> getCardPaymentTrace({
    required String tripId,
    int limit = 200,
  }) async {
    if (!_tripRuntimeEnabled) {
      return _errorToMap(
        _tripRuntimeDisabledException('Rastreio de pagamento de corrida'),
      );
    }
    try {
      final response = await _api.invokeEdgeFunction('payment-flow-status', {
        'trip_id': tripId,
        'limit': limit,
      });
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      debugPrint(
        '❌ [CentralService] Erro ao consultar rastreio de pagamento: $e',
      );
      return {..._errorToMap(e), 'trip_id': tripId};
    }
  }

  /// Tokeniza cartão de crédito via PaymentService
  Future<Map<String, dynamic>> tokenizeCard(
    Map<String, dynamic> creditCard,
  ) async {
    final paymentService = PaymentService();
    final userId = int.tryParse(_api.userId ?? '');
    if (userId == null) {
      return {
        'success': false,
        'error': 'Usuário inválido para tokenização de cartão',
        'status_code': 400,
      };
    }
    return await paymentService.tokenizeCard(
      userId: userId,
      cardData: creditCard,
    );
  }

  // Registro de conta Mercado Pago migrado com sucesso.

  /// Stream de acompanhamento em tempo real via Supabase (Trips)
  Stream<Map<String, dynamic>?> watchTrip(String tripId) {
    return Stream<Map<String, dynamic>?>.value(null);
  }

  /// Stream de acompanhamento em tempo real via Supabase (Services)
  Stream<Map<String, dynamic>?> watchService(
    String serviceId, {
    ServiceDataScope scope = ServiceDataScope.auto,
  }) {
    return DataGateway()
        .watchService(serviceId, scope: scope)
        .map((service) => service['not_found'] == true ? null : service);
  }

  /// Stream para acompanhar TODOS os motoristas online (para o mapa do cliente)
  Stream<List<Map<String, dynamic>>> watchAllOnlineDrivers() {
    return const Stream<List<Map<String, dynamic>>>.empty();
  }

  /// Stream para acompanhar as solicitações de serviço do usuário (Client ou Provider)
  Stream<List<Map<String, dynamic>>> watchUserServices(String userId) {
    debugPrint('🎧 [CentralService] watchUserServices para userId: $userId');
    final clientIdInt = int.tryParse(userId.trim());
    final baseStream = Supabase.instance.client
        .from('service_requests')
        .stream(primaryKey: ['id']);
    final filteredStream = clientIdInt != null
        ? baseStream.eq('client_id', clientIdInt)
        : baseStream.eq('client_id', userId);

    return filteredStream
        .order('created_at', ascending: false)
        .map((list) => list.cast<Map<String, dynamic>>())
        .map((list) {
          // Não mostrar serviços cancelados na listagem do cliente.
          return list.where((row) {
            final st = (row['status'] ?? '').toString().toLowerCase().trim();
            return st != 'cancelled' && st != 'canceled';
          }).toList();
        });
  }

  /// Stream para acompanhar a localização do motorista em tempo real
  /// Stream para acompanhar a localização do motorista em tempo real.
  /// Aceita [int] driverId para performance máxima ou [String] tripId para compatibilidade.
  Stream<List<Map<String, dynamic>>> watchDriverLocation(dynamic identifier) {
    return const Stream<List<Map<String, dynamic>>>.empty();
  }

  /// Busca a viagem ativa do cliente
  Future<Map<String, dynamic>?> getActiveTripForClient(String clientId) async {
    return null;
  }

  /// Busca o serviço ativo do cliente (Unificado: Mobile, Fixed e Transporte)
  Future<Map<String, dynamic>?> getActiveServiceForClient(
    String clientId,
  ) async {
    if (!SupabaseConfig.isInitialized) return null;
    try {
      debugPrint(
        '🔎 [CentralService] Buscando atividade unificada para o cliente: $clientId',
      );

      final clientIdInt = int.tryParse(clientId.trim());
      final authUid = Supabase.instance.client.auth.currentUser?.id.trim();

      // Status ativos unificados
      const activeStatuses = [
        'pending',
        'searching',
        'waiting_payment',
        'waiting_pix',
        'accepted',
        'provider_near',
        'arrived',
        'in_progress',
        'waiting_remaining_payment',
        'waiting_payment_remaining',
        'awaiting_confirmation',
        'waiting_client_confirmation',
        'contested',
      ];

      // 1) Busca em service_requests (Serviços Móveis)
      List<dynamic> services = const [];
      if (clientIdInt != null) {
        services = await Supabase.instance.client
            .from('service_requests')
            .select(
              'id,client_id,client_uid,provider_id,status,created_at,updated_at,'
              'address,description,category,subcategory,service_type,'
              'requester_name,provider_name,final_price,payment_method',
            )
            .eq('client_id', clientIdInt)
            .inFilter('status', activeStatuses)
            .order('created_at', ascending: false)
            .limit(1);
      }

      if (services.isEmpty &&
          authUid != null &&
          authUid.isNotEmpty &&
          _looksLikeUuid(authUid)) {
        services = await Supabase.instance.client
            .from('service_requests')
            .select(
              'id,client_id,client_uid,provider_id,status,created_at,updated_at,'
              'address,description,category,subcategory,service_type,'
              'requester_name,provider_name,final_price,payment_method',
            )
            .eq('client_uid', authUid)
            .inFilter('status', activeStatuses)
            .order('created_at', ascending: false)
            .limit(1);
      }

      if (services.isNotEmpty) {
        return Map<String, dynamic>.from(services.first);
      }

      // 3) Busca em agendamento_servico (Agendamentos Fixos 101)
      List<dynamic> bookings = const [];
      if (authUid != null && authUid.isNotEmpty && _looksLikeUuid(authUid)) {
        bookings = await Supabase.instance.client
            .from('agendamento_servico')
            .select('*, task_catalog(name)')
            .eq('cliente_uid', authUid)
            .inFilter('status', [
              'PENDENTE',
              'CONFIRMADO',
              'EM_DESLOCAMENTO',
              'EM_EXECUCAO',
              'confirmed',
            ])
            .order('created_at', ascending: false)
            .limit(1);
      }

      if (bookings.isNotEmpty) {
        final booking = Map<String, dynamic>.from(bookings.first);
        return {
          ...booking,
          'is_fixed': true,
          'at_provider': true,
          'status': switch ((booking['status'] ?? '')
              .toString()
              .toUpperCase()) {
            'PENDENTE' => 'waiting_payment',
            'CONFIRMADO' => 'accepted',
            'EM_DESLOCAMENTO' => 'arrived',
            'EM_EXECUCAO' => 'in_progress',
            'CONCLUIDO' => 'completed',
            'CANCELADO' => 'cancelled',
            _ => (booking['status'] ?? '').toString().toLowerCase(),
          },
          'scheduled_at': booking['data_agendada'],
          'task_name': booking['task_catalog']?['name'] ?? 'Agendamento',
        };
      }

      return null;
    } catch (e) {
      debugPrint(
        '❌ [CentralService] Erro ao consultar atividade unificada: $e',
      );
      return null;
    }
  }

  /// Busca a viagem ativa do motorista (Desativado / Migrado)
  Future<Map<String, dynamic>?> getActiveTripForDriver(String driverId) async {
    return null;
  }

  /// Recupera o histórico de viagens do usuário (Cliente) (Desativado)
  Future<List<Map<String, dynamic>>> getUserTrips(String userId) async {
    return [];
  }

  /// Salva a avaliação de uma viagem (Legacy wrapper)
  Future<void> rateTrip({
    required String tripId,
    required double rating,
    String? comment,
  }) async {}

  /// Inicia uma simulação de movimento seguindo uma polilinha com velocidade constante
  void startRouteSimulation({
    required String driverId,
    required List<LatLng> polyline,
    double speedKmH = 30.0,
    Duration tickInterval = const Duration(milliseconds: 500),
  }) {}

  /// Para a simulação de movimento
  void stopRouteSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _simulationProgressController?.close();
    _simulationProgressController = null;
  }

  /// Recupera o meio de pagamento preferido do usuário
  Future<String> getPreferredPaymentMethod(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('preferred_payment_method')
          .eq('id', userId)
          .maybeSingle();

      final saved = (response?['preferred_payment_method'] as String?) ?? 'PIX';
      // Normaliza valores legados
      if (saved == 'PIX Direto' || saved == 'PIX Plataforma') return 'PIX';
      // PIX direto com motorista deixou de ser opção selecionável no app (agora é automático).
      if (saved.toLowerCase().trim() == 'pix_direct') return 'PIX';
      if (saved.toLowerCase().trim().startsWith('card_machine')) {
        return 'card_machine';
      }
      // Dinheiro/Direto não é mais método selecionável no fluxo Uber atual.
      if (saved == 'Dinheiro' || saved == 'Dinheiro/Direto') return 'PIX';
      if (saved == 'Método salvo' ||
          saved == 'Metodo salvo' ||
          saved == 'MÉTODO SALVO' ||
          saved == 'METODO SALVO') {
        return 'Card';
      }
      return saved;
    } catch (e) {
      debugPrint(
        '❌ [CentralService] Erro ao buscar meio de pagamento preferido: $e',
      );
      return 'PIX';
    }
  }

  /// Atualiza o meio de pagamento preferido do usuário
  Future<void> updatePreferredPaymentMethod({
    required String userId,
    required String method,
  }) async {
    try {
      await Supabase.instance.client
          .from('users')
          .update({'preferred_payment_method': method})
          .eq('id', userId);

      debugPrint(
        '✅ [CentralService] Meio de pagamento preferido atualizado para: $method',
      );
    } catch (e) {
      debugPrint(
        '❌ [CentralService] Erro ao atualizar meio de pagamento preferido: $e',
      );
      throw Exception('Erro ao atualizar preferência de pagamento');
    }
  }
}
