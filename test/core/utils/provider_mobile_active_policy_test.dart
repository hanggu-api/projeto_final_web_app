import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/core/utils/provider_mobile_active_policy.dart';

void main() {
  group('resolveProviderMobileActiveRoute', () {
    test('envia status ativos moveis para provider-active', () {
      for (final status in const [
        'in_progress',
        'arrived',
        'waiting_payment_remaining',
        'awaiting_confirmation',
        'waiting_client_confirmation',
        'completion_requested',
        'schedule_proposed',
        'scheduled',
      ]) {
        expect(
          resolveProviderMobileActiveRoute({
            'id': 'svc-$status',
            'status': status,
            'is_fixed': false,
          }),
          '/provider-active/svc-$status',
        );
      }
    });

    test('nao envia servico fixo ou terminal para provider-active', () {
      expect(
        resolveProviderMobileActiveRoute({
          'id': 'fixed-1',
          'status': 'in_progress',
          'is_fixed': true,
        }),
        isNull,
      );
      expect(
        resolveProviderMobileActiveRoute({
          'id': 'done-1',
          'status': 'completed',
          'is_fixed': false,
        }),
        isNull,
      );
    });
  });
}
