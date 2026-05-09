import '../network/backend_api_client.dart';

class BackendSchedulingApi {
  const BackendSchedulingApi({BackendApiClient? client})
    : _client = client ?? const BackendApiClient();

  final BackendApiClient _client;

  Future<Map<String, dynamic>?> createBookingIntent({
    required int providerId,
    required String procedureName,
    required DateTime scheduledStartUtc,
    DateTime? scheduledEndUtc,
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
    final decoded = await _client.postJson(
      '/api/v1/bookings/intents',
      body: {
        'providerId': providerId,
        'procedureName': procedureName,
        'scheduledStartUtc': scheduledStartUtc.toUtc().toIso8601String(),
        if (scheduledEndUtc != null)
          'scheduledEndUtc': scheduledEndUtc.toUtc().toIso8601String(),
        'totalPrice': totalPrice,
        'upfrontPrice': upfrontPrice,
        if (professionId != null) 'professionId': professionId,
        if (professionName != null && professionName.trim().isNotEmpty)
          'professionName': professionName.trim(),
        if (taskId != null) 'taskId': taskId,
        if (taskName != null && taskName.trim().isNotEmpty)
          'taskName': taskName.trim(),
        if (categoryId != null) 'categoryId': categoryId,
        if (address != null && address.trim().isNotEmpty)
          'address': address.trim(),
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'imageKeys': imageKeys,
        if (videoKey != null && videoKey.trim().isNotEmpty)
          'videoKey': videoKey.trim(),
      },
    );
    final data = decoded?['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return decoded;
  }

  Future<bool> cancelBookingIntent(String intentId) async {
    final normalizedIntentId = intentId.trim();
    if (normalizedIntentId.isEmpty) return false;
    final encodedIntentId = Uri.encodeComponent(normalizedIntentId);
    final decoded = await _client.postJson(
      '/api/v1/bookings/intents/$encodedIntentId/cancel',
    );
    return decoded != null;
  }

  Future<Map<String, dynamic>?> confirmBookingIntent(String intentId) async {
    final normalizedIntentId = intentId.trim();
    if (normalizedIntentId.isEmpty) return null;
    final decoded = await _client.postJson(
      '/api/v1/bookings/confirm',
      body: {'intentId': normalizedIntentId},
    );
    final data = decoded?['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return decoded;
  }

  Future<Map<String, dynamic>?> getBookingIntent(String intentId) async {
    final normalizedIntentId = intentId.trim();
    if (normalizedIntentId.isEmpty) return null;
    final encodedIntentId = Uri.encodeComponent(normalizedIntentId);
    final decoded = await _client.getJson(
      '/api/v1/bookings/intents/$encodedIntentId',
    );
    final data = decoded?['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  Future<Map<String, dynamic>?> getLatestBookingIntent() async {
    final decoded = await _client.getJson('/api/v1/bookings/intents/latest');
    final data = decoded?['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  Future<Map<String, dynamic>?> fetchProviderSchedule(int providerId) async {
    if (providerId <= 0) return null;
    final decoded = await _client.getJson(
      '/api/v1/providers/$providerId/schedule',
    );
    final data = decoded?['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  Future<Map<String, dynamic>?> saveProviderSchedule(
    int providerId,
    List<Map<String, dynamic>> configs,
  ) async {
    if (providerId <= 0) return null;
    final decoded = await _client.putJson(
      '/api/v1/providers/$providerId/schedule',
      body: {'configs': configs},
    );
    final data = decoded?['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return decoded;
  }

  Future<List<Map<String, dynamic>>?> fetchProviderScheduleExceptions(
    int providerId,
  ) async {
    if (providerId <= 0) return null;
    final decoded = await _client.getJson(
      '/api/v1/providers/$providerId/schedule/exceptions',
    );
    final data = decoded?['data'];
    final exceptions = data is Map
        ? data['exceptions']
        : decoded?['exceptions'];
    if (exceptions is! List) return null;
    return exceptions
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>?> saveProviderScheduleExceptions(
    int providerId,
    List<Map<String, dynamic>> exceptions,
  ) async {
    if (providerId <= 0) return null;
    final decoded = await _client.putJson(
      '/api/v1/providers/$providerId/schedule/exceptions',
      body: {'exceptions': exceptions},
    );
    final data = decoded?['data'];
    final saved = data is Map ? data['exceptions'] : decoded?['exceptions'];
    if (saved is! List) return null;
    return saved
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>?> fetchProviderSlots(
    int providerId, {
    String? date,
  }) async {
    if (providerId <= 0) return null;
    final query = date != null && date.trim().isNotEmpty
        ? '?date=${Uri.encodeQueryComponent(date.trim())}'
        : '';
    final decoded = await _client.getJson(
      '/api/v1/providers/$providerId/slots$query',
    );
    final data = decoded?['data'];
    final slots = data is Map ? data['slots'] : decoded?['slots'];
    if (slots is! List) return null;
    return slots
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();
  }

  Future<bool> markProviderSlotBusy(
    int providerId,
    DateTime startTime, {
    DateTime? endTime,
  }) async {
    if (providerId <= 0) return false;
    final decoded = await _client.postJson(
      '/api/v1/providers/$providerId/slots/busy',
      body: {
        'startTime': startTime.toUtc().toIso8601String(),
        if (endTime != null) 'endTime': endTime.toUtc().toIso8601String(),
      },
    );
    return decoded != null;
  }

  Future<bool> bookProviderSlot(
    int providerId, {
    required int clientId,
    required DateTime startTime,
    DateTime? endTime,
    String? serviceRequestId,
    String? agendamentoServicoId,
    String? procedureName,
  }) async {
    if (providerId <= 0 || clientId <= 0) return false;
    final decoded = await _client.postJson(
      '/api/v1/providers/$providerId/slots/book',
      body: {
        'clientId': clientId,
        'startTime': startTime.toUtc().toIso8601String(),
        if (endTime != null) 'endTime': endTime.toUtc().toIso8601String(),
        if (serviceRequestId != null && serviceRequestId.trim().isNotEmpty)
          'serviceRequestId': serviceRequestId.trim(),
        if (agendamentoServicoId != null &&
            agendamentoServicoId.trim().isNotEmpty)
          'agendamentoServicoId': agendamentoServicoId.trim(),
        if (procedureName != null && procedureName.trim().isNotEmpty)
          'procedureName': procedureName.trim(),
      },
    );
    return decoded != null;
  }

  Future<bool> createManualAppointment({
    required int providerId,
    required DateTime startTime,
    required DateTime endTime,
    required String clientName,
    required String procedureName,
    String? notes,
  }) async {
    if (providerId <= 0) return false;
    final decoded = await _client.postJson(
      '/api/v1/providers/$providerId/appointments/manual',
      body: {
        'startTime': startTime.toUtc().toIso8601String(),
        'endTime': endTime.toUtc().toIso8601String(),
        'clientName': clientName,
        'procedureName': procedureName,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    return decoded != null;
  }

  Future<bool> deleteAppointment(String appointmentId) async {
    final normalizedId = appointmentId.trim();
    if (normalizedId.isEmpty) return false;
    final decoded = await _client.deleteJson(
      '/api/v1/providers/appointments/${Uri.encodeComponent(normalizedId)}',
    );
    return decoded != null;
  }

  Future<List<Map<String, dynamic>>?> fetchProviderAvailability(
    int providerId, {
    String? date,
    int? requiredDurationMinutes,
  }) async {
    if (providerId <= 0) return null;
    final params = <String, String>{
      if (date != null && date.trim().isNotEmpty) 'date': date.trim(),
      if (requiredDurationMinutes != null)
        'requiredDurationMinutes': '$requiredDurationMinutes',
    };
    final query = params.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    final decoded = await _client.getJson(
      '/api/v1/providers/$providerId/availability${query.isEmpty ? '' : '?$query'}',
    );
    final data = decoded?['data'];
    final slots = data is Map ? data['slots'] : decoded?['slots'];
    if (slots is! List) return null;
    return slots
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>?> fetchProviderNextAvailableSlot(
    int providerId, {
    int horizonDays = 14,
    int? requiredDurationMinutes,
  }) async {
    if (providerId <= 0) return null;
    final params = <String, String>{
      'horizonDays': '$horizonDays',
      if (requiredDurationMinutes != null)
        'requiredDurationMinutes': '$requiredDurationMinutes',
    };
    final query = params.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    final decoded = await _client.getJson(
      '/api/v1/providers/$providerId/next-available-slot?$query',
    );
    final data = decoded?['data'];
    final slot = data is Map ? data['slot'] : decoded?['slot'];
    if (slot is Map) return slot.cast<String, dynamic>();
    return null;
  }
}
