class ServiceStatusView {
  final String serviceId;
  final String status;
  final String? serviceScope;
  final bool providerAssigned;
  final bool isFixed;

  const ServiceStatusView({
    required this.serviceId,
    required this.status,
    required this.serviceScope,
    required this.providerAssigned,
    required this.isFixed,
  });

  factory ServiceStatusView.fromMap(
    Map<String, dynamic> map, {
    String? serviceScope,
  }) {
    final providerAssigned =
        map['provider_id'] != null ||
        (map['provider_uid'] ?? '').toString().trim().isNotEmpty;
    final resolvedScope =
        serviceScope ?? (map['service_scope'] ?? map['service_kind'])?.toString();
    return ServiceStatusView(
      serviceId: (map['id'] ?? '').toString(),
      status: (map['status'] ?? '').toString().trim().toLowerCase(),
      serviceScope: resolvedScope?.trim().toLowerCase(),
      providerAssigned: providerAssigned,
      isFixed: resolvedScope?.trim().toLowerCase() == 'fixed',
    );
  }
}
