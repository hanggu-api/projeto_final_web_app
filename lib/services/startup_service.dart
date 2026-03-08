import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'notification_service.dart';
import 'remote_config_service.dart';
import 'theme_service.dart';
import 'global_startup_manager.dart';
import '../core/utils/logger.dart';

class StartupService {
  static final StartupService _instance = StartupService._internal();
  factory StartupService() => _instance;
  StartupService._internal();

  bool _isCriticalInitialized = false;

  /// Fase 0: Inicialização Crítica (Bloqueante)
  /// Ocorre antes ou durante a Splash Screen.
  /// Carrega apenas o necessário para montar a UI básica.
  Future<void> initializeCritical(
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    if (_isCriticalInitialized) return;

    try {
      AppLogger.sistema('Iniciando Fase 0: Crítica (Bloqueante)');

      // 1. Remote Config (Features flags, URLs essenciais)
      await RemoteConfigService.init();

      // 2. Tema (Para evitar flash de cores erradas)
      await ThemeService().loadTheme();

      // 3. Notification Service (Apenas init básico, sem sync pesado)
      await NotificationService().init(navigatorKey);

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

    final api = ApiService();
    // Carregar token cached para requests futuros
    await api.loadToken();

    final currentUser = Supabase.instance.client.auth.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role');

    // Configurar modo do ThemeService baseado na role
    if (role != null) {
      ThemeService().setProviderMode(role == 'provider');
    }

    await Future.delayed(const Duration(milliseconds: 200));

    // Refresh de perfil (importante para flags de UI como biometria/status)
    if (currentUser != null && role != null) {
      try {
        await api.getMyProfile();
      } catch (e) {
        AppLogger.erro('Erro ao atualizar perfil no startup', e);
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _waitFor(int ms) => Future.delayed(Duration(milliseconds: ms));

  /// Fase 2: Inicialização Background (Lazy / Low Priority)
  /// Ocorre com delay para não travar animações de entrada.
  Future<void> initializeBackground() async {
    AppLogger.sistema('⚙️ [STARTUP] Iniciando Fase 2: Background (Lazy)');

    // 1. ESPERA INICIAL (Reduzido para 3s para dar feedback mais rápido ao usuário)
    await _waitFor(3000);

    final currentUser = Supabase.instance.client.auth.currentUser;

    // --- LOTE 1: SERVIÇOS DE DADOS ---
    AppLogger.sistema('📦 [STARTUP] Lote 1: Dados e Configurações');
    await Future.wait([
      // AdConfigService, etc se houvesse
      NotificationService().syncToken(),
    ]).timeout(const Duration(seconds: 10)).catchError((e) {
      AppLogger.erro('Erro Lote 1', e);
      return <void>[];
    });

    await _waitFor(500);

    // --- LOTE 2: PERMISSÕES E STATUS ---
    AppLogger.sistema('📦 [STARTUP] Lote 2: Permissões e Perfil');
    if (currentUser != null) {
      try {
        final api = ApiService();
        await api.getMyProfile();

        final prefs = await SharedPreferences.getInstance();
        final role = prefs.getString('user_role');
        if (role == 'provider') {
          // Permissões de Overlay etc
        }
      } catch (e) {
        AppLogger.erro('Erro Lote 2', e);
      }
    }

    await _waitFor(500);

    // --- LOTE 3: FINALIZAÇÃO ---
    AppLogger.sistema('📦 [STARTUP] Lote 3: Finalização e Liberação');

    // Libera widgets pesados (AdCarousel, Mapas, etc)
    // unleashTheBeast agora tem seu próprio delay interno de 500ms
    await GlobalStartupManager.instance.unleashTheBeast();

    AppLogger.sistema('✅ [STARTUP] Fase 2 Concluída. A besta foi liberada!');
  }
}
