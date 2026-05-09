class ServiceOfferState {
  final String serviceId;
  final int? queueRowId;
  final int providerUserId;
  final String status;
  final DateTime? responseDeadlineAt;
  final int notificationCount;
  final int attemptNo;
  final int maxAttempts;
  final int? queueOrder;
  final int? cycle;
  final DateTime? lastNotifiedAt;
  final DateTime? answeredAt;
  final String? skipReason;

  const ServiceOfferState({
    required this.serviceId,
    required this.queueRowId,
    required this.providerUserId,
    required this.status,
    required this.responseDeadlineAt,
    required this.notificationCount,
    required this.attemptNo,
    required this.maxAttempts,
    required this.queueOrder,
    required this.cycle,
    required this.lastNotifiedAt,
    required this.answeredAt,
    required this.skipReason,
  });

  bool get isActiveOffer => status == 'notified';

  static DateTime? _parseDate(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static int? _parseInt(dynamic raw) {
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}');
  }

  factory ServiceOfferState.fromMap(
    String serviceId,
    Map<String, dynamic> map,
  ) {
    return ServiceOfferState(
      serviceId: serviceId,
      queueRowId: _parseInt(map['id']),
      providerUserId: _parseInt(map['provider_user_id']) ?? 0,
      status: (map['status'] ?? '').toString().trim().toLowerCase(),
      responseDeadlineAt: _parseDate(map['response_deadline_at']),
      notificationCount: _parseInt(map['notification_count']) ?? 0,
      attemptNo: _parseInt(map['attempt_no']) ?? 1,
      maxAttempts: _parseInt(map['max_attempts']) ?? 3,
      queueOrder: _parseInt(map['queue_order']),
      cycle: _parseInt(map['ciclo_atual']) ?? _parseInt(map['attempt_no']),
      lastNotifiedAt: _parseDate(map['last_notified_at']),
      answeredAt: _parseDate(map['answered_at']),
      skipReason: map['skip_reason']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': queueRowId,
      'service_id': serviceId,
      'provider_user_id': providerUserId,
      'status': status,
      'response_deadline_at': responseDeadlineAt?.toIso8601String(),
      'notification_count': notificationCount,
      'attempt_no': attemptNo,
      'max_attempts': maxAttempts,
      'queue_order': queueOrder,
      'ciclo_atual': cycle,
      'last_notified_at': lastNotifiedAt?.toIso8601String(),
      'answered_at': answeredAt?.toIso8601String(),
      'skip_reason': skipReason,
    };
  }
}
