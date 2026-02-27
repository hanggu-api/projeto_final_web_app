import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentService {
  /// Public Key do Mercado Pago — usada APENAS para tokenizar o cartão no frontend
  static const String mpPublicKey = String.fromEnvironment(
    'MP_PUBLIC_KEY',
    defaultValue: 'APP_USR-146c3bc4-631d-44cb-aec3-81cc7b6026d9',
  );

  final http.Client _client;

  PaymentService({http.Client? client}) : _client = client ?? http.Client();

  /// Gera um Device ID (Fingerprint) para prevenção de fraude do Mercado Pago
  Future<String> getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'ios-device-id';
      }
      return 'device-id-fallback';
    } catch (e) {
      return 'device-id-error';
    }
  }

  /// Cria um token de cartão diretamente na API pública do Mercado Pago.
  /// Esta chamada é feita do FRONTEND com a public key — NÃO usa o backend.
  Future<String> createCardToken({
    required String cardNumber,
    required String cardholderName,
    required String expirationMonth,
    required String expirationYear,
    required String securityCode,
    required String identificationType,
    required String identificationNumber,
  }) async {
    debugPrint('PaymentService: createCardToken →  MP API');
    try {
      final url = Uri.parse(
        'https://api.mercadopago.com/v1/card_tokens?public_key=$mpPublicKey',
      );

      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'card_number': cardNumber.replaceAll(' ', ''),
          'cardholder': {
            'name': cardholderName,
            'identification': {
              'type': identificationType,
              'number': identificationNumber,
            },
          },
          'security_code': securityCode,
          'expiration_month': int.tryParse(expirationMonth),
          'expiration_year': int.tryParse(expirationYear),
        }),
      );

      debugPrint('createCardToken → status: ${response.statusCode}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['id'];
      } else {
        final error = jsonDecode(response.body);
        final errorMessage =
            error['message'] ?? error['error'] ?? 'Erro desconhecido ao tokenizar cartão';
        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint('Erro ao criar token de cartão: $e');
      rethrow;
    }
  }

  void dispose() {
    _client.close();
  }

  /// Processa o pagamento via Supabase Edge Function `payments`.
  /// A Edge Function chama a API do Mercado Pago de forma segura (server-side)
  /// usando o MP_ACCESS_TOKEN armazenado nos secrets do Supabase.
  Future<Map<String, dynamic>> processPayment({
    required double amount,
    required String token,
    required String description,
    required int installments,
    required String paymentMethodId,
    required String email,
    required String serviceId,
    String? issuerId,
    String? paymentType,
    Map<String, dynamic>? payer,
    String? deviceId,
  }) async {
    try {
      debugPrint('PaymentService: processPayment → Supabase Edge Fn payments');

      // Sprint 3: Chama a Edge Function `payments` em vez do backend legado
      final response = await Supabase.instance.client.functions.invoke(
        'payments',
        body: {
          'transaction_amount': amount,
          'token': token,
          'description': description,
          'installments': installments,
          'payment_method_id': paymentMethodId,
          'payer': payer ?? {'email': email},
          'service_id': serviceId,
          'device_id': deviceId,
          'issuer_id': issuerId,
          'payment_type': paymentType,
        },
        method: HttpMethod.post,
      );

      final data = response.data as Map<String, dynamic>? ?? {};

      if (data['success'] == true) {
        final payment = data['payment'] as Map<String, dynamic>? ?? {};
        if (payment.containsKey('warning')) {
          debugPrint('⚠️ WARNING: ${payment['warning']}');
        }
        return {
          'status': payment['status'] ?? 'approved',
          'transaction_id': payment['id'].toString(),
          'amount': amount,
          'date_created': DateTime.now().toIso8601String(),
          'original_response': data,
        };
      } else {
        final errMsg = data['error'] ?? data['message'] ?? 'Falha no pagamento';
        debugPrint('❌ Pagamento recusado: $errMsg');
        throw Exception(errMsg);
      }
    } catch (e) {
      debugPrint('Erro no processamento do pagamento: $e');
      rethrow;
    }
  }
}
