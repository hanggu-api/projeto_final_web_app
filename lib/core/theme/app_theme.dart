import 'package:flutter/material.dart';
import '../../services/theme_service.dart';
import '../../services/remote_theme_service.dart';

class AppTheme {
  // ══════════════════════════════════════════════════════════
  // 101 Service Design System v1.0 (Stitch)
  // ══════════════════════════════════════════════════════════

  // Primary Palette
  static Color get primaryYellow => const Color(0xFFFFC107);
  static Color get primaryDark => primaryYellow;
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

  static const Color cardBorderColor = Color(0xFFE6ECF5);
  static const BorderSide cardBorderSide = BorderSide(
    color: cardBorderColor,
    width: 1.2,
  );

  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      blurRadius: 18,
      spreadRadius: 0,
      offset: const Offset(0, 6),
    ),
  ];

  static BoxBorder get cardBorder =>
      Border.all(color: cardBorderSide.color, width: cardBorderSide.width);

  static BoxDecoration get cardDecoration => BoxDecoration(
    color: surfaceWhite,
    borderRadius: BorderRadius.circular(borderRadius),
    border: cardBorder,
    boxShadow: cardShadow,
  );

  static BoxDecoration get cardDecorationElevated => BoxDecoration(
    color: surfaceWhite,
    borderRadius: BorderRadius.circular(borderRadiusLarge),
    border: cardBorder,
    boxShadow: cardShadow,
  );

  static BoxDecoration surfacedCardDecoration({
    Color color = surfaceWhite,
    double radius = borderRadiusLarge,
    BoxBorder? border,
    List<BoxShadow>? shadow,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: border ?? cardBorder,
      boxShadow: shadow ?? cardShadow,
    );
  }

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

  static InputDecoration authInputDecoration(
    String hint,
    IconData icon, {
    Widget? suffixIcon,
    bool hasError = false,
  }) {
    const borderRadiusValue = 18.0;
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadiusValue),
      borderSide: BorderSide(
        color: hasError ? errorRed.withOpacity(0.4) : const Color(0xFFE6ECF5),
        width: 1.2,
      ),
    );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: fontFamily,
        color: textMuted,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
      prefixIcon: Icon(icon, color: accentBlue, size: 21),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: surfaceWhite,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      border: baseBorder,
      enabledBorder: baseBorder,
      focusedBorder: baseBorder.copyWith(
        borderSide: BorderSide(
          color: primaryYellow.withOpacity(0.95),
          width: 2,
        ),
      ),
      errorBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: errorRed.withOpacity(0.75), width: 1.4),
      ),
      focusedErrorBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: errorRed, width: 1.8),
      ),
    );
  }

  static ButtonStyle primaryActionButtonStyle({
    double radius = 18,
    double height = 54,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: primaryYellow,
      foregroundColor: textDark,
      disabledBackgroundColor: primaryYellow.withOpacity(0.55),
      disabledForegroundColor: textDark.withOpacity(0.7),
      minimumSize: Size(double.infinity, height),
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      textStyle: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }

  static ButtonStyle secondaryActionButtonStyle({
    double radius = 18,
    double height = 54,
  }) {
    return OutlinedButton.styleFrom(
      backgroundColor: surfaceWhite,
      foregroundColor: textDark,
      minimumSize: Size(double.infinity, height),
      side: const BorderSide(color: Color(0xFFE6ECF5), width: 1.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      textStyle: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeService().currentThemeData;
  }
}
