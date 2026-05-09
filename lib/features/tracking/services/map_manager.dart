import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:latlong2/latlong.dart' as ll;
import 'package:flutter/material.dart' show Color, Colors, debugPrint;

class MapManager {
  mapbox.MapboxMap? mapboxMap;
  mapbox.PolylineAnnotationManager? _polylineAnnotationManager;
  mapbox.PointAnnotationManager? _pointAnnotationManager;
  bool _isDisposed = false;
  bool _carIconReady = false;
  bool _isLoadingCarIcon = false;

  Future<void> initializeMap(mapbox.MapboxMap map) async {
    _isDisposed = false;
    mapboxMap = map;
    
    // Configurações básicas de UI que podem ser feitas imediatamente Marina! Marina! Marina!
    await mapboxMap!.scaleBar.updateSettings(
      mapbox.ScaleBarSettings(enabled: false),
    );
    if (_isDisposed) return;

    await mapboxMap!.location.updateSettings(
      mapbox.LocationComponentSettings(enabled: false),
    );
  }

  /// Chamado explicitamente quando o estilo do mapa termina de carregar
  void onStyleLoaded() {
    debugPrint('🔔 [MapManager] Evento onStyleLoaded disparado!');
    if (!_isDisposed) {
      _carIconReady = false;
      _loadMapImagesWithRetry();
      _set3DLighting();
    }
  }

  Future<void> _set3DLighting() async {
    if (mapboxMap == null || _isDisposed) return;
    try {
      final style = mapboxMap!.style;
      await style.setLight(mapbox.FlatLight(
        id: "main-light",
        anchor: mapbox.Anchor.VIEWPORT,
        color: Colors.white.toARGB32(),
        intensity: 0.4,
        position: [1.5, 90, 80],
      ));
      debugPrint('💡 [MapManager] Iluminação 3D configurada com sucesso.');
    } catch (e) {
      debugPrint('⚠️ [MapManager] Erro ao configurar iluminação 3D: $e');
    }
  }

  Future<void> _loadMapImagesWithRetry() async {
    if (_isLoadingCarIcon || _isDisposed) return;
    _isLoadingCarIcon = true;
    try {
      const maxAttempts = 3;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        if (_isDisposed) return;
        final ok = await _loadMapImages();
        if (ok) {
          _carIconReady = true;
          return;
        }
        await Future.delayed(Duration(milliseconds: 250 * attempt));
      }
      debugPrint(
        '⚠️ [MapManager] Não foi possível registrar car-icon após tentativas. Usando fallback.',
      );
    } finally {
      _isLoadingCarIcon = false;
    }
  }

  Future<bool> _loadMapImages() async {
    if (mapboxMap == null || _isDisposed) return false;
    try {
      debugPrint('🎨 [MapManager] Iniciando carregamento de imagens no estilo...');
      
      // Verifica se o style ainda está acessível
      final style = mapboxMap!.style;
      
      final ByteData bytes = await rootBundle.load('assets/images/car_top.png');
      if (_isDisposed) return false;
      final Uint8List list = bytes.buffer.asUint8List();

      final codec = await ui.instantiateImageCodec(
        list,
        targetWidth: 128,
        targetHeight: 128,
      );
      final frame = await codec.getNextFrame();
      if (_isDisposed) return false;
      final image = frame.image;

      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null || _isDisposed) {
        debugPrint('❌ [MapManager] Erro ao decodificar imagem do carro: byteData nulo ou disposed');
        return false;
      }

      await style.addStyleImage(
        'car-icon',
        3.5,
        mapbox.MbxImage(
          width: image.width,
          height: image.height,
          data: byteData.buffer.asUint8List(),
        ),
        false,
        [],
        [],
        null,
      );
      debugPrint('✅ [MapManager] Imagem do carro carregada com sucesso: ${image.width}x${image.height}');
      return true;
    } catch (e) {
      debugPrint('❌ [MapManager] Erro crítico ao carregar imagem do carro no estilo: $e');
      return false;
    }
  }

  Future<void> drawRoute(
    List<ll.LatLng> points,
    Color color,
    ll.LatLng? driverLocation,
  ) async {
    if (mapboxMap == null || points.isEmpty) return;

    if (_polylineAnnotationManager == null) {
      _polylineAnnotationManager = await mapboxMap!.annotations
          .createPolylineAnnotationManager();
    } else {
      await _polylineAnnotationManager!.deleteAll();
    }
    if (_isDisposed) return;

    List<ll.LatLng> finalPoints = List.from(points);
    if (driverLocation != null && finalPoints.isNotEmpty) {
      finalPoints = _truncateRouteFromDriver(finalPoints, driverLocation);
    }

    if (finalPoints.length < 2) return;

    final positions = finalPoints
        .map((p) => mapbox.Position(p.longitude, p.latitude))
        .toList();

    final polylineOptions = mapbox.PolylineAnnotationOptions(
      geometry: mapbox.LineString(coordinates: positions),
      lineColor: color.toARGB32(),
      lineWidth: 6.0, // Um pouco mais grosso Marina! Marina! Marina!
      lineJoin: mapbox.LineJoin.ROUND,
    );

    await _polylineAnnotationManager!.create(polylineOptions);
  }

  List<ll.LatLng> _truncateRouteFromDriver(
    List<ll.LatLng> points,
    ll.LatLng driverLocation,
  ) {
    int closestIndex = 0;
    double minDistance = double.infinity;
    const ll.Distance distanceCalculator = ll.Distance();

    for (int i = 0; i < points.length; i++) {
      final d = distanceCalculator.as(
        ll.LengthUnit.Meter,
        driverLocation,
        points[i],
      );
      if (d < minDistance) {
        minDistance = d.toDouble();
        closestIndex = i;
      }
    }

    final truncated = points.sublist(closestIndex);
    if (truncated.isEmpty || truncated.first != driverLocation) {
      truncated.insert(0, driverLocation);
    }
    return truncated;
  }

  Future<void> drawMarkers({
    ll.LatLng? pickupLocation,
    ll.LatLng? dropoffLocation,
    ll.LatLng? driverLocation,
    double? bearing,
  }) async {
    if (mapboxMap == null) return;

    if (_pointAnnotationManager == null) {
      _pointAnnotationManager = await mapboxMap!.annotations
          .createPointAnnotationManager();
    } else {
      await _pointAnnotationManager!.deleteAll();
    }
    if (_isDisposed) return;

    final List<mapbox.PointAnnotationOptions> annotations = [];

    if (pickupLocation != null) {
      annotations.add(_createMarker(pickupLocation, Colors.blueAccent));
    }

    if (dropoffLocation != null) {
      annotations.add(_createMarker(dropoffLocation, Colors.redAccent));
    }

    if (driverLocation != null) {
      if (_carIconReady) {
        annotations.add(
          mapbox.PointAnnotationOptions(
            geometry: mapbox.Point(
              coordinates: mapbox.Position(
                driverLocation.longitude,
                driverLocation.latitude,
              ),
            ),
            iconImage: 'car-icon',
            iconRotate: bearing ?? 0.0,
            iconSize: 1.0,
            symbolSortKey: 10.0,
          ),
        );
      } else {
        // Fallback para evitar crash/channel-error enquanto estilo ainda não aceitou addStyleImage.
        annotations.add(_createMarker(driverLocation, Colors.black));
      }
    }

    if (annotations.isNotEmpty) {
      await _pointAnnotationManager!.createMulti(annotations);
    } else {
      debugPrint('⚠️ [MapManager] Nenhuma anotação para desenhar.');
    }
  }

  mapbox.PointAnnotationOptions _createMarker(ll.LatLng location, Color color) {
    return mapbox.PointAnnotationOptions(
      geometry: mapbox.Point(
        coordinates: mapbox.Position(location.longitude, location.latitude),
      ),
      iconImage: 'marker-15',
      iconColor: color.toARGB32(),
      iconSize: 2.0,
    );
  }

  Future<void> fitRoute({
    required List<ll.LatLng> points,
    double topPadding = 150.0,
    double bottomPadding = 350.0,
  }) async {
    if (mapboxMap == null || points.length < 2) return;

    final camera = await mapboxMap!.cameraForCoordinatesPadding(
      points
          .map(
            (p) => mapbox.Point(
              coordinates: mapbox.Position(p.longitude, p.latitude),
            ),
          )
          .toList(),
      mapbox.CameraOptions(),
      mapbox.MbxEdgeInsets(
        top: topPadding,
        left: 50.0,
        bottom: bottomPadding,
        right: 50.0,
      ),
      null,
      null,
    );
    if (_isDisposed) return;

    await mapboxMap!.setCamera(camera);
  }

  Future<void> animateToLocation({
    required ll.LatLng location,
    double zoom = 17.5,
    double bearing = 0.0,
    int duration = 500,
  }) async {
    if (mapboxMap == null) return;

    await mapboxMap!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(location.longitude, location.latitude),
        ),
        zoom: zoom,
        bearing: bearing,
        pitch: kIsWeb ? 0.0 : 45.0,
      ),
      mapbox.MapAnimationOptions(duration: duration),
    );
  }

  Future<void> lockCameraToCar({
    required ll.LatLng location,
    required double bearing,
    double zoom = 17.5,
  }) async {
    if (mapboxMap == null) return;

    await mapboxMap!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(location.longitude, location.latitude),
        ),
        zoom: zoom,
        bearing: bearing,
        pitch: kIsWeb ? 0.0 : 60.0, // Ângulo Marina! Marina! Marina!
      ),
      mapbox.MapAnimationOptions(duration: 800),
    );
  }

  Future<void> zoomIn() async {
    if (mapboxMap == null) return;
    final cameraState = await mapboxMap!.getCameraState();
    await mapboxMap!.setCamera(
      mapbox.CameraOptions(zoom: cameraState.zoom + 1),
    );
  }

  Future<void> zoomOut() async {
    if (mapboxMap == null) return;
    final cameraState = await mapboxMap!.getCameraState();
    await mapboxMap!.setCamera(
      mapbox.CameraOptions(zoom: cameraState.zoom - 1),
    );
  }

  void dispose() {
    _isDisposed = true;
    _polylineAnnotationManager = null;
    _pointAnnotationManager = null;
    mapboxMap = null;
  }
}
