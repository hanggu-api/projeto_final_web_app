import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/services/support/api_active_service_policy.dart';

void main() {
  group('ApiActiveServicePolicy', () {
    test('considera status terminal como inativo', () {
      final result = ApiActiveServicePolicy.isActiveForCurrentRole(
        service: {'status': 'completed', 'client_uid': 'client-1'},
        authUid: 'client-1',
        userId: 10,
        role: 'client',
      );

      expect(result, isFalse);
    });

    test('ignora fixo pending/waiting_payment para cliente', () {
      final pending = ApiActiveServicePolicy.isActiveForCurrentRole(
        service: {
          'status': 'waiting_payment',
          'is_fixed': true,
          'client_uid': 'client-1',
        },
        authUid: 'client-1',
        userId: 10,
        role: 'client',
      );

      final scheduled = ApiActiveServicePolicy.isActiveForCurrentRole(
        service: {
          'status': 'scheduled',
          'is_fixed': true,
          'client_uid': 'client-1',
        },
        authUid: 'client-1',
        userId: 10,
        role: 'client',
      );

      expect(pending, isFalse);
      expect(scheduled, isTrue);
    });

    test('reconhece atribuição ao provider por uid', () {
      final result = ApiActiveServicePolicy.isAssignedToProvider(
        service: {'provider_uid': 'prov-1'},
        authUid: 'prov-1',
        userId: null,
      );

      expect(result, isTrue);
    });

    test('reconhece atribuição ao client por id numérico', () {
      final result = ApiActiveServicePolicy.isAssignedToClient(
        service: {'client_id': '42'},
        authUid: 'other',
        userId: 42,
      );

      expect(result, isTrue);
    });

    test('aceita serviço móvel ativo para provider', () {
      final result = ApiActiveServicePolicy.isActiveForCurrentRole(
        service: {
          'status': 'accepted',
          'provider_uid': 'prov-2',
          'is_fixed': false,
        },
        authUid: 'prov-2',
        userId: 99,
        role: 'provider',
      );

      expect(result, isTrue);
    });

    test('rejeita serviço sem vínculo com role atual', () {
      final result = ApiActiveServicePolicy.isActiveForCurrentRole(
        service: {
          'status': 'accepted',
          'provider_uid': 'prov-9',
          'client_uid': 'client-9',
        },
        authUid: 'outsider',
        userId: 1,
        role: 'provider',
      );

      expect(result, isFalse);
    });
  });
}
