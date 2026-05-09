import '../../../core/utils/fixed_booking_hold_policy.dart';

/// Constantes de domínio de agendamento.
class SchedulingConstants {
  static const Set<String> blockingAppointmentStatuses = {
    'confirmed',
    'scheduled',
    'waiting_payment',
    'booked',
    'in_progress',
  };

  static const List<String> slotHoldSelectFallbacks = [
    'id,prestador_user_id,cliente_user_id,status,scheduled_at,scheduled_end_at,duration_minutes,expires_at,pix_intent_id,created_at,updated_at',
    'id,prestador_user_id,cliente_user_id,status,scheduled_at,scheduled_end_at,duration_minutes,expires_at,pix_intent_id,created_at',
    'id,prestador_user_id,cliente_user_id,status,scheduled_at,scheduled_end_at,pix_intent_id,created_at',
  ];

  static const String appointmentSlotSelect =
      'id,provider_id,status,start_time,end_time,agendamento_servico_id,service_request_id,client_id,created_at';
}

/// Gerador de slots de agenda — lógica pura sem I/O.
///
/// Extraído de [ApiService._generateSlotsForDate].
/// Testável de forma isolada sem dependência de Supabase.
class SlotGenerator {
  const SlotGenerator();

  // --- Helpers de parsing ---

  static DateTime? parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static DateTime? tryParseDateTime(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  static String toLocalIsoString(dynamic raw) {
    final parsed = tryParseDateTime(raw);
    if (parsed == null) return '${raw ?? ''}';
    return parsed.toLocal().toIso8601String();
  }

  static bool isScheduleEnabled(Map<String, dynamic> row) {
    final rawIsEnabled = row['is_enabled'] ?? row['enabled'] ?? row['is_active'];
    if (rawIsEnabled == null) {
      final start = row['start_time']?.toString().trim() ?? '';
      final end = row['end_time']?.toString().trim() ?? '';
      return start.isNotEmpty && end.isNotEmpty;
    }
    return _parseBool(rawIsEnabled);
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value == 1;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return false;
  }

  static Map<String, dynamic> mapScheduleRowToConfig(
    Map<String, dynamic> row,
  ) => {
    'day_of_week': row['day_of_week'],
    'start_time': row['start_time'],
    'end_time': row['end_time'],
    'lunch_start': row['break_start'] ?? row['lunch_start'],
    'lunch_end': row['break_end'] ?? row['lunch_end'],
    'break_start': row['break_start'] ?? row['lunch_start'],
    'break_end': row['break_end'] ?? row['lunch_end'],
    'slot_duration': row['slot_duration'] ?? 30,
    'is_enabled': isScheduleEnabled(row),
  };

  static List<Map<String, dynamic>> normalizeLegacyConfigs(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).map((
      conf,
    ) {
      final start =
          (conf['start_time'] ?? conf['start'] ?? '08:00:00').toString();
      final end = (conf['end_time'] ?? conf['end'] ?? '18:00:00').toString();
      final lunchStart =
          (conf['lunch_start'] ?? conf['break_start'])?.toString();
      final lunchEnd = (conf['lunch_end'] ?? conf['break_end'])?.toString();
      final slotDuration = conf['slot_duration'] is int
          ? conf['slot_duration'] as int
          : int.tryParse(conf['slot_duration']?.toString() ?? '') ?? 30;
      final dayOfWeek =
          conf['day_of_week'] ??
          conf['day'] ??
          int.tryParse(conf['day_of_week']?.toString() ?? '') ??
          int.tryParse(conf['day']?.toString() ?? '');
      return {
        'day_of_week': dayOfWeek,
        'start_time': start,
        'end_time': end,
        'lunch_start': lunchStart,
        'lunch_end': lunchEnd,
        'break_start': lunchStart,
        'break_end': lunchEnd,
        'slot_duration': slotDuration.clamp(15, 180),
        'is_enabled': isScheduleEnabled(conf),
      };
    }).toList();
  }

  // --- Hold helpers ---

  static Map<String, dynamic>? extractIntentSnapshotFromHold(
    Map<String, dynamic> hold, {
    Map<String, dynamic>? intent,
  }) {
    if (intent != null) return intent;
    final snapshot = <String, dynamic>{
      'status': hold['intent_status'],
      'payment_status': hold['intent_payment_status'],
      'created_service_id': hold['created_service_id'],
      'hold_status': hold['status'],
      'hold_expires_at': hold['expires_at'],
    }..removeWhere((_, v) => v == null);
    return snapshot.isEmpty ? null : snapshot;
  }

  static bool isActiveSlotHold(
    Map<String, dynamic> hold, {
    Map<String, dynamic>? intent,
  }) {
    final decision = FixedBookingHoldPolicy.resolveHold(
      hold,
      intent: extractIntentSnapshotFromHold(hold, intent: intent),
    );
    return decision.blocksAvailability;
  }

  // --- Geração de slots ---

  /// Gera os slots de um dia a partir das configurações de agenda.
  ///
  /// Equivalente a [ApiService._generateSlotsForDate].
  List<Map<String, dynamic>> generateSlotsForDate({
    required int providerId,
    required DateTime selectedDate,
    required List<Map<String, dynamic>> configsRaw,
    required List<Map<String, dynamic>> appointmentsList,
    List<Map<String, dynamic>> slotHoldsList = const [],
    int? requiredDurationMinutes,
  }) {
    final int dayIndex = selectedDate.weekday % 7;
    final previousDate = selectedDate.subtract(const Duration(days: 1));
    final previousDayIndex = previousDate.weekday % 7;

    bool spansNextDay(Map<String, dynamic> conf) {
      final startRaw = '${conf['start_time'] ?? ''}'.trim();
      final endRaw = '${conf['end_time'] ?? ''}'.trim();
      if (startRaw.isEmpty || endRaw.isEmpty) return false;
      final startParts = startRaw.split(':').map(int.tryParse).toList();
      final endParts = endRaw.split(':').map(int.tryParse).toList();
      if (startParts.length < 2 ||
          endParts.length < 2 ||
          startParts[0] == null ||
          startParts[1] == null ||
          endParts[0] == null ||
          endParts[1] == null) {
        return false;
      }
      final anchor = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );
      final start = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
        startParts[0]!,
        startParts[1]!,
      );
      final end = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
        endParts[0]!,
        endParts[1]!,
      );
      return !start.isBefore(end);
    }

    final dayConfigsWithAnchor =
        <({Map<String, dynamic> config, DateTime anchorDate})>[];
    for (final rawConf in configsRaw) {
      final conf = Map<String, dynamic>.from(rawConf);
      final confDay = conf['day_of_week'] is int
          ? conf['day_of_week'] as int
          : int.tryParse(conf['day_of_week']?.toString() ?? '') ?? -1;
      if (!isScheduleEnabled(conf)) continue;
      if (confDay == dayIndex) {
        dayConfigsWithAnchor.add((config: conf, anchorDate: selectedDate));
        continue;
      }
      if (confDay == previousDayIndex && spansNextDay(conf)) {
        dayConfigsWithAnchor.add((config: conf, anchorDate: previousDate));
      }
    }

    if (dayConfigsWithAnchor.isEmpty) return const [];

    final busyAppointments = appointmentsList
        .map((appt) {
          final status =
              (appt['status'] ?? '').toString().toLowerCase().trim();
          if (!SchedulingConstants.blockingAppointmentStatuses.contains(
            status,
          )) {
            return null;
          }
          final start = tryParseDateTime(appt['start_time']?.toString());
          final end = tryParseDateTime(appt['end_time']?.toString());
          if (start == null || end == null) return null;
          return {'raw': appt, 'start': start, 'end': end};
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    final busyHolds = slotHoldsList
        .map((hold) {
          final holdMap = Map<String, dynamic>.from(hold);
          final decision = FixedBookingHoldPolicy.resolveHold(
            holdMap,
            intent: extractIntentSnapshotFromHold(holdMap),
          );
          if (!decision.blocksAvailability) return null;
          final start = tryParseDateTime(holdMap['scheduled_at']?.toString());
          final end = tryParseDateTime(
            holdMap['scheduled_end_at']?.toString(),
          );
          if (start == null || end == null) return null;
          return {
            'raw': {
              ...holdMap,
              'service_status': decision.providerAgendaServiceStatus,
              'hold_lifecycle': decision.lifecycle.name,
            },
            'start': start,
            'end': end,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    final generatedSlots = <Map<String, dynamic>>[];

    for (final entry in dayConfigsWithAnchor) {
      final conf = entry.config;
      final anchorDate = entry.anchorDate;

      DateTime? parseTimeForAnchor(String? value) {
        if (value == null || value.isEmpty) return null;
        final parts = value.split(':').map((p) => int.tryParse(p)).toList();
        if (parts.length < 2 || parts[0] == null || parts[1] == null) {
          return null;
        }
        return DateTime(
          anchorDate.year,
          anchorDate.month,
          anchorDate.day,
          parts[0]!,
          parts[1]!,
        );
      }

      final start = parseTimeForAnchor(
        conf['start_time']?.toString() ?? '08:00',
      );
      var end = parseTimeForAnchor(conf['end_time']?.toString() ?? '18:00');
      if (start == null || end == null) continue;
      if (!start.isBefore(end)) end = end.add(const Duration(days: 1));

      final lunchStart = parseTimeForAnchor(
        conf['lunch_start']?.toString() ??
            conf['break_start']?.toString() ??
            '',
      );
      var lunchEnd = parseTimeForAnchor(
        conf['lunch_end']?.toString() ?? conf['break_end']?.toString() ?? '',
      );
      if (lunchStart != null &&
          lunchEnd != null &&
          !lunchStart.isBefore(lunchEnd)) {
        lunchEnd = lunchEnd.add(const Duration(days: 1));
      }

      final configuredDuration = conf['slot_duration'] is int
          ? conf['slot_duration'] as int
          : int.tryParse(conf['slot_duration']?.toString() ?? '') ?? 30;
      final slotDuration = configuredDuration.clamp(15, 180);

      DateTime slot = start;
      while (slot.isBefore(end)) {
        final slotEnd = slot.add(Duration(minutes: slotDuration));
        if (slotEnd.isAfter(end)) break;
        if (slotEnd.isBefore(selectedDate) ||
            slot.isAfter(selectedDate.add(const Duration(days: 1)))) {
          slot = slotEnd;
          continue;
        }

        if (lunchStart != null && lunchEnd != null) {
          final overlapsLunch =
              slot.isBefore(lunchEnd) && slotEnd.isAfter(lunchStart);
          if (overlapsLunch) {
            generatedSlots.add({
              'start_time': slot.toIso8601String(),
              'end_time': slotEnd.toIso8601String(),
              'status': 'lunch',
              'is_selectable': false,
              'provider_id': providerId,
              'lunch_label':
                  '${lunchStart.toString().substring(11, 16)}-${lunchEnd.toString().substring(11, 16)}',
            });
            slot = slotEnd;
            continue;
          }
        }

        bool occupied = false;
        Map<String, dynamic>? appointment;

        for (final appt in busyAppointments) {
          final apptStart = appt['start'] as DateTime;
          final apptEnd = appt['end'] as DateTime;
          if (slot.isBefore(apptEnd) && apptStart.isBefore(slotEnd)) {
            occupied = true;
            appointment = Map<String, dynamic>.from(
              appt['raw'] as Map<String, dynamic>,
            );
            break;
          }
        }

        if (!occupied) {
          for (final hold in busyHolds) {
            final holdStart = hold['start'] as DateTime;
            final holdEnd = hold['end'] as DateTime;
            if (slot.isBefore(holdEnd) && holdStart.isBefore(slotEnd)) {
              occupied = true;
              appointment = Map<String, dynamic>.from(
                hold['raw'] as Map<String, dynamic>,
              )..['is_slot_hold'] = true;
              break;
            }
          }
        }

        generatedSlots.add({
          'start_time': slot.toIso8601String(),
          'end_time': slotEnd.toIso8601String(),
          'status': occupied ? 'booked' : 'free',
          'is_manual_block': false,
          'provider_id': providerId,
          if (occupied) 'appointment': appointment,
        });

        slot = slotEnd;
      }
    }

    generatedSlots.sort((a, b) {
      final aStart = DateTime.parse(a['start_time'].toString());
      final bStart = DateTime.parse(b['start_time'].toString());
      return aStart.compareTo(bStart);
    });

    if (requiredDurationMinutes != null && requiredDurationMinutes > 0) {
      for (int i = 0; i < generatedSlots.length; i++) {
        final current = generatedSlots[i];
        if (current['status'] != 'free') {
          current['is_selectable'] = false;
          continue;
        }
        final startTime = DateTime.parse(current['start_time']);
        final targetEnd = startTime.add(
          Duration(minutes: requiredDurationMinutes),
        );
        bool canFit = true;
        DateTime checkTime = startTime;
        int j = i;
        while (checkTime.isBefore(targetEnd)) {
          if (j >= generatedSlots.length) {
            canFit = false;
            break;
          }
          final s = generatedSlots[j];
          final sStart = DateTime.parse(s['start_time']);
          final sEnd = DateTime.parse(s['end_time']);
          if (s['status'] != 'free' || sStart != checkTime) {
            canFit = false;
            break;
          }
          checkTime = sEnd;
          j++;
        }
        current['is_selectable'] = canFit;
      }
    } else {
      for (final s in generatedSlots) {
        s['is_selectable'] = s['status'] == 'free';
      }
    }

    return generatedSlots;
  }
}
