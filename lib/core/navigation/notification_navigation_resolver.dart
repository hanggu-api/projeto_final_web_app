import '../utils/fixed_schedule_gate.dart';
import '../utils/mobile_client_navigation_gate.dart';

class NotificationNavigationTarget {
  final String route;
  final bool replace;

  const NotificationNavigationTarget({
    required this.route,
    required this.replace,
  });
}

class NotificationNavigationResolver {
  static NotificationNavigationTarget homeForRole(String? role) {
    return NotificationNavigationTarget(
      route: role == 'provider' || role == 'driver'
          ? '/provider-home'
          : '/home',
      replace: true,
    );
  }

  static NotificationNavigationTarget scheduleConfirmed({
    required String? role,
    required String serviceId,
  }) {
    return NotificationNavigationTarget(
      route: role == 'provider' || role == 'driver'
          ? '/provider-active/$serviceId'
          : '/service-tracking/$serviceId',
      replace: role == 'provider' || role == 'driver',
    );
  }

  static NotificationNavigationTarget providerAcceptedService({
    required String serviceId,
  }) {
    return NotificationNavigationTarget(
      route: '/provider-active/$serviceId',
      replace: true,
    );
  }

  static NotificationNavigationTarget serviceLifecycleFallback({
    required String? role,
    required String serviceId,
  }) {
    return NotificationNavigationTarget(
      route: role == 'provider'
          ? '/provider-active/$serviceId'
          : '/service-tracking/$serviceId',
      replace: false,
    );
  }

  static NotificationNavigationTarget serviceLifecycleFromDetails({
    required String? role,
    required String serviceId,
    required Map<String, dynamic> details,
  }) {
    if (role == 'provider') {
      final isFixed = isCanonicalFixedServiceRecord(details);
      return NotificationNavigationTarget(
        route: isFixed ? '/provider-home' : '/provider-active/$serviceId',
        replace: true,
      );
    }

    return NotificationNavigationTarget(
      route: resolveClientActiveServiceRoute(details, serviceId),
      replace: false,
    );
  }
}
