import '../../core/utils/fixed_schedule_gate.dart';

class ApiActiveServicePolicy {
  const ApiActiveServicePolicy._();

  static bool isTerminalStatus(String rawStatus) {
    final s = rawStatus.toLowerCase().trim();
    return {
      'completed',
      'finished',
      'done',
      'cancelled',
      'canceled',
      'concluido',
      'cancelado',
      'refunded',
      'expired',
      'closed',
      'deleted',
      'not_found',
    }.contains(s);
  }

  static bool isAssignedToProvider({
    required Map<String, dynamic> service,
    required String authUid,
    required int? userId,
  }) {
    final providerUid = (service['provider_uid'] ?? service['prestador_uid'] ?? '')
        .toString()
        .trim();
    final providerId = (service['provider_id'] ?? '').toString().trim();
    if (providerUid.isNotEmpty && providerUid == authUid) return true;
    if (userId != null &&
        providerId.isNotEmpty &&
        providerId == userId.toString()) {
      return true;
    }
    return false;
  }

  static bool isAssignedToClient({
    required Map<String, dynamic> service,
    required String authUid,
    required int? userId,
  }) {
    final clientUid = (service['client_uid'] ?? service['cliente_uid'] ?? '')
        .toString()
        .trim();
    final clientId = (service['client_id'] ?? '').toString().trim();
    if (clientUid.isNotEmpty && clientUid == authUid) return true;
    if (userId != null &&
        clientId.isNotEmpty &&
        clientId == userId.toString()) {
      return true;
    }
    return false;
  }

  static bool isFixedService(Map<String, dynamic> service) {
    return isCanonicalFixedServiceRecord(service);
  }

  static bool isActiveForCurrentRole({
    required Map<String, dynamic> service,
    required String authUid,
    required int? userId,
    required String? role,
  }) {
    final status = (service['status'] ?? '').toString();
    if (status.trim().isEmpty || isTerminalStatus(status)) return false;
    final normalizedStatus = status.trim().toLowerCase();
    final isFixed = isFixedService(service);
    if (isFixed && {'waiting_payment', 'pending'}.contains(normalizedStatus)) {
      return false;
    }
    if (role == 'provider') {
      return isAssignedToProvider(
        service: service,
        authUid: authUid,
        userId: userId,
      );
    }
    if (role == 'client') {
      return isAssignedToClient(
        service: service,
        authUid: authUid,
        userId: userId,
      );
    }
    return isAssignedToProvider(
          service: service,
          authUid: authUid,
          userId: userId,
        ) ||
        isAssignedToClient(
          service: service,
          authUid: authUid,
          userId: userId,
        );
  }
}
