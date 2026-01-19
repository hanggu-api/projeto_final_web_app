import 'package:flutter/material.dart';
import 'remote_theme_service.dart';

class ThemeConfig {
  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color error;
  final Color success;
  final Color warning;
  final Color textPrimary;

  ThemeConfig({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.error,
    required this.success,
    required this.warning,
    required this.textPrimary,
  });

  factory ThemeConfig.fromJson(Map<String, dynamic> json) {
    return ThemeConfig(
      primary: _parseColor(json['primary']),
      secondary: _parseColor(json['secondary']),
      background: _parseColor(json['background']),
      surface: _parseColor(json['surface']),
      error: _parseColor(json['error']),
      success: _parseColor(json['success']),
      warning: _parseColor(json['warning']),
      textPrimary: _parseColor(json['text_primary']),
    );
  }

  static Color _parseColor(dynamic hex) {
    if (hex == null || hex.toString().isEmpty) return Colors.black;
    String s = hex.toString().replaceAll('#', '');
    if (s.length == 6) {
      s = 'FF$s';
    }
    try {
      return Color(int.parse(s, radix: 16));
    } catch (_) {
      return Colors.black;
    }
  }

  // Default Client Theme (Vibrant Yellow & Black)
  static ThemeConfig get defaultClient => ThemeConfig(
    primary: const Color(0xFFFFD700),
    secondary: const Color(0xFF000000),
    background: Colors.white,
    surface: const Color(0xFFF5F5F5),
    error: const Color(0xFFD32F2F),
    success: const Color(0xFF4CAF50),
    warning: const Color(0xFFFF9800),
    textPrimary: const Color(0xFF000000),
  );

  // Default Provider Theme (Vibrant Yellow & Black)
  static ThemeConfig get defaultProvider => ThemeConfig(
    primary: const Color(0xFFFFD700),
    secondary: const Color(0xFF000000),
    background: Colors.white,
    surface: const Color(0xFFF5F5F5),
    error: const Color(0xFFD32F2F),
    success: const Color(0xFF4CAF50),
    warning: const Color(0xFFFF9800),
    textPrimary: const Color(0xFF000000),
  );
}

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  ThemeConfig _clientConfig = ThemeConfig.defaultClient;
  final ThemeConfig _providerConfig = ThemeConfig.defaultProvider;

  bool _isProviderMode = false;

  ThemeConfig get currentConfig =>
      _isProviderMode ? _providerConfig : _clientConfig;

  Future<void> loadTheme() async {
    try {
      debugPrint('🎨 [ThemeService] Syncing with RemoteThemeService...');
      await RemoteThemeService().initialize();
      
      final theme = RemoteThemeService().getRemoteTheme();
      if (theme != null) {
        _clientConfig = ThemeConfig(
          primary: ThemeConfig._parseColor(theme.colors.primary),
          secondary: ThemeConfig._parseColor(theme.colors.secondary),
          background: ThemeConfig._parseColor(theme.colors.background),
          surface: ThemeConfig._parseColor(theme.colors.surface),
          error: ThemeConfig._parseColor(theme.colors.error),
          success: ThemeConfig._parseColor(theme.colors.success),
          warning: ThemeConfig._parseColor(theme.colors.warning),
          textPrimary: ThemeConfig._parseColor(theme.colors.textPrimary),
        );
      }
    } catch (e) {
      debugPrint('⚠️ [ThemeService] Error syncing theme: $e');
    }
    notifyListeners();
  }

  void setProviderMode(bool isProvider) {
    if (_isProviderMode != isProvider) {
      _isProviderMode = isProvider;
      notifyListeners();
    }
  }

  ThemeData get currentThemeData {
    // Tenta obter o ThemeData completo do RemoteThemeService
    final remoteTheme = RemoteThemeService().getThemeData();
    if (RemoteThemeService().hasTheme) {
      return remoteTheme;
    }

    // Fallback para o tema construído manualmente ou padrão
    final config = currentConfig;
    return ThemeData(
      useMaterial3: true,
      platform: TargetPlatform.iOS, // Enables iOS-style transitions globally
      colorScheme: ColorScheme.fromSeed(
        seedColor: config.primary,
        primary: config.primary,
        secondary: config.secondary,
        surface: config.background,
      ),
      scaffoldBackgroundColor: config.background,
      appBarTheme: AppBarTheme(
        backgroundColor: config.primary,
        foregroundColor: config.textPrimary,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: config.textPrimary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: config.secondary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
