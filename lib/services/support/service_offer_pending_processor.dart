import '../../core/utils/notification_type_helper.dart';
import '../models/notification_payload.dart';

class ServiceOfferPendingProcessingResult {
  final bool shouldWaitForContext;
  final bool shouldLogDelivered;
  final String? serviceId;
  final Map<String, dynamic> mappedPayload;

  const ServiceOfferPendingProcessingResult({
    required this.shouldWaitForContext,
    required this.shouldLogDelivered,
    required this.serviceId,
    required this.mappedPayload,
  });
}

class ServiceOfferPendingProcessor {
  static ServiceOfferPendingProcessingResult prepare(
    Map<String, dynamic> data,
  ) {
    final notificationPayload = NotificationPayload.fromMap(data);
    final type = notificationPayload.type;
    final serviceId = notificationPayload.entityId;
    final mappedPayload = notificationPayload.toMap();

    final shouldWaitForContext =
        isServiceOfferNotificationType(type) &&
        !isLegacyTripNotificationType(type);

    final shouldLogDelivered =
        serviceId != null && !isLegacyTripNotificationType(type);

    return ServiceOfferPendingProcessingResult(
      shouldWaitForContext: shouldWaitForContext,
      shouldLogDelivered: shouldLogDelivered,
      serviceId: serviceId,
      mappedPayload: mappedPayload,
    );
  }
}
