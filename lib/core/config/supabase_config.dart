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
  static const _compileGoogleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const _compileSignupVerifyToken = String.fromEnvironment(
    'SIGNUP_VERIFY_TOKEN',
  );
  static const bool allowLocalBackend = bool.fromEnvironment(
    'ALLOW_LOCAL_BACKEND',
    defaultValue: false,
  );

  static bool isLocalUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    final host = uri?.host.toLowerCase() ?? '';
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '10.0.2.2' ||
        host == '::1';
  }

  static String get url {
    final value = _compileUrl.isNotEmpty
        ? _compileUrl
        : dotenv.get('SUPABASE_URL', fallback: '');
    if (!allowLocalBackend && isLocalUrl(value)) return '';
    return value;
  }

  static String get anonKey => _compileKey.isNotEmpty
      ? _compileKey
      : dotenv.get('SUPABASE_ANON_KEY', fallback: '');
  static String get mapboxToken {
    if (_compileMapbox.isNotEmpty) return _compileMapbox;
    try {
      return dotenv.get('MAPBOX_TOKEN', fallback: '');
    } catch (_) {
      return '';
    }
  }

  static String get tomTomKey =>
      _compileTomTom.isNotEmpty ? _compileTomTom : dotenv.get('TOMTOM_API_KEY');
  static String get googleWebClientId {
    if (_compileGoogleWebClientId.isNotEmpty) return _compileGoogleWebClientId;
    try {
      return dotenv.get('GOOGLE_WEB_CLIENT_ID', fallback: '');
    } catch (_) {
      return '';
    }
  }

  static String get signupVerifyToken {
    if (_compileSignupVerifyToken.isNotEmpty) return _compileSignupVerifyToken;
    try {
      return dotenv.get('SIGNUP_VERIFY_TOKEN');
    } catch (_) {
      return '';
    }
  }

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  static Future<void> _tryLoadDotenv(String fileName) async {
    await dotenv.load(fileName: fileName);
    debugPrint('✅ [SupabaseConfig] env loaded from $fileName');
  }

  static Future<void> initialize({
    bool disableAuthAutoRefresh = false,
    bool detectSessionInUri = true,
  }) async {
    try {
      if (!dotenv.isInitialized) {
        try {
          // Tenta primeiro o assets/env/app.env (funciona em todas as plataformas)
          await _tryLoadDotenv('assets/env/app.env');
        } catch (primaryError) {
          debugPrint(
            '⚠️ [SupabaseConfig] assets/env/app.env load failed: $primaryError',
          );
          try {
            // Fallback para .env na raiz (desenvolvimento local via flutter run)
            await _tryLoadDotenv('.env');
          } catch (secondaryError) {
            debugPrint('⚠️ [SupabaseConfig] .env load failed: $secondaryError');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [SupabaseConfig] .env load error: $e');
    }

    String supabaseUrl = _compileUrl;
    String supabaseAnonKey = _compileKey;

    try {
      if (supabaseUrl.isEmpty) {
        supabaseUrl = dotenv.get('SUPABASE_URL', fallback: '');
      }
      if (supabaseAnonKey.isEmpty) {
        supabaseAnonKey = dotenv.get('SUPABASE_ANON_KEY', fallback: '');
      }
      if (!allowLocalBackend && isLocalUrl(supabaseUrl)) {
        debugPrint(
          '❌ [SupabaseConfig] URL local bloqueada. Use Supabase remoto online ou compile com ALLOW_LOCAL_BACKEND=true apenas em desenvolvimento.',
        );
        supabaseUrl = '';
      } else if (allowLocalBackend &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          (supabaseUrl.contains('127.0.0.1') ||
              supabaseUrl.contains('localhost'))) {
        supabaseUrl = supabaseUrl
            .replaceAll('127.0.0.1', '10.0.2.2')
            .replaceAll('localhost', '10.0.2.2');
      }
    } catch (e) {
      debugPrint('⚠️ [SupabaseConfig] Erro ao ler chaves do dotenv: $e');
    }

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      debugPrint(
        '❌ [SupabaseConfig] SUPABASE_URL/SUPABASE_ANON_KEY não encontradas via env ou compile-time.',
      );
      _initialized = false;
      return;
    }

    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        debug: kDebugMode,
        authOptions: FlutterAuthClientOptions(
          autoRefreshToken: !disableAuthAutoRefresh,
          detectSessionInUri: detectSessionInUri,
        ),
      );
      _initialized = true;
      debugPrint('✅ [SupabaseConfig] Supabase initialized | url=$supabaseUrl');
    } catch (e) {
      _initialized = false;
      debugPrint('❌ [SupabaseConfig] Supabase.initialize failed: $e');
    }
  }
}
