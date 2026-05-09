import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/notification_dispatch_request.dart';
import '../models/notification_registry_entry.dart';
import 'notification_registry.dart';

class NotificationDispatcher {
  final FlutterLocalNotificationsPlugin localNotifications;
  final NotificationRegistry registry;

  NotificationDispatcher({
    required this.localNotifications,
    NotificationRegistry? registry,
  }) : registry = registry ?? NotificationRegistry();

  Future<void> dispatchLocal(NotificationDispatchRequest request) async {
    if (registry.shouldIgnoreDuplicate(request.payload)) {
      registry.record(
        request.payload,
        NotificationDispatchStatus.ignoredDuplicate,
        reason: 'dedupe_window',
      );
      return;
    }

    registry.record(request.payload, NotificationDispatchStatus.prepared);
    try {
      await localNotifications.show(
        id: request.id,
        title: request.payload.title,
        body: request.payload.body,
        notificationDetails: request.details,
        payload: jsonEncode(request.payload.toMap()),
      );
      registry.record(request.payload, NotificationDispatchStatus.displayed);
    } catch (e) {
      registry.record(
        request.payload,
        NotificationDispatchStatus.failed,
        reason: e.toString(),
      );
      rethrow;
    }
  }
}
