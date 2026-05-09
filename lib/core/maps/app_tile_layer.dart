import 'package:flutter_map/flutter_map.dart';

class AppTileLayer {
  static const List<String> _fallbackTileUrls = [
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
  ];

  static TileLayer standard({required String mapboxToken}) {
    return standardWithFallback(mapboxToken: mapboxToken, variant: 0);
  }

  static TileLayer lightweight() {
    return TileLayer(
      urlTemplate: _fallbackTileUrls.first,
      userAgentPackageName: 'br.com.play101.serviceapp',
      maxZoom: 19,
    );
  }

  static TileLayer standardWithFallback({
    required String mapboxToken,
    int variant = 0,
  }) {
    final token = mapboxToken.trim();
    final index = variant.abs() % _fallbackTileUrls.length;
    final publicUrl = _fallbackTileUrls[index];
    final publicFallbackUrl =
        _fallbackTileUrls[(index + 1) % _fallbackTileUrls.length];
    final usesSubdomain = publicUrl.contains('{s}.');
    final subdomains = usesSubdomain
        ? const ['a', 'b', 'c', 'd']
        : const <String>[];

    if (token.isEmpty) {
      return TileLayer(
        urlTemplate: publicUrl,
        fallbackUrl: publicFallbackUrl,
        subdomains: subdomains,
        userAgentPackageName: 'br.com.play101.serviceapp',
        maxZoom: 20,
      );
    }

    // Usa Mapbox quando houver token e aplica fallback para tiles públicos.
    return TileLayer(
      urlTemplate:
          'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=$token',
      fallbackUrl: publicUrl,
      subdomains: subdomains,
      userAgentPackageName: 'br.com.play101.serviceapp',
      tileDimension: 512,
      zoomOffset: -1,
      maxZoom: 22,
    );
  }
}
