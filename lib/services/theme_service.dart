import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'remote_theme_service.dart';
import '../core/theme/app_theme.dart';

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

  // Default Client Theme (Stitch v1.0 Style)
  static ThemeConfig get defaultClient => ThemeConfig(
    primary: const Color(0xFFFFC107),
    secondary: const Color(0xFF0F172A), // Dark blue from Stitch
    background: const Color(0xFFF1F5F9), // backgroundLight from Stitch
    surface: Colors.white,
    error: const Color(0xFFEF4444),
    success: const Color(0xFF22C55E),
    warning: const Color(0xFFF59E0B),
    textPrimary: const Color(0xFF0F172A),
  );

  // Default Provider Theme (Stitch v1.0 Style)
  static ThemeConfig get defaultProvider => ThemeConfig(
    primary: const Color(0xFFFFC107),
    secondary: const Color(0xFF0F172A),
    background: const Color(0xFFF1F5F9),
    surface: Colors.white,
    error: const Color(0xFFEF4444),
    success: const Color(0xFF22C55E),
    warning: const Color(0xFFF59E0B),
    textPrimary: const Color(0xFF0F172A),
  );
}

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  ThemeConfig _clientConfig = ThemeConfig.defaultClient;
  final ThemeConfig _providerConfig = ThemeConfig.defaultProvider;

  bool _isProviderMode = false;
  bool _isNavBarVisible = true;

  ThemeConfig get currentConfig =>
      _isProviderMode ? _providerConfig : _clientConfig;

  bool get isNavBarVisible => _isNavBarVisible;

  Future<void> loadTheme() async {
    try {
      debugPrint('🎨 [ThemeService] Syncing with RemoteThemeService...');
      await RemoteThemeService()
          .initialize()
          .timeout(const Duration(seconds: 4));

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
    } on TimeoutException catch (_) {
      debugPrint(
        '⏳ [ThemeService] RemoteThemeService demorou demais no bootstrap; seguindo com tema local.',
      );
    } catch (e) {
      debugPrint('⚠️ [ThemeService] Error syncing theme: $e');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  void setProviderMode(bool isProvider) {
    if (_isProviderMode != isProvider) {
      _isProviderMode = isProvider;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  void setNavBarVisible(bool visible) {
    if (_isNavBarVisible != visible) {
      _isNavBarVisible = visible;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  ThemeData get currentThemeData {
    // Tenta obter o ThemeData completo do RemoteThemeService
    final remoteTheme = RemoteThemeService().getThemeData();
    if (RemoteThemeService().hasTheme) {
      return remoteTheme;
    }

    // Fallback para o tema construído manualmente ou padrão (Stitch Style)
    final config = currentConfig;

    final baseTextTheme = GoogleFonts.manropeTextTheme();

    return ThemeData(
      useMaterial3: true,
      fontFamily: GoogleFonts.manrope().fontFamily,
      platform: TargetPlatform.iOS,
      colorScheme: ColorScheme.fromSeed(
        seedColor: config.primary,
        primary: config.primary,
        secondary: config.secondary,
        surface: config.surface,
        error: config.error,
        onSurface: config.textPrimary,
      ),
      scaffoldBackgroundColor: config.background,
      appBarTheme: AppBarTheme(
        backgroundColor: config.primary,
        foregroundColor: config.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: config.textPrimary,
        ),
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: GoogleFonts.manrope(
          fontSize: 36,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: config.textPrimary,
        ),
        headlineMedium: GoogleFonts.manrope(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: config.textPrimary,
        ),
        titleLarge: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: config.textPrimary,
        ),
        bodyLarge: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.6,
          color: config.textPrimary,
        ),
        bodyMedium: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: config.textPrimary.withOpacity(0.8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge + 2),
          borderSide: const BorderSide(color: Color(0xFFE6ECF5), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge + 2),
          borderSide: const BorderSide(color: Color(0xFFE6ECF5), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge + 2),
          borderSide: BorderSide(color: config.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge + 2),
          borderSide: BorderSide(
            color: config.error.withOpacity(0.75),
            width: 1.4,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge + 2),
          borderSide: BorderSide(color: config.error, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        labelStyle: GoogleFonts.manrope(
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: GoogleFonts.manrope(
          color: AppTheme.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: config.primary,
          foregroundColor: config.textPrimary,
          disabledBackgroundColor: config.primary.withOpacity(0.55),
          disabledForegroundColor: config.textPrimary.withOpacity(0.7),
          minimumSize: const Size(double.infinity, 54),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge + 2),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: config.textPrimary,
          minimumSize: const Size(double.infinity, 54),
          side: const BorderSide(color: Color(0xFFE6ECF5), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge + 2),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: config.surface,
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge + 2),
          side: AppTheme.cardBorderSide,
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }
}
