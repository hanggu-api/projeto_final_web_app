import '../../services/api_service.dart';
import '../../services/theme_service.dart';

typedef ProviderRouteForService = String Function(Map<String, dynamic> service);
typedef ClientActiveRouteResolver =
    String Function(Map<String, dynamic> service, String serviceId);

class AppNavigationPolicy {
  final ApiService api;
  final String? roleOverride;
  final bool? isMedicalOverride;
  final bool? isLoggedInOverride;
  final bool Function(Map<String, dynamic> service) isFixedService;
  final bool Function(Map<String, dynamic> service)? isFixedScheduledFlowReady;
  final ProviderRouteForService providerRouteForService;
  final ClientActiveRouteResolver resolveClientActiveServiceRoute;

  const AppNavigationPolicy({
    required this.api,
    required this.isFixedService,
    required this.providerRouteForService,
    required this.resolveClientActiveServiceRoute,
    this.isFixedScheduledFlowReady,
    this.roleOverride,
    this.isMedicalOverride,
    this.isLoggedInOverride,
  });

  String? get role => roleOverride ?? api.role;
  bool get isMedical => isMedicalOverride ?? api.isMedical;
  bool get isLoggedIn => isLoggedInOverride ?? api.isLoggedIn;

  String resolveDriverHomeRoute() {
    ThemeService().setProviderMode(false);
    return '/home';
  }

  String resolveProviderBaseRoute() {
    ThemeService().setProviderMode(true);
    return isMedical ? '/medical-home' : '/provider-home';
  }

  String resolveDefaultLoggedInRoute() {
    if (role == 'driver') {
      return resolveDriverHomeRoute();
    }
    if (role == 'provider') {
      return resolveProviderBaseRoute();
    }
    ThemeService().setProviderMode(false);
    return '/home';
  }

  String resolveProviderActiveRoute(Map<String, dynamic> service) {
    if (isFixedService(service)) {
      return resolveProviderBaseRoute();
    }
    return providerRouteForService(service);
  }

  String resolveClientActiveRoute(Map<String, dynamic> service) {
    final serviceId = service['id']?.toString() ?? '';
    if (serviceId.isEmpty) return '/home';
    return resolveClientActiveServiceRoute(service, serviceId);
  }

  String resolveBootstrapRoute({
    required bool hasCurrentUser,
    required String? role,
    required int? registerStep,
    required Map<String, dynamic>? activeService,
  }) {
    if (!hasCurrentUser || role == null) {
      if ((registerStep ?? 0) > 0) {
        return '/register';
      }
      return '/login';
    }

    if (role == 'provider') {
      if (activeService != null) {
        return resolveProviderActiveRoute(activeService);
      }
      return resolveProviderBaseRoute();
    }

    if (role == 'driver') {
      return resolveDriverHomeRoute();
    }

    ThemeService().setProviderMode(false);
    if (activeService != null) {
      final serviceId = activeService['id']?.toString() ?? '';
      if (serviceId.isNotEmpty) {
        final isFixed = isFixedService(activeService);
        final fixedReady =
            isFixedScheduledFlowReady?.call(activeService) ?? false;
        if (fixedReady) {
          return '/scheduled-service/$serviceId';
        }
        if (!isFixed) {
          return resolveClientActiveServiceRoute(activeService, serviceId);
        }
      }
    }
    return '/home';
  }
}
