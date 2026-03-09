import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'remote_config_service.dart';

class PhotonAutocompleteService {
  static const String _baseUrl = 'https://photon.komoot.io/api/';

  // Fórmula de Haversine para calcular distância em km
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0; // Raio da Terra em km
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  Future<List<Map<String, dynamic>>> search(
    String query, {
    double? lat,
    double? lon,
    String? countryCode = 'br', // Foca no Brasil
  }) async {
    if (query.length < 3) return [];

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'q': query,
        'limit':
            '15', // Maior limite para compensar os itens filtrados pelo raio
        'lang': 'pt',
        'countrycode': countryCode,
        'lat': lat?.toString(),
        'lon': lon?.toString(),
      },
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;
        final maxRadiusKm = RemoteConfigService.searchRadiusKm;

        final List<Map<String, dynamic>> results = [];

        for (var feature in features) {
          final props = feature['properties'];
          final geom = feature['geometry']['coordinates'];
          final double rLat = geom[1] as double;
          final double rLon = geom[0] as double;

          if (lat != null && lon != null) {
            final distanceKm = _calculateDistance(lat, lon, rLat, rLon);
            if (distanceKm > maxRadiusKm) {
              continue; // Ignora se estiver fora do raio permitido
            }
          }

          results.add({
            'label': props['name'] ?? '',
            'street': props['street'] ?? '',
            'city': props['city'] ?? props['state'] ?? '',
            'postcode': props['postcode'] ?? '',
            'country': props['country'] ?? 'Brasil',
            'latitude': rLat,
            'longitude': rLon,
            'fullAddress': [
              props['name'],
              props['street'],
              props['housenumber'],
              props['postcode'],
              props['city'],
              props['state'],
            ].where((e) => e != null && e.toString().isNotEmpty).join(', '),
            // Compatibility fields with HomeScreen's existing expectations
            'display_name': [
              props['name'],
              props['street'],
              props['city'],
            ].where((e) => e != null && e.toString().isNotEmpty).join(', '),
            'lat': rLat,
            'lon': rLon,
            'category':
                '${props['osm_value'] ?? ''} ${props['osm_key'] ?? ''} ${props['type'] ?? ''}'
                    .toLowerCase(),
          });
        }

        return results.take(5).toList(); // Retorna no máximo 5 após o filtro
      }
    } catch (e) {
      debugPrint('❌ Erro no autocomplete (Photon): $e');
    }

    return [];
  }
}
