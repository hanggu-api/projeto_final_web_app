import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/core/utils/mobile_client_navigation_gate.dart';

void main() {
  group('resolveClientActiveServiceRoute', () {
    test('servico searching_provider sem prestador vai para busca movel', () {
      final route = resolveClientActiveServiceRoute({
        'id': 'svc-1',
        'status': 'searching_provider',
        'is_fixed': false,
      }, 'svc-1');

      expect(route, '/service-busca-prestador-movel/svc-1');
    });

    test('servico accepted com prestador vai para tracking', () {
      final route = resolveClientActiveServiceRoute({
        'id': 'svc-2',
        'status': 'accepted',
        'is_fixed': false,
        'provider_id': 42,
      }, 'svc-2');

      expect(route, '/service-tracking/svc-2');
    });

    test('pagamento pendente continua no tracking atual', () {
      final route = resolveClientActiveServiceRoute({
        'id': 'svc-3',
        'status': 'waiting_payment',
        'is_fixed': false,
      }, 'svc-3');

      expect(route, '/service-tracking/svc-3');
    });
  });
}
