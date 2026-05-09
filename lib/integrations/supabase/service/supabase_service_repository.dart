import '../../../core/tracking/backend_tracking_api.dart';
import '../../../domains/service/data/service_repository.dart';
import '../../../domains/service/models/service_state.dart';

class SupabaseServiceRepository implements ServiceRepository {
  final BackendTrackingApi _tracking;

  const SupabaseServiceRepository({BackendTrackingApi? tracking})
    : _tracking = tracking ?? const BackendTrackingApi();

  @override
  Future<void> updateStatus({
    required String serviceId,
    required ServiceState newState,
  }) async {
    await _tracking.updateServiceStatus(
      serviceId,
      status: newState.name,
      scope: 'auto',
    );
  }
}
