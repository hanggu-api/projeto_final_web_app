import '../constants/trip_statuses.dart';
import 'fixed_schedule_gate.dart';
import 'service_flow_classifier.dart';

String normalizeMobileClientStatus(String? rawStatus) {
  return normalizeServiceStatus(rawStatus);
}

bool shouldKeepClientOnHomeForMobileService(Map<String, dynamic>? service) {
  if (!isMobileServiceFlow(service)) return false;
  final resolvedService = service!;
  final status = normalizeMobileClientStatus(
    resolvedService['status']?.toString(),
  );
  return ServiceStatusSets.clientHomeFallback.contains(status);
}

bool shouldClientOpenTrackingForMobileService(Map<String, dynamic>? service) {
  if (!isMobileServiceFlow(service)) return false;
  final resolvedService = service!;
  final status = normalizeMobileClientStatus(
    resolvedService['status']?.toString(),
  );
  return ServiceStatusSets.clientTracking.contains(status);
}

bool hasAcceptedMobileProvider(Map<String, dynamic>? service) {
  if (service == null) return false;
  return service['provider_id'] != null ||
      (service['provider_uid'] ?? '').toString().trim().isNotEmpty;
}

bool shouldClientOpenMobileProviderSearch(Map<String, dynamic>? service) {
  if (!isMobileServiceFlow(service)) return false;
  if (hasAcceptedMobileProvider(service)) return false;
  final resolvedService = service!;
  final status = normalizeMobileClientStatus(
    resolvedService['status']?.toString(),
  );
  return ServiceStatusSets.clientSearch.contains(status);
}

String resolveClientActiveServiceRoute(
  Map<String, dynamic> service,
  String serviceId,
) {
  final flow = classifyServiceFlow(service);
  if (flow == ServiceFlowKind.trip) {
    return '/uber-tracking/$serviceId';
  }
  if (evaluateFixedScheduleGate(service).shouldStayOnScheduledScreen) {
    return '/scheduled-service/$serviceId';
  }
  if (flow == ServiceFlowKind.fixed) {
    return '/home';
  }
  if (shouldClientOpenMobileProviderSearch(service)) {
    return '/service-busca-prestador-movel/$serviceId';
  }
  return shouldKeepClientOnHomeForMobileService(service)
      ? '/home'
      : '/service-tracking/$serviceId';
}
