import '../models/notification_payload.dart';
import '../models/notification_registry_entry.dart';

class NotificationRegistry {
  final Map<String, NotificationRegistryEntry> _latestByKey = {};
  final List<NotificationRegistryEntry> _history = [];
  final Duration dedupeWindow;

  NotificationRegistry({this.dedupeWindow = const Duration(seconds: 2)});

  List<NotificationRegistryEntry> get history => List.unmodifiable(_history);

  bool shouldIgnoreDuplicate(NotificationPayload payload) {
    final key = payload.dedupeKey();
    final latest = _latestByKey[key];
    if (latest == null) return false;
    final elapsed = DateTime.now().difference(latest.at);
    return elapsed < dedupeWindow &&
        (latest.status == NotificationDispatchStatus.prepared ||
            latest.status == NotificationDispatchStatus.displayed);
  }

  NotificationRegistryEntry record(
    NotificationPayload payload,
    NotificationDispatchStatus status, {
    String? reason,
  }) {
    final entry = NotificationRegistryEntry(
      dedupeKey: payload.dedupeKey(),
      type: payload.type,
      entityId: payload.entityId,
      status: status,
      at: DateTime.now(),
      reason: reason,
    );
    _latestByKey[entry.dedupeKey] = entry;
    _history.add(entry);
    if (_history.length > 200) {
      _history.removeRange(0, _history.length - 200);
    }
    return entry;
  }
}
