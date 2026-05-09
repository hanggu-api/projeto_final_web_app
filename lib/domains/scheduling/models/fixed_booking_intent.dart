class FixedBookingIntent {
  final String id;
  final String clienteUid;
  final String? prestadorUid;
  final int clienteUserId;
  final int prestadorUserId;
  final String status;
  final String paymentStatus;
  final String description;
  final int? professionId;
  final String? professionName;
  final int? taskId;
  final String? taskName;
  final int? categoryId;
  final DateTime scheduledAt;
  final int durationMinutes;
  final double priceEstimated;
  final double priceUpfront;
  final String? holdStatus;
  final DateTime? holdExpiresAt;
  final String? createdServiceId;

  const FixedBookingIntent({
    required this.id,
    required this.clienteUid,
    this.prestadorUid,
    required this.clienteUserId,
    required this.prestadorUserId,
    required this.status,
    required this.paymentStatus,
    required this.description,
    this.professionId,
    this.professionName,
    this.taskId,
    this.taskName,
    this.categoryId,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.priceEstimated,
    required this.priceUpfront,
    this.holdStatus,
    this.holdExpiresAt,
    this.createdServiceId,
  });

  bool get isPending =>
      status == 'pending_payment' && paymentStatus == 'pending';

  bool get isPaid =>
      {'paid', 'approved', 'paid_manual'}.contains(paymentStatus) ||
      status == 'paid';

  factory FixedBookingIntent.fromMap(Map<String, dynamic> map) =>
      FixedBookingIntent(
        id: map['id'].toString(),
        clienteUid: map['cliente_uid']?.toString() ?? '',
        prestadorUid: map['prestador_uid']?.toString(),
        clienteUserId: (map['cliente_user_id'] as num).toInt(),
        prestadorUserId: (map['prestador_user_id'] as num).toInt(),
        status: map['status']?.toString() ?? '',
        paymentStatus: map['payment_status']?.toString() ?? '',
        description: map['description']?.toString() ?? '',
        professionId: (map['profession_id'] as num?)?.toInt(),
        professionName: map['profession_name']?.toString(),
        taskId: (map['task_id'] as num?)?.toInt(),
        taskName: map['task_name']?.toString(),
        categoryId: (map['category_id'] as num?)?.toInt(),
        scheduledAt: DateTime.parse(map['scheduled_at'].toString()),
        durationMinutes: (map['duration_minutes'] as num?)?.toInt() ?? 60,
        priceEstimated: (map['price_estimated'] as num?)?.toDouble() ?? 0.0,
        priceUpfront: (map['price_upfront'] as num?)?.toDouble() ?? 0.0,
        holdStatus: map['hold_status']?.toString(),
        holdExpiresAt: map['hold_expires_at'] != null
            ? DateTime.tryParse(map['hold_expires_at'].toString())
            : null,
        createdServiceId: map['created_service_id']?.toString(),
      );
}
