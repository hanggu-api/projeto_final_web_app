import '../../domains/service_tracking/models/service_status_view.dart';

class BackendActiveServiceState {
  const BackendActiveServiceState({
    required this.service,
    required this.statusView,
  });

  final Map<String, dynamic>? service;
  final ServiceStatusView? statusView;

  factory BackendActiveServiceState.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? json;
    final serviceRaw = data['service'];
    final statusViewRaw = data['statusView'];

    return BackendActiveServiceState(
      service: serviceRaw is Map ? serviceRaw.cast<String, dynamic>() : null,
      statusView: statusViewRaw is Map<String, dynamic>
          ? _toStatusView(statusViewRaw)
          : statusViewRaw is Map
          ? _toStatusView(statusViewRaw.cast<String, dynamic>())
          : null,
    );
  }

  static ServiceStatusView _toStatusView(Map<String, dynamic> raw) {
    return ServiceStatusView(
      serviceId: raw['serviceId']?.toString() ?? '',
      status: raw['status']?.toString() ?? '',
      serviceScope: raw['serviceScope']?.toString(),
      providerAssigned: raw['providerAssigned'] == true,
      isFixed: raw['isFixed'] == true,
    );
  }
}
