class DispatchQueueItem {
  final String serviceId;
  final int providerUserId;
  final String status;
  final int? queueOrder;
  final int attemptNo;
  final int maxAttempts;
  final int notificationCount;
  final String? skipReason;

  const DispatchQueueItem({
    required this.serviceId,
    required this.providerUserId,
    required this.status,
    required this.queueOrder,
    required this.attemptNo,
    required this.maxAttempts,
    required this.notificationCount,
    required this.skipReason,
  });

  factory DispatchQueueItem.fromMap(Map<String, dynamic> map) {
    int? parseInt(dynamic raw) {
      if (raw is num) return raw.toInt();
      return int.tryParse('${raw ?? ''}');
    }

    return DispatchQueueItem(
      serviceId: (map['service_id'] ?? '').toString(),
      providerUserId: parseInt(map['provider_user_id']) ?? 0,
      status: (map['status'] ?? '').toString().trim().toLowerCase(),
      queueOrder: parseInt(map['queue_order']),
      attemptNo: parseInt(map['attempt_no']) ?? 1,
      maxAttempts: parseInt(map['max_attempts']) ?? 3,
      notificationCount: parseInt(map['notification_count']) ?? 0,
      skipReason: map['skip_reason']?.toString(),
    );
  }
}
