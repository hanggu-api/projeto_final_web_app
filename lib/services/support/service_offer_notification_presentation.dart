import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/utils/notification_type_helper.dart';

class ServiceOfferNotificationPresentation {
  static const String channelName = 'Ofertas de atendimento';
  static const String subText = 'Oferta premium';
  static const String summaryText = 'Oferta disponivel agora';
  static const int timeoutMs = 30000;

  static bool handles(String? type) {
    final normalized = normalizeNotificationType(type);
    return normalized == kCanonicalServiceOfferType ||
        normalized == 'manual_visual_test';
  }

  static String? resolveChannelId(
    String? type, {
    required String serviceOfferChannelId,
  }) {
    if (!handles(type)) return null;
    return serviceOfferChannelId;
  }

  static String? resolveChannelName(String? type) {
    if (!handles(type)) return null;
    return channelName;
  }

  static AndroidNotificationCategory? resolveCategory(String? type) {
    if (!handles(type)) return null;
    return AndroidNotificationCategory.call;
  }

  static Importance? resolveImportance(String? type) {
    if (!handles(type)) return null;
    return Importance.max;
  }

  static Priority? resolvePriority(String? type) {
    if (!handles(type)) return null;
    return Priority.max;
  }

  static bool? resolveFullScreenIntent(String? type) {
    if (!handles(type)) return null;
    return true;
  }

  static int? resolveTimeout(String? type) {
    final normalized = normalizeNotificationType(type);
    if (normalized == 'manual_visual_test') return null;
    if (!handles(type)) return null;
    return timeoutMs;
  }

  static String? resolveSubText(String? type) {
    if (!handles(type)) return null;
    return subText;
  }

  static String? resolveStatusSummary(String? type) {
    if (!handles(type)) return null;
    return summaryText;
  }
}
