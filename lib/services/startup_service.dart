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
  Future<void> initializeCritical(GlobalKey<NavigatorState> navigatorKey) async {
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

  /// Fase 2: Inicialização Background (Lazy / Low Priority)
  /// Ocorre com delay (ex: 2-3s após o boot) para não travar animações.
  /// Geolocator, Sync pesado de FCM, Cache de imagens, TTS.
  Future<void> initializeBackground() async {
    AppLogger.sistema('Iniciando Fase 2: Background (Lazy)');

    // Delay maior (5s) para garantir que a UI e animações iniciais terminaram - Otimização Moto G34
    await Future.delayed(const Duration(seconds: 5));
    
    final currentUser = Supabase.instance.client.auth.currentUser;

    // 1. Sync FCM Token (I/O pesado)
    if (currentUser != null) {
      try {
        await NotificationService().syncToken();
        
        // Se for prestador, solicitar permissões avançadas (Overlay)
        final prefs = await SharedPreferences.getInstance();
        final role = prefs.getString('user_role');
        if (role == 'provider') {
           // DISABLED: Requesting overlay on startup causes errors on some devices (e.g. Motorola)
           // Moving to a manual button in Settings
           // await NotificationService().requestProviderPermissions();
        }
      } catch (e) {
        AppLogger.erro('Erro ao sincronizar token FCM no background', e);
      }
    }

    // 2. Outros serviços pesados podem vir aqui (ex: Pré-cache agressivo)
    
    // 3. Liberar widgets pesados (AdCarousel, Mapas, etc)
    // Isso notificará todos os ouvintes que a "Fase Pesada" começou
    GlobalStartupManager.instance.unleashTheBeast();
  }
}
