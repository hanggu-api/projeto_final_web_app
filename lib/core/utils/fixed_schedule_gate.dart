import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'service_flow_classifier.dart';

class FixedScheduleGateDecision {
  final bool isCanonicalFixed;
  final bool shouldStayOnScheduledScreen;
  final String status;
  final DateTime? scheduledAt;
  final DateTime now;
  final int? minutesUntilSchedule;

  const FixedScheduleGateDecision({
    required this.isCanonicalFixed,
    required this.shouldStayOnScheduledScreen,
    required this.status,
    required this.scheduledAt,
    required this.now,
    required this.minutesUntilSchedule,
  });

  Map<String, Object?> toLogPayload({
    Object? serviceId,
    required String source,
  }) {
    return <String, Object?>{
      'serviceId': serviceId,
      'source': source,
      'status': status,
      'scheduledAt': scheduledAt?.toIso8601String(),
      'now': now.toIso8601String(),
      'minutesUntil': minutesUntilSchedule,
      'decision': shouldStayOnScheduledScreen
          ? 'stay_on_scheduled_screen'
          : 'go_home',
      'isCanonicalFixed': isCanonicalFixed,
    };
  }
}

bool isCanonicalFixedServiceRecord(Map<String, dynamic> service) {
  return isFixedServiceFlow(service);
}

FixedScheduleGateDecision evaluateFixedScheduleGate(
  Map<String, dynamic> service, {
  DateTime? now,
}) {
  final resolvedNow = (now ?? DateTime.now()).toLocal();
  if (!isCanonicalFixedServiceRecord(service)) {
    return FixedScheduleGateDecision(
      isCanonicalFixed: false,
      shouldStayOnScheduledScreen: false,
      status: (service['status'] ?? '').toString().trim().toLowerCase(),
      scheduledAt: null,
      now: resolvedNow,
      minutesUntilSchedule: null,
    );
  }

  final status = (service['status'] ?? '').toString().trim().toLowerCase();
  final rawScheduledAt =
      service['scheduled_at'] ?? service['data_agendada'] ?? service['date'];
  final scheduledAt = rawScheduledAt == null
      ? null
      : DateTime.tryParse(rawScheduledAt.toString())?.toLocal();
  final minutesUntilSchedule = scheduledAt?.difference(resolvedNow).inMinutes;
  final isPreScheduleWindowActive =
      minutesUntilSchedule != null &&
      minutesUntilSchedule >= 0 &&
      minutesUntilSchedule <= 30;
  final isOperationalStatus = <String>{
    'client_departing',
    'client_arrived',
    'arrived',
    'in_progress',
    'awaiting_confirmation',
    'waiting_client_confirmation',
  }.contains(status);
  final isPreScheduleStatus = <String>{
    'accepted',
    'scheduled',
    'confirmed',
  }.contains(status);

  final shouldStayOnScheduledScreen =
      scheduledAt != null &&
      ((isPreScheduleStatus && isPreScheduleWindowActive) ||
          (isOperationalStatus && minutesUntilSchedule != null));

  return FixedScheduleGateDecision(
    isCanonicalFixed: true,
    shouldStayOnScheduledScreen: shouldStayOnScheduledScreen,
    status: status,
    scheduledAt: scheduledAt,
    now: resolvedNow,
    minutesUntilSchedule: minutesUntilSchedule,
  );
}

void logFixedScheduleGateDecision(
  String source,
  Map<String, dynamic> service, {
  DateTime? now,
}) {
  final decision = evaluateFixedScheduleGate(service, now: now);
  debugPrint(
    '🧭 [FixedScheduleGate] ${jsonEncode(decision.toLogPayload(serviceId: service['id'], source: source))}',
  );
}
