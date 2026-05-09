import '../network/backend_api_client.dart';
import 'backend_client_home_state.dart';
import 'backend_provider_home_state.dart';

class BackendHomeApi {
  static const Duration _homeSnapshotTtl = Duration(seconds: 20);
  static const Duration _homeSnapshotTimeout = Duration(seconds: 6);
  static BackendClientHomeState? _clientHomeCache;
  static DateTime? _clientHomeCacheAt;
  static Future<BackendClientHomeState?>? _clientHomeInFlight;
  static BackendProviderHomeState? _providerHomeCache;
  static DateTime? _providerHomeCacheAt;
  static Future<BackendProviderHomeState?>? _providerHomeInFlight;

  const BackendHomeApi({BackendApiClient? client})
    : _client = client ?? const BackendApiClient();

  final BackendApiClient _client;

  Future<BackendClientHomeState?> fetchClientHome({bool force = false}) async {
    if (!force &&
        _clientHomeCache != null &&
        _clientHomeCacheAt != null &&
        DateTime.now().difference(_clientHomeCacheAt!) < _homeSnapshotTtl) {
      return _clientHomeCache;
    }

    if (!force && _clientHomeInFlight != null) {
      return _clientHomeInFlight!;
    }

    final future = _fetchClientHomeFromBackend(allowStale: !force);
    _clientHomeInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_clientHomeInFlight, future)) {
        _clientHomeInFlight = null;
      }
    }
  }

  Future<BackendProviderHomeState?> fetchProviderHome({
    bool force = false,
  }) async {
    if (!force &&
        _providerHomeCache != null &&
        _providerHomeCacheAt != null &&
        DateTime.now().difference(_providerHomeCacheAt!) < _homeSnapshotTtl) {
      return _providerHomeCache;
    }

    if (!force && _providerHomeInFlight != null) {
      return _providerHomeInFlight!;
    }

    final future = _fetchProviderHomeFromBackend(allowStale: !force);
    _providerHomeInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_providerHomeInFlight, future)) {
        _providerHomeInFlight = null;
      }
    }
  }

  Future<BackendClientHomeState?> _fetchClientHomeFromBackend({
    required bool allowStale,
  }) async {
    final decoded = await _client.getJson(
      '/api/v1/home/client',
      timeout: _homeSnapshotTimeout,
      maxRetries: 1,
    );
    if (decoded == null) {
      return allowStale ? _clientHomeCache : null;
    }
    final snapshot = BackendClientHomeState.fromJson(decoded);
    _clientHomeCache = snapshot;
    _clientHomeCacheAt = DateTime.now();
    return snapshot;
  }

  Future<BackendProviderHomeState?> _fetchProviderHomeFromBackend({
    required bool allowStale,
  }) async {
    final decoded = await _client.getJson(
      '/api/v1/home/provider',
      timeout: _homeSnapshotTimeout,
      maxRetries: 1,
    );
    if (decoded == null) {
      return allowStale ? _providerHomeCache : null;
    }
    final snapshot = BackendProviderHomeState.fromJson(decoded);
    _providerHomeCache = snapshot;
    _providerHomeCacheAt = DateTime.now();
    return snapshot;
  }

  Future<Map<String, dynamic>?> createPendingFixedBookingIntent({
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
      '/api/v1/home/pending-fixed',
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

  Future<bool> cancelPendingFixedBookingIntent(String intentId) async {
    final normalizedIntentId = intentId.trim();
    if (normalizedIntentId.isEmpty) return false;
    final encodedIntentId = Uri.encodeComponent(normalizedIntentId);
    final decoded = await _client.postJson(
      '/api/v1/home/pending-fixed/$encodedIntentId/cancel',
    );
    return decoded != null;
  }
}
