import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class MapService {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  final String _baseUrl = 'https://api.mapbox.com/directions/v5/mapbox/driving';

  Future<Map<String, dynamic>> getMultiPointRoute(List<LatLng> points) async {
    if (points.length < 2) {
      return {'points': points, 'distance': 0.0, 'duration': 0.0};
    }

    final token = dotenv.env['MAPBOX_TOKEN'] ?? '';
    final tomtomKey = dotenv.env['TOMTOM_API_KEY'] ?? '';

    if (token.isNotEmpty) {
      final String coordinates = points
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');
      final String url =
          '$_baseUrl/$coordinates?overview=full&geometries=geojson&access_token=$token';

      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 8));
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

            if (parsedPoints.length > 2) {
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
    if (tomtomKey.isNotEmpty && points.length == 2) {
      try {
        final String start = '${points[0].latitude},${points[0].longitude}';
        final String end = '${points[1].latitude},${points[1].longitude}';
        final String ttUrl =
            'https://api.tomtom.com/routing/1/calculateRoute/$start:$end/json?key=$tomtomKey&routeType=fastest&travelMode=car';

        final response = await http
            .get(Uri.parse(ttUrl))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['routes'] != null && data['routes'].isNotEmpty) {
            final route = data['routes'][0];
            final List<dynamic> legs = route['legs'];
            final List<LatLng> ttPoints = [];

            for (var leg in legs) {
              final List<dynamic> points = leg['points'];
              ttPoints.addAll(
                points.map(
                  (p) => LatLng(
                    (p['latitude'] as num).toDouble(),
                    (p['longitude'] as num).toDouble(),
                  ),
                ),
              );
            }

            final summary = route['summary'];
            return {
              'points': ttPoints,
              'distance': (summary['lengthInMeters'] / 1000.0),
              'duration': (summary['travelTimeInSeconds'] / 60.0),
            };
          }
        }
      } catch (e) {
        debugPrint('❌ [MapService] Erro TomTom Fallback: $e');
      }
    }

    return {'points': points, 'distance': 0.0, 'duration': 0.0};
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
