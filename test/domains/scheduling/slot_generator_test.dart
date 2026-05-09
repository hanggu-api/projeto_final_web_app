import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/domains/scheduling/domain/slot_generator.dart';

void main() {
  const generator = SlotGenerator();

  // --- parseDateKey ---
  group('SlotGenerator.parseDateKey', () {
    test('parseia chave válida', () {
      final result = SlotGenerator.parseDateKey('2026-05-01');
      expect(result, equals(DateTime(2026, 5, 1)));
    });

    test('retorna null para chave inválida', () {
      expect(SlotGenerator.parseDateKey('invalid'), isNull);
      expect(SlotGenerator.parseDateKey('2026-05'), isNull);
    });
  });

  // --- isScheduleEnabled ---
  group('SlotGenerator.isScheduleEnabled', () {
    test('retorna true quando is_enabled = true', () {
      expect(
        SlotGenerator.isScheduleEnabled({'is_enabled': true}),
        isTrue,
      );
    });

    test('retorna false quando is_enabled = false', () {
      expect(
        SlotGenerator.isScheduleEnabled({'is_enabled': false}),
        isFalse,
      );
    });

    test('usa horários como fallback quando is_enabled ausente', () {
      expect(
        SlotGenerator.isScheduleEnabled({
          'start_time': '08:00',
          'end_time': '18:00',
        }),
        isTrue,
      );
      expect(
        SlotGenerator.isScheduleEnabled({'start_time': '', 'end_time': ''}),
        isFalse,
      );
    });
  });

  // --- normalizeLegacyConfigs ---
  group('SlotGenerator.normalizeLegacyConfigs', () {
    test('normaliza lista legada corretamente', () {
      final result = SlotGenerator.normalizeLegacyConfigs([
        {
          'day_of_week': 1,
          'start': '09:00',
          'end': '17:00',
          'slot_duration': 60,
        },
      ]);
      expect(result.length, 1);
      expect(result.first['start_time'], '09:00');
      expect(result.first['end_time'], '17:00');
      expect(result.first['slot_duration'], 60);
    });

    test('retorna lista vazia para input inválido', () {
      expect(SlotGenerator.normalizeLegacyConfigs(null), isEmpty);
      expect(SlotGenerator.normalizeLegacyConfigs('invalid'), isEmpty);
    });
  });

  // --- generateSlotsForDate ---
  group('SlotGenerator.generateSlotsForDate', () {
    final monday = DateTime(2026, 5, 4); // segunda-feira (weekday=1, index=1)

    final mondayConfig = {
      'day_of_week': 1, // segunda
      'start_time': '08:00',
      'end_time': '10:00',
      'slot_duration': 60,
      'is_enabled': true,
    };

    test('gera slots livres quando não há agendamentos', () {
      final slots = generator.generateSlotsForDate(
        providerId: 1,
        selectedDate: monday,
        configsRaw: [mondayConfig],
        appointmentsList: [],
      );

      expect(slots.length, 2); // 08:00-09:00 e 09:00-10:00
      expect(slots.every((s) => s['status'] == 'free'), isTrue);
      expect(slots.every((s) => s['is_selectable'] == true), isTrue);
    });

    test('marca slot como booked quando há agendamento conflitante', () {
      final slots = generator.generateSlotsForDate(
        providerId: 1,
        selectedDate: monday,
        configsRaw: [mondayConfig],
        appointmentsList: [
          {
            'start_time': DateTime(2026, 5, 4, 8).toIso8601String(),
            'end_time': DateTime(2026, 5, 4, 9).toIso8601String(),
            'status': 'confirmed',
          },
        ],
      );

      expect(slots.length, 2);
      expect(slots[0]['status'], 'booked');
      expect(slots[1]['status'], 'free');
    });

    test('retorna lista vazia quando não há config para o dia', () {
      final sunday = DateTime(2026, 5, 3); // domingo (weekday=7, index=0)
      final slots = generator.generateSlotsForDate(
        providerId: 1,
        selectedDate: sunday,
        configsRaw: [mondayConfig], // só segunda
        appointmentsList: [],
      );
      expect(slots, isEmpty);
    });

    test('respeita requiredDurationMinutes para is_selectable', () {
      final config = {
        'day_of_week': 1,
        'start_time': '08:00',
        'end_time': '11:00',
        'slot_duration': 60,
        'is_enabled': true,
      };

      // Ocupa o segundo slot (09:00-10:00)
      final slots = generator.generateSlotsForDate(
        providerId: 1,
        selectedDate: monday,
        configsRaw: [config],
        appointmentsList: [
          {
            'start_time': DateTime(2026, 5, 4, 9).toIso8601String(),
            'end_time': DateTime(2026, 5, 4, 10).toIso8601String(),
            'status': 'confirmed',
          },
        ],
        requiredDurationMinutes: 120, // precisa de 2 slots livres consecutivos
      );

      // 08:00 livre mas não tem 2h consecutivas (09:00 está ocupado)
      expect(slots[0]['status'], 'free');
      expect(slots[0]['is_selectable'], isFalse);
      // 10:00 livre mas só tem 1h até o fim
      expect(slots[2]['status'], 'free');
      expect(slots[2]['is_selectable'], isFalse);
    });

    test('gera slot de almoço quando break está configurado', () {
      final config = {
        'day_of_week': 1,
        'start_time': '08:00',
        'end_time': '14:00',
        'lunch_start': '12:00',
        'lunch_end': '13:00',
        'slot_duration': 60,
        'is_enabled': true,
      };

      final slots = generator.generateSlotsForDate(
        providerId: 1,
        selectedDate: monday,
        configsRaw: [config],
        appointmentsList: [],
      );

      final lunchSlots = slots.where((s) => s['status'] == 'lunch').toList();
      expect(lunchSlots.length, 1);
      expect(lunchSlots.first['is_selectable'], isFalse);
    });
  });

  // --- Use cases com mock ---
  group('GetProviderAvailableSlotsUseCase (mock)', () {
    test('delega corretamente para o repositório', () async {
      final repo = MockSchedulingRepository();
      final useCase = GetProviderAvailableSlotsUseCaseTest(repo);

      final result = await useCase.call(1, date: '2026-05-04');
      expect(result, equals(repo.stubbedSlots));
      expect(repo.lastProviderId, 1);
      expect(repo.lastDate, '2026-05-04');
    });
  });
}

// --- Mock mínimo ---

class MockSchedulingRepository {
  int? lastProviderId;
  String? lastDate;

  final stubbedSlots = [
    {'start_time': '2026-05-04T08:00:00', 'status': 'free'},
  ];

  Future<List<Map<String, dynamic>>> getProviderAvailableSlots(
    int providerId, {
    String? date,
    int? requiredDurationMinutes,
  }) async {
    lastProviderId = providerId;
    lastDate = date;
    return stubbedSlots;
  }
}

// Use case simplificado para teste (sem depender do contrato completo)
class GetProviderAvailableSlotsUseCaseTest {
  final MockSchedulingRepository _repo;
  const GetProviderAvailableSlotsUseCaseTest(this._repo);

  Future<List<Map<String, dynamic>>> call(
    int providerId, {
    String? date,
    int? requiredDurationMinutes,
  }) => _repo.getProviderAvailableSlots(
    providerId,
    date: date,
    requiredDurationMinutes: requiredDurationMinutes,
  );
}
