import 'package:flutter/foundation.dart';
import '../api_service.dart';
import '../../core/payment/ipayment_gateway.dart';

class MercadoPagoGateway implements IPaymentGateway {
  final ApiService _api;

  MercadoPagoGateway(this._api);

  @override
  String get name => 'mercado_pago';

  @override
  Future<String> createCustomer({
    required String name,
    required String email,
    required String document,
    String? phone,
  }) async {
    debugPrint('🔄 [MercadoPagoGateway] Iniciando createCustomer: name=$name, email=$email, document=$document, phone=$phone');
    try {
      final response = await _api.invokeEdgeFunction('mp-customer-manager', {
        'action': 'ensure_customer',
        'name': name,
        'email': email,
        'cpfCnpj': document,
        if (phone != null) 'phone': phone,
      });
      final map = Map<String, dynamic>.from(response as Map? ?? const {});
      final customerId = (map['customer_id'] ?? map['id'] ?? '').toString().trim();
      if (customerId.isEmpty) {
        debugPrint('❌ [MercadoPagoGateway] Falha ao criar cliente: resposta vazia ou sem customer_id');
        throw Exception('Falha ao criar cliente no Mercado Pago');
      }
      debugPrint('✅ [MercadoPagoGateway] Cliente criado com sucesso: customerId=$customerId');
      return customerId;
    } catch (e) {
      debugPrint('❌ [MercadoPagoGateway] Erro em createCustomer: $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> generatePix({
    required String customerId,
    required double amount,
    required String description,
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('🔄 [MercadoPagoGateway] Iniciando generatePix: customerId=$customerId, amount=$amount, description=$description, metadata=$metadata');
    try {
      final response = await _api.invokeEdgeFunction('mp-process-payment', {
        'payment_method': 'pix',
        'customer_id': customerId,
        'amount': amount,
        'description': description,
        if (metadata != null) 'metadata': metadata,
      });
      final map = Map<String, dynamic>.from(response as Map? ?? const {});
      debugPrint('✅ [MercadoPagoGateway] PIX gerado com sucesso: ${map.keys.join(', ')}');
      return map;
    } catch (e) {
      debugPrint('❌ [MercadoPagoGateway] Erro em generatePix: $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> processCardPayment({
    required String customerId,
    required String cardId,
    required double amount,
    required String description,
    String? securityCode,
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('🔄 [MercadoPagoGateway] Iniciando processCardPayment: customerId=$customerId, cardId=$cardId, amount=$amount, cvv=${securityCode != null ? "***" : "N/A"}');
    try {
      final response = await _api.invokeEdgeFunction('mp-process-payment', {
        'payment_method': 'credit_card',
        'customer_id': customerId,
        'creditCardToken': cardId,
        'amount': amount,
        'description': description,
        if (securityCode != null) 'security_code': securityCode,
        if (metadata != null) 'metadata': metadata,
      });
      final map = Map<String, dynamic>.from(response as Map? ?? const {});
      debugPrint(
        '📡 [MercadoPagoGateway] processCardPayment trace_id=${map['trace_id'] ?? 'N/A'} step=${map['step'] ?? 'N/A'} status=${map['status'] ?? 'N/A'}',
      );
      if (map.containsKey('error') || (map['status'] != null && map['status'] != 'approved')) {
        debugPrint('❌ [MercadoPagoGateway] Pagamento com cartão falhou: ${map['error'] ?? 'Status não aprovado'}');
      } else {
        debugPrint('✅ [MercadoPagoGateway] Pagamento com cartão processado com sucesso');
      }
      return map;
    } on ApiException catch (e) {
      // Se for um erro de negócio (ex: requer CVV), retornamos os detalhes para a UI tratar
      if (e.statusCode == 400 && e.details != null) {
        debugPrint('⚠️ [MercadoPagoGateway] ApiException 400 detectada. Retornando detalhes para fallback: ${e.details}');
        return e.details!;
      }
      debugPrint('❌ [MercadoPagoGateway] ApiException em processCardPayment: $e');
      rethrow;
    } catch (e) {
      debugPrint('❌ [MercadoPagoGateway] Erro em processCardPayment: $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> tokenizeCard({
    required String customerId,
    required Map<String, dynamic> cardData,
  }) async {
    debugPrint('🔄 [MercadoPagoGateway] Iniciando tokenizeCard: customerId=$customerId, cardData keys=${cardData.keys.join(', ')}');
    try {
      final response = await _api.invokeEdgeFunction('mp-tokenize-card', {
        'customer_id': customerId,
        'creditCard': {
          'holderName': cardData['holderName'],
          'number': cardData['number'],
          'expiryMonth': cardData['expiryMonth'],
          'expiryYear': cardData['expiryYear'],
          'ccv': cardData['ccv'],
        },
        'creditCardHolderInfo': {
          'cpfCnpj': cardData['cpfCnpj'], // Passando o CPF do perfil
          'postalCode': cardData['postalCode'],
          'addressNumber': cardData['addressNumber'],
        },
      });

      final map = Map<String, dynamic>.from(response as Map? ?? const {});
      final savedCardId = (map['card_id'] ?? map['creditCardToken'] ?? '')
          .toString()
          .trim();
      if (savedCardId.isEmpty) {
        debugPrint('❌ [MercadoPagoGateway] Falha ao tokenizar cartão: ${map['error'] ?? 'Resposta sem card_id'}');
        throw Exception(map['error']?.toString() ?? 'Erro ao tokenizar cartão');
      }
      
      final brand = map['brand']?.toString();
      final mpPaymentMethodId = map['mp_payment_method_id']?.toString();
      
      debugPrint('✅ [MercadoPagoGateway] Cartão tokenizado com sucesso: cardId=$savedCardId, brand=$brand, mp_payment_method_id=$mpPaymentMethodId');
      return {
        'creditCardToken': savedCardId,
        'brand': brand,
        'mp_payment_method_id': mpPaymentMethodId,
        'gateway': name,
      };
    } catch (e) {
      debugPrint('❌ [MercadoPagoGateway] Erro em tokenizeCard: $e');
      rethrow;
    }
  }

  @override
  Future<String> generateCardToken({
    required String cardId,
    required String securityCode,
  }) async {
    debugPrint('🔄 [MercadoPagoGateway] Iniciando generateCardToken: cardId=$cardId');
    try {
      final response = await _api.invokeEdgeFunction('mp-tokenize-card', {
        'action': 'tokenize_saved_card',
        'card_id': cardId,
        'security_code': securityCode,
      });

      final map = Map<String, dynamic>.from(response as Map? ?? const {});
      final token = (map['id'] ?? map['token'] ?? '').toString().trim();
      
      if (token.isEmpty) {
        throw Exception(map['error']?.toString() ?? 'Erro ao gerar token do cartão');
      }
      
      debugPrint('✅ [MercadoPagoGateway] Token gerado com sucesso: $token');
      return token;
    } catch (e) {
      debugPrint('❌ [MercadoPagoGateway] Erro em generateCardToken: $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> processPayout({
    required String accountId,
    required double amount,
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('🔄 [MercadoPagoGateway] Iniciando processPayout: accountId=$accountId, amount=$amount, metadata=$metadata');
    try {
      final response = await _api.invokeEdgeFunction('mp-request-payout', {
        'account_id': accountId,
        'amount': amount,
        if (metadata != null) 'metadata': metadata,
      });
      final map = Map<String, dynamic>.from(response as Map? ?? const {});
      debugPrint('✅ [MercadoPagoGateway] Payout processado: ${map.keys.join(', ')}');
      return map;
    } catch (e) {
      debugPrint('❌ [MercadoPagoGateway] Erro em processPayout: $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> processWalletPayment({
    required int userId,
    required double amount,
    required String description,
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('🔄 [MercadoPagoGateway] Iniciando processWalletPayment: userId=$userId, amount=$amount, description=$description');
    try {
      final response = await _api.invokeEdgeFunction('mp-process-payment', {
        'payment_method': 'mercado_pago', // Identificador para fluxo Wallet no backend
        'amount': amount,
        'description': description,
        'trip_id': metadata?['trip_id'], // O backend espera trip_id
        if (metadata != null) 'metadata': metadata,
      });

      final map = Map<String, dynamic>.from(response as Map? ?? const {});
      debugPrint(
        '📡 [MercadoPagoGateway] processWalletPayment response status=${map['status'] ?? 'N/A'}',
      );

      if (map.containsKey('error') || (map['status'] != null && map['status'] != 'APPROVED')) {
         debugPrint('❌ [MercadoPagoGateway] Pagamento via Wallet falhou: ${map['error'] ?? 'Status não aprovado'}');
      } else {
        debugPrint('✅ [MercadoPagoGateway] Pagamento via Wallet processado com sucesso');
      }

      return map;
    } catch (e) {
      debugPrint('❌ [MercadoPagoGateway] Erro em processWalletPayment: $e');
      rethrow;
    }
  }
}

