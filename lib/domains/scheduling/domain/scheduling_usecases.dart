import '../data/scheduling_repository.dart';
import '../models/fixed_booking_intent.dart';
import '../models/schedule_config.dart';
import '../models/schedule_config_result.dart';

class GetScheduleConfigUseCase {
  final SchedulingRepository _repository;
  const GetScheduleConfigUseCase(this._repository);

  Future<ScheduleConfigResult> call(int providerId) =>
      _repository.getScheduleConfigResult(providerId);
}

class SaveScheduleConfigUseCase {
  final SchedulingRepository _repository;
  const SaveScheduleConfigUseCase(this._repository);

  Future<void> call(
    int providerId,
    String? providerUid,
    List<ScheduleConfig> configs,
  ) => _repository.saveScheduleConfig(providerId, providerUid, configs);
}

class GetProviderAvailableSlotsUseCase {
  final SchedulingRepository _repository;
  const GetProviderAvailableSlotsUseCase(this._repository);

  Future<List<Map<String, dynamic>>> call(
    int providerId, {
    String? date,
    int? requiredDurationMinutes,
  }) => _repository.getProviderAvailableSlots(
    providerId,
    date: date,
    requiredDurationMinutes: requiredDurationMinutes,
  );
}

class GetProviderNextAvailableSlotUseCase {
  final SchedulingRepository _repository;
  const GetProviderNextAvailableSlotUseCase(this._repository);

  Future<Map<String, dynamic>?> call(
    int providerId, {
    int horizonDays = 14,
    int? requiredDurationMinutes,
  }) => _repository.getProviderNextAvailableSlot(
    providerId,
    horizonDays: horizonDays,
    requiredDurationMinutes: requiredDurationMinutes,
  );
}

class CreateFixedBookingIntentUseCase {
  final SchedulingRepository _repository;
  const CreateFixedBookingIntentUseCase(this._repository);

  Future<FixedBookingIntent> call({
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
  }) => _repository.createPendingFixedBookingIntent(
    clientUserId: clientUserId,
    clienteUid: clienteUid,
    providerId: providerId,
    providerUid: providerUid,
    procedureName: procedureName,
    scheduledStartUtc: scheduledStartUtc,
    durationMinutes: durationMinutes,
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
}

class CancelFixedBookingIntentUseCase {
  final SchedulingRepository _repository;
  const CancelFixedBookingIntentUseCase(this._repository);

  Future<void> call(String intentId) =>
      _repository.cancelPendingFixedBookingIntent(intentId);
}

class ConfirmFixedBookingIntentUseCase {
  final SchedulingRepository _repository;
  const ConfirmFixedBookingIntentUseCase(this._repository);

  Future<Map<String, dynamic>?> call(String intentId) =>
      _repository.confirmPendingFixedBookingIntent(intentId);
}

class ConfirmScheduleUseCase {
  final SchedulingRepository _repository;
  const ConfirmScheduleUseCase(this._repository);

  Future<void> call(
    String serviceId,
    DateTime time,
    int? providerId,
    int? clientId,
  ) => _repository.confirmSchedule(serviceId, time, providerId, clientId);
}
