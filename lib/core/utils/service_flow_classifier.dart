enum ServiceFlowKind { mobile, fixed, trip, unknown }

String serviceFlowKindTag(ServiceFlowKind kind) {
  switch (kind) {
    case ServiceFlowKind.mobile:
      return 'mobile';
    case ServiceFlowKind.fixed:
      return 'fixed';
    case ServiceFlowKind.trip:
      return 'trip';
    case ServiceFlowKind.unknown:
      return 'unknown';
  }
}

ServiceFlowKind classifyServiceFlow(Map<String, dynamic>? service) {
  if (service == null) return ServiceFlowKind.unknown;

  final explicit = (service['service_scope'] ?? service['service_kind'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  if (explicit == 'mobile') return ServiceFlowKind.mobile;
  if (explicit == 'fixed') return ServiceFlowKind.fixed;
  if (explicit == 'trip') return ServiceFlowKind.trip;

  final tipoFluxo = (service['tipo_fluxo'] ?? '')
      .toString()
      .trim()
      .toUpperCase();
  if (tipoFluxo == 'MOVEL') return ServiceFlowKind.mobile;
  if (tipoFluxo == 'FIXO') return ServiceFlowKind.fixed;

  if (service['is_mobile'] == true) return ServiceFlowKind.mobile;
  if (service['is_fixed'] == true || service['at_provider'] == true) {
    return ServiceFlowKind.fixed;
  }

  final locationType = (service['location_type'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final serviceType = (service['service_type'] ?? '')
      .toString()
      .trim()
      .toLowerCase();

  if (locationType == 'provider' ||
      locationType == 'at_provider' ||
      serviceType == 'at_provider') {
    return ServiceFlowKind.fixed;
  }

  if (locationType == 'client' ||
      locationType == 'customer' ||
      locationType == 'home' ||
      serviceType == 'mobile') {
    return ServiceFlowKind.mobile;
  }

  final tripId = (service['trip_id'] ?? service['uber_trip_id'] ?? '')
      .toString()
      .trim();
  if (tripId.isNotEmpty) return ServiceFlowKind.trip;

  return ServiceFlowKind.mobile;
}

bool isFixedServiceFlow(Map<String, dynamic>? service) {
  return classifyServiceFlow(service) == ServiceFlowKind.fixed;
}

bool isMobileServiceFlow(Map<String, dynamic>? service) {
  return classifyServiceFlow(service) == ServiceFlowKind.mobile;
}

bool isTripServiceFlow(Map<String, dynamic>? service) {
  return classifyServiceFlow(service) == ServiceFlowKind.trip;
}
