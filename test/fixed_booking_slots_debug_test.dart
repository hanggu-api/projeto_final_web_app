import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

import 'package:service_101/services/api_service.dart';

void main() {
  test('debug fixed booking slots for casa barba on 2026-04-24', () async {
    SharedPreferences.setMockInitialValues({});
    await dotenv.load(fileName: '.env');

    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );

    final api = ApiService();
    const providerId = 229;
    const dateKey = '2026-04-24';

    final configResult = await api.getScheduleConfigResultForProvider(
      providerId,
    );
    final directSlots = await api.getProviderAvailableSlots(
      providerId,
      date: dateKey,
      requiredDurationMinutes: 60,
    );
    final batchSlots = await api.getProvidersAvailableSlotsBatch(
      providerIds: const [providerId],
      dateKeys: const [dateKey],
      requiredDurationMinutes: 60,
    );

    final batchDay = batchSlots['$providerId|$dateKey'] ?? const [];

    // ignore: avoid_print
    print('DEBUG_CONFIG_COUNT=${configResult.configCount}');
    // ignore: avoid_print
    print('DEBUG_CONFIGS=${configResult.configs}');
    // ignore: avoid_print
    print('DEBUG_DIRECT_SLOT_COUNT=${directSlots.length}');
    // ignore: avoid_print
    print('DEBUG_DIRECT_SLOTS=$directSlots');
    // ignore: avoid_print
    print('DEBUG_BATCH_SLOT_COUNT=${batchDay.length}');
    // ignore: avoid_print
    print('DEBUG_BATCH_SLOTS=$batchDay');
  });

  test('supports schedule spanning from 07:00 to 04:00 next day', () {
    final api = ApiService();
    final configs = [
      {
        'day_of_week': 5,
        'start_time': '07:00:00',
        'end_time': '04:00:00',
        'break_start': null,
        'break_end': null,
        'slot_duration': 60,
        'is_enabled': true,
      },
    ];

    final sameDaySlots = api.debugGenerateSlotsForDate(
      providerId: 999,
      selectedDate: DateTime(2026, 4, 24),
      configsRaw: configs,
      appointmentsList: const [],
      requiredDurationMinutes: 60,
    );

    final nextDayCarryoverSlots = api.debugGenerateSlotsForDate(
      providerId: 999,
      selectedDate: DateTime(2026, 4, 25),
      configsRaw: configs,
      appointmentsList: const [],
      requiredDurationMinutes: 60,
    );

    expect(
      sameDaySlots.any(
        (slot) => '${slot['start_time']}'.startsWith('2026-04-24T23:00:00'),
      ),
      isTrue,
    );
    expect(
      nextDayCarryoverSlots.any(
        (slot) => '${slot['start_time']}'.startsWith('2026-04-25T00:00:00'),
      ),
      isTrue,
    );
    expect(
      nextDayCarryoverSlots.any(
        (slot) => '${slot['start_time']}'.startsWith('2026-04-25T03:00:00'),
      ),
      isTrue,
    );
  });
}
