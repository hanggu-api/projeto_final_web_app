import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_payload.dart';

class NotificationDispatchRequest {
  final int id;
  final NotificationPayload payload;
  final NotificationDetails details;

  const NotificationDispatchRequest({
    required this.id,
    required this.payload,
    required this.details,
  });
}
