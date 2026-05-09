import '../models/service_state.dart';

abstract class ServiceRepository {
  Future<void> updateStatus({
    required String serviceId,
    required ServiceState newState,
  });
}
