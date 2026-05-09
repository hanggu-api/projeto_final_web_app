import 'models/service_status_view.dart';

typedef RawActiveServiceSnapshotGetter = Map<String, dynamic>? Function();
typedef ActiveServiceSnapshotLoader =
    Future<Map<String, dynamic>?> Function({
      bool forceRefresh,
      Duration ttl,
    });
typedef ServiceScopeTagResolver = String? Function(Map<String, dynamic>? service);

class TrackingApi {
  final RawActiveServiceSnapshotGetter _activeSnapshotGetter;
  final ActiveServiceSnapshotLoader _loadActiveSnapshot;
  final ServiceScopeTagResolver _resolveScopeTag;

  const TrackingApi({
    required RawActiveServiceSnapshotGetter activeSnapshotGetter,
    required ActiveServiceSnapshotLoader loadActiveSnapshot,
    required ServiceScopeTagResolver resolveScopeTag,
  }) : _activeSnapshotGetter = activeSnapshotGetter,
       _loadActiveSnapshot = loadActiveSnapshot,
       _resolveScopeTag = resolveScopeTag;

  Map<String, dynamic>? get activeServiceSnapshot {
    final snapshot = _activeSnapshotGetter();
    return snapshot == null ? null : Map<String, dynamic>.from(snapshot);
  }

  ServiceStatusView? get activeServiceStatusView {
    final snapshot = activeServiceSnapshot;
    if (snapshot == null) return null;
    return ServiceStatusView.fromMap(
      snapshot,
      serviceScope: _resolveScopeTag(snapshot),
    );
  }

  Future<Map<String, dynamic>?> getActiveServiceSnapshot({
    bool forceRefresh = false,
    Duration ttl = const Duration(seconds: 15),
  }) {
    return _loadActiveSnapshot(forceRefresh: forceRefresh, ttl: ttl);
  }

  Future<ServiceStatusView?> getActiveServiceStatusView({
    bool forceRefresh = false,
    Duration ttl = const Duration(seconds: 15),
  }) async {
    final snapshot = await getActiveServiceSnapshot(
      forceRefresh: forceRefresh,
      ttl: ttl,
    );
    if (snapshot == null) return null;
    return ServiceStatusView.fromMap(
      snapshot,
      serviceScope: _resolveScopeTag(snapshot),
    );
  }
}
