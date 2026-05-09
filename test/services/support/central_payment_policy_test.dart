import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/services/support/central_payment_policy.dart';

void main() {
  group('CentralPaymentPolicy', () {
    test('does not add fee for direct pix or cash', () {
      expect(CentralPaymentPolicy.calculateFareWithFees(100, 'PIX'), 100);
      expect(
        CentralPaymentPolicy.calculateFareWithFees(100, 'PIX Direto'),
        100,
      );
      expect(CentralPaymentPolicy.calculateFareWithFees(100, 'Dinheiro'), 100);
      expect(
        CentralPaymentPolicy.calculateFareWithFees(100, 'Dinheiro/Direto'),
        100,
      );
      expect(
        CentralPaymentPolicy.calculateFareWithFees(100, 'pix_direct'),
        100,
      );
    });

    test('adds Mercado Pago platform fee', () {
      expect(
        CentralPaymentPolicy.calculateFareWithFees(100, 'MercadoPago'),
        105,
      );
      expect(
        CentralPaymentPolicy.calculateFareWithFees(100, 'Saldo Mercado Pago'),
        105,
      );
    });

    test('adds card platform fee for generic and saved cards', () {
      expect(CentralPaymentPolicy.calculateFareWithFees(100, 'Card'), 105);
      expect(CentralPaymentPolicy.calculateFareWithFees(100, 'Card_123'), 105);
      expect(
        CentralPaymentPolicy.calculateFareWithFees(100, 'Cartão salvo'),
        105,
      );
    });

    test('adds machine card fee', () {
      expect(
        CentralPaymentPolicy.calculateFareWithFees(
          100,
          'card_machine_physical',
        ),
        105,
      );
    });

    test('keeps unknown payment methods unchanged', () {
      expect(CentralPaymentPolicy.calculateFareWithFees(100, 'outro'), 100);
    });
  });
}
