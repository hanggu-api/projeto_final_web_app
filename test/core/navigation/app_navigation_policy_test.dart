import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/core/navigation/app_bootstrap_route_resolver.dart';
import 'package:service_101/core/navigation/app_navigation_policy.dart';
import 'package:service_101/core/navigation/app_redirect_resolver.dart';
import 'package:service_101/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppBootstrapRouteResolver', () {
    AppNavigationPolicy buildPolicy({
      String? role,
      bool isMedical = false,
    }) {
      return AppNavigationPolicy(
        api: ApiService(),
        roleOverride: role,
        isMedicalOverride: isMedical,
        isFixedService: (service) => service['is_fixed'] == true,
        isFixedScheduledFlowReady: (service) => service['ready'] == true,
        providerRouteForService: (service) =>
            '/provider-active/${service['id']}',
        resolveClientActiveServiceRoute: (service, serviceId) =>
            '/service-tracking/$serviceId',
      );
    }

    test('envia para register quando cadastro está em andamento', () {
      final resolver = AppBootstrapRouteResolver(
        policy: buildPolicy(),
        snapshot: const AppBootstrapRouteSnapshot(
          hasCurrentUser: false,
          role: null,
          registerStep: 2,
          activeService: null,
        ),
      );

      expect(resolver.resolve(), '/register');
    });

    test('envia provider médico para medical-home sem serviço ativo', () {
      final resolver = AppBootstrapRouteResolver(
        policy: buildPolicy(role: 'provider', isMedical: true),
        snapshot: const AppBootstrapRouteSnapshot(
          hasCurrentUser: true,
          role: 'provider',
          registerStep: null,
          activeService: null,
        ),
      );

      expect(resolver.resolve(), '/medical-home');
    });

    test('envia cliente com serviço fixo pronto para scheduled-service', () {
      final resolver = AppBootstrapRouteResolver(
        policy: buildPolicy(role: 'client'),
        snapshot: const AppBootstrapRouteSnapshot(
          hasCurrentUser: true,
          role: 'client',
          registerStep: null,
          activeService: {'id': 'svc-1', 'is_fixed': true, 'ready': true},
        ),
      );

      expect(resolver.resolve(), '/scheduled-service/svc-1');
    });

    test('envia cliente com serviço móvel ativo para service-tracking', () {
      final resolver = AppBootstrapRouteResolver(
        policy: buildPolicy(role: 'client'),
        snapshot: const AppBootstrapRouteSnapshot(
          hasCurrentUser: true,
          role: 'client',
          registerStep: null,
          activeService: {'id': 'svc-2', 'is_fixed': false, 'ready': false},
        ),
      );

      expect(resolver.resolve(), '/service-tracking/svc-2');
    });
  });

  group('AppRedirectResolver', () {
    AppNavigationPolicy buildPolicy({
      required String? role,
      required bool isLoggedIn,
      bool isMedical = false,
      String Function(Map<String, dynamic> service, String serviceId)?
      clientRoute,
    }) {
      return AppNavigationPolicy(
        api: ApiService(),
        roleOverride: role,
        isMedicalOverride: isMedical,
        isLoggedInOverride: isLoggedIn,
        isFixedService: (service) => service['is_fixed'] == true,
        providerRouteForService: (service) =>
            '/provider-active/${service['id']}',
        resolveClientActiveServiceRoute:
            clientRoute ??
            (service, serviceId) => '/service-tracking/$serviceId',
      );
    }

    test('redireciona usuário deslogado para login', () async {
      final resolver = AppRedirectResolver(
        policy: buildPolicy(role: null, isLoggedIn: false),
        snapshot: const AppRedirectSnapshot(matchedLocation: '/home'),
        findActiveService: () async => null,
        resolveProviderActiveRoute: () async => null,
      );

      expect(await resolver.resolve(), '/login');
    });

    test('redireciona login de provider para provider-active quando há serviço', () async {
      final resolver = AppRedirectResolver(
        policy: buildPolicy(role: 'provider', isLoggedIn: true),
        snapshot: const AppRedirectSnapshot(matchedLocation: '/login'),
        findActiveService: () async => {'id': 'svc-10', 'is_fixed': false},
        resolveProviderActiveRoute: () async => '/provider-active/svc-10',
      );

      expect(await resolver.resolve(), '/provider-active/svc-10');
    });

    test('permanece em rotas permitidas quando provider tem serviço fixo ativo', () async {
      final resolver = AppRedirectResolver(
        policy: buildPolicy(role: 'provider', isLoggedIn: true),
        snapshot: const AppRedirectSnapshot(matchedLocation: '/notifications'),
        findActiveService: () async => {'id': 'svc-11', 'is_fixed': true},
        resolveProviderActiveRoute: () async => null,
      );

      expect(await resolver.resolve(), isNull);
    });

    test('manda cliente para home quando policy resolve rota neutra e ele está no tracking', () async {
      final resolver = AppRedirectResolver(
        policy: buildPolicy(
          role: 'client',
          isLoggedIn: true,
          clientRoute: (service, serviceId) => '/home',
        ),
        snapshot: const AppRedirectSnapshot(
          matchedLocation: '/service-tracking/svc-20',
        ),
        findActiveService: () async => {'id': 'svc-20', 'is_fixed': false},
        resolveProviderActiveRoute: () async => null,
      );

      expect(await resolver.resolve(), '/home');
    });
  });
}
