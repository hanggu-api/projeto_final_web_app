import 'package:flutter/foundation.dart';

import '../../../core/scheduling/backend_scheduling_api.dart';
import '../../../core/tracking/backend_tracking_api.dart';
import '../../../domains/scheduling/data/scheduling_repository.dart';
import '../../../domains/scheduling/models/fixed_booking_intent.dart';
import '../../../domains/scheduling/models/schedule_config.dart';
import '../../../domains/scheduling/models/schedule_config_result.dart';

/// Implementação de [SchedulingRepository] com priorização backend-first.
///
class SupabaseSchedulingRepository implements SchedulingRepository {
  final BackendSchedulingApi _backendSchedulingApi;
  final BackendTrackingApi _backendTrackingApi;

  SupabaseSchedulingRepository({
    BackendSchedulingApi backendSchedulingApi = const BackendSchedulingApi(),
    BackendTrackingApi backendTrackingApi = const BackendTrackingApi(),
  }) : _backendSchedulingApi = backendSchedulingApi,
       _backendTrackingApi = backendTrackingApi;

  @override
  Future<ScheduleConfigResult> getScheduleConfigResult(int providerId) async {
    try {
      final backendResult = await _backendSchedulingApi.fetchProviderSchedule(
        providerId,
      );
      if (backendResult != null) {
        final configsRaw = backendResult['configs'];
        final configs = configsRaw is List
            ? configsRaw
                  .whereType<Map>()
                  .map(
                    (row) =>
                        ScheduleConfig.fromMap(row.cast<String, dynamic>()),
                  )
                  .toList()
            : <ScheduleConfig>[];
        return ScheduleConfigResult(
          providerId:
              (backendResult['providerId'] as num?)?.toInt() ?? providerId,
          providerUid: backendResult['providerUid']?.toString(),
          configs: configs,
          usedLegacyFallback:
              backendResult['usedLegacyFallback'] as bool? ?? false,
          foundProviderSchedules:
              backendResult['foundProviderSchedules'] as bool? ?? false,
        );
      }
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] provider schedule backend-first falhou: $e',
      );
    }

    return ScheduleConfigResult(
      providerId: providerId,
      providerUid: null,
      configs: const <ScheduleConfig>[],
      usedLegacyFallback: false,
      foundProviderSchedules: false,
    );
  }

  @override
  Future<List<ScheduleConfig>> getScheduleConfig(int providerId) async {
    final result = await getScheduleConfigResult(providerId);
    return result.configs;
  }

  @override
  Future<void> saveScheduleConfig(
    int providerId,
    String? providerUid,
    List<ScheduleConfig> configs,
  ) async {
    final rawConfigs = configs.map((c) => c.toMap()).toList();
    try {
      final backendResult = await _backendSchedulingApi.saveProviderSchedule(
        providerId,
        rawConfigs,
      );
      if (backendResult != null) return;
    } catch (e) {
      debugPrint('⚠️ [SchedulingRepo] save schedule backend-first falhou: $e');
    }
    throw Exception('Falha ao salvar agenda no backend canônico.');
  }

  @override
  Future<List<Map<String, dynamic>>> getScheduleExceptions(
    int providerId,
  ) async {
    try {
      final backendExceptions = await _backendSchedulingApi
          .fetchProviderScheduleExceptions(providerId);
      if (backendExceptions != null) return backendExceptions;
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] schedule exceptions backend-first falhou: $e',
      );
    }
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<void> saveScheduleExceptions(
    int providerId,
    List<Map<String, dynamic>> exceptions,
  ) async {
    try {
      final backendSaved = await _backendSchedulingApi
          .saveProviderScheduleExceptions(providerId, exceptions);
      if (backendSaved != null) return;
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] save schedule exceptions backend-first falhou: $e',
      );
    }
    throw Exception('Falha ao salvar exceções de agenda no backend canônico.');
  }

  @override
  Future<List<Map<String, dynamic>>> getProviderSlots(
    int providerId, {
    String? date,
  }) async {
    try {
      final backendSlots = await _backendSchedulingApi.fetchProviderSlots(
        providerId,
        date: date,
      );
      if (backendSlots != null) return backendSlots;
    } catch (e) {
      debugPrint('⚠️ [SchedulingRepo] provider slots backend-first falhou: $e');
    }
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<List<Map<String, dynamic>>> getProviderAvailableSlots(
    int providerId, {
    String? date,
    int? requiredDurationMinutes,
  }) async {
    try {
      final backendSlots = await _backendSchedulingApi
          .fetchProviderAvailability(
            providerId,
            date: date,
            requiredDurationMinutes: requiredDurationMinutes,
          );
      if (backendSlots != null) return backendSlots;
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] provider availability backend-first falhou: $e',
      );
    }
    return const [];
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>>
  getProvidersAvailableSlotsBatch({
    required List<int> providerIds,
    required List<String> dateKeys,
    int? requiredDurationMinutes,
  }) async {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final providerId in providerIds.toSet()) {
      for (final dateKey in dateKeys.toSet()) {
        final key = '${providerId}_$dateKey';
        result[key] = await getProviderAvailableSlots(
          providerId,
          date: dateKey,
          requiredDurationMinutes: requiredDurationMinutes,
        );
      }
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>?> getProviderNextAvailableSlot(
    int providerId, {
    int horizonDays = 14,
    int? requiredDurationMinutes,
  }) async {
    try {
      final backendSlot = await _backendSchedulingApi
          .fetchProviderNextAvailableSlot(
            providerId,
            horizonDays: horizonDays,
            requiredDurationMinutes: requiredDurationMinutes,
          );
      if (backendSlot != null) return backendSlot;
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] next available slot backend-first falhou: $e',
      );
    }
    return null;
  }

  @override
  Future<void> markSlotBusy(
    int providerId,
    DateTime startTime, {
    DateTime? endTime,
  }) async {
    try {
      final backendMarked = await _backendSchedulingApi.markProviderSlotBusy(
        providerId,
        startTime,
        endTime: endTime,
      );
      if (backendMarked) return;
    } catch (e) {
      debugPrint('⚠️ [SchedulingRepo] mark slot busy backend-first falhou: $e');
    }
    throw Exception('Falha ao bloquear slot no backend canônico.');
  }

  @override
  Future<void> bookSlot(
    int providerId,
    int clientId,
    DateTime startTime, {
    DateTime? endTime,
    String? serviceRequestId,
    String? agendamentoServicoId,
    String? procedureName,
  }) async {
    try {
      final backendBooked = await _backendSchedulingApi.bookProviderSlot(
        providerId,
        clientId: clientId,
        startTime: startTime,
        endTime: endTime,
        serviceRequestId: serviceRequestId,
        agendamentoServicoId: agendamentoServicoId,
        procedureName: procedureName,
      );
      if (backendBooked) return;
    } catch (e) {
      debugPrint('⚠️ [SchedulingRepo] book slot backend-first falhou: $e');
    }
    throw Exception('Falha ao reservar slot no backend canônico.');
  }

  @override
  Future<void> createManualAppointment({
    required int providerId,
    required DateTime startTime,
    required DateTime endTime,
    required String clientName,
    required String procedureName,
    String? notes,
  }) async {
    try {
      final backendCreated = await _backendSchedulingApi
          .createManualAppointment(
            providerId: providerId,
            startTime: startTime,
            endTime: endTime,
            clientName: clientName,
            procedureName: procedureName,
            notes: notes,
          );
      if (backendCreated) return;
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] create manual appointment backend-first falhou: $e',
      );
    }
    throw Exception('Falha ao criar appointment manual no backend canônico.');
  }

  @override
  Future<void> deleteAppointment(String appointmentId) async {
    try {
      final backendDeleted = await _backendSchedulingApi.deleteAppointment(
        appointmentId,
      );
      if (backendDeleted) return;
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] delete appointment backend-first falhou: $e',
      );
    }
    throw Exception('Falha ao excluir appointment no backend canônico.');
  }

  @override
  Future<void> confirmSchedule(
    String serviceId,
    DateTime time,
    int? providerId,
    int? clientId,
  ) async {
    try {
      final backendConfirmed = await _backendTrackingApi.confirmSchedule(
        serviceId,
        scheduledAt: time,
      );
      if (backendConfirmed) return;
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] confirmSchedule backend-first falhou: $e',
      );
    }
    throw Exception('Falha ao confirmar agenda no backend canônico.');
  }

  @override
  Future<FixedBookingIntent> createPendingFixedBookingIntent({
    required int clientUserId,
    required String clienteUid,
    required int providerId,
    required String? providerUid,
    required String procedureName,
    required DateTime scheduledStartUtc,
    required int durationMinutes,
    required double totalPrice,
    required double upfrontPrice,
    int? professionId,
    String? professionName,
    int? taskId,
    String? taskName,
    int? categoryId,
    String? address,
    double? latitude,
    double? longitude,
    List<String> imageKeys = const [],
    String? videoKey,
  }) async {
    final scheduledEndUtc = scheduledStartUtc.add(
      Duration(minutes: durationMinutes),
    );
    try {
      final backendIntent = await _backendSchedulingApi.createBookingIntent(
        providerId: providerId,
        procedureName: procedureName,
        scheduledStartUtc: scheduledStartUtc,
        scheduledEndUtc: scheduledEndUtc,
        totalPrice: totalPrice,
        upfrontPrice: upfrontPrice,
        professionId: professionId,
        professionName: professionName,
        taskId: taskId,
        taskName: taskName,
        categoryId: categoryId,
        address: address,
        latitude: latitude,
        longitude: longitude,
        imageKeys: imageKeys,
        videoKey: videoKey,
      );
      if (backendIntent != null) {
        return FixedBookingIntent.fromMap(backendIntent);
      }
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] createBookingIntent backend-first falhou: $e',
      );
    }
    throw Exception('Falha ao criar intent de booking no backend canônico.');
  }

  @override
  Future<FixedBookingIntent?> getPendingFixedBookingIntent(
    String intentId,
  ) async {
    try {
      final backendIntent = await _backendSchedulingApi.getBookingIntent(
        intentId,
      );
      if (backendIntent != null) {
        return FixedBookingIntent.fromMap(backendIntent);
      }
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] getBookingIntent backend-first falhou: $e',
      );
    }

    return null;
  }

  @override
  Future<FixedBookingIntent?> getLatestPendingIntentForClient(
    String clientUid,
  ) async {
    try {
      final backendIntent = await _backendSchedulingApi
          .getLatestBookingIntent();
      if (backendIntent != null) {
        return FixedBookingIntent.fromMap(backendIntent);
      }
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] getLatestBookingIntent backend-first falhou: $e',
      );
    }

    return null;
  }

  @override
  Future<Map<String, dynamic>?> confirmPendingFixedBookingIntent(
    String intentId,
  ) async {
    try {
      final backendConfirmed = await _backendSchedulingApi.confirmBookingIntent(
        intentId,
      );
      if (backendConfirmed != null) return backendConfirmed;
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] confirmBookingIntent backend-first falhou: $e',
      );
    }
    return null;
  }

  @override
  Future<void> cancelPendingFixedBookingIntent(String intentId) async {
    try {
      final backendCancelled = await _backendSchedulingApi.cancelBookingIntent(
        intentId,
      );
      if (backendCancelled) return;
    } catch (e) {
      debugPrint(
        '⚠️ [SchedulingRepo] cancelBookingIntent backend-first falhou: $e',
      );
    }
    throw Exception('Falha ao cancelar intent no backend canônico.');
  }
}
