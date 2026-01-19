import 'dart:convert';
import 'package:http/http.dart' as http;

class PhotonAutocompleteService {
  static const String _baseUrl = 'https://photon.komoot.io/api/';
  
  Future<List<Map<String, dynamic>>> search(String query, {
    double? lat,
    double? lon,
    String? countryCode = 'br', // Foca no Brasil
  }) async {
    if (query.length < 3) return [];
    
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'q': query,
      'limit': '5',
      'lang': 'pt',
      if (countryCode != null) 'countrycode': countryCode,
      if (lat != null && lon != null) 'lat': lat.toString(),
      if (lat != null && lon != null) 'lon': lon.toString(),
    });
    
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;
        
        return features.map((feature) {
          final props = feature['properties'];
          final geom = feature['geometry']['coordinates'];
          
          return {
            'label': props['name'] ?? '',
            'street': props['street'] ?? '',
            'city': props['city'] ?? props['state'] ?? '',
            'postcode': props['postcode'] ?? '',
            'country': props['country'] ?? 'Brasil',
            'latitude': geom[1] as double,
            'longitude': geom[0] as double,
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
              props['city']
            ].where((e) => e != null && e.toString().isNotEmpty).join(', '),
            'lat': geom[1],
            'lon': geom[0],
          };
        }).toList();
      }
    } catch (e) {
      print('❌ Erro no autocomplete (Photon): $e');
    }
    
    return [];
  }
}
