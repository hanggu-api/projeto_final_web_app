import 'package:flutter/foundation.dart';

/// Lightweight in-app bus so NotificationService can ask the currently open
/// ServiceTrackingPage to refresh immediately (useful when Realtime is flaky).
class ServiceTrackingBus {
  static final ServiceTrackingBus _instance = ServiceTrackingBus._internal();
  factory ServiceTrackingBus() => _instance;
  ServiceTrackingBus._internal();

  String? _activeServiceId;
  VoidCallback? _refresh;

  void setActive(String serviceId, VoidCallback refresh) {
    _activeServiceId = serviceId;
    _refresh = refresh;
  }

  void clearActive(String serviceId) {
    if (_activeServiceId == serviceId) {
      _activeServiceId = null;
      _refresh = null;
    }
  }

  void refreshIfActive(String? serviceId) {
    if (serviceId == null) return;
    if (_activeServiceId != serviceId) return;
    _refresh?.call();
  }
}

