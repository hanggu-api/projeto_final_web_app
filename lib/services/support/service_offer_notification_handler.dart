import 'service_offer_notification_flow.dart';

enum ServiceOfferHandlingDecision {
  ignore,
  defer,
  openDriverFlow,
  openProviderFlow,
}

class ServiceOfferNotificationHandler {
  static ServiceOfferHandlingDecision decideForeground(
    Map<String, dynamic> data, {
    required String? role,
    required bool isProviderLikeRole,
    required bool isDriverRole,
  }) {
    final type = data['type']?.toString();
    if (!ServiceOfferNotificationFlow.handlesType(type)) {
      return ServiceOfferHandlingDecision.ignore;
    }

    if (!isProviderLikeRole) {
      return (role ?? '').trim().isEmpty
          ? ServiceOfferHandlingDecision.defer
          : ServiceOfferHandlingDecision.ignore;
    }

    if (isDriverRole) {
      return ServiceOfferHandlingDecision.openDriverFlow;
    }

    return ServiceOfferHandlingDecision.openProviderFlow;
  }

  static ServiceOfferHandlingDecision decideTapFallback(
    Map<String, dynamic> data, {
    required String? role,
    required bool isProviderLikeRole,
    required bool isDriverRole,
  }) {
    final type = data['type']?.toString();
    if (!ServiceOfferNotificationFlow.handlesType(type)) {
      return ServiceOfferHandlingDecision.ignore;
    }

    if (!isProviderLikeRole) {
      return (role ?? '').trim().isEmpty
          ? ServiceOfferHandlingDecision.defer
          : ServiceOfferHandlingDecision.ignore;
    }

    if (isDriverRole) {
      return ServiceOfferHandlingDecision.openDriverFlow;
    }

    return ServiceOfferHandlingDecision.openProviderFlow;
  }
}
