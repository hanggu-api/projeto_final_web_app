import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class RemoteConfigService {
  static final _api = ApiService();
  
  // Cache constants
  static const String _kConfigCacheKey = 'app_config_cache';
  
  // Current loaded config state
  static Map<String, dynamic> _configs = {
    'enable_packages': false, // Default desativado
    'enable_reserve': false,  // Default desativado
    'search_radius_km': 50.0, // Default 50km
  };

  /// Initialize the service by loading the last cached configs to prevent UI jumps before network finishes
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedString = prefs.getString(_kConfigCacheKey);
      
      if (cachedString != null) {
        final decoded = json.decode(cachedString);
        if (decoded is Map<String, dynamic>) {
          _configs = decoded;
          debugPrint('🔧 [RemoteConfig] Configurações em cache carregadas: ${_configs.length} chaves');
        }
      }
      
      // Attempt background refresh silently
      _fetchRemoteConfig();
    } catch (e) {
      debugPrint('⚠️ [RemoteConfig] Erro ao carregar cache de config: $e');
    }
  }

  /// Pull latest config from API and save to SharedPreferences
  static Future<void> _fetchRemoteConfig() async {
    try {
      final response = await _api.get('/config');
      
      if (response['success'] == true && response['config'] != null) {
        final newConfigs = response['config'] as Map<String, dynamic>;
        
        // Update memory
        _configs = newConfigs;
        
        // Save to cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kConfigCacheKey, json.encode(_configs));
        
        debugPrint('✅ [RemoteConfig] Sincronizado com backend com sucesso.');
      }
    } catch (e) {
      debugPrint('⚠️ [RemoteConfig] Erro ao buscar configs remotos: $e');
    }
  }

  // --- Getters ---
  
  static bool get enablePackages => _configs['enable_packages'] ?? false;
  static bool get enableReserve => _configs['enable_reserve'] ?? false;
  static double get searchRadiusKm {
    final val = _configs['search_radius_km'];
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 50.0;
    return 50.0;
  }
  
  // Generic fallback if needed
  static dynamic getValue(String key, dynamic defaultValue) {
    return _configs[key] ?? defaultValue;
  }
}
