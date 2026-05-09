import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/fixed_booking_hold_policy.dart';

enum PendingFixedBookingResolution {
  keepPending,
  openScheduledService,
  clearPending,
}

class PendingFixedBookingDecision {
  final PendingFixedBookingResolution resolution;
  final String createdServiceId;

  const PendingFixedBookingDecision({
    required this.resolution,
    this.createdServiceId = '',
  });

  bool get shouldClearCache =>
      resolution != PendingFixedBookingResolution.keepPending;

  bool get shouldNavigateToScheduledService =>
      resolution == PendingFixedBookingResolution.openScheduledService &&
      createdServiceId.isNotEmpty;

  String get scheduledServiceRoute => '/scheduled-service/$createdServiceId';
}

class PendingFixedBookingPolicy {
  static const String pendingPixPrefsKey = 'fixed_booking_pending_pix_v2';
  static const String legacyPendingPixPrefsKey = 'fixed_booking_pending_pix_v1';
  static const Duration pendingHoldDuration = Duration(minutes: 10);

  const PendingFixedBookingPolicy._();

  static bool isPaid(Map<String, dynamic> intent) {
    return FixedBookingHoldPolicy.isIntentPaid(intent);
  }

  static bool isTerminal(Map<String, dynamic> intent) {
    return FixedBookingHoldPolicy.resolveIntent(intent).isReleased;
  }

  static DateTime? resolveExpiryAt(Map<String, dynamic>? intent) {
    if (intent == null) return null;

    final explicitExpiry = _parseDateTime(
      intent['hold_expires_at'] ??
          intent['expires_at'] ??
          intent['slot_hold']?['expires_at'],
    );
    if (explicitExpiry != null) {
      return explicitExpiry.toLocal();
    }

    final savedAt = _parseDateTime(intent['saved_at']);
    if (savedAt != null) {
      return savedAt.toLocal().add(pendingHoldDuration);
    }

    final createdAt = _parseDateTime(intent['created_at']);
    if (createdAt != null) {
      return createdAt.toLocal().add(pendingHoldDuration);
    }

    return null;
  }

  static PendingFixedBookingDecision evaluate(Map<String, dynamic>? intent) {
    if (intent == null) {
      return const PendingFixedBookingDecision(
        resolution: PendingFixedBookingResolution.clearPending,
      );
    }

    final createdServiceId = (intent['created_service_id'] ?? '')
        .toString()
        .trim();
    if (isPaid(intent) && createdServiceId.isNotEmpty) {
      return PendingFixedBookingDecision(
        resolution: PendingFixedBookingResolution.openScheduledService,
        createdServiceId: createdServiceId,
      );
    }

    if (isTerminal(intent)) {
      return const PendingFixedBookingDecision(
        resolution: PendingFixedBookingResolution.clearPending,
      );
    }

    final expiryAt = resolveExpiryAt(intent);
    if (expiryAt != null && !expiryAt.isAfter(DateTime.now())) {
      return const PendingFixedBookingDecision(
        resolution: PendingFixedBookingResolution.clearPending,
      );
    }

    return const PendingFixedBookingDecision(
      resolution: PendingFixedBookingResolution.keepPending,
    );
  }

  static Future<void> clearLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(pendingPixPrefsKey);
    await prefs.remove(legacyPendingPixPrefsKey);
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
