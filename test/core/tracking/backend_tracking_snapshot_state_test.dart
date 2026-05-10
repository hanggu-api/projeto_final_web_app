import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/core/tracking/backend_tracking_snapshot_state.dart';
import 'package:service_101/services/api_service.dart';

void main() {
  group('BackendTrackingSnapshotState', () {
    test('parseia viewState pronto enviado pelo backend', () {
      final snapshot = BackendTrackingSnapshotState.fromJson({
        'data': {
          'service': {'id': 'svc-1', 'status': 'in_progress'},
          'viewState': {
            'serviceId': 'svc-1',
            'role': 'provider',
            'route': '/provider-active/svc-1',
            'screen': 'provider_tracking',
            'stage': 'execution',
            'title': 'Serviço em execução',
            'message': 'Resposta pronta do backend.',
            'isActive': true,
            'shouldPinTracking': true,
            'primaryAction': {
              'type': 'finish_service',
              'label': 'FINALIZAR SERVIÇO',
            },
            'secondaryActions': ['chat', 'navigation'],
          },
        },
      }, scope: ServiceDataScope.mobileOnly);

      expect(snapshot.viewState?.route, '/provider-active/svc-1');
      expect(snapshot.viewState?.title, 'Serviço em execução');
      expect(snapshot.viewState?.primaryAction?['type'], 'finish_service');
      expect(snapshot.viewState?.secondaryActions, ['chat', 'navigation']);
    });

    test('deriva viewState fallback quando backend ainda nao envia', () {
      final snapshot = BackendTrackingSnapshotState.fromJson({
        'data': {
          'service': {
            'id': 'svc-2',
            'status': 'awaiting_confirmation',
            'is_fixed': false,
          },
        },
      }, scope: ServiceDataScope.mobileOnly);

      expect(snapshot.viewState?.route, '/provider-active/svc-2');
      expect(snapshot.viewState?.stage, 'completion');
      expect(snapshot.viewState?.shouldPinTracking, isTrue);
    });
  });
}
