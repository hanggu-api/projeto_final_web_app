import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
import '../../services/data_gateway.dart';

/// Serviço de domínio do prestador móvel.
/// Flutter só chama endpoints — nenhuma regra de negócio aqui.
class ProviderMobileService {
  ProviderMobileService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  /// Busca serviços disponíveis para o prestador.
  /// O backend filtra por profissão, fila privada e calcula provider_amount.
  Future<List<Map<String, dynamic>>> getAvailableServices({
    required String providerUserId,
    bool includeEmergency = true,
  }) async {
    try {
      final result = await _api.invokeEdgeFunction('get-available-services', {
        'provider_user_id': providerUserId,
        'include_emergency': includeEmergency,
        'limit': 30,
      });
      final raw = result as Map<String, dynamic>? ?? {};
      final services = raw['services'] as List? ?? [];
      return services
          .whereType<Map>()
          .map((s) => Map<String, dynamic>.from(s))
          .toList();
    } catch (e) {
      debugPrint('⚠️ [ProviderMobileService] getAvailableServices erro: $e');
      return [];
    }
  }

  /// Busca ofertas ativas para o prestador (polling fallback).
  /// O backend valida deadline e retorna apenas ofertas válidas.
  Future<List<Map<String, dynamic>>> getActiveOffers({
    required String providerUserId,
  }) async {
    try {
      final result = await _api.invokeEdgeFunction('get-provider-offers', {
        'provider_user_id': providerUserId,
      });
      final raw = result as Map<String, dynamic>? ?? {};
      final offers = raw['offers'] as List? ?? [];
      return offers
          .whereType<Map>()
          .map((o) => Map<String, dynamic>.from(o))
          .toList();
    } catch (e) {
      debugPrint('⚠️ [ProviderMobileService] getActiveOffers erro: $e');
      return [];
    }
  }

  /// Aceita um serviço — delega ao backend.
  Future<void> acceptService(String serviceId) async {
    await _api.dispatch.acceptService(serviceId);
  }

  /// Recusa um serviço — delega ao backend.
  Future<void> rejectService(String serviceId) =>
      _api.dispatch.rejectService(serviceId);

  /// Busca meus serviços ativos e histórico.
  Future<List<dynamic>> getMyServices() => DataGateway().loadMyServices();

  /// Carrega perfil do prestador.
  Future<Map<String, dynamic>> getMyProfile() => _api.getMyProfile();
}
