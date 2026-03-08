import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'features/agency/screens/agency_home_screen.dart';
import 'features/agency/screens/agency_onboarding_screen.dart';
import 'features/agency/screens/agency_public_profile_screen.dart';
import 'features/agency/screens/create_campaign_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/cupertino_login_screen.dart';
import 'features/client/client_settings_screen.dart';
import 'features/client/confirmation_screen.dart';
import 'features/client/my_services_screen.dart';
import 'features/client/payment_screen.dart';
import 'features/client/service_request_screen.dart';
import 'features/client/refund_request_screen.dart';
import 'features/client/scheduled_service_screen.dart';
import 'features/client/service_verification_screen.dart';
import 'features/client/tracking_screen.dart';
import 'features/activity/activity_screen.dart';
import 'features/client/service_discovery_screen.dart';

import 'features/common/review_screen.dart';
import 'features/dev/simulation_screen.dart';
import 'features/home/home_screen.dart';
import 'features/provider/edit_request_screen.dart';
import 'features/provider/finish_service_screen.dart';
import 'features/provider/medical_home_screen.dart';
import 'features/provider/provider_home_screen.dart';
import 'features/profile/provider_profile_screen.dart';
import 'features/provider/provider_schedule_settings_screen.dart';
import 'features/provider/provider_profile_content.dart';
import 'features/shared/chat_list_screen.dart';
import 'features/provider/service_details_screen_fixed.dart';
import 'features/shared/chat_screen.dart';
import 'features/shared/notification_screen.dart';
import 'features/shared/warranty_screen.dart';
import 'features/uber/uber_request_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'features/uber/uber_tracking_screen.dart';
import 'features/uber/driver_home_screen.dart';
import 'features/uber/driver_trip_screen.dart';
import 'features/uber/driver_earnings_screen.dart';
import 'features/uber/driver_settings_screen.dart';
import 'features/uber/user_history_screen.dart';
import 'firebase_options.dart';
import 'services/api_service.dart';
import 'services/startup_service.dart';
import 'services/theme_service.dart';
import 'services/analytics_service.dart';
import 'services/uber_service.dart';
import 'services/remote_config_service.dart';
import 'services/app_config_service.dart';
import 'widgets/scaffold_with_nav_bar.dart';
import 'core/utils/logger.dart';
import 'core/config/supabase_config.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  debugPrint = customDebugPrint;
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Inicializa variáveis de ambiente e Supabase primeiro
    try {
      await SupabaseConfig.initialize();

      // Inicializa o token do Mapbox para o SDK oficial
      try {
        final mapboxToken = SupabaseConfig.mapboxToken;
        if (mapboxToken.isNotEmpty) {
          mapbox.MapboxOptions.setAccessToken(mapboxToken);
          debugPrint('✅ [Main] Mapbox Access Token initialized');
        }
      } catch (e) {
        debugPrint('⚠️ [Main] Mapbox init error: $e');
      }

      await AppConfigService().preload();
      debugPrint('✅ [Main] Supabase & AppConfig initialized');
    } catch (e) {
      debugPrint('⚠️ [Main] Supabase init failed (missing .env or keys): $e');
    }

    // Firebase é opcional em plataformas Desktop não configuradas
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('✅ [Main] Firebase initialized');
      } catch (e) {
        debugPrint('⚠️ [Main] Firebase init failed: $e');
      }
    } else {
      debugPrint('ℹ️ [Main] Firebase skipped on this platform');
    }

    await AnalyticsService().initSession();
    AnalyticsService().logEvent(
      'APP_OPENED',
      details: {'platform': kIsWeb ? 'web' : 'mobile'},
    );

    await initializeDateFormatting('pt_BR', null);

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // Initialize Analytics to log app open and prevent "library missing" warning
      try {
        await FirebaseAnalytics.instance.logEvent(name: 'app_open');
      } catch (e) {
        // Ignore analytics errors in debug/dev
        debugPrint('Firebase Analytics error: $e');
      }
    }

    // Initialize background service
    // if (!kIsWeb) {
    //   await initializeBackgroundService();
    // }

    // Configurar Crashlytics
    if (!kIsWeb) {
      // Pass all uncaught "fatal" errors from the framework to Crashlytics
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
  } catch (e) {
    debugPrint('Initialization error: $e');
  }

  // Debug: Show errors on screen
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red.shade100,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Erro na Aplicação',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    details.exceptionAsString(),
                    style: const TextStyle(color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };

  runApp(const ProviderScope(child: AppBootstrapper()));
}

class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  bool _initialized = false;
  String? _error;
  String _initialLocation = '/login';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    String step = 'start';
    try {
      step = 'ApiService()';
      final api = ApiService();

      step = 'api.loadToken()';
      await api.loadToken();

      step = 'StartupService.initializeCritical()';
      await StartupService().initializeCritical(navigatorKey);

      step = 'ThemeService.loadTheme()';
      try {
        debugPrint('🎨 [Main] Initializing Remote Theme via ThemeService...');
        await ThemeService().loadTheme();
        debugPrint('✅ [Main] Remote Theme synced successfully');
      } catch (e) {
        debugPrint('⚠️ [Main] Error loading remote theme: $e');
      }

      step = 'RemoteConfigService.init()';
      try {
        await RemoteConfigService.init();
      } catch (e) {
        debugPrint('⚠️ [Main] Error loading remote config: $e');
      }

      await Future.delayed(const Duration(milliseconds: 50));

      step = 'Supabase.auth.currentUser';
      var currentUser = Supabase.instance.client.auth.currentUser;
      final prefs = await SharedPreferences.getInstance();
      var role = prefs.getString('user_role');

      if (currentUser == null && role != null) {
        debugPrint(
          '⏳ [Main] Usuário logado mas sessão ainda não restaurada. Aguardando...',
        );
        await Future.delayed(const Duration(milliseconds: 800));
        currentUser = Supabase.instance.client.auth.currentUser;
        if (currentUser == null) {
          await api.loadToken();
        }
      }

      step = 'setState(_initialized)';
      if (mounted) {
        // 1. Definir rota inicial baseada no role
        if (currentUser == null || role == null) {
          _initialLocation = '/login';
        } else if (role == 'driver') {
          ThemeService().setProviderMode(true);
          _initialLocation = '/uber-driver';
        } else if (role == 'provider') {
          ThemeService().setProviderMode(true);
          _initialLocation = api.isMedical ? '/medical-home' : '/provider-home';
        } else {
          ThemeService().setProviderMode(false);
          _initialLocation = '/home';
        }

        // 2. Garantir que api.userId está populado antes de verificar viagem ativa
        if (currentUser != null && role != null && role != 'provider') {
          if (api.userId == null) {
            try {
              step = 'loginWithFirebase (sync userId)';
              final token =
                  Supabase.instance.client.auth.currentSession?.accessToken;
              if (token != null) await api.loginWithFirebase(token);
            } catch (e) {
              debugPrint('⚠️ [Main] Erro ao popular userId: $e');
            }
          }

          // 3. Verificar viagem ativa
          if (api.userId != null) {
            step = 'UberService.getActiveTrip';
            try {
              if (role == 'driver') {
                final activeDriverTrip = await UberService()
                    .getActiveTripForDriver(api.userId!);
                if (activeDriverTrip != null) {
                  debugPrint(
                    '✅ [Main] Viagem ativa motorista: ${activeDriverTrip['id']}',
                  );
                  _initialLocation =
                      '/uber-driver-trip/${activeDriverTrip['id']}';
                }
              } else {
                final activeClientTrip = await UberService()
                    .getActiveTripForClient(api.userId!);
                if (activeClientTrip != null) {
                  debugPrint(
                    '✅ [Main] Viagem ativa cliente: ${activeClientTrip['id']}',
                  );
                  _initialLocation = '/uber-tracking/${activeClientTrip['id']}';
                } else {
                  debugPrint(
                    'ℹ️ [Main] Nenhuma viagem ativa para userId=${api.userId}',
                  );
                }
              }
            } catch (e) {
              debugPrint('⚠️ [Main] Erro ao buscar viagem ativa no boot: $e');
            }
          } else {
            debugPrint(
              '⚠️ [Main] api.userId ainda null. Verificação de viagem ignorada.',
            );
          }
        }

        if (mounted) {
          setState(() {
            _initialized = true;
          });
        }

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          step = 'postFrameInitialization';
          await StartupService().postFrameInitialization();

          step = 'initializeBackground';
          await StartupService().initializeBackground();
        });
      }
    } catch (e, stack) {
      final msg = '❌ STEP: $step\n\n$e\n\n--- Stack Trace ---\n$stack';
      debugPrint('Erro fatal ao inicializar app: $msg');
      if (mounted) {
        setState(() {
          _error = msg;
        });
      }
    }
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
      backgroundColor: const Color(0xFFFFD700), // AppTheme.primaryYellow
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
                  color: Colors.black.withValues(alpha: 0.5),
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
    final logged = api.isLoggedIn;
    final loggingIn = state.matchedLocation == '/login';
    final registering = state.matchedLocation == '/register';
    final simulating = state.matchedLocation == '/simulation';

    if (!logged && !loggingIn && !registering && !simulating) {
      return '/login';
    }

    if (logged && loggingIn) {
      if (api.role == 'driver') {
        ThemeService().setProviderMode(true);
        return '/uber-driver';
      }
      if (api.role == 'provider') {
        ThemeService().setProviderMode(true);
        return api.isMedical ? '/medical-home' : '/provider-home';
      }
      ThemeService().setProviderMode(false);
      return '/home';
    }

    // Verificação de viagem ativa ao entrar na Home ou Driver Home
    if (logged &&
        (state.matchedLocation == '/home' ||
            state.matchedLocation == '/uber-driver' ||
            state.matchedLocation == '/')) {
      try {
        if (api.role == 'driver') {
          final activeTrip = await UberService().getActiveTripForDriver(
            api.userId!,
          );
          if (activeTrip != null) {
            return '/uber-driver-trip/${activeTrip['id']}';
          }
        } else if (api.role == 'client') {
          final activeTrip = await UberService().getActiveTripForClient(
            api.userId!,
          );
          if (activeTrip != null) return '/uber-tracking/${activeTrip['id']}';
        }
      } catch (e) {
        debugPrint('⚠️ [Redirect] Erro ao buscar viagem ativa: $e');
      }
    }

    // Motorista logado acessando rota errada → redirecionar para /uber-driver
    if (logged && api.role == 'driver' && state.matchedLocation == '/home') {
      ThemeService().setProviderMode(true);
      return '/uber-driver';
    }

    // Se estiver na raiz (/), redireciona para home ou login
    if (state.matchedLocation == '/') {
      return logged ? '/home' : '/login';
    }

    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
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
          path: '/servicos',
          builder: (context, state) => const ServiceDiscoveryScreen(),
        ),
        GoRoute(
          path: '/uber-request',
          builder: (context, state) => const UberRequestScreen(),
        ),
        GoRoute(
          path: '/uber-tracking/:tripId',
          builder: (context, state) =>
              UberTrackingScreen(tripId: state.pathParameters['tripId'] ?? ''),
        ),
        GoRoute(
          path: '/uber-history',
          builder: (context, state) => const UserHistoryScreen(),
        ),
        GoRoute(
          path: '/uber-driver',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return DriverHomeScreen(
              cancellationMessage: extra?['cancellationMessage'],
              cancellationFee: (extra?['cancellationFee'] as num?)?.toDouble(),
            );
          },
        ),
        GoRoute(
          path: '/uber-driver-trip/:tripId',
          builder: (context, state) =>
              DriverTripScreen(tripId: state.pathParameters['tripId'] ?? ''),
        ),
        GoRoute(
          path: '/uber-driver-earnings',
          builder: (context, state) => const DriverEarningsScreen(),
        ),
        GoRoute(
          path: '/driver-settings',
          builder: (context, state) => const DriverSettingsScreen(),
        ),
        GoRoute(
          path: '/chats',
          builder: (context, state) => const ChatListScreen(),
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
          builder: (context, state) => const ClientSettingsScreen(),
        ),
        GoRoute(
          path: '/tracking/:serviceId',
          builder: (context, state) => TrackingScreen(
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
          path: '/medical-home',
          builder: (context, state) => const MedicalHomeScreen(),
        ),
        GoRoute(
          path: '/provider-profile',
          builder: (context, state) {
            final providerId = state.extra as int? ?? 0;
            return ProviderProfileScreen(providerId: providerId);
          },
        ),
        GoRoute(
          path: '/my-provider-profile',
          builder: (context, state) =>
              const Scaffold(body: ProviderProfileContent()),
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
          builder: (context, state) => const ConfirmationScreen(),
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
              return '/provider-service-details/$serviceId';
            } else {
              return '/tracking/$serviceId';
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
          path: '/refund-request',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return RefundRequestScreen(
              serviceId: extra['id']?.toString() ?? '',
              title: extra['title']?.toString() ?? 'Solicitar Devolução',
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/create-service',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ServiceRequestScreen(
          initialProviderId: extra?['providerId'],
          initialService: extra?['service'],
          initialProvider: extra?['provider'],
          initialPrompt: extra?['initialPrompt'],
        );
      },
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
        );
      },
    ),
    GoRoute(
      path: '/simulation',
      builder: (context, state) => const SimulationScreen(),
    ),
    GoRoute(
      path: '/agency',
      builder: (context, state) => const AgencyHomeScreen(),
    ),
    GoRoute(
      path: '/agency/onboarding',
      builder: (context, state) => const AgencyOnboardingScreen(),
    ),
    GoRoute(
      path: '/agency/create-campaign',
      builder: (context, state) => const CreateCampaignScreen(),
    ),
    GoRoute(
      path: '/agency/profile/:id',
      builder: (context, state) =>
          AgencyPublicProfileScreen(userId: state.pathParameters['id'] ?? 'me'),
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
