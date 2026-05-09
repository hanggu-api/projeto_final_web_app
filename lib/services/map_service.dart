import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import 'package:service_101/core/config/supabase_config.dart';

class MapService {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  final String _baseUrl = 'https://api.mapbox.com/directions/v5/mapbox/driving';

  // Timeout values tuned after seeing Mapbox requests occasionally take ~9-10s
  // on slower connections. We give Mapbox a little more time before falling
  // back so the UI does not surface a TimeoutException.
  static const _mapboxTimeout = Duration(seconds: 12);
  static const _tomtomTimeout = Duration(seconds: 8);

  Future<Map<String, dynamic>> getMultiPointRoute(List<LatLng> points) async {
    if (points.length < 2) {
      return {'points': points, 'distance': 0.0, 'duration': 0.0};
    }

    final token = SupabaseConfig.mapboxToken;
    final tomtomKey = SupabaseConfig.tomTomKey;

    if (token.isNotEmpty) {
      final String coordinates = points
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');
      // Usamos overview=full para ter o traçado preciso seguindo as ruas.
      final String url =
          '$_baseUrl/$coordinates?overview=full&geometries=geojson&steps=false&access_token=$token';

      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(_mapboxTimeout);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['routes'] != null && data['routes'].isNotEmpty) {
            final route = data['routes'][0];
            final Map<String, dynamic> geometry = route['geometry'];
            final List<dynamic> coords = geometry['coordinates'];
            final List<LatLng> parsedPoints = coords
                .map(
                  (c) => LatLng(
                    (c[1] as num).toDouble(),
                    (c[0] as num).toDouble(),
                  ),
                )
                .toList();

            if (parsedPoints.length >= 2) {
              return {
                'points': parsedPoints,
                'distance': (route['distance'] / 1000.0),
                'duration': (route['duration'] / 60.0),
              };
            }
          }
        }
        debugPrint(
          '⚠️ [MapService] Mapbox retornou status ${response.statusCode} ou poucos pontos.',
        );
      } catch (e) {
        debugPrint('❌ [MapService] Erro Mapbox: $e');
      }
    }

    // Fallback TomTom se Mapbox falhar ou retornar rota inválida
    if (tomtomKey.isNotEmpty && points.length >= 2) {
      try {
        final Map<String, dynamic>? tomtomRoute = await _getTomTomRoute(
          points,
          tomtomKey,
        );
        if (tomtomRoute != null) return tomtomRoute;
      } catch (e) {
        debugPrint('❌ [MapService] Erro TomTom Fallback: $e');
      }
    }

    return {'points': points, 'distance': 0.0, 'duration': 0.0};
  }

  Future<Map<String, dynamic>?> _getTomTomRoute(
    List<LatLng> points,
    String apiKey,
  ) async {
    double totalDistanceKm = 0.0;
    double totalDurationMin = 0.0;
    final List<LatLng> aggregatedPoints = [];

    for (int i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      final String startStr = '${start.latitude},${start.longitude}';
      final String endStr = '${end.latitude},${end.longitude}';

      final String url =
          'https://api.tomtom.com/routing/1/calculateRoute/$startStr:$endStr/json?key=$apiKey&routeType=fastest&travelMode=car';

      final response = await http
          .get(Uri.parse(url)).timeout(_tomtomTimeout);

      if (response.statusCode != 200) continue;

      final data = json.decode(response.body);
      if (data['routes'] == null || data['routes'].isEmpty) continue;

      final route = data['routes'][0];
      final List<dynamic> legs = route['legs'];
      final summary = route['summary'];

      for (final leg in legs) {
        final List<dynamic> legPoints = leg['points'];

        // Evita duplicar o ponto inicial entre segmentos consecutivos
        if (aggregatedPoints.isNotEmpty) {
          aggregatedPoints.removeLast();
        }

        aggregatedPoints.addAll(
          legPoints.map(
            (p) => LatLng(
              (p['latitude'] as num).toDouble(),
              (p['longitude'] as num).toDouble(),
            ),
          ),
        );
      }

      totalDistanceKm += (summary['lengthInMeters'] / 1000.0);
      totalDurationMin += (summary['travelTimeInSeconds'] / 60.0);
    }

    if (aggregatedPoints.length >= 2) {
      return {
        'points': aggregatedPoints,
        'distance': totalDistanceKm,
        'duration': totalDurationMin,
      };
    }

    return null;
  }

  /// Obtém a rota completa (pontos e métricas) entre duas coordenadas
  Future<Map<String, dynamic>> getRoute(LatLng start, LatLng end) async {
    return getMultiPointRoute([start, end]);
  }

  /// Obtém os pontos da rota (mantido para compatibilidade)
  Future<List<LatLng>> getRoutePoints(LatLng start, LatLng end) async {
    final res = await getRoute(start, end);
    return res['points'] as List<LatLng>;
  }
}
