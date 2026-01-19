import 'package:flutter/material.dart';
import '../../services/theme_service.dart';
import '../../services/remote_theme_service.dart';

class AppTheme {
  // Cores extraídas da imagem enviada
  static Color get primaryYellow => ThemeService().currentConfig.primary; // Amarelo do fundo
  static Color get accentOrange => ThemeService().currentConfig.secondary; // Laranja do botão selecionado
  static Color get darkBlueText => ThemeService().currentConfig.textPrimary; // Azul do título "101 Service"
  static Color get lightGray => const Color(0xFFF3F4F6);

  // Adicionando cores faltantes para corrigir erros de compilação
  static Color get primaryPurple => ThemeService().currentConfig.textPrimary; // Mapeado para cor de texto principal (Azul/Verde Escuro)
  static Color get secondaryOrange => accentOrange; // Alias para accentOrange
  static Color get successGreen => ThemeService().currentConfig.success; // Verde sucesso
  static Color get primaryGreen => ThemeService().currentConfig.success; // Verde principal
  static Color get errorRed => ThemeService().currentConfig.error; // Vermelho erro
  static Color get textBrown => const Color(0xFF8B4513); // Texto marrom escuro
  static Color get primaryBlue => RemoteThemeService().getColor('primaryBlue');
  static Color get categoryTripBg => RemoteThemeService().getColor('categoryTripBg');
  static Color get categoryServiceBg => RemoteThemeService().getColor('categoryServiceBg');
  static Color get categoryPackageBg => RemoteThemeService().getColor('categoryPackageBg');
  static Color get categoryReserveBg => RemoteThemeService().getColor('categoryReserveBg');

  static Color get darkGray => const Color(0xFF4B5563);

  static InputDecoration inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: primaryPurple),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: primaryPurple, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  static ThemeData get lightTheme {
    return ThemeService().currentThemeData;
  }
}
