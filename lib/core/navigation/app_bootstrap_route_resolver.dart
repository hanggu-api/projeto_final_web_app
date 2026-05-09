import 'app_navigation_policy.dart';

class AppBootstrapRouteSnapshot {
  final bool hasCurrentUser;
  final String? role;
  final int? registerStep;
  final Map<String, dynamic>? activeService;

  const AppBootstrapRouteSnapshot({
    required this.hasCurrentUser,
    required this.role,
    required this.registerStep,
    required this.activeService,
  });
}

class AppBootstrapRouteResolver {
  final AppNavigationPolicy policy;
  final AppBootstrapRouteSnapshot snapshot;

  const AppBootstrapRouteResolver({
    required this.policy,
    required this.snapshot,
  });

  String resolve() {
    return policy.resolveBootstrapRoute(
      hasCurrentUser: snapshot.hasCurrentUser,
      role: snapshot.role,
      registerStep: snapshot.registerStep,
      activeService: snapshot.activeService,
    );
  }
}
