import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config_entry.dart';
import '../core/config/supabase_config.dart';
import '../core/constants/table_names.dart';
import '../core/runtime/app_runtime_service.dart';

class RemoteConfigService {
  static const String _kConfigCacheKey = 'app_config_cache';
  static const String _defaultPlatformScope = 'all';

  static Map<String, dynamic> _configs = {
    'enable_packages': false,
    'enable_reserve': false,
    'search_radius_km': 50.0,
    'flag.remote_ui.enabled': true,
    'flag.remote_ui.help.enabled': true,
    'flag.remote_ui.home_explore.enabled': true,
    'flag.remote_ui.driver_home.enabled': true,
    'flag.remote_ui.provider_search.enabled': true,
    'flag.remote_ui.service_payment.enabled': true,
    'kill_switch.remote_ui.help': false,
    'kill_switch.remote_ui.home_explore': false,
    'kill_switch.remote_ui.driver_home': false,
    'kill_switch.remote_ui.provider_search': false,
    'kill_switch.remote_ui.service_payment': false,
  };

  static Map<String, AppConfigEntry> _entries = <String, AppConfigEntry>{};

  static String get _platformScope =>
      defaultTargetPlatform.name.toLowerCase().trim();

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedString = prefs.getString(_kConfigCacheKey);

      if (cachedString != null) {
        _restoreCache(cachedString);
        debugPrint(
          '🔧 [RemoteConfig] Configurações em cache carregadas: ${_configs.length} chaves',
        );
      }

      AppRuntimeService.instance.updateActiveFlags(activeFlagsSnapshot());
      _fetchRemoteConfig();
    } catch (e, stackTrace) {
      debugPrint('⚠️ [RemoteConfig] Erro ao carregar cache de config: $e');
      AppRuntimeService.instance.logConfigFailure(
        'remote_config:init_cache',
        e,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> _fetchRemoteConfig() async {
    if (!SupabaseConfig.isInitialized) {
      debugPrint(
        '⚠️ [RemoteConfig] Refresh remoto ignorado: Supabase não inicializado',
      );
      return;
    }
    try {
      final client = Supabase.instance.client;
      final List<dynamic> response = await client
          .from(TableNames.appConfigs)
          .select('key, value, category, platform_scope, is_active, revision');

      if (response.isEmpty) return;

      final Map<String, dynamic> newConfigs = <String, dynamic>{};
      final Map<String, AppConfigEntry> newEntries =
          <String, AppConfigEntry>{};

      for (final item in response) {
        final row = _readMap(item);
        final entry = AppConfigEntry.fromRow(row);
        if (entry.key.isEmpty ||
            !entry.isActive ||
            !entry.matchesPlatform(_platformScope)) {
          continue;
        }

        newConfigs[entry.key] = entry.value;
        newEntries[entry.key] = entry;
      }

      if (newConfigs.isEmpty) return;

      _configs = {..._defaultConfigs, ...newConfigs};
      _entries = newEntries;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kConfigCacheKey,
        jsonEncode({
          'configs': _configs,
          'entries': _entries.map(
            (key, entry) => MapEntry(key, entry.toSnapshotJson()),
          ),
        }),
      );

      AppRuntimeService.instance.updateActiveFlags(activeFlagsSnapshot());
      debugPrint('✅ [RemoteConfig] Sincronizado com Supabase com sucesso.');
    } catch (e, stackTrace) {
      debugPrint(
        '⚠️ [RemoteConfig] Erro ao buscar configs remotos do Supabase: $e',
      );
      AppRuntimeService.instance.logConfigFailure(
        'remote_config:fetch',
        e,
        stackTrace: stackTrace,
      );
    }
  }

  static Map<String, bool> activeFlagsSnapshot() {
    final flags = <String, bool>{};
    for (final entry in _entries.entries) {
      final key = entry.key;
      if (_isFlagKey(key) || _isKillSwitchKey(key)) {
        flags[key] = entry.value.boolValue(
          fallback: _defaultConfigs[key] == true,
        );
      }
    }

    for (final key in _defaultConfigs.keys) {
      if (_isFlagKey(key) || _isKillSwitchKey(key)) {
        flags.putIfAbsent(key, () => _readBool(_configs[key], fallback: false));
      }
    }

    return flags;
  }

  static bool isRemoteUiEnabledForScreen(String screenKey) {
    final normalized = screenKey.trim().toLowerCase();
    final globalFlag = getBool('flag.remote_ui.enabled', defaultValue: true);
    final screenFlag = getBool(
      'flag.remote_ui.$normalized.enabled',
      defaultValue: true,
    );
    final globalKillSwitch = getBool(
      'kill_switch.remote_ui.global',
      defaultValue: false,
    );
    final screenKillSwitch = getBool(
      'kill_switch.remote_ui.$normalized',
      defaultValue: false,
    );

    return globalFlag && screenFlag && !globalKillSwitch && !screenKillSwitch;
  }

  static bool get enablePackages =>
      getBool('enable_packages', defaultValue: false);
  static bool get enableReserve =>
      getBool('enable_reserve', defaultValue: false);

  static double get searchRadiusKm {
    return getDouble('search_radius_km', defaultValue: 50.0);
  }

  static bool getBool(String key, {required bool defaultValue}) {
    return _readBool(_configs[key], fallback: defaultValue);
  }

  static int getInt(String key, {required int defaultValue}) {
    final raw = _configs[key];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? defaultValue;
  }

  static double getDouble(String key, {required double defaultValue}) {
    final raw = _configs[key];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? defaultValue;
  }

  static dynamic getValue(String key, dynamic defaultValue) {
    return _configs[key] ?? defaultValue;
  }

  static Map<String, dynamic> get snapshotJson {
    return {
      'platform_scope': _platformScope.isEmpty
          ? _defaultPlatformScope
          : _platformScope,
      'configs': _configs,
      'entries': _entries.map(
        (key, value) => MapEntry(key, value.toSnapshotJson()),
      ),
    };
  }

  static Map<String, dynamic> get _defaultConfigs => {
    'enable_packages': false,
    'enable_reserve': false,
    'search_radius_km': 50.0,
    'flag.remote_ui.enabled': true,
    'flag.remote_ui.help.enabled': true,
    'flag.remote_ui.home_explore.enabled': true,
    'flag.remote_ui.driver_home.enabled': true,
    'flag.remote_ui.provider_search.enabled': true,
    'flag.remote_ui.service_payment.enabled': true,
    'kill_switch.remote_ui.global': false,
    'kill_switch.remote_ui.help': false,
    'kill_switch.remote_ui.home_explore': false,
    'kill_switch.remote_ui.driver_home': false,
    'kill_switch.remote_ui.provider_search': false,
    'kill_switch.remote_ui.service_payment': false,
  };

  static void _restoreCache(String cachedString) {
    final decoded = json.decode(cachedString);
    if (decoded is! Map) return;

    final payload = decoded.map((key, value) => MapEntry('$key', value));
    final cachedConfigs = payload['configs'];
    if (cachedConfigs is Map) {
      _configs = {
        ..._defaultConfigs,
        ...cachedConfigs.map((key, value) => MapEntry('$key', value)),
      };
    } else if (payload.isNotEmpty) {
      _configs = {
        ..._defaultConfigs,
        ...payload,
      };
    }

    final cachedEntries = payload['entries'];
    if (cachedEntries is Map) {
      _entries = cachedEntries.map((key, value) {
        final row = _readMap(value);
        return MapEntry('$key', AppConfigEntry.fromRow({...row, 'key': '$key'}));
      });
    }
  }

  static Map<String, dynamic> _readMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry('$key', value));
    }
    return const <String, dynamic>{};
  }

  static bool _readBool(dynamic raw, {required bool fallback}) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final text = raw?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return fallback;
  }

  static bool _isFlagKey(String key) =>
      key.startsWith('flag.') || key.startsWith('feature.');

  static bool _isKillSwitchKey(String key) => key.startsWith('kill_switch.');
}
