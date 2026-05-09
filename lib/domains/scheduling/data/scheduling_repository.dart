import '../models/fixed_booking_intent.dart';
import '../models/schedule_config.dart';
import '../models/schedule_config_result.dart';

abstract class SchedulingRepository {
  // --- Configuração de agenda ---

  Future<ScheduleConfigResult> getScheduleConfigResult(int providerId);

  Future<List<ScheduleConfig>> getScheduleConfig(int providerId);

  Future<void> saveScheduleConfig(
    int providerId,
    String? providerUid,
    List<ScheduleConfig> configs,
  );

  Future<List<Map<String, dynamic>>> getScheduleExceptions(int providerId);

  Future<void> saveScheduleExceptions(
    int providerId,
    List<Map<String, dynamic>> exceptions,
  );

  // --- Slots e disponibilidade ---

  /// Retorna os slots do dia para o painel do prestador (inclui holds).
  Future<List<Map<String, dynamic>>> getProviderSlots(
    int providerId, {
    String? date,
  });

  /// Retorna slots disponíveis para seleção pelo cliente.
  Future<List<Map<String, dynamic>>> getProviderAvailableSlots(
    int providerId, {
    String? date,
    int? requiredDurationMinutes,
  });

  /// Retorna disponibilidade em lote para múltiplos prestadores e datas.
  Future<Map<String, List<Map<String, dynamic>>>>
  getProvidersAvailableSlotsBatch({
    required List<int> providerIds,
    required List<String> dateKeys,
    int? requiredDurationMinutes,
  });

  /// Retorna o próximo slot disponível dentro de um horizonte de dias.
  Future<Map<String, dynamic>?> getProviderNextAvailableSlot(
    int providerId, {
    int horizonDays = 14,
    int? requiredDurationMinutes,
  });

  // --- Agendamentos ---

  Future<void> markSlotBusy(
    int providerId,
    DateTime startTime, {
    DateTime? endTime,
  });

  Future<void> bookSlot(
    int providerId,
    int clientId,
    DateTime startTime, {
    DateTime? endTime,
    String? serviceRequestId,
    String? agendamentoServicoId,
    String? procedureName,
  });

  Future<void> createManualAppointment({
    required int providerId,
    required DateTime startTime,
    required DateTime endTime,
    required String clientName,
    required String procedureName,
    String? notes,
  });

  Future<void> deleteAppointment(String appointmentId);

  Future<void> confirmSchedule(
    String serviceId,
    DateTime time,
    int? providerId,
    int? clientId,
  );

  // --- Fixed Booking Intent (PIX) ---

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
    List<String> imageKeys,
    String? videoKey,
  });

  Future<FixedBookingIntent?> getPendingFixedBookingIntent(String intentId);

  Future<FixedBookingIntent?> getLatestPendingIntentForClient(String clientUid);

  Future<Map<String, dynamic>?> confirmPendingFixedBookingIntent(
    String intentId,
  );

  Future<void> cancelPendingFixedBookingIntent(String intentId);
}
