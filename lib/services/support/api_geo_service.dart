import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/supabase_config.dart';

typedef EdgeFunctionInvoker =
    Future<dynamic> Function(
      String functionName, [
      Map<String, dynamic>? body,
      Map<String, String>? queryParams,
    ]);

class ApiGeoService {
  ApiGeoService({required EdgeFunctionInvoker invokeEdgeFunction})
    : _invokeEdgeFunction = invokeEdgeFunction;

  final EdgeFunctionInvoker _invokeEdgeFunction;
  final http.Client _client = http.Client();

  Future<void> registerProviderLocation(
    int providerId, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _invokeEdgeFunction('location', {
        'provider_id': providerId,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('⚠️ [ApiGeoService] registerProviderLocation: $e');
    }
  }

  Future<Map<String, dynamic>> reverseGeocode(double lat, double lon) async {
    try {
      debugPrint(
        '📍 [ApiGeoService] reverseGeocode(edge) lat=${lat.toStringAsFixed(6)} lon=${lon.toStringAsFixed(6)}',
      );
      final result = await _invokeEdgeFunction('geo', null, {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'path': 'reverse',
      });
      if (result is Map<String, dynamic>) {
        debugPrint('📍 [ApiGeoService] reverseGeocode(edge) response=$result');
        if (_hasUsefulAddress(result)) return result;
      } else {
        debugPrint(
          '⚠️ [ApiGeoService] reverseGeocode(edge) tipo inesperado: ${result.runtimeType}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ [ApiGeoService] reverseGeocode(edge) erro: $e');
    }

    return _reverseGeocodeWithMapbox(lat, lon);
  }

  Future<List<dynamic>> searchAddress(
    String query, {
    double? lat,
    double? lon,
    double? radiusKm,
  }) async {
    final params = <String, String>{'q': query, 'path': 'search'};
    if (lat != null && lon != null) {
      params['proximity'] = '$lat,$lon';
      params['radius'] = (radiusKm ?? 50).toString();
      debugPrint(
        '📍 [ApiGeoService] Buscando endereço: "$query" Proximidade: $lat,$lon Raio: ${radiusKm ?? 50}km',
      );
    } else {
      debugPrint(
        '📍 [ApiGeoService] Buscando endereço: "$query" (Sem coordenadas de proximidade)',
      );
    }
    final result = await _invokeEdgeFunction('geo', null, params);
    if (result is List) return result;
    return [];
  }

  Future<void> registerAddressInRegistry({
    required String fullAddress,
    String? streetName,
    String? streetNumber,
    String? neighborhood,
    String? city,
    String? stateCode,
    String? poiName,
    required double lat,
    required double lon,
    String? category,
  }) async {
    try {
      await _invokeEdgeFunction('geo', {
        'action': 'register',
        'full_address': fullAddress,
        'street_name': streetName,
        'street_number': streetNumber,
        'neighborhood': neighborhood,
        'city': city ?? 'Imperatriz',
        'state_code': stateCode ?? 'MA',
        'poi_name': poiName,
        'lat': lat,
        'lon': lon,
        'category': category,
      });
      debugPrint('📍 [GeoRegistry] Local registrado: $fullAddress');
    } catch (e) {
      debugPrint('⚠️ [GeoRegistry] Erro ao registrar local: $e');
    }
  }

  bool _hasUsefulAddress(Map<String, dynamic> map) {
    final keys = [
      'street',
      'road',
      'display_name',
      'city',
      'neighborhood',
      'suburb',
    ];
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> _reverseGeocodeWithMapbox(
    double lat,
    double lon,
  ) async {
    final mapboxToken = SupabaseConfig.mapboxToken.trim();
    if (mapboxToken.isEmpty) {
      debugPrint(
        '⚠️ [ApiGeoService] MAPBOX_TOKEN vazio no app; sem fallback direto',
      );
      return {};
    }

    try {
      final uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lon,$lat.json'
        '?access_token=$mapboxToken&types=address,poi&limit=5&language=pt',
      );
      debugPrint('🔁 [ApiGeoService] reverseGeocode(fallback-mapbox) uri=$uri');
      final resp = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(resp.body);
      final features =
          decoded is Map<String, dynamic> && decoded['features'] is List
          ? decoded['features'] as List
          : const [];
      final feature = features.cast<dynamic>().firstWhere(
        (f) =>
            f is Map<String, dynamic> &&
            f['place_type'] is List &&
            (f['place_type'] as List).contains('address'),
        orElse: () => features.isNotEmpty ? features.first : null,
      );
      if (feature is Map<String, dynamic>) {
        final canonical = _mapboxToCanonical(feature);
        debugPrint(
          '📍 [ApiGeoService] reverseGeocode(fallback-mapbox) response=$canonical',
        );
        return canonical;
      }
      debugPrint(
        '⚠️ [ApiGeoService] reverseGeocode(fallback-mapbox) sem features úteis body=${resp.body}',
      );
    } catch (e) {
      debugPrint('❌ [ApiGeoService] reverseGeocode(fallback-mapbox) erro: $e');
    }

    return {};
  }

  Map<String, dynamic> _mapboxToCanonical(Map<String, dynamic> feat) {
    final context = (feat['context'] is List)
        ? feat['context'] as List
        : const [];
    Map<String, dynamic>? findCtx(String prefix) {
      for (final item in context) {
        if (item is Map<String, dynamic>) {
          final id = (item['id'] ?? '').toString();
          if (id.startsWith(prefix)) return item;
        }
      }
      return null;
    }

    final region = findCtx('region');
    final place = findCtx('place') ?? findCtx('locality');
    final neighborhood =
        findCtx('neighborhood') ?? findCtx('district') ?? findCtx('locality');

    final stateCodeRaw = (region?['short_code'] ?? '').toString();
    final stateCode = stateCodeRaw.contains('-')
        ? stateCodeRaw.split('-').last.toUpperCase()
        : stateCodeRaw.toUpperCase();

    return {
      'display_name': (feat['place_name'] ?? '').toString(),
      'street': (feat['text'] ?? '').toString(),
      'house_number': (feat['address'] ?? '').toString(),
      'neighborhood': (neighborhood?['text'] ?? '').toString(),
      'suburb': (neighborhood?['text'] ?? '').toString(),
      'neighbourhood': (neighborhood?['text'] ?? '').toString(),
      'city': (place?['text'] ?? '').toString(),
      'state': (region?['text'] ?? '').toString(),
      'state_code': stateCode,
    };
  }
}
