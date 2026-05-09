import 'dart:async';

abstract class IPaymentGateway {
  /// Nome identificador do gateway (ex: 'mercado_pago', 'stripe')
  String get name;

  /// Cria ou recupera um cliente no gateway
  Future<String> createCustomer({
    required String name,
    required String email,
    required String document,
    String? phone,
  });

  /// Gera um PIX para pagamento
  Future<Map<String, dynamic>> generatePix({
    required String customerId,
    required double amount,
    required String description,
    Map<String, dynamic>? metadata,
  });

  /// Processa pagamento via cartão de crédito (usando token/ID salvo)
  Future<Map<String, dynamic>> processCardPayment({
    required String customerId,
    required String cardId,
    required double amount,
    required String description,
    String? securityCode,
    Map<String, dynamic>? metadata,
  });

  /// Salva um cartão no gateway e retorna o ID/Token e metadados
  Future<Map<String, dynamic>> tokenizeCard({
    required String customerId,
    required Map<String, dynamic> cardData,
  });

  /// Gera um token temporário para um cartão já salvo (usado para validar CVV antes da viagem)
  Future<String> generateCardToken({
    required String cardId,
    required String securityCode,
  });

  /// Realiza checkout/split para prestadores (opcional dependendo do gateway)
  Future<Map<String, dynamic>> processPayout({
    required String accountId,
    required double amount,
    Map<String, dynamic>? metadata,
  });

  /// Processa pagamento usando o saldo da carteira (Wallet) vinculada do usuário
  Future<Map<String, dynamic>> processWalletPayment({
    required int userId,
    required double amount,
    required String description,
    Map<String, dynamic>? metadata,
  });
}
