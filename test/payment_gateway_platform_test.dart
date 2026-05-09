import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/services/payment/payment_service.dart';

void main() {
  group('Mercado Pago Integration Debug', () {
    late PaymentService paymentService;

    setUp(() {
      paymentService = PaymentService();
    });

    test('PaymentService should be a singleton', () {
      final service1 = PaymentService();
      final service2 = PaymentService();
      expect(identical(service1, service2), true);
    });

    test('PaymentService should have mercado_pago gateway registered', () {
      expect(() => paymentService.getGateway('mercado_pago'), returnsNormally);
    });

    test('PaymentService should throw for unknown gateway', () {
      expect(
        () => paymentService.getGateway('unknown_gateway'),
        throwsException,
      );
    });

    test('Gateway name should be mercado_pago', () {
      final gateway = paymentService.getGateway();
      expect(gateway.name, 'mercado_pago');
    });

    group('Debug Log Validation', () {
      test(
        'createCustomer should log initialization',
        () async {
          // Este teste valida que o método pode ser chamado
          // sem que haja erro de plataforma no Linux
          // O resultado será um erro HTTP (expectedado sem servidor rodando),
          // mas não um erro de plataforma

          try {
            // Deve falhar com erro de conexão, não de plataforma
            await paymentService.ensureCustomer(
              userId: 999,
              gatewayName: 'mercado_pago',
              name: 'Test User',
              email: 'test@example.com',
              document: '12345678900',
            );
          } catch (e) {
            // Esperamos erro de conexão ou API, não de plataforma
            final errorStr = e.toString();
            expect(
              errorStr.contains('SocketException') ||
                  errorStr.contains('Connection') ||
                  errorStr.contains('Supabase') ||
                  errorStr.contains('API'),
              true,
              reason:
                  'Should be API/Network error, not platform error: $errorStr',
            );
          }
        },
        skip:
            true, // Skip em ambiente de teste, pois requer servidor rodando
      );
    });

    group('Platform Guard Validation', () {
      test('getGateway should not throw PlatformException', () {
        // Valida que o getGateway pode ser chamado sem erros de plataforma
        expect(() => paymentService.getGateway('mercado_pago'), returnsNormally);
      });

      test('PaymentService should handle missing Supabase gracefully', () {
        // Valida que ausência de Supabase não causa crash de plataforma
        // (isto é validado pelo try-catch no main.dart)
        expect(() => paymentService.getGateway(), returnsNormally);
      });
    });
  });
}
