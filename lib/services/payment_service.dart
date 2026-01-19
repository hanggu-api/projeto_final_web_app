import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'api_service.dart';

class PaymentService {
  // TODO: Substitua pela sua Public Key do Mercado Pago (Sandbox ou Produção)
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
        return androidInfo.id; // stable Android ID
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'ios-device-id';
      }
      return 'device-id-fallback';
    } catch (e) {
      return 'device-id-error';
    }
  }

  /// Cria um token de cartão usando a API do Mercado Pago.
  Future<String> createCardToken({
    required String cardNumber,
    required String cardholderName,
    required String expirationMonth,
    required String expirationYear,
    required String securityCode,
    required String identificationType,
    required String identificationNumber,
  }) async {
    debugPrint('DEBUG: createCardToken NO TIMEOUT VERSION');
    debugPrint('Iniciando createCardToken...'); // DEBUG
    try {
      final url = Uri.parse(
        'https://api.mercadopago.com/v1/card_tokens?public_key=$mpPublicKey',
      );
      debugPrint('URL: $url'); // DEBUG

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
      debugPrint('Response status: ${response.statusCode}'); // DEBUG
      debugPrint('Response body: ${response.body}'); // DEBUG

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['id'];
      } else {
        final error = jsonDecode(response.body);
        // Tenta extrair a mensagem de erro da resposta do MP
        final errorMessage =
            error['message'] ??
            error['error'] ??
            'Erro desconhecido ao tokenizar cartão';
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

  /// Processa o pagamento enviando os dados para o backend.
  /// [amount] deve ser enviado com precisão.
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
      // Usa o ApiService para se comunicar com o seu backend
      // O ApiService já gerencia a URL base e autenticação (Bearer token)
      debugPrint('Enviando pagamento para o backend...'); // DEBUG
      final response = await ApiService().post('/payment/process', {
        'transaction_amount': amount,
        'token': token,
        'description': description,
        'installments': installments,
        'payment_method_id': paymentMethodId,
        'payer': payer ?? {'email': email},
        'service_id': serviceId,
        'device_id': deviceId,
        'issuer_id': ?issuerId,
        'payment_type': ?paymentType,
      });

      // O backend retorna { success: true, payment: { ... } }
      // Adaptamos para o formato esperado pela UI se necessário, ou retornamos direto
      if (response['success'] == true) {
        if (response.containsKey('warning')) {
          debugPrint('⚠️ WARNING: ${response['warning']}');
        }
        return {
          'status':
              response['payment']['status'] ??
              'approved', // Mapeia status do MP
          'transaction_id': response['payment']['id'].toString(),
          'amount': amount,
          'date_created': DateTime.now().toIso8601String(),
          'original_response': response,
        };
      } else {
        if (response.containsKey('error') && response['error'] is Map) {
          final err = response['error'];
          final code = err['code'] ?? 'UNKNOWN';
          final msg = err['message'] ?? 'Falha no pagamento';
          debugPrint('❌ Erro de Pagamento ($code): $msg');
          throw Exception('[$code] $msg');
        }
        throw Exception(response['message'] ?? 'Falha no pagamento');
      }
    } catch (e) {
      debugPrint('Erro no processamento do pagamento: $e');
      rethrow;
    }
  }
}
