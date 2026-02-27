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

  /// Obtém a rota entre múltiplos pontos (waypoints)
  Future<Map<String, dynamic>> getMultiPointRoute(List<LatLng> points) async {
    if (points.length < 2) return {'points': points, 'distance': 0.0, 'duration': 0.0};
    
    final token = dotenv.env['MAPBOX_TOKEN'];
    if (token == null || token.isEmpty) {
      return {
        'points': points,
        'distance': 0.0,
        'duration': 0.0,
      };
    }

    final String coordinates = points.map((p) => '${p.longitude},${p.latitude}').join(';');
    final String url =
        '$_baseUrl/$coordinates?overview=full&geometries=polyline&access_token=$token';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final String encodedPolyline = route['geometry'];
          return {
            'points': _decodePolyline(encodedPolyline),
            'distance': (route['distance'] / 1000.0), // Converter para km
            'duration': (route['duration'] / 60.0), // Converter para min
          };
        }
      }
    } catch (e) {
      debugPrint('❌ [MapService] Falha ao buscar multi-rota: $e');
    }

    return {
      'points': points,
      'distance': 0.0,
      'duration': 0.0,
    };
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

  /// Decodifica uma string de polyline (algoritmo padrão do Google/Mapbox)
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
