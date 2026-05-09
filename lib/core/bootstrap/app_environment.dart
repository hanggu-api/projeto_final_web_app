import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../firebase_options.dart';
import '../../services/notification_service.dart';
import '../config/supabase_config.dart';
import '../runtime/app_runtime_service.dart';
import '../utils/logger.dart';

class AppEnvironment {
  static Future<void> prepareRuntime() async {
    debugPrint = customDebugPrint;
    usePathUrlStrategy();
    WidgetsFlutterBinding.ensureInitialized();
    AppRuntimeService.instance.bootstrap();
    await _configureFonts();
    await _initializeBackendServices();
    installErrorWidget();
  }

  static Future<void> _configureFonts() async {
    if (kIsWeb) {
      GoogleFonts.config.allowRuntimeFetching = true;
      debugPrint('🌐 [Fonts] Web detectado. Runtime fetching ON.');
      return;
    }

    try {
      await rootBundle.load('assets/fonts/Manrope-Bold.ttf');
      GoogleFonts.config.allowRuntimeFetching = false;
      debugPrint('✅ [Fonts] Manrope local encontrada. Runtime fetching OFF.');
    } catch (_) {
      GoogleFonts.config.allowRuntimeFetching = true;
      debugPrint(
        '⚠️ [Fonts] Manrope local ausente no bundle. Runtime fetching ON.',
      );
    }
  }

  static Future<void> _initializeBackendServices() async {
    try {
      try {
        await SupabaseConfig.initialize();

        if (SupabaseConfig.isInitialized) {
          await _initializeMapbox();
          debugPrint('✅ [Main] Supabase initialized');
        } else {
          debugPrint(
            '❌ [Main] Supabase initialization failed; SUPABASE_URL/SUPABASE_ANON_KEY missing or invalid.',
          );
        }
      } catch (e) {
        debugPrint('⚠️ [Main] Supabase init failed (missing .env or keys): $e');
      }

      if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
        try {
          await _ensureFirebaseInitialized();
          FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler,
          );
          debugPrint('✅ [Main] Firebase initialized');
        } catch (e) {
          debugPrint('⚠️ [Main] Firebase init failed (não crítico): $e');
        }
      } else {
        debugPrint(
          'ℹ️ [Main] Firebase skipped on Desktop platform (${Platform.operatingSystem})',
        );
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
    }
  }

  static Future<void> _initializeMapbox() async {
    try {
      final mapboxToken = SupabaseConfig.mapboxToken;
      if (!kIsWeb &&
          (Platform.isAndroid || Platform.isIOS) &&
          mapboxToken.isNotEmpty) {
        mapbox.MapboxOptions.setAccessToken(mapboxToken);
        debugPrint('✅ [Main] Mapbox Access Token initialized');
      } else if (kIsWeb) {
        debugPrint('ℹ️ [Main] Mapbox SDK nativo ignorado no Web');
      } else if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        debugPrint(
          'ℹ️ [Main] Mapbox SDK nativo ignorado no Desktop (${Platform.operatingSystem})',
        );
      } else {
        debugPrint('⚠️ [Main] MAPBOX_TOKEN vazio; mapa pode não carregar');
      }
    } catch (e) {
      debugPrint('⚠️ [Main] Mapbox init error (não crítico): $e');
    }
  }

  static Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isNotEmpty) {
      debugPrint('ℹ️ [Main] Firebase já inicializado, reutilizando app padrão');
      return;
    }
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  static void installErrorWidget() {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      if (kDebugMode) {
        return MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.red.shade100,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Erro na Aplicação (Debug)',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        details.exceptionAsString(),
                        style: const TextStyle(color: Colors.black87),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 48),
                SizedBox(height: 16),
                Text(
                  'Algo deu errado.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Por favor, reinicie o aplicativo.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    };
  }
}
