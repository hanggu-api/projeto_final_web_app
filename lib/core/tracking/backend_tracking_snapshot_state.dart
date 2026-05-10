import '../../services/api_service.dart';
import 'backend_tracking_view_state.dart';

class BackendTrackingSnapshotState {
  const BackendTrackingSnapshotState({
    required this.service,
    required this.providerLocation,
    required this.paymentSummary,
    required this.finalActions,
    required this.openDispute,
    required this.latestPrimaryDispute,
    required this.viewState,
  });

  final Map<String, dynamic>? service;
  final Map<String, dynamic>? providerLocation;
  final Map<String, dynamic>? paymentSummary;
  final Map<String, dynamic>? finalActions;
  final Map<String, dynamic>? openDispute;
  final Map<String, dynamic>? latestPrimaryDispute;
  final BackendTrackingViewState? viewState;

  factory BackendTrackingSnapshotState.fromJson(
    Map<String, dynamic> json, {
    ServiceDataScope scope = ServiceDataScope.auto,
    String? role,
  }) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? json;

    Map<String, dynamic>? readMap(String key) {
      final raw = data[key];
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return raw.cast<String, dynamic>();
      return null;
    }

    final service = readMap('service');
    final rawViewState =
        readMap('viewState') ?? readMap('view_state') ?? readMap('screenState');

    return BackendTrackingSnapshotState(
      service: service,
      providerLocation: readMap('providerLocation'),
      paymentSummary: readMap('paymentSummary'),
      finalActions: readMap('finalActions'),
      openDispute: readMap('openDispute'),
      latestPrimaryDispute: readMap('latestPrimaryDispute'),
      viewState: rawViewState != null
          ? BackendTrackingViewState.fromMap(rawViewState)
          : service != null
          ? BackendTrackingViewState.fallback(
              service: service,
              scope: scope,
              role: role,
            )
          : null,
    );
  }
}
