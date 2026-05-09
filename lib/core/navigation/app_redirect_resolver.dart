import 'app_navigation_policy.dart';

typedef ActiveServiceFinder = Future<Map<String, dynamic>?> Function();
typedef ProviderActiveRouteResolver = Future<String?> Function();

class AppRedirectSnapshot {
  final String matchedLocation;

  const AppRedirectSnapshot({required this.matchedLocation});

  bool get isLogin => matchedLocation == '/login';
  bool get isRegister => matchedLocation == '/register';
  bool get isFaceValidationTest => matchedLocation == '/face-validation-test';
  bool get isRoot => matchedLocation == '/';
  bool get isProviderHome => matchedLocation == '/provider-home';
  bool get isHomeOrRoot => matchedLocation == '/home' || matchedLocation == '/';
  bool get isProviderRoute =>
      matchedLocation.startsWith('/provider') ||
      matchedLocation.startsWith('/medical');
  bool get isScheduledServiceRoute =>
      matchedLocation.startsWith('/scheduled-service/');
  bool get isServiceTrackingRoute =>
      matchedLocation.startsWith('/service-tracking/');
}

class AppRedirectResolver {
  final AppNavigationPolicy policy;
  final AppRedirectSnapshot snapshot;
  final ActiveServiceFinder findActiveService;
  final ProviderActiveRouteResolver resolveProviderActiveRoute;

  const AppRedirectResolver({
    required this.policy,
    required this.snapshot,
    required this.findActiveService,
    required this.resolveProviderActiveRoute,
  });

  Future<String> resolveProviderHomeRoute() async {
    if (policy.isMedical) return policy.resolveProviderBaseRoute();
    final activeRoute = await resolveProviderActiveRoute();
    return activeRoute ?? policy.resolveProviderBaseRoute();
  }

  Future<String?> resolve() async {
    final logged = policy.isLoggedIn;

    if (!logged &&
        !snapshot.isLogin &&
        !snapshot.isRegister &&
        !snapshot.isFaceValidationTest) {
      return '/login';
    }

    if (logged && snapshot.isLogin) {
      if (policy.role == 'provider') {
        return resolveProviderHomeRoute();
      }
      return policy.resolveDefaultLoggedInRoute();
    }

    if (logged && policy.role == 'provider' && snapshot.isProviderHome) {
      final activeRoute = await resolveProviderActiveRoute();
      if (activeRoute != null) return activeRoute;
    }

    if (logged && policy.role == 'driver' && snapshot.isProviderRoute) {
      return policy.resolveDriverHomeRoute();
    }

    final activeService = await findActiveService();
    if (activeService != null) {
      final isFixed = policy.isFixedService(activeService);

      if (policy.role == 'provider') {
        final providerAllowedWhileFixedActive = <String>{
          '/provider-home',
          '/my-provider-profile',
          '/provider-schedule',
          '/chats',
          '/notifications',
        };
        final target = policy.resolveProviderActiveRoute(activeService);
        if (isFixed &&
            providerAllowedWhileFixedActive.contains(
              snapshot.matchedLocation,
            )) {
          return null;
        }
        if (snapshot.matchedLocation != target) return target;
      } else {
        final target = policy.resolveClientActiveRoute(activeService);
        if (target == '/home') {
          if (snapshot.isServiceTrackingRoute) {
            return '/home';
          }
          if (isFixed && snapshot.isScheduledServiceRoute) {
            return '/home';
          }
        } else if (snapshot.matchedLocation != target) {
          return target;
        } else if (isFixed && snapshot.isScheduledServiceRoute) {
          return '/home';
        }
      }
    }

    if (logged && policy.role == 'provider' && snapshot.isHomeOrRoot) {
      return resolveProviderHomeRoute();
    }

    if (snapshot.isRoot) {
      if (!logged) return '/login';
      if (policy.role == 'provider') {
        return resolveProviderHomeRoute();
      }
      return policy.resolveDefaultLoggedInRoute();
    }

    return null;
  }
}
