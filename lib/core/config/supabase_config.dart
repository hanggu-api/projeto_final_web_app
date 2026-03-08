import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class SupabaseConfig {
  // Lidas em tempo de compilação via --dart-define (produção)
  // Fallback para .env (desenvolvimento local)
  static const _compileUrl = String.fromEnvironment('SUPABASE_URL');
  static const _compileKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _compileMapbox = String.fromEnvironment('MAPBOX_TOKEN');
  static const _compileTomTom = String.fromEnvironment('TOMTOM_API_KEY');

  // Credenciais hardcoded removidas para segurança (GitHub Secret Scanning)
  static const _defaultUrl = '';
  static const _defaultKey = '';
  static const _defaultMapbox = '';
  static const _defaultTomTom = '';

  static Future<void> initialize() async {
    // Prioridade: --dart-define > .env > hardcoded
    String supabaseUrl = _compileUrl.isNotEmpty ? _compileUrl : _defaultUrl;
    String supabaseAnonKey = _compileKey.isNotEmpty ? _compileKey : _defaultKey;

    // Tenta sobrescrever com .env (apenas no debug/localhost)
    if (!kIsWeb || _compileUrl.isEmpty) {
      try {
        await dotenv.load(fileName: '.env');
        final envUrl = dotenv.env['SUPABASE_URL'];
        final envKey = dotenv.env['SUPABASE_ANON_KEY'];
        if (envUrl != null && envUrl.isNotEmpty) supabaseUrl = envUrl;
        if (envKey != null && envKey.isNotEmpty) supabaseAnonKey = envKey;
      } catch (_) {
        // .env não disponível — usa compile-time ou hardcoded
      }
    }

    debugPrint(
      '✅ [Supabase] Inicializando com: ${supabaseUrl.substring(0, 30)}...',
    );

    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
  static String get anonKey =>
      _compileKey.isNotEmpty ? _compileKey : _defaultKey;
  static String get url => _compileUrl.isNotEmpty ? _compileUrl : _defaultUrl;

  static String get mapboxToken => _compileMapbox.isNotEmpty
      ? _compileMapbox
      : (dotenv.env['MAPBOX_TOKEN'] ?? _defaultMapbox);

  static String get tomTomKey => _compileTomTom.isNotEmpty
      ? _compileTomTom
      : (dotenv.env['TOMTOM_API_KEY'] ?? _defaultTomTom);
}
