class BackendTrackingSnapshotState {
  const BackendTrackingSnapshotState({
    required this.service,
    required this.providerLocation,
    required this.paymentSummary,
    required this.finalActions,
    required this.openDispute,
    required this.latestPrimaryDispute,
  });

  final Map<String, dynamic>? service;
  final Map<String, dynamic>? providerLocation;
  final Map<String, dynamic>? paymentSummary;
  final Map<String, dynamic>? finalActions;
  final Map<String, dynamic>? openDispute;
  final Map<String, dynamic>? latestPrimaryDispute;

  factory BackendTrackingSnapshotState.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? json;

    Map<String, dynamic>? readMap(String key) {
      final raw = data[key];
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return raw.cast<String, dynamic>();
      return null;
    }

    return BackendTrackingSnapshotState(
      service: readMap('service'),
      providerLocation: readMap('providerLocation'),
      paymentSummary: readMap('paymentSummary'),
      finalActions: readMap('finalActions'),
      openDispute: readMap('openDispute'),
      latestPrimaryDispute: readMap('latestPrimaryDispute'),
    );
  }
}
