import 'dart:convert';

import '../../core/utils/notification_type_helper.dart';

class ServiceOfferNotificationFlow {
  static bool handlesType(String? type) {
    return isServiceOfferNotificationType(type);
  }

  static String? extractServiceId(Map<String, dynamic> data) {
    final serviceId =
        data['service_id']?.toString().trim() ??
        data['id']?.toString().trim() ??
        '';
    return serviceId.isEmpty ? null : serviceId;
  }

  static String? presentationKey(Map<String, dynamic> data) {
    final type = data['type']?.toString().trim();
    if (!handlesType(type)) return null;
    final serviceId = extractServiceId(data);
    if (serviceId == null) return null;
    final normalizedType = normalizeNotificationType(type);
    return '${normalizedType ?? kCanonicalServiceOfferType}:$serviceId';
  }

  static String encodePendingPayload(
    Map<String, dynamic> data, {
    required String reason,
  }) {
    return jsonEncode({
      'data': data,
      'received_at': DateTime.now().toIso8601String(),
      'service_id': extractServiceId(data),
      'type': normalizeNotificationType(data['type']?.toString()),
      'reason': reason,
    });
  }
}
