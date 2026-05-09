import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../../services/analytics_service.dart';
import '../utils/logger.dart';
import 'app_runtime_snapshot.dart';

class AppRuntimeService {
  AppRuntimeService._internal();

  static final AppRuntimeService instance = AppRuntimeService._internal();

  static const String storeVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.2+6',
  );
  static const String patchVersion = String.fromEnvironment(
    'SHOREBIRD_PATCH_NUMBER',
    defaultValue: 'store',
  );
  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );

  AppRuntimeSnapshot _snapshot = const AppRuntimeSnapshot(
    storeVersion: storeVersion,
    patchVersion: patchVersion,
    environment: environment,
    activeFlags: <String, bool>{},
    remoteScreenSources: <String, String>{},
  );

  AppRuntimeSnapshot get snapshot => _snapshot;

  String get runtimeLabel =>
      'store=$storeVersion patch=$patchVersion env=$environment';

  void bootstrap() {
    AppLogger.sistema('🚀 [Runtime] Snapshot inicializado | $runtimeLabel');
    _applyCrashlyticsContext();
  }

  void updateActiveFlags(Map<String, bool> flags) {
    _snapshot = _snapshot.copyWith(
      activeFlags: Map<String, bool>.unmodifiable(Map<String, bool>.from(flags)),
    );
    AppLogger.sistema(
      '🎛️ [Runtime] Flags ativas carregadas: ${_snapshot.activeFlags}',
    );
    _applyCrashlyticsContext();
  }

  void recordRemoteScreenSource(
    String screenKey,
    String source, {
    String? revision,
    bool logAnalytics = true,
  }) {
    final previousSource = _snapshot.remoteScreenSources[screenKey];
    final nextSources = Map<String, String>.from(_snapshot.remoteScreenSources);
    nextSources[screenKey] = source;
    _snapshot = _snapshot.copyWith(
      remoteScreenSources: Map<String, String>.unmodifiable(nextSources),
    );

    AppLogger.sistema(
      '🧭 [Runtime] Tela remota $screenKey resolvida via $source'
      '${revision == null || revision.isEmpty ? '' : ' rev=$revision'}',
    );
    _applyCrashlyticsContext();

    if (logAnalytics && previousSource != source) {
      AnalyticsService().logEvent(
        'REMOTE_SCREEN_SOURCE_RECORDED',
        details: {
          'screen_key': screenKey,
          'source': source,
          'revision': revision,
          'patch_version': patchVersion,
          'store_version': storeVersion,
        },
      );
    }
  }

  void logConfigFailure(
    String scope,
    Object error, {
    StackTrace? stackTrace,
  }) {
    AppLogger.erro('Falha operacional em $scope', error);
    if (!kIsWeb) {
      try {
        FirebaseCrashlytics.instance.recordError(
          error,
          stackTrace,
          reason: 'runtime_scope:$scope',
          fatal: false,
        );
      } catch (_) {
        // Crashlytics opcional; preservar a execução local.
      }
    }
  }

  void _applyCrashlyticsContext() {
    if (kIsWeb) return;
    try {
      FirebaseCrashlytics.instance.setCustomKey(
        'app_store_version',
        _snapshot.storeVersion,
      );
      FirebaseCrashlytics.instance.setCustomKey(
        'app_patch_version',
        _snapshot.patchVersion,
      );
      FirebaseCrashlytics.instance.setCustomKey(
        'app_environment',
        _snapshot.environment,
      );
      FirebaseCrashlytics.instance.setCustomKey(
        'runtime_active_flags',
        _snapshot.activeFlags.entries
            .map((entry) => '${entry.key}:${entry.value}')
            .join(','),
      );
      FirebaseCrashlytics.instance.setCustomKey(
        'runtime_remote_sources',
        _snapshot.remoteScreenSources.entries
            .map((entry) => '${entry.key}:${entry.value}')
            .join(','),
      );
    } catch (_) {
      // Crashlytics é melhor esforço; não deve interromper o fluxo.
    }
  }
}
