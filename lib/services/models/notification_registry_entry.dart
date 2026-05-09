enum NotificationDispatchStatus {
  prepared,
  displayed,
  ignoredDuplicate,
  failed,
}

class NotificationRegistryEntry {
  final String dedupeKey;
  final String type;
  final String? entityId;
  final NotificationDispatchStatus status;
  final DateTime at;
  final String? reason;

  const NotificationRegistryEntry({
    required this.dedupeKey,
    required this.type,
    required this.status,
    required this.at,
    this.entityId,
    this.reason,
  });
}
