import 'package:flutter/material.dart';
import '../../services/theme_service.dart';
import '../../services/remote_theme_service.dart';

class AppTheme {
  // ══════════════════════════════════════════════════════════
  // 101 Service Design System v1.0 (Stitch)
  // ══════════════════════════════════════════════════════════

  // Primary Palette
  static Color get primaryYellow => const Color(0xFFFFD700);
  static Color get primaryDark => const Color(0xFFE6C200);
  static Color get accentOrange => ThemeService().currentConfig.secondary;
  static const Color accentBlue = Color(0xFF427CF0);

  // Text Colors
  static Color get darkBlueText => const Color(0xFF0F172A);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textLight = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF64748B);

  // Surface & Background
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color backgroundLight = Color(0xFFF8F9FC); // v1.0 background
  static const Color backgroundDark = Color(0xFF101622);
  static Color get lightGray => const Color(0xFFF3F4F6);

  // Status Colors
  static Color get successGreen =>
      const Color(0xFF10B981); // Emerald-600 inspired
  static Color get primaryGreen => const Color(0xFF22C55E);
  static Color get errorRed => const Color(0xFFEF4444);
  static Color get warningOrange => const Color(0xFFF59E0B);

  // Aliases (backward compat)
  static Color get primaryPurple => ThemeService().currentConfig.textPrimary;
  static Color get secondaryOrange => accentOrange;
  static Color get textBrown => const Color(0xFF8B4513);
  static Color get primaryBlue => RemoteThemeService().getColor('primaryBlue');
  static Color get categoryTripBg =>
      RemoteThemeService().getColor('categoryTripBg');
  static Color get categoryServiceBg =>
      RemoteThemeService().getColor('categoryServiceBg');
  static Color get categoryPackageBg =>
      RemoteThemeService().getColor('categoryPackageBg');
  static Color get categoryReserveBg =>
      RemoteThemeService().getColor('categoryReserveBg');
  static Color get darkGray => const Color(0xFF4B5563);

  // ══════════════════════════════════════════════════════════
  // Typography (Manrope)
  // ══════════════════════════════════════════════════════════

  static const String fontFamily = 'Manrope';

  static TextStyle get displayLarge => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 36,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.0,
    color: textDark,
  );

  static TextStyle get headingMedium => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: textDark,
  );

  static TextStyle get subheading => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textDark,
  );

  static TextStyle get bodyText => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: textDark,
  );

  static TextStyle get bodySmall => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textMuted,
  );

  static TextStyle get caption => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textMuted,
  );

  // ══════════════════════════════════════════════════════════
  // Component Styles
  // ══════════════════════════════════════════════════════════

  static const double borderRadius = 12.0; // DEFAULT 0.75rem
  static const double borderRadiusLarge = 16.0; // LG 1rem
  static const double borderRadiusXL = 24.0; // XL 1.5rem
  static const double borderRadiusXXL =
      32.0; // Manual adjustment for specific cards

  static BoxDecoration get cardDecoration => BoxDecoration(
    color: surfaceWhite,
    borderRadius: BorderRadius.circular(borderRadius),
    boxShadow: const [
      BoxShadow(
        color: Color(0x0A000000),
        blurRadius: 10,
        spreadRadius: 0,
        offset: Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration get cardDecorationElevated => BoxDecoration(
    color: surfaceWhite,
    borderRadius: BorderRadius.circular(borderRadiusLarge),
    boxShadow: const [
      BoxShadow(
        color: Color(0x14000000),
        blurRadius: 20,
        spreadRadius: 0,
        offset: Offset(0, 8),
      ),
    ],
  );

  static InputDecoration inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: darkGray, fontFamily: fontFamily),
      prefixIcon: Icon(icon, color: darkGray),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: darkBlueText, width: 1.5),
      ),
      filled: true,
      fillColor: backgroundLight,
    );
  }

  static ThemeData get lightTheme {
    return ThemeService().currentThemeData;
  }
}
