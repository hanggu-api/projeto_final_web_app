enum FixedBookingHoldLifecycle { provisional, confirmed, released }

class FixedBookingHoldDecision {
  final FixedBookingHoldLifecycle lifecycle;

  const FixedBookingHoldDecision(this.lifecycle);

  bool get isProvisional => lifecycle == FixedBookingHoldLifecycle.provisional;
  bool get isConfirmed => lifecycle == FixedBookingHoldLifecycle.confirmed;
  bool get isReleased => lifecycle == FixedBookingHoldLifecycle.released;
  bool get blocksAvailability => !isReleased;
  String get providerAgendaServiceStatus =>
      isProvisional ? 'waiting_payment' : 'scheduled';
}

class FixedBookingHoldPolicy {
  const FixedBookingHoldPolicy._();

  static bool isIntentPaid(Map<String, dynamic>? intent) {
    if (intent == null) return false;
    final paymentStatus = _normalize(intent['payment_status']);
    final status = _normalize(intent['status']);
    final createdServiceId = _stringValue(intent['created_service_id']);

    return paymentStatus == 'paid' ||
        paymentStatus == 'approved' ||
        paymentStatus == 'paid_manual' ||
        status == 'paid' ||
        createdServiceId.isNotEmpty;
  }

  static FixedBookingHoldDecision resolveHold(
    Map<String, dynamic>? hold, {
    Map<String, dynamic>? intent,
    DateTime? now,
  }) {
    final holdStatus = _normalize(hold?['status']);
    final intentStatus = _normalize(intent?['status']);
    final paymentStatus = _normalize(intent?['payment_status']);
    final expiresAt = _parseDateTime(
      hold?['expires_at'] ??
          intent?['hold_expires_at'] ??
          intent?['expires_at'],
    );
    final referenceNow = (now ?? DateTime.now()).toLocal();

    if (holdStatus == 'paid' || isIntentPaid(intent)) {
      return const FixedBookingHoldDecision(
        FixedBookingHoldLifecycle.confirmed,
      );
    }

    if (_isReleasedStatus(holdStatus) ||
        _isReleasedStatus(intentStatus) ||
        _isReleasedStatus(paymentStatus)) {
      return const FixedBookingHoldDecision(FixedBookingHoldLifecycle.released);
    }

    if (holdStatus == 'active') {
      if (expiresAt != null && expiresAt.toLocal().isBefore(referenceNow)) {
        return const FixedBookingHoldDecision(
          FixedBookingHoldLifecycle.released,
        );
      }
      return const FixedBookingHoldDecision(
        FixedBookingHoldLifecycle.provisional,
      );
    }

    if (expiresAt != null) {
      if (expiresAt.toLocal().isBefore(referenceNow)) {
        return const FixedBookingHoldDecision(
          FixedBookingHoldLifecycle.released,
        );
      }
      return const FixedBookingHoldDecision(
        FixedBookingHoldLifecycle.provisional,
      );
    }

    if (intentStatus == 'pending_payment' || paymentStatus == 'pending') {
      return const FixedBookingHoldDecision(
        FixedBookingHoldLifecycle.provisional,
      );
    }

    return const FixedBookingHoldDecision(FixedBookingHoldLifecycle.released);
  }

  static FixedBookingHoldDecision resolveIntent(
    Map<String, dynamic>? intent, {
    DateTime? now,
  }) {
    if (intent == null) {
      return const FixedBookingHoldDecision(FixedBookingHoldLifecycle.released);
    }

    final slotHold = intent['slot_hold'];
    final hold = slotHold is Map<String, dynamic>
        ? slotHold
        : (slotHold is Map ? Map<String, dynamic>.from(slotHold) : null);

    final fallbackHold = <String, dynamic>{
      'status': intent['hold_status'],
      'expires_at': intent['hold_expires_at'] ?? intent['expires_at'],
    }..removeWhere((key, value) => value == null);

    return resolveHold(hold ?? fallbackHold, intent: intent, now: now);
  }

  static bool _isReleasedStatus(String status) =>
      status == 'cancelled' || status == 'expired' || status == 'failed';

  static String _normalize(dynamic value) =>
      value?.toString().toLowerCase().trim() ?? '';

  static String _stringValue(dynamic value) => value?.toString().trim() ?? '';

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
