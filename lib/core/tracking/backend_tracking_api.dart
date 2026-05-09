import '../network/backend_api_client.dart';
import 'backend_active_service_state.dart';
import 'backend_tracking_snapshot_state.dart';

class BackendTrackingApi {
  const BackendTrackingApi({BackendApiClient? client})
    : _client = client ?? const BackendApiClient();

  final BackendApiClient _client;

  Future<BackendActiveServiceState?> fetchActiveService() async {
    final decoded = await _client.getJson('/api/v1/tracking/active-service');
    if (decoded == null) return null;
    return BackendActiveServiceState.fromJson(decoded);
  }

  Future<Map<String, dynamic>?> fetchServiceDetails(
    String serviceId, {
    required String scope,
  }) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return null;
    final encodedServiceId = Uri.encodeComponent(normalizedServiceId);
    final encodedScope = Uri.encodeQueryComponent(
      scope.trim().isEmpty ? 'auto' : scope,
    );
    final decoded = await _client.getJson(
      '/api/v1/tracking/services/$encodedServiceId?scope=$encodedScope',
    );
    if (decoded == null) return null;
    final data = (decoded['data'] as Map?)?.cast<String, dynamic>() ?? decoded;
    final service = data['service'];
    if (service is Map<String, dynamic>) return service;
    if (service is Map) return service.cast<String, dynamic>();
    return null;
  }

  Future<BackendTrackingSnapshotState?> fetchTrackingSnapshot(
    String serviceId, {
    required String scope,
  }) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return null;
    final encodedServiceId = Uri.encodeComponent(normalizedServiceId);
    final encodedScope = Uri.encodeQueryComponent(
      scope.trim().isEmpty ? 'auto' : scope,
    );
    final decoded = await _client.getJson(
      '/api/v1/tracking/services/$encodedServiceId/snapshot?scope=$encodedScope',
    );
    if (decoded == null) return null;
    return BackendTrackingSnapshotState.fromJson(decoded);
  }

  Future<bool> confirmFinalService(
    String serviceId, {
    int? rating,
    String? comment,
  }) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return false;
    final encodedServiceId = Uri.encodeComponent(normalizedServiceId);
    final decoded = await _client.postJson(
      '/api/v1/tracking/services/$encodedServiceId/confirm-final',
      body: {
        if (rating != null) 'rating': rating,
        if (comment != null) 'comment': comment,
      },
    );
    return decoded != null;
  }

  Future<bool> cancelService(String serviceId, {required String scope}) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return false;
    final encodedServiceId = Uri.encodeComponent(normalizedServiceId);
    final decoded = await _client.postJson(
      '/api/v1/tracking/services/$encodedServiceId/cancel',
      body: {'scope': scope},
    );
    if (decoded == null) return false;
    final directSuccess = decoded['success'];
    if (directSuccess is bool) return directSuccess;
    final data = decoded['data'];
    if (data is Map && data['success'] is bool) {
      return data['success'] as bool;
    }
    // Backward compatibility for endpoints that return 200 with no explicit success flag.
    return true;
  }

  Future<bool> submitComplaint(
    String serviceId, {
    required String claimType,
    required String reason,
    List<Map<String, String>> attachments = const [],
  }) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return false;
    final encodedServiceId = Uri.encodeComponent(normalizedServiceId);
    final decoded = await _client.postJson(
      '/api/v1/tracking/services/$encodedServiceId/complaints',
      body: {
        'claimType': claimType,
        'reason': reason,
        'attachments': attachments,
      },
    );
    return decoded != null;
  }

  Future<bool> confirmSchedule(
    String serviceId, {
    required DateTime scheduledAt,
  }) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return false;
    final encodedServiceId = Uri.encodeComponent(normalizedServiceId);
    final decoded = await _client.postJson(
      '/api/v1/tracking/services/$encodedServiceId/confirm-schedule',
      body: {'scheduledAt': scheduledAt.toUtc().toIso8601String()},
    );
    return decoded != null;
  }

  Future<bool> proposeSchedule(
    String serviceId, {
    required DateTime scheduledAt,
  }) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return false;
    final encodedServiceId = Uri.encodeComponent(normalizedServiceId);
    final decoded = await _client.postJson(
      '/api/v1/tracking/services/$encodedServiceId/propose-schedule',
      body: {'scheduledAt': scheduledAt.toUtc().toIso8601String()},
    );
    return decoded != null;
  }

  Future<bool> updateServiceStatus(
    String serviceId, {
    required String status,
    required String scope,
  }) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return false;
    final encodedServiceId = Uri.encodeComponent(normalizedServiceId);
    final decoded = await _client.postJson(
      '/api/v1/tracking/services/$encodedServiceId/status',
      body: {'status': status, 'scope': scope},
    );
    return decoded != null;
  }
}
