import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Serviço para gerenciar tema remoto carregado do backend
class RemoteThemeService {
  static final RemoteThemeService _instance = RemoteThemeService._internal();
  factory RemoteThemeService() => _instance;
  RemoteThemeService._internal();

  final _api = ApiService();
  RemoteThemeData? _currentTheme;
  Map<String, String> _strings = {};
  Map<String, dynamic> _config = {};

  // Cache keys
  static const String _cacheKeyTheme = 'cached_theme';
  static const String _cacheKeyStrings = 'cached_strings';
  static const String _cacheKeyConfig = 'cached_config';
  static const String _cacheKeyThemeVersion = 'cached_theme_version';

  /// Carrega tema do backend
  Future<void> loadTheme() async {
    try {
      debugPrint('🎨 [RemoteTheme] Loading theme from backend...');
      final response = await _api.invokeEdgeFunction('theme');

      if (response['success'] == true && response['theme'] != null) {
        _currentTheme = RemoteThemeData.fromJson(response['theme']);
        await _saveThemeToCache(_currentTheme!);
        debugPrint('🎨 [RemoteTheme] Theme loaded: ${_currentTheme!.name}');
      }
    } catch (e) {
      debugPrint('⚠️ [RemoteTheme] Error loading theme: $e');
      // Fallback para tema em cache
      _currentTheme = await _loadThemeFromCache();
      if (_currentTheme != null) {
        debugPrint('📦 [RemoteTheme] Using cached theme');
      } else {
        debugPrint('🔴 [RemoteTheme] No cached theme, using defaults');
        _currentTheme = RemoteThemeData.defaultTheme();
      }
    }
  }

  /// Carrega strings traduzidas
  Future<void> loadStrings(String language) async {
    try {
      debugPrint('🌐 [RemoteTheme] Loading strings for $language...');
      final response = await _api.invokeEdgeFunction('strings', null, {'lang': language});

      if (response['success'] == true && response['strings'] != null) {
        _strings = Map<String, String>.from(response['strings']);
        await _saveStringsToCache(_strings);
        debugPrint('🌐 [RemoteTheme] Loaded ${_strings.length} strings');
      }
    } catch (e) {
      debugPrint('⚠️ [RemoteTheme] Error loading strings: $e');
      _strings = await _loadStringsFromCache();
      debugPrint('📦 [RemoteTheme] Using ${_strings.length} cached strings');
    }
  }

  /// Carrega configurações do app
  Future<void> loadConfig() async {
    try {
      debugPrint('⚙️ [RemoteTheme] Loading config...');
      final response = await _api.invokeEdgeFunction('config');

      if (response['success'] == true && response['config'] != null) {
        _config = Map<String, dynamic>.from(response['config']);
        await _saveConfigToCache(_config);
        debugPrint('⚙️ [RemoteTheme] Loaded config');
      }
    } catch (e) {
      debugPrint('⚠️ [RemoteTheme] Error loading config: $e');
      _config = await _loadConfigFromCache();
    }
  }

  /// Inicializa tema completo
  Future<void> initialize() async {
    await Future.wait([
      loadTheme(),
      loadStrings('pt-BR'),
      loadConfig(),
    ]);
  }

  // ==================== GETTERS ====================
  
  /// Indica se o tema foi carregado com sucesso
  bool get hasTheme => _currentTheme != null;

  /// Obtém o tema remoto bruto
  RemoteThemeData? getRemoteTheme() => _currentTheme;

  /// Obtém string traduzida
  String getString(String key, {String fallback = ''}) {
    return _strings[key] ?? fallback;
  }

  /// Obtém valor de configuração
  T? getConfig<T>(String key) {
    return _config[key] as T?;
  }

  /// Obtém cor como Color do Flutter
  Color getColor(String colorKey) {
    if (_currentTheme == null) return Colors.black;

    final hexColor = _getColorHex(colorKey);
    return _hexToColor(hexColor);
  }

  String _getColorHex(String key) {
    final theme = _currentTheme!;
    switch (key) {
      case 'primary':
        return theme.colors.primary;
      case 'primaryBlue':
        return theme.colors.primaryBlue;
      case 'secondary':
        return theme.colors.secondary;
      case 'background':
        return theme.colors.background;
      case 'textPrimary':
        return theme.colors.textPrimary;
      case 'buttonPrimaryBg':
        return theme.colors.buttonPrimaryBg;
      case 'buttonPrimaryText':
        return theme.colors.buttonPrimaryText;
      case 'buttonOutlineColor':
        return theme.colors.buttonOutlineColor;
      case 'categoryTripBg':
        return theme.colors.categoryTripBg;
      case 'categoryServiceBg':
        return theme.colors.categoryServiceBg;
      case 'categoryPackageBg':
        return theme.colors.categoryPackageBg;
      case 'categoryReserveBg':
        return theme.colors.categoryReserveBg;
      default:
        return theme.colors.primary;
    }
  }

  /// Obtém raio de borda
  double getBorderRadius(String size) {
    if (_currentTheme == null) return 12;

    switch (size) {
      case 'small':
        return _currentTheme!.borders.radiusSmall;
      case 'medium':
        return _currentTheme!.borders.radiusMedium;
      case 'large':
        return _currentTheme!.borders.radiusLarge;
      case 'xlarge':
        return _currentTheme!.borders.radiusXLarge;
      default:
        return _currentTheme!.borders.radiusMedium;
    }
  }

  /// Obtém sombra padrão configurável remotamente
  List<BoxShadow> getShadow({double? customOpacity, double? customBlur}) {
    if (_currentTheme == null) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: customOpacity ?? 0.08),
          blurRadius: customBlur ?? 6,
          offset: const Offset(0, 3),
        ),
      ];
    }
    final s = _currentTheme!.borders;
    return [
      BoxShadow(
        color: _hexToColor(s.shadowColor).withValues(alpha: customOpacity ?? s.shadowOpacity),
        blurRadius: customBlur ?? s.shadowBlur,
        offset: Offset(s.shadowOffsetX, s.shadowOffsetY),
      ),
    ];
  }

  /// Obtém tamanho de fonte
  double getFontSize(String size) {
    if (_currentTheme == null) return 14;

    switch (size) {
      case 'tiny':
        return _currentTheme!.typography.sizeTiny;
      case 'small':
        return _currentTheme!.typography.sizeSmall;
      case 'medium':
        return _currentTheme!.typography.sizeMedium;
      case 'large':
        return _currentTheme!.typography.sizeLarge;
      case 'xlarge':
        return _currentTheme!.typography.sizeXLarge;
      case 'title':
        return _currentTheme!.typography.sizeTitle;
      default:
        return _currentTheme!.typography.sizeMedium;
    }
  }

  /// Gera ThemeData do Flutter
  ThemeData getThemeData() {
    if (_currentTheme == null) {
      return ThemeData.light();
    }

    final theme = _currentTheme!;

    return ThemeData(
      useMaterial3: true,
      primaryColor: _hexToColor(theme.colors.primary),
      scaffoldBackgroundColor: _hexToColor(theme.colors.background),
      colorScheme: ColorScheme.light(
        primary: _hexToColor(theme.colors.primary),
        secondary: _hexToColor(theme.colors.secondary),
        surface: _hexToColor(theme.colors.surface),
        error: _hexToColor(theme.colors.error),
        onPrimary: _hexToColor(theme.colors.buttonPrimaryText),
        onSurface: _hexToColor(theme.colors.textPrimary),
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(
          fontSize: theme.typography.sizeTitle,
          color: _hexToColor(theme.colors.textPrimary),
          fontWeight: FontWeight.bold,
        ),
        bodyLarge: TextStyle(
          fontSize: theme.typography.sizeLarge,
          color: _hexToColor(theme.colors.textPrimary),
        ),
        bodyMedium: TextStyle(
          fontSize: theme.typography.sizeMedium,
          color: _hexToColor(theme.colors.textPrimary),
        ),
        bodySmall: TextStyle(
          fontSize: theme.typography.sizeSmall,
          color: _hexToColor(theme.colors.textSecondary),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _hexToColor(theme.colors.buttonPrimaryBg),
          foregroundColor: _hexToColor(theme.colors.buttonPrimaryText),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.borders.radiusMedium),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _hexToColor(theme.colors.textPrimary),
          side: BorderSide(
            color: _hexToColor(theme.borders.color),
            width: theme.borders.width,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.borders.radiusMedium),
          ),
        ),
      ),
    );
  }

  // ==================== CACHE ====================

  Future<void> _saveThemeToCache(RemoteThemeData theme) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeyTheme, jsonEncode(theme.toJson()));
      await prefs.setInt(_cacheKeyThemeVersion, theme.version);
      debugPrint('💾 [RemoteTheme] Theme saved to cache');
    } catch (e) {
      debugPrint('⚠️ [RemoteTheme] Error saving theme to cache: $e');
    }
  }

  Future<RemoteThemeData?> _loadThemeFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKeyTheme);
      if (cached != null) {
        return RemoteThemeData.fromJson(jsonDecode(cached));
      }
    } catch (e) {
      debugPrint('⚠️ [RemoteTheme] Error loading theme from cache: $e');
    }
    return null;
  }

  Future<void> _saveStringsToCache(Map<String, String> strings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeyStrings, jsonEncode(strings));
    } catch (e) {
      debugPrint('⚠️ [RemoteTheme] Error saving strings: $e');
    }
  }

  Future<Map<String, String>> _loadStringsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKeyStrings);
      if (cached != null) {
        return Map<String, String>.from(jsonDecode(cached));
      }
    } catch (e) {
      debugPrint('⚠️ [RemoteTheme] Error loading strings: $e');
    }
    return {};
  }

  Future<void> _saveConfigToCache(Map<String, dynamic> config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeyConfig, jsonEncode(config));
    } catch (e) {
      debugPrint('⚠️ [RemoteTheme] Error saving config: $e');
    }
  }

  Future<Map<String, dynamic>> _loadConfigFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKeyConfig);
      if (cached != null) {
        return Map<String, dynamic>.from(jsonDecode(cached));
      }
    } catch (e) {
      debugPrint('⚠️ [RemoteTheme] Error loading config: $e');
    }
    return {};
  }

  // ==================== UTILS ====================

  Color _hexToColor(String colorString) {
    if (colorString.startsWith('rgba')) {
      try {
        final values = colorString
            .replaceAll('rgba(', '')
            .replaceAll(')', '')
            .split(',')
            .map((v) => v.trim())
            .toList();
        if (values.length == 4) {
          final r = int.parse(values[0]);
          final g = int.parse(values[1]);
          final b = int.parse(values[2]);
          final a = (double.parse(values[3]) * 255).round();
          return Color.fromARGB(a, r, g, b);
        }
      } catch (e) {
        debugPrint('⚠️ [RemoteTheme] Error parsing rgba: $colorString');
      }
    }

    var hex = colorString.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }

    try {
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      debugPrint('⚠️ [RemoteTheme] Invalid hex color: $colorString');
      return Colors.black;
    }
  }
}

// ==================== MODELS ====================

class RemoteThemeData {
  final int version;
  final String name;
  final ThemeColors colors;
  final ThemeBorders borders;
  final ThemeTypography typography;
  final ThemeSpacing spacing;

  RemoteThemeData({
    required this.version,
    required this.name,
    required this.colors,
    required this.borders,
    required this.typography,
    required this.spacing,
  });

  factory RemoteThemeData.fromJson(Map<String, dynamic> json) {
    return RemoteThemeData(
      version: json['version'] ?? 1,
      name: json['name'] ?? 'Default',
      colors: ThemeColors.fromJson(json['colors'] ?? {}),
      borders: ThemeBorders.fromJson(json['borders'] ?? {}),
      typography: ThemeTypography.fromJson(json['typography'] ?? {}),
      spacing: ThemeSpacing.fromJson(json['spacing'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'name': name,
      'colors': colors.toJson(),
      'borders': borders.toJson(),
      'typography': typography.toJson(),
      'spacing': spacing.toJson(),
    };
  }

  factory RemoteThemeData.defaultTheme() {
    return RemoteThemeData(
      version: 1,
      name: 'Default',
      colors: ThemeColors.defaultColors(),
      borders: ThemeBorders.defaultBorders(),
      typography: ThemeTypography.defaultTypography(),
      spacing: ThemeSpacing.defaultSpacing(),
    );
  }
}

class ThemeColors {
  final String primary;
  final String primaryBlue;
  final String secondary;
  final String background;
  final String surface;
  final String error;
  final String success;
  final String warning;
  final String textPrimary;
  final String textSecondary;
  final String textDisabled;
  final String textHint;
  final String buttonPrimaryBg;
  final String buttonPrimaryText;
  final String buttonSecondaryBg;
  final String buttonSecondaryText;
  final String buttonOutlineColor;
  final String categoryTripBg;
  final String categoryServiceBg;
  final String categoryPackageBg;
  final String categoryReserveBg;

  ThemeColors({
    required this.primary,
    required this.primaryBlue,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.error,
    required this.success,
    required this.warning,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.textHint,
    required this.buttonPrimaryBg,
    required this.buttonPrimaryText,
    required this.buttonSecondaryBg,
    required this.buttonSecondaryText,
    required this.buttonOutlineColor,
    required this.categoryTripBg,
    required this.categoryServiceBg,
    required this.categoryPackageBg,
    required this.categoryReserveBg,
  });

  factory ThemeColors.fromJson(Map<String, dynamic> json) {
    return ThemeColors(
      primary: json['primary'] ?? '#FFD700',
      primaryBlue: json['primaryBlue'] ?? '#2196F3',
      secondary: json['secondary'] ?? '#FFA500',
      background: json['background'] ?? '#FFFFFF',
      surface: json['surface'] ?? '#F5F5F5',
      error: json['error'] ?? '#FF0000',
      success: json['success'] ?? '#4CAF50',
      warning: json['warning'] ?? '#FF9800',
      textPrimary: json['textPrimary'] ?? '#000000',
      textSecondary: json['textSecondary'] ?? '#757575',
      textDisabled: json['textDisabled'] ?? '#BDBDBD',
      textHint: json['textHint'] ?? '#9E9E9E',
      buttonPrimaryBg: json['buttonPrimaryBg'] ?? '#FFD700',
      buttonPrimaryText: json['buttonPrimaryText'] ?? '#000000',
      buttonSecondaryBg: json['buttonSecondaryBg'] ?? '#FFFFFF',
      buttonSecondaryText: json['buttonSecondaryText'] ?? '#000000',
      buttonOutlineColor: json['buttonOutlineColor'] ?? '#000000',
      categoryTripBg: json['categoryTripBg'] ?? '#33FFD700',
      categoryServiceBg: json['categoryServiceBg'] ?? '#1A2196F3',
      categoryPackageBg: json['categoryPackageBg'] ?? '#1AFFA500',
      categoryReserveBg: json['categoryReserveBg'] ?? '#1A4CAF50',
    );
  }

  Map<String, dynamic> toJson() => {
        'primary': primary,
        'primaryBlue': primaryBlue,
        'secondary': secondary,
        'background': background,
        'surface': surface,
        'error': error,
        'success': success,
        'warning': warning,
        'textPrimary': textPrimary,
        'textSecondary': textSecondary,
        'textDisabled': textDisabled,
        'textHint': textHint,
        'buttonPrimaryBg': buttonPrimaryBg,
        'buttonPrimaryText': buttonPrimaryText,
        'buttonSecondaryBg': buttonSecondaryBg,
        'buttonSecondaryText': buttonSecondaryText,
        'buttonOutlineColor': buttonOutlineColor,
        'categoryTripBg': categoryTripBg,
        'categoryServiceBg': categoryServiceBg,
        'categoryPackageBg': categoryPackageBg,
        'categoryReserveBg': categoryReserveBg,
      };

  factory ThemeColors.defaultColors() {
    return ThemeColors.fromJson({});
  }
}

class ThemeBorders {
  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;
  final double radiusXLarge;
  final double width;
  final String color;
  // Shadow properties (configuráveis remotamente)
  final String shadowColor;
  final double shadowOpacity;
  final double shadowBlur;
  final double shadowOffsetX;
  final double shadowOffsetY;

  ThemeBorders({
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.radiusXLarge,
    required this.width,
    required this.color,
    required this.shadowColor,
    required this.shadowOpacity,
    required this.shadowBlur,
    required this.shadowOffsetX,
    required this.shadowOffsetY,
  });

  factory ThemeBorders.fromJson(Map<String, dynamic> json) {
    return ThemeBorders(
      radiusSmall: (json['radiusSmall'] ?? 8).toDouble(),
      radiusMedium: (json['radiusMedium'] ?? 12).toDouble(),
      radiusLarge: (json['radiusLarge'] ?? 16).toDouble(),
      radiusXLarge: (json['radiusXLarge'] ?? 24).toDouble(),
      width: (json['width'] ?? 2).toDouble(),
      color: json['color'] ?? '#000000',
      shadowColor: json['shadowColor'] ?? '#000000',
      shadowOpacity: (json['shadowOpacity'] ?? 0.08).toDouble(),
      shadowBlur: (json['shadowBlur'] ?? 6).toDouble(),
      shadowOffsetX: (json['shadowOffsetX'] ?? 0).toDouble(),
      shadowOffsetY: (json['shadowOffsetY'] ?? 3).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'radiusSmall': radiusSmall,
        'radiusMedium': radiusMedium,
        'radiusLarge': radiusLarge,
        'radiusXLarge': radiusXLarge,
        'width': width,
        'color': color,
        'shadowColor': shadowColor,
        'shadowOpacity': shadowOpacity,
        'shadowBlur': shadowBlur,
        'shadowOffsetX': shadowOffsetX,
        'shadowOffsetY': shadowOffsetY,
      };

  factory ThemeBorders.defaultBorders() {
    return ThemeBorders.fromJson({});
  }
}

class ThemeTypography {
  final String fontFamily;
  final double sizeTiny;
  final double sizeSmall;
  final double sizeMedium;
  final double sizeLarge;
  final double sizeXLarge;
  final double sizeTitle;

  ThemeTypography({
    required this.fontFamily,
    required this.sizeTiny,
    required this.sizeSmall,
    required this.sizeMedium,
    required this.sizeLarge,
    required this.sizeXLarge,
    required this.sizeTitle,
  });

  factory ThemeTypography.fromJson(Map<String, dynamic> json) {
    return ThemeTypography(
      fontFamily: json['fontFamily'] ?? 'Roboto',
      sizeTiny: (json['sizeTiny'] ?? 10).toDouble(),
      sizeSmall: (json['sizeSmall'] ?? 12).toDouble(),
      sizeMedium: (json['sizeMedium'] ?? 14).toDouble(),
      sizeLarge: (json['sizeLarge'] ?? 18).toDouble(),
      sizeXLarge: (json['sizeXLarge'] ?? 24).toDouble(),
      sizeTitle: (json['sizeTitle'] ?? 32).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'fontFamily': fontFamily,
        'sizeTiny': sizeTiny,
        'sizeSmall': sizeSmall,
        'sizeMedium': sizeMedium,
        'sizeLarge': sizeLarge,
        'sizeXLarge': sizeXLarge,
        'sizeTitle': sizeTitle,
      };

  factory ThemeTypography.defaultTypography() {
    return ThemeTypography.fromJson({});
  }
}

class ThemeSpacing {
  final double tiny;
  final double small;
  final double medium;
  final double large;
  final double xlarge;

  ThemeSpacing({
    required this.tiny,
    required this.small,
    required this.medium,
    required this.large,
    required this.xlarge,
  });

  factory ThemeSpacing.fromJson(Map<String, dynamic> json) {
    return ThemeSpacing(
      tiny: (json['tiny'] ?? 4).toDouble(),
      small: (json['small'] ?? 8).toDouble(),
      medium: (json['medium'] ?? 16).toDouble(),
      large: (json['large'] ?? 24).toDouble(),
      xlarge: (json['xlarge'] ?? 32).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'tiny': tiny,
        'small': small,
        'medium': medium,
        'large': large,
        'xlarge': xlarge,
      };

  factory ThemeSpacing.defaultSpacing() {
    return ThemeSpacing.fromJson({});
  }
}
