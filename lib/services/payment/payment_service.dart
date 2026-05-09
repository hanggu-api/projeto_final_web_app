import 'package:flutter/foundation.dart';
import '../../core/network/backend_api_client.dart';
import '../api_service.dart';
import '../../core/payment/ipayment_gateway.dart';
import 'mercado_pago_gateway.dart';

class PaymentService {
  final ApiService _api = ApiService();
  final BackendApiClient _backend = const BackendApiClient();
  final Map<String, IPaymentGateway> _gateways = {};

  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;

  PaymentService._internal() {
    _registerGateway(MercadoPagoGateway(_api));
  }

  void _registerGateway(IPaymentGateway gateway) {
    _gateways[gateway.name] = gateway;
  }

  IPaymentGateway getGateway([String? name]) {
    final effectiveName = name ?? 'mercado_pago';
    if (!_gateways.containsKey(effectiveName)) {
      throw Exception('Gateway "$effectiveName" não configurado.');
    }
    return _gateways[effectiveName]!;
  }

  Future<String?> getExternalId(int userId, String gatewayName) async {
    final res = await _backend.getJson(
      '/api/v1/users/$userId/payment-accounts?gateway_name_eq=$gatewayName',
    );
    final list = res?['data'] as List?;
    return list?.isNotEmpty == true
        ? list!.first['external_id']?.toString()
        : null;
  }

  Future<void> savePaymentAccount({
    required int userId,
    required String gatewayName,
    required String externalId,
    String? walletId,
  }) async {
    await _backend.putJson(
      '/api/v1/users/$userId/payment-accounts',
      body: {
        'gateway_name': gatewayName,
        'external_id': externalId,
        if (walletId != null) 'wallet_id': walletId,
      },
    );
  }

  Future<String> ensureCustomer({
    required int userId,
    required String gatewayName,
    required String name,
    required String email,
    required String document,
    String? phone,
  }) async {
    debugPrint(
      '🔄 [PaymentService] ensureCustomer: userId=$userId gateway=$gatewayName',
    );
    try {
      final existingId = await getExternalId(userId, gatewayName);
      if (existingId != null && existingId.trim().isNotEmpty) {
        return existingId.trim();
      }
      final gateway = getGateway(gatewayName);
      final newExternalId = await gateway.createCustomer(
        name: name,
        email: email,
        document: document,
        phone: phone,
      );
      await savePaymentAccount(
        userId: userId,
        gatewayName: gatewayName,
        externalId: newExternalId,
      );
      return newExternalId;
    } catch (e) {
      debugPrint('❌ [PaymentService] ensureCustomer: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getSavedCards() async {
    try {
      final res = await _backend.getJson('/api/v1/users/me/payment-methods');
      return res?['data'] as List? ?? [];
    } catch (e) {
      debugPrint('❌ [PaymentService] getSavedCards: $e');
      return [];
    }
  }

  Future<void> savePaymentMethod({
    required String paymentMethodId,
    required String brand,
    required String last4,
    required int expMonth,
    required int expYear,
    String provider = 'mercado_pago',
    String? mpPaymentMethodId,
  }) async {
    await _backend.postJson(
      '/api/v1/users/me/payment-methods',
      body: {
        'mp_card_id': provider == 'mercado_pago' ? paymentMethodId : null,
        if (provider == 'mercado_pago' && mpPaymentMethodId != null)
          'mp_payment_method_id': mpPaymentMethodId,
        'brand': brand,
        'last4': last4,
        'exp_month': expMonth,
        'exp_year': expYear,
        'is_default': true,
      },
    );
  }

  Future<void> deletePaymentMethod({required dynamic paymentMethodId}) async {
    await _backend.deleteJson(
      '/api/v1/users/me/payment-methods/$paymentMethodId',
    );
  }

  Future<void> deleteAllPaymentMethods() async {
    await _backend.deleteJson('/api/v1/users/me/payment-methods');
  }

  Future<Map<String, dynamic>> generatePix({
    required int userId,
    required double amount,
    required String description,
    String? gatewayName,
  }) async {
    final gateway = getGateway(gatewayName);
    final customerId =
        (await getExternalId(userId, gateway.name))?.trim() ?? '';
    return gateway.generatePix(
      customerId: customerId,
      amount: amount,
      description: description,
    );
  }

  Future<Map<String, dynamic>> processCardPayment({
    required int userId,
    required String cardToken,
    required double amount,
    required String description,
    String? securityCode,
    String? gatewayName,
  }) async {
    final gateway = getGateway(gatewayName);
    var customerId = await getExternalId(userId, gateway.name);
    if (customerId == null || customerId.trim().isEmpty) {
      final userData = await _backend.getJson('/api/v1/users/$userId');
      customerId = await ensureCustomer(
        userId: userId,
        gatewayName: gateway.name,
        name: userData?['full_name'] ?? 'Usuário $userId',
        email: userData?['email'] ?? '',
        document: userData?['document_value'] ?? '',
        phone: userData?['phone'],
      );
    }
    return gateway.processCardPayment(
      customerId: customerId,
      cardId: cardToken,
      amount: amount,
      description: description,
      securityCode: securityCode,
    );
  }

  Future<Map<String, dynamic>> processWalletPayment({
    required int userId,
    required double amount,
    required String description,
    Map<String, dynamic>? metadata,
    String? gatewayName,
  }) async {
    final gateway = getGateway(gatewayName);
    return gateway.processWalletPayment(
      userId: userId,
      amount: amount,
      description: description,
      metadata: metadata,
    );
  }

  Future<Map<String, dynamic>> tokenizeCard({
    required int userId,
    required Map<String, dynamic> cardData,
    String? gatewayName,
  }) async {
    final gateway = getGateway(gatewayName);
    final userData = await _backend.getJson('/api/v1/users/$userId');
    final customerId = await ensureCustomer(
      userId: userId,
      gatewayName: gateway.name,
      name: userData?['full_name'] ?? 'Usuário $userId',
      email: userData?['email'] ?? '',
      document: userData?['document_value'] ?? '',
      phone: userData?['phone'],
    );
    return gateway.tokenizeCard(
      customerId: customerId,
      cardData: {...cardData, 'cpfCnpj': userData?['document_value']},
    );
  }

  Future<String> generateCardToken({
    required String cardId,
    required String securityCode,
    String? gatewayName,
  }) async {
    final gateway = getGateway(gatewayName);
    return gateway.generateCardToken(
      cardId: cardId,
      securityCode: securityCode,
    );
  }

  Future<String?> ensureCustomerForUser({
    required int userId,
    String? gatewayName,
  }) async {
    final gateway = getGateway(gatewayName);
    final userData = await _backend.getJson('/api/v1/users/$userId');
    final document = (userData?['document_value'] ?? '').toString().trim();
    if (document.isEmpty) return null;

    if (gateway.name == 'mercado_pago') {
      final role = (userData?['role'] ?? '').toString().trim();
      final accountPath = role == 'driver'
          ? '/api/v1/users/$userId/mp-account?role=driver'
          : '/api/v1/users/$userId/mp-account?role=passenger';
      final mpAccount = await _backend.getJson(accountPath);
      final accessToken =
          (mpAccount?['access_token'] ?? '').toString().trim();
      final refreshToken =
          (mpAccount?['refresh_token'] ?? '').toString().trim();
      if (accessToken.isEmpty && refreshToken.isEmpty) return null;
    }

    return ensureCustomer(
      userId: userId,
      gatewayName: gateway.name,
      name: userData?['full_name'] ?? 'Usuário $userId',
      email: userData?['email'] ?? '',
      document: document,
      phone: userData?['phone'],
    );
  }

}
