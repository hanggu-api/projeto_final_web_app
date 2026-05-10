import '../constants/trip_statuses.dart';
import 'service_flow_classifier.dart';

bool isActiveMobileServiceForProvider(Map<String, dynamic>? service) {
  if (service == null) return false;
  if (classifyServiceFlow(service) != ServiceFlowKind.mobile) return false;
  final status = normalizeServiceStatus(service['status']?.toString());
  return ServiceStatusSets.mobileActive.contains(status);
}

String? resolveProviderMobileActiveRoute(Map<String, dynamic>? service) {
  if (!isActiveMobileServiceForProvider(service)) return null;
  final serviceId = service?['id']?.toString().trim() ?? '';
  if (serviceId.isEmpty) return null;
  return '/provider-active/$serviceId';
}
