import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/ai/genkit_service.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../services/global_startup_manager.dart';
import '../../services/startup_service.dart';
import '../../services/token_manager.dart';
import 'backend_bootstrap_api.dart';
import 'backend_bootstrap_state.dart';
import '../config/supabase_config.dart';
import '../navigation/app_bootstrap_route_resolver.dart';
import '../navigation/app_navigation_policy.dart';
import '../runtime/app_runtime_service.dart';
import '../tracking/backend_tracking_api.dart';

class AppBootstrapInitializationResult {
  final String initialLocation;
  final String? error;

  const AppBootstrapInitializationResult({
    required this.initialLocation,
    required this.error,
  });

  bool get isSuccess => error == null;
}

class AppBootstrapCoordinator {
  bool _postFrameBootstrapStarted = false;
  bool _deferredFrameworkWarmupStarted = false;
  final BackendBootstrapApi _backendBootstrapApi = const BackendBootstrapApi();
  final BackendTrackingApi _backendTrackingApi = const BackendTrackingApi();

  Future<T?> awaitBootstrapStep<T>(
    String label,
    Future<T?> future, {
    Duration timeout = const Duration(seconds: 8),
    T? fallback,
  }) async {
    try {
      return await future.timeout(timeout);
    } on TimeoutException {
      debugPrint(
        '⏳ [Main] Bootstrap timeout em $label após ${timeout.inSeconds}s. Seguindo com fallback.',
      );
      return fallback;
    } catch (e) {
      debugPrint('⚠️ [Main] Falha em $label: $e');
      return fallback;
    }
  }

  Future<AppBootstrapInitializationResult> initialize({
    required ApiService api,
    required GlobalKey<NavigatorState> navigatorKey,
    required AppNavigationPolicy Function(ApiService api)
    navigationPolicyBuilder,
  }) async {
    String step = 'start';
    try {
      step = 'ApiService.init()';
      api.init();

      final prefsFuture = SharedPreferences.getInstance();

      step = 'bootstrap warmup';
      final loadTokenFuture = awaitBootstrapStep(
        'api.loadToken()',
        api.loadToken(),
        timeout: const Duration(seconds: 5),
      );
      final criticalInitFuture = awaitBootstrapStep(
        'StartupService.initializeCritical()',
        StartupService().initializeCritical(navigatorKey),
        timeout: const Duration(seconds: 8),
      );
      await loadTokenFuture;
      await criticalInitFuture;

      step = 'Supabase.auth.currentUser check';
      User? currentUser;
      if (SupabaseConfig.isInitialized) {
        currentUser = Supabase.instance.client.auth.currentUser;
      }
      final prefs = await prefsFuture;
      var role = api.role ?? prefs.getString('user_role');
      final registerStep = prefs.getInt('register_step');
      BackendBootstrapState? backendBootstrap;
      Map<String, dynamic>? activeService;

      if (currentUser == null && role != null) {
        debugPrint(
          '⏳ [Main] Usuário logado mas sessão ainda não restaurada. Aguardando...',
        );
        if (SupabaseConfig.isInitialized) {
          currentUser = Supabase.instance.client.auth.currentUser;
        }
        if (currentUser == null) {
          await awaitBootstrapStep(
            'api.loadToken() retry',
            api.loadToken(),
            timeout: const Duration(seconds: 4),
          );
        }
      }

      step = 'backend auth/bootstrap';
      backendBootstrap = await awaitBootstrapStep(
        'backend auth/bootstrap',
        _backendBootstrapApi.fetchBootstrap(),
        timeout: const Duration(seconds: 4),
      );

      if (backendBootstrap != null) {
        await api.persistBootstrapIdentity(
          role: backendBootstrap.role,
          isMedical: backendBootstrap.isMedical,
          isFixedLocation: backendBootstrap.isFixedLocation,
          registerStep: backendBootstrap.registerStep,
        );
        role = backendBootstrap.role ?? role;
      }

      step = 'resolveBootstrapRoute';
      if (backendBootstrap != null &&
          backendBootstrap.nextRoute.trim().isNotEmpty) {
        return AppBootstrapInitializationResult(
          initialLocation: backendBootstrap.nextRoute,
          error: null,
        );
      }

      if (currentUser != null && role == 'client') {
        step = 'backend tracking/active-service';
        final activeState = await awaitBootstrapStep(
          'backend tracking/active-service',
          _backendTrackingApi.fetchActiveService(),
          timeout: const Duration(seconds: 3),
        );
        final service = activeState?.service;
        if (service != null && service['id'] != null) {
          activeService = Map<String, dynamic>.from(service);
          debugPrint(
            '✅ [Main] Serviço ativo encontrado no bootstrap: ${service['id']}. Abrindo rota ativa imediatamente.',
          );
        }
      }

      if (currentUser != null) {
        debugPrint(
          '⚠️ [Main] Sem resposta canônica de /api/v1/auth/bootstrap no ambiente atual; usando fallback local de rota.',
        );
      }

      final bootstrapResolver = AppBootstrapRouteResolver(
        policy: navigationPolicyBuilder(api),
        snapshot: AppBootstrapRouteSnapshot(
          hasCurrentUser: currentUser != null,
          role: role,
          registerStep: registerStep,
          activeService: activeService,
        ),
      );

      return AppBootstrapInitializationResult(
        initialLocation: bootstrapResolver.resolve(),
        error: null,
      );
    } catch (e, stack) {
      final msg = '❌ STEP: $step\n\n$e\n\n--- Stack Trace ---\n$stack';
      debugPrint('Erro fatal ao inicializar app: $msg');
      return AppBootstrapInitializationResult(
        initialLocation: '/login',
        error: msg,
      );
    }
  }

  void schedulePostFrameBootstrap() {
    if (_postFrameBootstrapStarted) return;
    _postFrameBootstrapStarted = true;

    scheduleDeferredFrameworkWarmup();

    if (!SupabaseConfig.isInitialized) {
      debugPrint(
        '⚠️ [Main] Startup pós-frame ignorado: Supabase não inicializado',
      );
      unawaited(GlobalStartupManager.instance.unleashTheBeast());
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 120));

      unawaited(
        awaitBootstrapStep(
          'TokenManager.warmUp()',
          TokenManager.instance.warmUp(),
          timeout: const Duration(seconds: 5),
        ),
      );

      unawaited(
        awaitBootstrapStep(
          'StartupService.postFrameInitialization()',
          StartupService().postFrameInitialization(),
          timeout: const Duration(seconds: 12),
        ),
      );

      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          try {
            GenkitService.instance.initialize();
          } catch (e) {
            debugPrint('⚠️ [Main] Falha ao iniciar Genkit no pós-frame: $e');
          }
        }),
      );

      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 600), () async {
          await awaitBootstrapStep(
            'StartupService.initializeBackground()',
            StartupService().initializeBackground(),
            timeout: const Duration(seconds: 30),
          );
        }),
      );
    });
  }

  void scheduleDeferredFrameworkWarmup() {
    if (_deferredFrameworkWarmupStarted) return;
    _deferredFrameworkWarmupStarted = true;

    unawaited(
      Future<void>(() async {
        await awaitBootstrapStep(
          'initializeDateFormatting(pt_BR)',
          initializeDateFormatting('pt_BR', null),
          timeout: const Duration(seconds: 8),
        );

        await awaitBootstrapStep(
          'AnalyticsService.initSession()',
          AnalyticsService().initSession(),
          timeout: const Duration(seconds: 5),
        );
        AnalyticsService().logEvent(
          'APP_OPENED',
          details: {
            'platform': kIsWeb ? 'web' : 'mobile',
            'store_version': AppRuntimeService.storeVersion,
            'patch_version': AppRuntimeService.patchVersion,
            'environment': AppRuntimeService.environment,
          },
        );

        await awaitBootstrapStep(
          'TokenManager.auditCurrentToken()',
          TokenManager.instance.auditCurrentToken(prefix: 'app-start'),
          timeout: const Duration(seconds: 5),
        );

        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          try {
            FlutterError.onError =
                FirebaseCrashlytics.instance.recordFlutterFatalError;
            PlatformDispatcher.instance.onError = (error, stack) {
              final runtime = AppRuntimeService.instance.snapshot;
              FirebaseCrashlytics.instance.setCustomKey(
                'runtime_snapshot',
                runtime.toJson().toString(),
              );
              FirebaseCrashlytics.instance.recordError(
                error,
                stack,
                fatal: true,
              );
              return true;
            };
            debugPrint('✅ [Main] Crashlytics configured');
          } catch (e) {
            debugPrint('⚠️ [Main] Crashlytics config failed: $e');
          }
        } else {
          debugPrint('ℹ️ [Main] Crashlytics skipped on this platform');
        }
      }),
    );
  }
}
