import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/profile/backend_profile_api.dart';
import '../core/config/supabase_config.dart';
import '../core/runtime/app_runtime_service.dart';
import 'api_service.dart';
import 'background_main.dart';
import 'client_tracking_service.dart';
import 'notification_service.dart';
import 'remote_config_service.dart';
import 'theme_service.dart';
import 'global_startup_manager.dart';
import 'provider_keepalive_service.dart';
import 'device_capability_service.dart';
import '../core/utils/logger.dart';

class StartupService {
  static final StartupService _instance = StartupService._internal();
  factory StartupService() => _instance;
  StartupService._internal();

  bool _isCriticalInitialized = false;
  bool _notificationsInitialized = false;
  bool _postFrameSyncScheduled = false;
  GlobalKey<NavigatorState>? _navigatorKey;
  final BackendProfileApi _backendProfileApi = const BackendProfileApi();

  Future<void> _refreshProfileFromBackend(ApiService api) async {
    final backendProfile = await _backendProfileApi.fetchMyProfile();
    if (backendProfile == null) {
      // Startup resiliente: perfil canônico pode demorar alguns segundos após sync.
      return;
    }
    await api.applyBackendProfileSnapshot(backendProfile.toApiUserMap());
  }

  /// Fase 0: Inicialização Crítica (Bloqueante)
  /// Ocorre antes ou durante a Splash Screen.
  /// Carrega apenas o necessário para montar a UI básica.
  Future<void> initializeCritical(
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    if (_isCriticalInitialized) return;
    _navigatorKey = navigatorKey;

    try {
      AppLogger.sistema('Iniciando Fase 0: Crítica (Bloqueante)');

      // Mantemos aqui apenas o que afeta a primeira pintura.
      await ThemeService().loadTheme();
      await DeviceCapabilityService.instance.initialize();
      _configureImageCache(DeviceCapabilityService.instance);

      _isCriticalInitialized = true;
    } catch (e) {
      AppLogger.erro('Erro na Fase Crítica de inicialização', e);
    }
  }

  /// Fase 1: Inicialização Pós-Frame (High Priority)
  /// Ocorre logo após o primeiro frame ser desenhado.
  /// Autenticação e dados vitais do usuário.
  Future<void> postFrameInitialization() async {
    AppLogger.sistema('Iniciando Fase 1: Pós-Frame (Prioridade Alta)');

    if (!SupabaseConfig.isInitialized) {
      AppLogger.sistema(
        '⚠️ [STARTUP] Fase 1 ignorada: Supabase não inicializado',
      );
      return;
    }

    final api = ApiService();
    // Carregar token cached para requests futuros
    await api.loadToken();

    final currentUser = Supabase.instance.client.auth.currentUser;
    final prefs = await SharedPreferences.getInstance();
    String? role = prefs.getString('user_role');
    role ??= api.role;

    // Configurar modo do ThemeService baseado na role atualizada
    if (role != null) {
      ThemeService().setProviderMode(role == 'provider' || role == 'driver');
    }

    if (!_notificationsInitialized && _navigatorKey != null) {
      try {
        await NotificationService().init(_navigatorKey!);
        _notificationsInitialized = true;
      } catch (e) {
        AppLogger.erro('Erro ao inicializar notificações no pós-frame', e);
      }
    }

    if (currentUser != null && !_postFrameSyncScheduled) {
      _postFrameSyncScheduled = true;
      Future<void>(() async {
        try {
          final token =
              Supabase.instance.client.auth.currentSession?.accessToken;
          if (token != null) {
            await api.syncUserProfile(token);
            final refreshedRole = api.role ?? prefs.getString('user_role');
            if (refreshedRole != null) {
              ThemeService().setProviderMode(
                refreshedRole == 'provider' || refreshedRole == 'driver',
              );
            }
          }
        } catch (e) {
          AppLogger.erro('Erro ao sincronizar perfil no startup', e);
        }

        try {
          await _refreshProfileFromBackend(api);
        } catch (e) {
          AppLogger.erro('Erro ao atualizar perfil no startup', e);
        }
      });
    }

    // Removido ensureCustomerForUser automático no startup para evitar erros 502/400 desnecessários.
    // O customer será criado sob demanda quando o usuário for cadastrar um cartão ou gerar um PIX.
  }

  Future<void> _waitFor(int ms) => Future.delayed(Duration(milliseconds: ms));

  void _configureImageCache(DeviceCapabilityService capability) {
    final imageCache = PaintingBinding.instance.imageCache;
    if (capability.isLowEndDevice) {
      imageCache.maximumSize = 40;
      imageCache.maximumSizeBytes = 40 << 20;
      AppLogger.sistema(
        '🖼️ [STARTUP] ImageCache reduzido para modo basic (40 imagens / 40MB)',
      );
      return;
    }
    if (capability.prefersLowResolutionImages) {
      imageCache.maximumSize = 60;
      imageCache.maximumSizeBytes = 60 << 20;
      AppLogger.sistema(
        '🖼️ [STARTUP] ImageCache ajustado para modo leve (60 imagens / 60MB)',
      );
    }
  }

  /// Fase 2: Inicialização Background (Lazy / Low Priority)
  /// Ocorre com delay para não travar animações de entrada.
  Future<void> initializeBackground() async {
    AppLogger.sistema('⚙️ [STARTUP] Iniciando Fase 2: Background (Lazy)');

    if (!SupabaseConfig.isInitialized) {
      AppLogger.sistema(
        '⚠️ [STARTUP] Fase 2 ignorada: Supabase não inicializado',
      );
      return;
    }

    final capability = DeviceCapabilityService.instance;

    // Dá mais tempo para a home estabilizar antes de iniciar cargas de fundo.
    await _waitFor(capability.prefersReducedBackground ? 6500 : 4500);

    final currentUser = Supabase.instance.client.auth.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role');

    if (currentUser != null && (role == 'provider' || role == 'driver')) {
      try {
        final onlineForDispatch =
            await ProviderKeepaliveService.isOnlineForDispatch();
        if (onlineForDispatch) {
          await initializeBackgroundService();
          await ProviderKeepaliveService.startBackgroundService();
        } else {
          AppLogger.sistema(
            'ℹ️ [STARTUP] Background service ignorado: prestador offline para despacho.',
          );
        }
      } catch (e) {
        AppLogger.erro('Erro ao configurar background service', e);
      }
    } else {
      AppLogger.sistema(
        'ℹ️ [STARTUP] Background service ignorado para cliente/usuário sem contexto de despacho.',
      );
    }

    if (currentUser != null &&
        await ClientTrackingService.isTrackingEnabled()) {
      try {
        await initializeBackgroundService();
        final service = FlutterBackgroundService();
        final running = await service.isRunning();
        if (!running) {
          await service.startService();
        }
        service.invoke('refreshContext');
      } catch (e) {
        AppLogger.erro(
          'Erro ao reativar tracking do cliente em background no startup',
          e,
        );
      }
    }

    // --- LOTE 1: SERVIÇOS DE DADOS ---
    AppLogger.sistema('📦 [STARTUP] Lote 1: Dados e Configurações');
    await Future.wait([
      RemoteConfigService.init(),
      NotificationService().syncToken(),
    ]).timeout(const Duration(seconds: 20)).catchError((e) {
      AppLogger.erro('Erro Lote 1', e);
      return <void>[];
    });
    AppLogger.sistema(
      '🧾 [STARTUP] Runtime snapshot: ${AppRuntimeService.instance.snapshot.toJson()}',
    );

    await _waitFor(capability.prefersReducedBackground ? 900 : 500);

    // --- LOTE 2: PERMISSÕES E STATUS ---
    AppLogger.sistema('📦 [STARTUP] Lote 2: Permissões e Perfil');
    if (currentUser != null) {
      try {
        final api = ApiService();
        if (api.userData == null) {
          await _refreshProfileFromBackend(api);
        }

        if (role == 'provider') {
          // Permissões de Overlay etc
        }
      } catch (e) {
        AppLogger.erro('Erro Lote 2', e);
      }
    }

    await _waitFor(capability.prefersReducedBackground ? 900 : 500);

    // --- LOTE 3: FINALIZAÇÃO ---
    AppLogger.sistema('📦 [STARTUP] Lote 3: Finalização e Liberação');

    // Libera widgets pesados (AdCarousel, Mapas, etc)
    // unleashTheBeast agora tem seu próprio delay interno de 500ms
    await GlobalStartupManager.instance.unleashTheBeast();

    AppLogger.sistema('✅ [STARTUP] Fase 2 Concluída. A besta foi liberada!');
  }
}
