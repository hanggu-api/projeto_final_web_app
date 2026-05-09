import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/core/utils/fixed_booking_hold_policy.dart';

void main() {
  group('FixedBookingHoldPolicy.resolveHold', () {
    test('mantem hold ativo nao expirado como provisório', () {
      final decision = FixedBookingHoldPolicy.resolveHold(
        {
          'status': 'active',
          'expires_at': DateTime.utc(2099, 1, 1).toIso8601String(),
        },
        intent: {'status': 'pending_payment', 'payment_status': 'pending'},
        now: DateTime.utc(2026, 4, 24, 12),
      );

      expect(decision.isProvisional, isTrue);
      expect(decision.blocksAvailability, isTrue);
      expect(decision.providerAgendaServiceStatus, 'waiting_payment');
    });

    test(
      'confirma hold quando pix foi pago mesmo antes do servico existir',
      () {
        final decision = FixedBookingHoldPolicy.resolveHold(
          {
            'status': 'active',
            'expires_at': DateTime.utc(2026, 4, 24, 12, 10).toIso8601String(),
          },
          intent: {'status': 'pending_payment', 'payment_status': 'approved'},
          now: DateTime.utc(2026, 4, 24, 12),
        );

        expect(decision.isConfirmed, isTrue);
        expect(decision.blocksAvailability, isTrue);
        expect(decision.providerAgendaServiceStatus, 'scheduled');
      },
    );

    test('libera hold expirado e pendente', () {
      final decision = FixedBookingHoldPolicy.resolveHold(
        {
          'status': 'active',
          'expires_at': DateTime.utc(2026, 4, 24, 11, 59).toIso8601String(),
        },
        intent: {'status': 'pending_payment', 'payment_status': 'pending'},
        now: DateTime.utc(2026, 4, 24, 12),
      );

      expect(decision.isReleased, isTrue);
      expect(decision.blocksAvailability, isFalse);
    });
  });

  group('FixedBookingHoldPolicy.resolveIntent', () {
    test('considera cancelamento como terminal', () {
      final decision = FixedBookingHoldPolicy.resolveIntent({
        'status': 'cancelled',
        'payment_status': 'cancelled',
        'hold_status': 'cancelled',
      });

      expect(decision.isReleased, isTrue);
    });
  });
}
