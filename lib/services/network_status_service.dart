import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/logger.dart';

enum NetworkStatusKind { online, offline, backendUnreachable }

class NetworkStatusSnapshot {
  const NetworkStatusSnapshot({
    required this.kind,
    required this.hasLocalConnectivity,
    this.lastReason,
    this.changedAt,
  });

  final NetworkStatusKind kind;
  final bool hasLocalConnectivity;
  final String? lastReason;
  final DateTime? changedAt;

  bool get isOffline => kind == NetworkStatusKind.offline;
  bool get isOnline => kind == NetworkStatusKind.online;
  bool get isBackendUnreachable =>
      kind == NetworkStatusKind.backendUnreachable;
}

class NetworkStatusService {
  NetworkStatusService._internal();

  static final NetworkStatusService _instance = NetworkStatusService._internal();
  factory NetworkStatusService() => _instance;

  final Connectivity _connectivity = Connectivity();
  final StreamController<NetworkStatusSnapshot> _controller =
      StreamController<NetworkStatusSnapshot>.broadcast();

  StreamSubscription? _connectivitySub;
  bool _initialized = false;
  int _backendFailureCount = 0;
  DateTime? _lastOfflineLogAt;
  DateTime? _lastRecoveryLogAt;
  NetworkStatusSnapshot _current = const NetworkStatusSnapshot(
    kind: NetworkStatusKind.online,
    hasLocalConnectivity: true,
  );

  Stream<NetworkStatusSnapshot> get stream => _controller.stream;
  NetworkStatusSnapshot get current => _current;
  bool get isOffline => _current.isOffline;
  bool get isOnline => _current.isOnline;
  bool get isBackendUnreachable => _current.isBackendUnreachable;
  bool get canAttemptSupabase => !_current.isOffline;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    await refreshConnectivity();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((result) {
      final hasConnectivity = _hasConnectivity(result);
      if (!hasConnectivity) {
        _backendFailureCount = 0;
        _setState(
          NetworkStatusSnapshot(
            kind: NetworkStatusKind.offline,
            hasLocalConnectivity: false,
            lastReason: 'offline_dns_or_network',
            changedAt: DateTime.now(),
          ),
        );
        return;
      }

      if (_current.isOffline) {
        _backendFailureCount = 0;
        _setState(
          NetworkStatusSnapshot(
            kind: NetworkStatusKind.online,
            hasLocalConnectivity: true,
            lastReason: 'connectivity_restored',
            changedAt: DateTime.now(),
          ),
        );
      }
    });
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    _initialized = false;
  }

  Future<void> refreshConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final hasConnectivity = _hasConnectivity(result);
      if (!hasConnectivity) {
        _backendFailureCount = 0;
        _setState(
          NetworkStatusSnapshot(
            kind: NetworkStatusKind.offline,
            hasLocalConnectivity: false,
            lastReason: 'offline_dns_or_network',
            changedAt: DateTime.now(),
          ),
        );
      } else if (_current.isOffline) {
        _setState(
          NetworkStatusSnapshot(
            kind: NetworkStatusKind.online,
            hasLocalConnectivity: true,
            lastReason: 'connectivity_restored',
            changedAt: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint(
        '⚠️ [NetworkStatusService] Falha ao verificar conectividade: $e',
      );
    }
  }

  bool shouldPauseSupabaseAttempts([Object? error]) {
    if (_current.isOffline) return true;
    if (error == null) return false;
    final text = error.toString().toLowerCase();
    return text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('software caused connection abort') ||
        text.contains('connection abort');
  }

  Future<void> markBackendFailure(Object error) async {
    await ensureInitialized();
    final reason = _classifyReason(error);
    final hasConnectivity = await _resolveHasConnectivity();

    if (!hasConnectivity || reason == 'offline_dns_or_network') {
      _backendFailureCount = 0;
      _setState(
        NetworkStatusSnapshot(
          kind: NetworkStatusKind.offline,
          hasLocalConnectivity: false,
          lastReason: reason,
          changedAt: DateTime.now(),
        ),
      );
      return;
    }

    _backendFailureCount = (_backendFailureCount + 1).clamp(1, 20);
    if (_backendFailureCount >= 2) {
      _setState(
        NetworkStatusSnapshot(
          kind: NetworkStatusKind.backendUnreachable,
          hasLocalConnectivity: true,
          lastReason: 'backend_unreachable',
          changedAt: DateTime.now(),
        ),
      );
    }
  }

  void markBackendRecovered() {
    _backendFailureCount = 0;
    _setState(
      NetworkStatusSnapshot(
        kind: NetworkStatusKind.online,
        hasLocalConnectivity: true,
        lastReason: 'backend_recovered',
        changedAt: DateTime.now(),
      ),
    );
  }

  String _classifyReason(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('software caused connection abort') ||
        text.contains('connection abort')) {
      return 'offline_dns_or_network';
    }
    return 'backend_unreachable';
  }

  Future<bool> _resolveHasConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return _hasConnectivity(result);
    } catch (_) {
      return _current.hasLocalConnectivity;
    }
  }

  bool _hasConnectivity(dynamic result) {
    if (result is List<ConnectivityResult>) {
      return result.any((item) => item != ConnectivityResult.none);
    }
    if (result is ConnectivityResult) {
      return result != ConnectivityResult.none;
    }
    return true;
  }

  void _setState(NetworkStatusSnapshot next) {
    if (_current.kind == next.kind &&
        _current.hasLocalConnectivity == next.hasLocalConnectivity &&
        _current.lastReason == next.lastReason) {
      return;
    }

    final previous = _current;
    _current = next;
    _controller.add(_current);

    if (_current.isOffline) {
      final now = DateTime.now();
      if (_lastOfflineLogAt == null ||
          now.difference(_lastOfflineLogAt!) >= const Duration(seconds: 30)) {
        _lastOfflineLogAt = now;
        AppLogger.info(
          '🌐 [NetworkStatus] offline reason=${_current.lastReason ?? "offline_dns_or_network"}',
        );
      }
      return;
    }

    if ((previous.isOffline || previous.isBackendUnreachable) &&
        _current.isOnline) {
      final now = DateTime.now();
      if (_lastRecoveryLogAt == null ||
          now.difference(_lastRecoveryLogAt!) >= const Duration(seconds: 15)) {
        _lastRecoveryLogAt = now;
        AppLogger.sistema(
          '🌐 [NetworkStatus] online restored reason=${_current.lastReason ?? "backend_recovered"}',
        );
      }
      return;
    }

    if (_current.isBackendUnreachable) {
      AppLogger.alerta(
        '🌐 [NetworkStatus] backend_unreachable com conectividade local ativa',
      );
    }
  }
}
