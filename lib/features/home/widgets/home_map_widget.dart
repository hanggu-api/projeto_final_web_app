import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/compass_service.dart';
import '../../../services/idle_driver_simulator.dart';
import '../../../services/app_config_service.dart';
import '../../../services/device_capability_service.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/maps/app_tile_layer.dart';

class HomeMapWidget extends StatefulWidget {
  final MapController mapController;
  final LatLng currentPosition;
  final List<LatLng> routePolyline;
  final LatLng? pickupLocation;
  final LatLng? dropoffLocation;
  final bool isInTripMode;
  final VoidCallback onMapReady;
  final VoidCallback? onAnimationStart;
  final VoidCallback? onAnimationEnd;
  final bool enableLiveSensors;

  const HomeMapWidget({
    super.key,
    required this.mapController,
    required this.currentPosition,
    required this.routePolyline,
    required this.onMapReady,
    this.enableLiveSensors = false,
    this.onAnimationStart,
    this.onAnimationEnd,
    this.pickupLocation,
    this.dropoffLocation,
    this.driverLatLng,
    this.arrivalPolyline = const [],
    this.tripStatus,
    this.isInTripMode = false,
    this.isPickingOnMap = false,
    this.simulatedCars,
    this.onPickingLocationChanged,
  });

  final bool isPickingOnMap;
  final LatLng? driverLatLng;
  final List<LatLng> arrivalPolyline;
  final String? tripStatus;
  final Function(LatLng)? onPickingLocationChanged;
  final List<SimulatedCar>? simulatedCars;

  @override
  State<HomeMapWidget> createState() => _HomeMapWidgetState();
}

class _HomeMapWidgetState extends State<HomeMapWidget>
    with TickerProviderStateMixin {
  static const double _minCameraRotationDelta = 2.0;
  static const double _fastCameraRotationDelta = 7.5;
  static const Duration _minCameraRotationInterval = Duration(
    milliseconds: 180,
  );
  mapbox.MapboxMap? _mapboxMap;
  late AnimationController _animationController;
  late AnimationController _pulseController;
  final List<AnimationController> _moveControllers =
      []; // Rastreia animações de movimento
  bool _mapReady = false;
  bool _animationPlayed = false;
  double _driverBearing = 0.0;
  StreamSubscription<Position>? _positionStream;
  final CompassService _compassService = CompassService();
  double _mapRotation = 0.0;
  DateTime? _lastCameraRotationAt;
  final bool _isHeadingUp = true; // Inicia com rotação automática

  @override
  void initState() {
    super.initState();

    // Controller para animação de 9 segundos (3 fases de 3s)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    // Controller para pulso constante do marcador de usuário
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) {
          setState(() {
            _animationPlayed = true;
          });
          widget.onAnimationEnd?.call(); // Dispara callback de fim
        }
      }
    });

    _syncLiveSensors();
  }

  void _startHeadingTracking() {
    if (_positionStream != null) return;
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2, // Filtro menor para mais precisão no movimento
          ),
        ).listen((Position position) {
          if (!mounted || !_isHeadingUp) return;

          double targetRotation;

          // Lógica Híbrida: GPS (> 5km/h) vs Bússola
          if (position.speed > 1.4 && position.heading != 0) {
            targetRotation = position.heading;
          } else {
            targetRotation = _compassService.currentHeading;
          }

          // Suavização da rotação do mapa
          final newRotation = CompassService.normalizeHeading(
            _mapRotation,
            targetRotation,
          );

          if (!_shouldApplyCameraRotation(newRotation)) return;
          _mapRotation = newRotation;

          if (kIsWeb) {
            widget.mapController.rotate(-_mapRotation);
          } else if (_mapboxMap != null) {
            unawaited(
              _mapboxMap!.setCamera(
                mapbox.CameraOptions(bearing: _mapRotation),
              ),
            );
          }
        });
  }

  void _syncLiveSensors() {
    if (kIsWeb) return;
    if (widget.enableLiveSensors) {
      _compassService.start();
      _startHeadingTracking();
      return;
    }
    _positionStream?.cancel();
    _positionStream = null;
    _compassService.stop();
  }

  bool _shouldApplyCameraRotation(double nextRotation) {
    final delta = _normalizedAngleDelta(_mapRotation, nextRotation);
    if (delta < _minCameraRotationDelta) return false;

    final now = DateTime.now();
    final lastUpdate = _lastCameraRotationAt;
    if (lastUpdate != null &&
        now.difference(lastUpdate) < _minCameraRotationInterval &&
        delta < _fastCameraRotationDelta) {
      return false;
    }

    _lastCameraRotationAt = now;
    return true;
  }

  double _normalizedAngleDelta(double current, double next) {
    final rawDelta = (next - current + 540) % 360 - 180;
    return rawDelta.abs();
  }

  @override
  void didUpdateWidget(HomeMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableLiveSensors != widget.enableLiveSensors) {
      _syncLiveSensors();
    }

    // Calcula o bearing (direção) do motorista
    if (widget.driverLatLng != null &&
        oldWidget.driverLatLng != null &&
        widget.driverLatLng != oldWidget.driverLatLng) {
      final bearing = _calculateBearing(
        oldWidget.driverLatLng!,
        widget.driverLatLng!,
      );
      if (bearing != 0 &&
          _normalizedAngleDelta(_driverBearing, bearing) >=
              _minCameraRotationDelta) {
        setState(() {
          _driverBearing = bearing;
        });
      }
    }

    // 4. Auto-foco quando o motorista aparecer pela primeira vez
    if (widget.driverLatLng != null &&
        oldWidget.driverLatLng == null &&
        _mapReady) {
      debugPrint('🎯 [HomeMap] Motorista apareceu! Re-centralizando mapa...');
      _centerRouteWithAnimation();
    }
    // 🎬 Dispara a animação se a rota acabou de chegar ou mudar
    if (widget.routePolyline.isNotEmpty &&
        (oldWidget.routePolyline.isEmpty ||
            widget.routePolyline.length != oldWidget.routePolyline.length) &&
        _mapReady) {
      // Reseta estado para permitir nova animação
      if (mounted) {
        setState(() {
          _animationPlayed = false;
        });
        _animationController.reset();
        Future.delayed(const Duration(milliseconds: 100), _playRouteAnimation);
      }
    }
  }

  @override
  void dispose() {
    _compassService.stop();
    _positionStream?.cancel();
    _animationController.dispose();
    _pulseController.dispose();
    for (var controller in _moveControllers) {
      if (controller.isAnimating) {
        controller.stop();
      }
      controller.dispose();
    }
    _moveControllers.clear();
    super.dispose();
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * pi / 180;
    final lon1 = start.longitude * pi / 180;
    final lat2 = end.latitude * pi / 180;
    final lon2 = end.longitude * pi / 180;

    final dLon = lon2 - lon1;

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    final bearing = atan2(y, x);
    return (bearing * 180 / pi + 360) % 360;
  }

  // 🎬 Helper para animar o movimento do mapa similar ao HomeScreen
  void _animatedMapMove(
    LatLng destLocation,
    double destZoom,
    Duration duration,
  ) {
    if (!mounted) return;
    if (!kIsWeb && _mapboxMap != null) {
      final config = AppConfigService();
      _mapboxMap!.setCamera(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              destLocation.longitude,
              destLocation.latitude,
            ),
          ),
          zoom: destZoom,
          pitch: config.homeMapTiltRadians * 180 / pi,
          bearing: _mapRotation,
        ),
      );
      return;
    }

    final latTween = Tween<double>(
      begin: widget.mapController.camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: widget.mapController.camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: widget.mapController.camera.zoom,
      end: destZoom,
    );

    final controller = AnimationController(duration: duration, vsync: this);
    _moveControllers.add(controller);

    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOut,
    );

    controller.addListener(() {
      if (mounted) {
        widget.mapController.move(
          LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
          zoomTween.evaluate(animation),
        );
      }
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _moveControllers.remove(controller);
        controller.dispose();
      }
    });

    controller.forward();
  }

  // 🎬 Executa a sequência de animação da câmera
  void _playRouteAnimation() {
    if (_animationPlayed || !mounted) return;

    widget.onAnimationStart?.call(); // Dispara callback de início

    // Executa enquadramento direto
    _centerRouteWithAnimation();

    // Inicia o controller para controle de estado
    _animationController.forward();
  }

  // 🎯 Calcula bounds da rota e centraliza com animação (considerando overlays)
  void _centerRouteWithAnimation() {
    if (widget.routePolyline.isEmpty || !mounted) return;

    // 1. Define os paddings visuais (baseados no design do Uber)
    // Topo: ~280px (Barra de pesquisa + card de endereços + status bar)
    // Base: ~540px (Card de veículos + botões + bottom nav)
    final padding = const EdgeInsets.only(
      top: 240, // Reduzido para subir um pouco a rota
      bottom: 420, // Reduzido (NavBar oculta + Painel mais baixo)
      left: 64,
      right: 64,
    );

    // 2. Calcula limites da rota (Foco inteligente no Encontro)
    double minLat, maxLat, minLng, maxLng;

    // Se a viagem está em busca do passageiro, focamos no Motorista + Pickup
    // Caso contrário, focamos na rota inteira
    final bool isEnRoute =
        widget.tripStatus == 'accepted' || widget.tripStatus == 'arrived';

    if (isEnRoute && widget.driverLatLng != null) {
      minLat = min(
        widget.driverLatLng!.latitude,
        widget.routePolyline[0].latitude,
      );
      maxLat = max(
        widget.driverLatLng!.latitude,
        widget.routePolyline[0].latitude,
      );
      minLng = min(
        widget.driverLatLng!.longitude,
        widget.routePolyline[0].longitude,
      );
      maxLng = max(
        widget.driverLatLng!.longitude,
        widget.routePolyline[0].longitude,
      );

      // Se tivermos a polilinha, incluímos apenas os pontos até o passageiro (metade opcional)
      // Mas para simplificar, garantimos que motorista e pickup estejam no quadro.
    } else {
      minLat = widget.routePolyline[0].latitude;
      maxLat = widget.routePolyline[0].latitude;
      minLng = widget.routePolyline[0].longitude;
      maxLng = widget.routePolyline[0].longitude;
    }

    if (widget.driverLatLng != null) {
      minLat = min(minLat, widget.driverLatLng!.latitude);
      maxLat = max(maxLat, widget.driverLatLng!.latitude);
      minLng = min(minLng, widget.driverLatLng!.longitude);
      maxLng = max(maxLng, widget.driverLatLng!.longitude);
    }

    for (final point in widget.routePolyline) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final bounds = LatLngBounds(
      LatLng(minLat, minLng), // southWest
      LatLng(maxLat, maxLng), // northEast
    );

    if (!mounted) return;

    final screenSize = MediaQuery.sizeOf(context);

    // 3. Calcula zoom ideal para caber na "área roxa" (safe area)
    final zoom = _calculateFitZoom(bounds, screenSize, padding);

    // 4. Calcula o centro geográfico da rota
    final routeCenterLat = (minLat + maxLat) / 2;
    final routeCenterLng = (minLng + maxLng) / 2;

    // 5. Ajusta o centro da câmera para compensar o desequilíbrio vertical (padding assimétrico)
    // Se o padding de baixo é maior, o centro da câmera deve ser DESLOCADO PARA BAIXO
    // em relação ao centro da rota, para que a rota "suba" para a área visível.
    final verticalOffsetPixels = (padding.bottom - padding.top) / 2;

    // Conversão aproximada de pixels para graus de latitude no nível de zoom alvo
    final zoomFactor = pow(2, zoom);
    final degreesPerPixel = 360 / (256 * zoomFactor);
    final latOffset = verticalOffsetPixels * degreesPerPixel;

    final cameraCenter = LatLng(routeCenterLat - latOffset, routeCenterLng);

    _animatedMapMove(cameraCenter, zoom, const Duration(milliseconds: 1500));
  }

  // 📐 Calcula zoom ideal para caber bounds na área útil da tela
  double _calculateFitZoom(
    LatLngBounds bounds,
    Size screenSize,
    EdgeInsets padding,
  ) {
    // Área efetivamente visível (a "área roxa" do pedido do usuário)
    final effectiveWidth = screenSize.width - padding.left - padding.right;
    final effectiveHeight = screenSize.height - padding.top - padding.bottom;

    final northEast = bounds.northEast;
    final southWest = bounds.southWest;

    final latDelta = (northEast.latitude - southWest.latitude).abs();
    final lngDelta = (northEast.longitude - southWest.longitude).abs();

    // Evita divisão por zero se os pontos forem iguais
    if (latDelta == 0 || lngDelta == 0) return 15.0;

    // Fórmula para calcular zoom baseado na área visível
    // 256 = tamanho padrão de tile em pixels
    final latZoom = log(360 / latDelta) / log(2);
    final lngZoom =
        log(360 / lngDelta) / log(2) +
        log(cos(southWest.latitude * pi / 180).abs()) / log(2);

    // Ajusta para o tamanho da área ÚTIL da tela
    final screenLatFactor = log(effectiveHeight / 256) / log(2);
    final screenLngFactor = log(effectiveWidth / 256) / log(2);

    // Retorna o menor zoom que garante que tudo caiba + margem de segurança mínima (0.2)
    final baseZoom = min(latZoom + screenLatFactor, lngZoom + screenLngFactor);

    // Zoom mais agressivo para preencher o quadro (removido desconto de 0.2)
    return baseZoom.clamp(10.0, 20.0);
  }

  @override
  Widget build(BuildContext context) {
    final useLightweightMap =
        kIsWeb || DeviceCapabilityService.instance.prefersLightweightMaps;
    final useBasicLightweightMap =
        DeviceCapabilityService.instance.prefersLightweightMaps;
    final config = AppConfigService();
    final tiltRadians = config.homeMapTiltRadians;
    final tiltPerspective = config.homeMapTiltPerspective;
    final tiltScaleX = config.homeMapTiltScaleX;
    final tiltScaleY = config.homeMapTiltScaleY;

    // Preset "navigation look": perspectiva forte de mapa inclinado.
    final effectiveTilt = tiltRadians.clamp(0.16, 0.28);
    final effectivePerspective = tiltPerspective.clamp(0.0012, 0.0028);
    final effectiveScaleX = tiltScaleX.clamp(1.00, 1.06);
    final effectiveScaleY = tiltScaleY.clamp(1.08, 1.28);

    if (!useLightweightMap) {
      const pitchDegrees = 20.0;
      return Stack(
        children: [
          mapbox.MapWidget(
            key: const ValueKey('home_mapbox'),
            styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
            cameraOptions: mapbox.CameraOptions(
              center: mapbox.Point(
                coordinates: mapbox.Position(
                  widget.currentPosition.longitude,
                  widget.currentPosition.latitude,
                ),
              ),
              zoom: 15.3,
              pitch: pitchDegrees,
              bearing: _mapRotation,
            ),
            onMapCreated: (map) async {
              _mapboxMap = map;
              await map.scaleBar.updateSettings(
                mapbox.ScaleBarSettings(enabled: false),
              );
              await map.compass.updateSettings(
                mapbox.CompassSettings(enabled: false),
              );
              await map.logo.updateSettings(
                mapbox.LogoSettings(enabled: false),
              );
              await map.attribution.updateSettings(
                mapbox.AttributionSettings(enabled: false),
              );
              await map.location.updateSettings(
                mapbox.LocationComponentSettings(
                  enabled: false,
                  pulsingEnabled: false,
                  puckBearingEnabled: false,
                ),
              );
              setState(() => _mapReady = true);
              widget.onMapReady();
            },
            onStyleLoadedListener: (_) async {
              if (_mapboxMap == null) return;
              await _mapboxMap!.setCamera(
                mapbox.CameraOptions(
                  pitch: pitchDegrees,
                  bearing: _mapRotation,
                ),
              );
            },
            onCameraChangeListener: (_) {
              if (widget.isPickingOnMap) {
                widget.onPickingLocationChanged?.call(widget.currentPosition);
              }
            },
          ),
          if (!widget.isInTripMode)
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.green.shade400,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.shade400.withOpacity(0.35),
                        blurRadius: 12,
                        spreadRadius: 3,
                      ),
                    ],
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    final mapContent = FlutterMap(
      mapController: widget.mapController,
      options: MapOptions(
        initialCenter: widget.currentPosition,
        initialZoom: useBasicLightweightMap ? 14.0 : 15.0,
        onMapReady: () {
          if (mounted) {
            setState(() => _mapReady = true);
            widget.onMapReady();

            if (widget.routePolyline.isNotEmpty && !_animationPlayed) {
              Future.delayed(
                const Duration(milliseconds: 500),
                _playRouteAnimation,
              );
            }
          }
        },
        onPositionChanged: (pos, hasGesture) {
          if (widget.isPickingOnMap && hasGesture) {
            widget.onPickingLocationChanged?.call(pos.center);
          }
        },
      ),
      children: [
        useBasicLightweightMap
            ? AppTileLayer.lightweight()
            : AppTileLayer.standard(mapboxToken: SupabaseConfig.mapboxToken),

        // 🛣️ Polilinha da rota
        if (widget.routePolyline.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: List<LatLng>.from(widget.routePolyline),
                strokeWidth: 5.0,
                color: AppTheme.accentBlue,
                borderColor: AppTheme.accentBlue.withOpacity(0.5),
                borderStrokeWidth: 1.0,
              ),
            ],
          ),

            // 📍 Marcadores
            MarkerLayer(
              markers: [
                // Marcador da posição atual (usuário)
                if (!widget.isInTripMode)
                  Marker(
                    point: widget.currentPosition,
                    width: 60,
                    height: 60,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Círculo de pulso
                            Container(
                              width: 20 + (25 * _pulseController.value),
                              height: 20 + (25 * _pulseController.value),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryYellow.withOpacity(
                                  0.5 * (1.0 - _pulseController.value),
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            // Marcador central
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                                border: Border.all(
                                  color: AppTheme.primaryYellow,
                                  width: 3,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.person,
                                  color: AppTheme.textDark,
                                  size: 12,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                // 🟢 Ponto de coleta (pickup) - DESIGN PREMIUM COM SETAS SAINDO
                if (widget.pickupLocation != null)
                  Marker(
                    point: widget.pickupLocation!,
                    width: 70,
                    height: 70,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Setas direcionais saindo (>>>>)
                        Positioned(
                          right: 0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              3,
                              (index) => Icon(
                                Icons.chevron_right,
                                color: Colors.green.withOpacity(
                                  0.5 - (index * 0.15),
                                ),
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        // Marcador Principal
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(color: Colors.green, width: 6),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 🔴 Ponto de entrega (dropoff) - DESIGN PREMIUM COM SETAS CHEGANDO
                if (widget.dropoffLocation != null)
                  Marker(
                    point: widget.dropoffLocation!,
                    width: 70,
                    height: 70,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Setas direcionais chegando (>>>>)
                        Positioned(
                          left: 0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              3,
                              (index) => Icon(
                                Icons.chevron_right,
                                color: Colors.orange.withOpacity(
                                  0.2 + (index * 0.15),
                                ),
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        // Marcador Principal (Pino mais clássico/estético)
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppTheme.textDark,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.location_on,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // 📍 Pino Central para Seleção de Local (Picking Mode)
                // Estilo Uber: O mapa se move por baixo do pino fixo no centro
                if (widget.isPickingOnMap)
                  Marker(
                    point: widget.mapController.camera.center,
                    width: 60,
                    height: 60,
                    child: Column(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: AppTheme.primaryBlue,
                          size: 40,
                        ),
                        const SizedBox(
                          height: 12,
                        ), // Espaço para o pino "flutuar"
                      ],
                    ),
                  ),

                // 🚗 Marcador do Motorista
                if (widget.driverLatLng != null)
                  Marker(
                    point: widget.driverLatLng!,
                    width: 70,
                    height: 70,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: _driverBearing),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      builder: (context, bearing, child) {
                        // Ajuste de orientação do asset (car_marker.png) para alinhar rodas para baixo
                        const double bearingOffset = -90;
                        return Transform.rotate(
                          angle: (bearing + bearingOffset) * pi / 180,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 10,
                                ),
                              ],
                              border: Border.all(
                                color: AppTheme.primaryYellow,
                                width: 2,
                              ),
                            ),
                            child: Image.asset(
                              'assets/images/car_marker.png',
                              width: 48,
                              height: 48,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    Icons.directions_car,
                                    color: AppTheme.primaryYellow,
                                    size: 36,
                                  ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // 🚙 Carros Livres (Simulados)
                if (widget.simulatedCars != null &&
                    widget.simulatedCars!.isNotEmpty)
                  ...widget.simulatedCars!.map(
                    (car) => Marker(
                      point: car.position,
                      width: 50,
                      height: 50,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: car.heading),
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.linear,
                        builder: (context, angle, child) {
                          return const Icon(
                            Icons.person_pin_circle,
                            color: Colors.deepPurple,
                            size: 32,
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),

            // 🎬 Indicador visual da animação
            if (!_animationPlayed &&
                _mapReady &&
                widget.routePolyline.isNotEmpty)
              Positioned(
                bottom: 30 + MediaQuery.of(context).padding.bottom,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) =>
                                CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.primaryYellow,
                                  ),
                                  value: _animationController.value,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Visualizando rota...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ],
    );

    if (useBasicLightweightMap) {
      return mapContent;
    }

    final tiltMatrix = Matrix4.identity()
      ..setEntry(3, 2, effectivePerspective)
      ..rotateX(effectiveTilt)
      ..scale(effectiveScaleX, effectiveScaleY)
      ..translate(0.0, 24.0, 0.0);

    return ClipRect(
      child: Transform(
        alignment: Alignment.bottomCenter,
        transform: tiltMatrix,
        transformHitTests: false,
        child: mapContent,
      ),
    );
  }
}
