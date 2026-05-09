import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/agency/screens/agency_home_screen.dart';
import 'features/agency/screens/agency_onboarding_screen.dart';

import 'features/agency/screens/agency_public_profile_screen.dart';
import 'features/agency/screens/create_campaign_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/cupertino_login_screen.dart';
import 'features/auth/cpf_completion_screen.dart';
import 'features/client/client_settings_screen.dart';
import 'features/client/confirmation_screen.dart';
import 'features/client/my_services_screen.dart';
import 'features/client/mobile_provider_search_page.dart';
import 'features/client/payment_screen.dart';
import 'features/client/refund_request_screen.dart';
import 'features/client/scheduled_service_screen.dart';
import 'features/client/service_verification_screen.dart';
import 'features/client/service_tracking_page.dart';
import 'features/activity/activity_screen.dart';

import 'features/common/review_screen.dart';
import 'features/dev/face_validation_test_screen.dart';
import 'features/dev/genkit_test_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/home_explore_screen.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_search_screen.dart';
import 'features/payment/models/pix_payment_contract.dart';
import 'features/payment/screens/pix_payment_screen.dart';
import 'features/provider/edit_request_screen.dart';
import 'features/provider/finish_service_screen.dart';
import 'features/provider/medical_home_screen.dart';
import 'features/provider/provider_home_screen.dart';
import 'features/provider/provider_active_service_mobile_screen.dart';
import 'features/profile/provider_profile_screen.dart';
import 'features/provider/provider_schedule_settings_screen.dart';
import 'features/provider/provider_profile_content.dart';
import 'features/shared/chat_list_screen.dart';
import 'features/provider/service_details_screen_fixed.dart';
import 'features/shared/chat_screen.dart';
import 'features/shared/notification_screen.dart';
import 'features/shared/help_screen.dart';
import 'features/shared/security_screen.dart';
import 'features/shared/general_settings_screen.dart';
import 'features/shared/warranty_screen.dart';
// import 'features/transport_central/central_tracking_screen.dart'; // Removido pois foi migrado para TrackingPage
// O tracking agora usa TrackingPage de features/tracking/tracking_page.dart
// Limpeza Uber finalizada
import 'features/auth/change_password_screen.dart';
import 'features/payment/screens/card_registration_screen.dart';
import 'features/payment/screens/payment_methods_screen.dart';
import 'services/api_service.dart';
import 'services/theme_service.dart';
import 'services/global_startup_manager.dart';
import 'widgets/scaffold_with_nav_bar.dart';
import 'core/navigation/app_navigation_policy.dart';
import 'core/navigation/app_redirect_resolver.dart';
import 'core/bootstrap/app_bootstrap_coordinator.dart';
import 'core/bootstrap/app_environment.dart';
import 'core/utils/logger.dart';
import 'core/utils/fixed_schedule_gate.dart';
import 'core/utils/mobile_client_navigation_gate.dart';
import 'core/constants/trip_statuses.dart';
import 'features/client/service_request_screen_mobile.dart';
import 'features/client/home_prestador_fixo.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const String _kLastClientActiveServiceId = 'last_client_active_service_id';

bool isCanonicalFixedService(Map<String, dynamic> service) {
  return isCanonicalFixedServiceRecord(service);
}

bool isFixedScheduledFlowReady(Map<String, dynamic> service) {
  logFixedScheduleGateDecision('redirect', service);
  return evaluateFixedScheduleGate(service).shouldStayOnScheduledScreen;
}

bool shouldProviderStayOnHomeForService(Map<String, dynamic> service) {
  final status = normalizeServiceStatus(service['status']?.toString());
  return ServiceStatusSets.providerConcluding.contains(status);
}

String _providerRouteForService(Map<String, dynamic> service) {
  final id = service['id']?.toString() ?? '';
  if (id.isEmpty) return '/provider-home';
  if (shouldProviderStayOnHomeForService(service)) {
    return '/provider-home';
  }
  final isFixed = isCanonicalFixedService(service);
  return isFixed ? '/provider-home' : '/provider-active/$id';
}

AppNavigationPolicy _buildNavigationPolicy(ApiService api) {
  return AppNavigationPolicy(
    api: api,
    isFixedService: isCanonicalFixedService,
    isFixedScheduledFlowReady: isFixedScheduledFlowReady,
    providerRouteForService: _providerRouteForService,
    resolveClientActiveServiceRoute: resolveClientActiveServiceRoute,
  );
}

void main() {
  runZonedGuarded(
    () async {
      await _mainImpl();
    },
    (error, stack) {
      if (AppLogger.shouldEmitRaw(error.toString(), category: 'ZONE_ERROR')) {
        debugPrint('❌ [ZONE] $error');
        debugPrint('🧵 [ZONE_STACK] $stack');
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (AppLogger.shouldEmitRaw(line, category: 'PRINT')) {
          parent.print(zone, line);
        }
      },
    ),
  );
}

Future<void> _mainImpl() async {
  await AppEnvironment.prepareRuntime();
  runApp(const ProviderScope(child: AppBootstrapper()));
}

class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  final AppBootstrapCoordinator _bootstrapCoordinator =
      AppBootstrapCoordinator();
  bool _initialized = false;
  String? _error;
  String _initialLocation = '/login';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final api = ApiService();
    final result = await _bootstrapCoordinator.initialize(
      api: api,
      navigatorKey: navigatorKey,
      navigationPolicyBuilder: _buildNavigationPolicy,
    );

    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() {
        _error = result.error;
      });
      return;
    }

    setState(() {
      _initialLocation = result.initialLocation;
      _initialized = true;
    });

    _bootstrapCoordinator.schedulePostFrameBootstrap();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Erro de Segurança ou Inicialização',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _initialized = false;
                      });
                      _init();
                    },
                    child: const Text('Tentar Novamente'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        onGenerateRoute: (_) =>
            MaterialPageRoute(builder: (context) => const SplashScreen()),
      );
    }

    return MyApp(initialLocation: _initialLocation);
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryYellow,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'app_logo',
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 180,
                    errorBuilder: (context, error, stackTrace) {
                      return Text(
                        '101',
                        style: GoogleFonts.manrope(
                          fontSize: 100,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                          letterSpacing: -5,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'SERVIÇOS DE A A Z',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: Colors.black.withOpacity(0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  final String initialLocation;
  const MyApp({super.key, this.initialLocation = '/login'});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter(widget.initialLocation);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, child) {
        return MaterialApp.router(
          title: '101 Service',
          theme: ThemeService().currentThemeData,
          routerConfig: _router,
          debugShowCheckedModeBanner: false,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        );
      },
    );
  }
}

GoRouter _buildRouter(String initialLocation) => GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: initialLocation,
  redirect: (context, state) async {
    final api = ApiService();
    final prefs = await SharedPreferences.getInstance();
    Future<Map<String, dynamic>?>? activeServiceFuture;

    Future<Map<String, dynamic>?> resolveActiveService() {
      final isStartupFastPath =
          GlobalStartupManager.instance.isStartingUp.value &&
          (state.matchedLocation == initialLocation ||
              state.matchedLocation == '/' ||
              state.matchedLocation == '/home' ||
              state.matchedLocation == '/provider-home');
      if (isStartupFastPath) {
        return Future<Map<String, dynamic>?>.value(
          api.tracking.activeServiceSnapshot,
        );
      }
      return activeServiceFuture ??= api.tracking.getActiveServiceSnapshot();
    }

    Future<String?> resolveProviderActiveRoute() async {
      if (api.role != 'provider' || api.isMedical) {
        return null;
      }
      try {
        final activeService = await resolveActiveService();
        if (activeService != null) {
          final serviceId = activeService['id']?.toString();
          if (serviceId != null && serviceId.isNotEmpty) {
            await prefs.setString(_kLastClientActiveServiceId, serviceId);
          }
          return _providerRouteForService(activeService);
        }
      } catch (e) {
        debugPrint(
          '⚠️ [Redirect] Falha ao resolver serviço ativo do prestador: $e',
        );
      }
      return null;
    }

    final resolver = AppRedirectResolver(
      policy: _buildNavigationPolicy(api),
      snapshot: AppRedirectSnapshot(matchedLocation: state.matchedLocation),
      findActiveService: resolveActiveService,
      resolveProviderActiveRoute: resolveProviderActiveRoute,
    );
    final resolved = await resolver.resolve();
    if (resolved != null) {
      return resolved;
    }

    if (api.isLoggedIn && api.role == 'client') {
      final activeService = await resolveActiveService();
      final serviceId = activeService?['id']?.toString();
      if (serviceId != null && serviceId.isNotEmpty) {
        await prefs.setString(_kLastClientActiveServiceId, serviceId);
      } else {
        await prefs.remove(_kLastClientActiveServiceId);
      }

      final canUseCachedRoute =
          state.matchedLocation == '/' || state.matchedLocation == '/home';
      if (canUseCachedRoute) {
        final cachedServiceId = prefs.getString(_kLastClientActiveServiceId);
        if (cachedServiceId != null && cachedServiceId.isNotEmpty) {
          return '/service-tracking/$cachedServiceId';
        }
      }
    }

    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/cpf-completion',
      builder: (context, state) => const CpfCompletionScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) {
        final role = state.extra as String?;
        return RegisterScreen(initialRole: role);
      },
    ),
    GoRoute(
      path: '/ios-login',
      builder: (context, state) => const CupertinoLoginScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => ScaffoldWithNavBar(child: child),
      routes: [
        GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/home-search',
          builder: (context, state) {
            final extra = state.extra;
            final data = extra is Map<String, dynamic>
                ? extra
                : <String, dynamic>{};
            return HomeSearchScreen(
              initialQuery: (data['query'] ?? '').toString(),
              initialProfessionName: data['profession_name']?.toString(),
            );
          },
        ),
        GoRoute(
          path: '/home-explore',
          builder: (context, state) => const HomeExploreScreen(),
        ),
        GoRoute(
          path: '/servicos',
          builder: (context, state) => ServiceRequestScreenMobile(
            onSwitchToFixed: (data) {
              context.push('/beauty-booking', extra: data);
            },
            initialData: state.extra is Map<String, dynamic>
                ? state.extra as Map<String, dynamic>
                : null,
          ),
        ),
        GoRoute(
          path: '/beauty-booking',
          builder: (context, state) => ServiceRequestScreenFixed(
            initialData: state.extra is Map<String, dynamic>
                ? state.extra as Map<String, dynamic>
                : null,
          ),
        ),
        GoRoute(
          path: '/pix-payment',
          builder: (context, state) =>
              PixPaymentScreen(args: PixPaymentArgs.fromUnknown(state.extra)),
        ),
        GoRoute(
          path: '/service-tracking/:serviceId',
          builder: (context, state) => ServiceTrackingPage(
            serviceId: state.pathParameters['serviceId'] ?? '',
            scope: ServiceDataScope.mobileOnly,
          ),
        ),
        GoRoute(
          path: '/payment-onboarding',
          builder: (context, state) => const ProviderScheduleSettingsScreen(),
        ),
        GoRoute(
          path: '/mercado-pago-onboarding',
          builder: (context, state) => const ProviderScheduleSettingsScreen(),
        ),

        GoRoute(
          path: '/change-password',
          builder: (context, state) => const ChangePasswordScreen(),
        ),
        GoRoute(
          path: '/chats',
          builder: (context, state) => const ChatListScreen(),
        ),
        GoRoute(path: '/help', builder: (context, state) => const HelpScreen()),
        GoRoute(
          path: '/security',
          builder: (context, state) => const SecurityScreen(),
        ),
        GoRoute(
          path: '/general-settings',
          builder: (context, state) => const GeneralSettingsScreen(),
        ),
        GoRoute(
          path: '/activity',
          builder: (context, state) => const ActivityScreen(),
        ),
        GoRoute(
          path: '/client-settings',

          builder: (context, state) => const ClientSettingsScreen(),
        ),
        GoRoute(
          path: '/provider-settings',
          builder: (context, state) => const ProviderProfileContent(),
        ),
        GoRoute(
          path: '/driver-settings',
          builder: (context, state) => const ProviderProfileContent(),
        ),
        GoRoute(
          path: '/tracking/:serviceId',
          builder: (context, state) => ServiceTrackingPage(
            serviceId: state.pathParameters['serviceId'] ?? '',
            scope: ServiceDataScope.mobileOnly,
          ),
        ),
        GoRoute(
          path: '/service-busca-prestador-movel/:serviceId',
          builder: (context, state) => MobileProviderSearchPage(
            serviceId: state.pathParameters['serviceId'] ?? '',
          ),
        ),
        GoRoute(
          path: '/scheduled-service/:serviceId',
          builder: (context, state) => ScheduledServiceScreen(
            serviceId: state.pathParameters['serviceId'] ?? '',
          ),
        ),
        GoRoute(
          path: '/provider-home',
          builder: (context, state) => const ProviderHomeScreen(),
        ),
        GoRoute(
          path: '/provider-active/:serviceId',
          builder: (context, state) => ProviderActiveServiceMobileScreen(
            serviceId: state.pathParameters['serviceId'] ?? '',
          ),
        ),
        GoRoute(
          path: '/provider-schedule',
          builder: (context, state) => const ProviderScheduleSettingsScreen(),
        ),
        GoRoute(
          path: '/medical-home',
          builder: (context, state) => const MedicalHomeScreen(),
        ),
        GoRoute(
          path: '/provider-profile',
          builder: (context, state) {
            final api = ApiService();
            final raw = state.extra;
            int providerId = 0;
            if (raw is int) {
              providerId = raw;
            } else if (raw is String) {
              providerId = int.tryParse(raw) ?? 0;
            } else if (raw is Map && raw['id'] != null) {
              providerId = int.tryParse(raw['id'].toString()) ?? 0;
            } else {
              providerId = int.tryParse(api.userId ?? '') ?? 0;
            }
            return ProviderProfileScreen(providerId: providerId);
          },
        ),
        GoRoute(
          path: '/my-provider-profile',
          builder: (context, state) => const ProviderProfileContent(),
        ),
        GoRoute(
          path: '/my-services',
          builder: (context, state) => const MyServicesScreen(),
        ),
        GoRoute(
          path: '/payment/:serviceId',
          builder: (context, state) {
            final extra = state.extra;
            if (extra != null) {
              return PaymentScreen(extraData: extra);
            }
            return PaymentScreen(extraData: state.pathParameters['serviceId']);
          },
        ),
        GoRoute(
          path: '/confirmation',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return ConfirmationScreen(
              serviceId: extra?['serviceId']?.toString(),
            );
          },
        ),
        GoRoute(
          path: '/warranty',
          builder: (context, state) => const WarrantyScreen(),
        ),
        // Helper route for notifications to dispatch based on role
        GoRoute(
          path: '/service-details',
          redirect: (context, state) {
            final api = ApiService();
            final extra = state.extra;
            final serviceId = extra is String
                ? extra
                : (extra as Map?)?['id']?.toString();

            if (serviceId == null) return '/home';

            if (api.role == 'provider') {
              return '/provider-home';
            } else {
              return '/service-tracking/$serviceId';
            }
          },
        ),
        GoRoute(
          path: '/provider-service-details/:serviceId',
          builder: (context, state) {
            final serviceId = state.pathParameters['serviceId'] ?? '';
            return ServiceDetailsScreen(serviceId: serviceId);
          },
        ),
        GoRoute(
          path: '/provider-service-finish/:serviceId',
          builder: (context, state) {
            final serviceId = state.pathParameters['serviceId'] ?? '';
            return FinishServiceScreen(serviceId: serviceId);
          },
        ),
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const NotificationScreen(),
        ),
        GoRoute(
          path: '/service-verification/:serviceId',
          builder: (context, state) => ServiceVerificationScreen(
            serviceId: state.pathParameters['serviceId'] ?? '',
          ),
        ),
        GoRoute(
          path: '/payment-methods',
          builder: (context, state) => const PaymentMethodsScreen(),
        ),
        GoRoute(
          path: '/card-registration',
          builder: (context, state) => const CardRegistrationScreen(),
        ),
        GoRoute(
          path: '/refund-request',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return RefundRequestScreen(
              serviceId: extra['id']?.toString() ?? '',
              title: extra['title']?.toString() ?? 'Solicitar Devolução',
              claimType: extra['claimType']?.toString() ?? 'complaint',
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/service-edit-request',
      builder: (context, state) =>
          EditRequestScreen(serviceId: state.extra as String),
    ),
    GoRoute(
      path: '/chat/:serviceId',
      builder: (context, state) {
        final serviceId = state.pathParameters['serviceId'] ?? '';
        final extra = state.extra;
        final Map<String, dynamic>? extraMap = extra is Map<String, dynamic>
            ? extra
            : null;
        final String extraServiceId = extra is String
            ? extra
            : (extraMap?['serviceId']?.toString() ?? '');

        return ChatScreen(
          serviceId: serviceId.isNotEmpty ? serviceId : extraServiceId,
          otherName: extraMap?['otherName'],
          otherAvatar: extraMap?['otherAvatar'],
          initialParticipants: (extraMap?['participants'] as List? ?? const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
          participantContextLabelOverride: extraMap?['participantContextLabel']
              ?.toString(),
        );
      },
    ),
    if (kDebugMode)
      GoRoute(
        path: '/face-validation-test',
        builder: (context, state) => const FaceValidationTestScreen(),
      ),
    if (kDebugMode)
      GoRoute(
        path: '/genkit-test',
        builder: (context, state) => const GenkitTestScreen(),
      ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const AgencyHomeScreen(),
    ),
    GoRoute(
      path: '/admin/create-campaign',
      builder: (context, state) => const CreateCampaignScreen(),
    ),
    GoRoute(
      path: '/admin/onboarding',
      builder: (context, state) => const AgencyOnboardingScreen(),
    ),
    GoRoute(
      path: '/admin/profile/:id',
      builder: (context, state) =>
          AgencyPublicProfileScreen(userId: state.pathParameters['id'] ?? 'me'),
    ),
    GoRoute(path: '/agency', redirect: (context, state) => '/admin'),
    GoRoute(
      path: '/agency/create-campaign',
      redirect: (context, state) => '/admin/create-campaign',
    ),
    GoRoute(
      path: '/agency/onboarding',
      redirect: (context, state) => '/admin/onboarding',
    ),
    GoRoute(
      path: '/agency/profile/:id',
      redirect: (context, state) =>
          '/admin/profile/${state.pathParameters['id'] ?? 'me'}',
    ),
    GoRoute(
      path: '/review/:serviceId',
      builder: (context, state) {
        final serviceId = state.pathParameters['serviceId']!;
        return ReviewScreen(serviceId: serviceId);
      },
    ),
    GoRoute(
      path: '/provider-schedule-settings',
      builder: (context, state) => const ProviderScheduleSettingsScreen(),
    ),
  ],
);
