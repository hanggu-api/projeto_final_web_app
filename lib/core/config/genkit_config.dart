import 'package:flutter_dotenv/flutter_dotenv.dart';

class GenkitConfig {
  static const _compileGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _compileGenkitModel = String.fromEnvironment(
    'GENKIT_GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );

  static String get geminiApiKey {
    if (_compileGeminiApiKey.isNotEmpty) return _compileGeminiApiKey;
    try {
      return dotenv.get('GEMINI_API_KEY', fallback: '');
    } catch (_) {
      return '';
    }
  }

  static String get defaultModel {
    if (_compileGenkitModel.isNotEmpty) return _compileGenkitModel;
    try {
      return dotenv.get('GENKIT_GEMINI_MODEL', fallback: 'gemini-2.5-flash');
    } catch (_) {
      return 'gemini-2.5-flash';
    }
  }

  static bool get isConfigured => geminiApiKey.trim().isNotEmpty;
}
