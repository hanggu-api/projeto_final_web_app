import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/uber_service.dart';
import '../../services/api_service.dart';
import '../../services/driver_simulation_service.dart';
import '../../services/map_service.dart';
import '../../services/theme_service.dart';
import '../../services/compass_service.dart';
import '../../core/theme/app_theme.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> with SingleTickerProviderStateMixin {
  final UberService _uberService = UberService();
  final ApiService _apiService = ApiService();
  final MapController _mapController = MapController();
  final CompassService _compassService = CompassService();
  StreamSubscription<double>? _compassSubscription;
  
  bool _isOnline = false;
  bool _isLoading = true;
  LatLng? _currentLocation;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<List<Map<String, dynamic>>>? _tripsSubscription;
  
  int? _vehicleTypeId;
  bool _isMoto = false;
  Map<String, dynamic>? _newTripRequest;
  Timer? _requestTimer;
  int _timerSeconds = 15;
  double _heading = 0;
  bool _isHeadingUp = true; // 🧭 Inicia com Heading Up ativado
  
  Map<String, dynamic>? _proposalPickupMetrics;
  Map<String, dynamic>? _proposalTripMetrics;
  List<LatLng> _proposalPoints = [];

  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    _compassService.start();
    _initCompassListener();
    _initDriver();
  }

  void _initCompassListener() {
    _compassSubscription = _compassService.headingStream.listen((heading) {
      if (_isHeadingUp && mounted) {
        // Só usa a bússola se estiver parado ou muito lento (ex: < 5km/h ou 1.4 m/s)
        // Isso será controlado dinamicamente no listener de posição
      }
    });
  }

  Future<void> _initDriver() async {
    try {
      final userId = _apiService.userId;
      if (userId != null) {
        _vehicleTypeId = await _uberService.getDriverVehicleTypeId(userId);
        try {
          final vehicleData = await Supabase.instance.client
              .from('vehicles')
              .select('color_hex, vehicle_type_id')
              .eq('driver_id', userId)
              .maybeSingle();
          if (vehicleData != null) {
            _isMoto = vehicleData['vehicle_type_id'] == 3;
          }
        } catch (_) {}
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() {
            _currentLocation = LatLng(pos.latitude, pos.longitude);
            _isLoading = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_isMapReady) {
              try { _mapController.move(_currentLocation!, 15.0); } catch(_) {}
            }
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }

      // Recuperar viagem ativa se existir
      _recoverActiveTrip();
    } catch (e) {
      debugPrint('Driver init error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _compassService.stop();
    _compassSubscription?.cancel();
    _positionStream?.cancel();
    _tripsSubscription?.cancel();
    _requestTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleOnline(bool value) async {
    final userId = _apiService.userId;
    if (userId == null) return;

    setState(() => _isLoading = true);
    
    try {
      if (value) {
        _startTracking();
        _startListeningToTrips();
      } else {
        _stopTracking();
        _stopListeningToTrips();
        setState(() => _newTripRequest = null);
      }

      await _uberService.toggleDriverStatus(
        isOnline: value,
        driverId: userId,
        latitude: _currentLocation?.latitude,
        longitude: _currentLocation?.longitude,
      );

      setState(() {
        _isOnline = value;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao mudar status: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      final newPos = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentLocation = newPos;
        });

        // 🧭 LÓGICA HÍBRIDA DE ROTAÇÃO (Estilo Google Maps)
        if (_isHeadingUp) {
          double targetRotation;
          
          // Se estiver movendo acima de ~7km/h (2 m/s), usa o GPS (Course)
          // Abaixo disso, usa a Bússola (Heading)
          if (position.speed > 2.0 && position.heading != 0) {
            targetRotation = position.heading;
          } else {
            targetRotation = _compassService.currentHeading;
          }

          // Aplica rotação suavizada (o CompassService já suaviza a bússola)
          // Se for GPS, o MapController faz a transição
          _mapController.rotate(-targetRotation);
          _heading = targetRotation; 
        }
        
        final userIdStr = _apiService.userId?.toString();
        if (userIdStr != null && _isOnline) {
          _uberService.updateDriverLocation(
            driverId: int.parse(userIdStr),
            latitude: position.latitude,
            longitude: position.longitude,
          );
        }
      }
    });
  }

  void _stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  void _startListeningToTrips() {
    if (_vehicleTypeId == null) return;
    
    _tripsSubscription = _uberService.streamAvailableTrips(_vehicleTypeId!).listen((trips) {
      if (trips.isNotEmpty && _newTripRequest == null) {
        final trip = trips.first;
        _showNewTripRequest(trip);
      } else if (_newTripRequest != null) {
        // Verifica se a viagem que estamos oferecendo ainda está DISPONÍVEL
        final stillAvailable = trips.any((t) => t['id'] == _newTripRequest!['id']);
        if (!stillAvailable) {
          debugPrint('🚫 [DriverHome] Oferta expirada ou cancelada: ${_newTripRequest!['id']}');
          _requestTimer?.cancel();
          if (mounted) {
            setState(() => _newTripRequest = null);
            ThemeService().setNavBarVisible(true);
          }
        }
      }
    });
  }

  void _stopListeningToTrips() {
    _tripsSubscription?.cancel();
    _tripsSubscription = null;
  }

  Future<void> _recoverActiveTrip() async {
    try {
      final userId = _apiService.userId;
      if (userId == null) return;

      debugPrint('🔎 [DriverRecovery] Verificando viagens ativas para o motorista ID: $userId');
      final activeTrip = await _uberService.getActiveTripForDriver(userId);

      if (activeTrip != null && mounted) {
        final tripId = activeTrip['id'].toString();
        debugPrint('✅ [DriverRecovery] Viagem ativa encontrada: $tripId. Redirecionando...');
        
        // Redireciona para a tela de viagem ativa do motorista
        if (mounted) {
          context.go('/uber-driver-trip/$tripId');
        }
      }
    } catch (e) {
      debugPrint('❌ [DriverRecovery] Erro ao recuperar viagem ativa: $e');
    }
  }

  void _showNewTripRequest(Map<String, dynamic> trip) {
    if (mounted) {
      // Oculta a NavBar para dar espaço à oferta
      ThemeService().setNavBarVisible(false);

      setState(() {
        _newTripRequest = trip;
        _timerSeconds = 15;
        _proposalPickupMetrics = null;
        _proposalTripMetrics = null;
      });
      
      _fetchProposalMetrics(trip);
      
      _requestTimer?.cancel();
      _requestTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_timerSeconds > 0) {
          if (mounted) setState(() => _timerSeconds--);
        } else {
          timer.cancel();
          if (mounted) {
            ThemeService().setNavBarVisible(true);
            setState(() => _newTripRequest = null);
          }
        }
      });
    }
  }

  Future<void> _fetchProposalMetrics(Map<String, dynamic> trip) async {
    if (_currentLocation == null) return;
    
    try {
      final pickupLat = double.tryParse(trip['pickup_lat']?.toString() ?? '');
      final pickupLng = double.tryParse(trip['pickup_lon']?.toString() ?? '');
      final dropLat = double.tryParse(trip['dropoff_lat']?.toString() ?? '');
      final dropLng = double.tryParse(trip['dropoff_lon']?.toString() ?? '');

      if (pickupLat == null || pickupLng == null || dropLat == null || dropLng == null) return;

      final pickupLatLng = LatLng(pickupLat, pickupLng);
      final dropLatLng = LatLng(dropLat, dropLng);

      // Busca métricas individuais para o painel
      final pickupRes = await MapService().getRoute(_currentLocation!, pickupLatLng);
      final tripRes = await MapService().getRoute(pickupLatLng, dropLatLng);

      // Busca rota completa para desenho e enquadramento
      final fullRouteRes = await MapService().getMultiPointRoute([
        _currentLocation!,
        pickupLatLng,
        dropLatLng
      ]);

      if (mounted) {
        setState(() {
          _proposalPickupMetrics = pickupRes;
          _proposalTripMetrics = tripRes;
          _proposalPoints = fullRouteRes['points'] as List<LatLng>;
        });
        
        // Dá um pequeno tempo para o layout estabilizar antes de centralizar
        Future.delayed(const Duration(milliseconds: 300), () => _fitRoute());
      }
    } catch (e) {
      debugPrint('Error fetching proposal metrics: $e');
    }
  }

  void _fitRoute() {
    if (_proposalPoints.isEmpty || !_isMapReady) return;

    try {
      // Ajusta para caber todos os pontos com padding para os cards
      // Top: 120 (barra de status + respiro)
      // Bottom: 420 (painel de oferta + botões)
      // Sides: 50
      final bounds = LatLngBounds.fromPoints(_proposalPoints);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(50, 120, 50, 420),
        ),
      );
    } catch (e) {
      debugPrint('Error fitting route: $e');
    }
  }

  Future<void> _acceptTrip() async {
    if (_newTripRequest == null) return;
    final tripId = _newTripRequest!['id'];
    final userId = _apiService.userId;
    if (userId == null) return;

    _requestTimer?.cancel();
    setState(() => _isLoading = true);
    
    try {
      await _uberService.acceptTrip(tripId, userId);
      
      ThemeService().setNavBarVisible(true);

      if (mounted) {
        context.go('/uber-driver-trip/$tripId');
      }
      setState(() {
        _newTripRequest = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao aceitar corrida: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // MAPA
          _isLoading && _currentLocation == null
              ? const Center(child: CircularProgressIndicator())
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLocation ?? const LatLng(-23.5505, -46.6333),
                    initialZoom: 17.0,
                    onMapReady: () => setState(() => _isMapReady = true),
                  ),
                    children: [
                    TileLayer(
                      urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=${dotenv.env["MAPBOX_TOKEN"] ?? ""}',
                      userAgentPackageName: 'com.play101.app',
                      tileDimension: 512,
                      zoomOffset: -1,
                      maxZoom: 22,
                    ),
                    if (_proposalPoints.isNotEmpty)
                      PolylineLayer(
                        polylines: <Polyline>[
                          Polyline(
                            points: _proposalPoints,
                            color: Colors.blueAccent.withOpacity(0.7),
                            strokeWidth: 5,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (_currentLocation != null)
                          Marker(
                            point: _currentLocation!,
                            width: 60,
                            height: 60,
                            child: Transform.rotate(
                              angle: _heading * pi / 180,
                              child: _buildDriverCarMarker(),
                            ),
                          ),
                        if (_newTripRequest != null) ...[
                          // Marcador de Embarque (Pickup)
                          Marker(
                            point: LatLng(
                              double.parse(_newTripRequest!['pickup_lat'].toString()),
                              double.parse(_newTripRequest!['pickup_lon'].toString()),
                            ),
                            width: 120,
                            height: 80,
                            alignment: Alignment.topCenter,
                            child: _buildPickupMarker(),
                          ),
                          // Marcador de Desembarque (Dropoff)
                          Marker(
                            point: LatLng(
                              double.parse(_newTripRequest!['dropoff_lat'].toString()),
                              double.parse(_newTripRequest!['dropoff_lon'].toString()),
                            ),
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.redAccent, width: 2),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                              ),
                              child: const Icon(LucideIcons.mapPin, color: Colors.redAccent, size: 20),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
          
          // HEADER STITCH: FLOTATING BAR WITH GLASS EFFECT
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.9),
                    Colors.white.withOpacity(0.0),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Perfil
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: const Icon(LucideIcons.user, size: 20, color: AppTheme.textDark),
                  ),
                  
                  // Badge Central
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        )
                      ],
                      border: Border.all(color: Colors.black.withOpacity(0.05)),
                    ),
                    child: Text(
                      '101 Service',
                      style: GoogleFonts.manrope(
                        color: AppTheme.primaryYellow,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  
                  // Notificações
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: const Icon(LucideIcons.bell, size: 20, color: AppTheme.textDark),
                  ),
                ],
              ),
            ),
          ),

          // STATUS INDICATOR (Mini)
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isOnline ? Colors.green.withOpacity(0.9) : Colors.grey.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isOnline ? 'ONLINE' : 'OFFLINE',
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // MAP CONTROLS (Floating)
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 100,
            child: Column(
              children: [
                _buildMapActionButton(LucideIcons.plus, () {
                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
                }),
                const SizedBox(height: 8),
                _buildMapActionButton(LucideIcons.minus, () {
                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
                }),
                const SizedBox(height: 16),
                _buildMapActionButton(LucideIcons.navigation2, () {
                  if (_currentLocation != null) {
                    _mapController.move(_currentLocation!, 17.0);
                  }
                }, isPrimary: true),
                const SizedBox(height: 8),
                // BOTÃO DE BÚSSOLA (HEADING UP)
                _buildMapActionButton(
                  LucideIcons.compass, 
                  () {
                    setState(() {
                      _isHeadingUp = !_isHeadingUp;
                      if (!_isHeadingUp) {
                        _mapController.rotate(0); // Volta para o norte fixo
                      }
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_isHeadingUp ? 'Navegação por bússola ativada' : 'Navegação por bússola desativada'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // BOTTOM: TOGGLE (Offline/Online Power Button)
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => _toggleOnline(!_isOnline),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 3000),
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: _isOnline ? Colors.red.shade500 : AppTheme.primaryYellow,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_isOnline ? Colors.red : AppTheme.primaryYellow).withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      _isOnline ? LucideIcons.power : LucideIcons.play,
                      color: _isOnline ? Colors.white : AppTheme.textDark,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (_newTripRequest != null) _buildTripProposalOverlay(),
        ],
      ),
    );
  }

  Widget _buildTripProposalOverlay() {
    final trip = _newTripRequest!;
    final pickup = trip['pickup_address'] ?? 'Endereço de partida';
    final fareStr = trip['fare_estimated']?.toString() ?? '0.00';
    final fare = double.tryParse(fareStr) ?? 0.0;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 34 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, -8),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Compacto
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nova Viagem!',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                    ),
                    Text(
                      'Distância total: ${fare > 20 ? "Longa" : "Curta"}',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryYellow.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.timer, size: 14, color: AppTheme.textDark),
                      const SizedBox(width: 6),
                      Text(
                        '${_timerSeconds}s',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Earnings & Metrics Compact Row
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'R\$ ${fare.toStringAsFixed(2)}',
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                      Text(
                        '4.9',
                        style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _buildMiniMetric(LucideIcons.navigation, 
                          _proposalPickupMetrics != null ? '${(_proposalPickupMetrics!['distance'] as double? ?? 0).toStringAsFixed(1)}km' : '--'),
                      const SizedBox(width: 12),
                      _buildMiniMetric(LucideIcons.clock, 
                          _proposalPickupMetrics != null ? '${(_proposalPickupMetrics!['duration'] as double? ?? 0).toInt()}min' : '--'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Pickup & Dropoff (Compact Version)
            Row(
              children: [
                Column(
                  children: [
                    Icon(LucideIcons.circle, size: 8, color: AppTheme.primaryYellow),
                    Container(width: 1, height: 16, color: Colors.grey[300]),
                    const Icon(LucideIcons.mapPin, size: 10, color: Colors.redAccent),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pickup,
                        style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        trip['dropoff_address'] ?? 'Destino',
                        style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Action Buttons (Same Line or Tight)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _acceptTrip,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryYellow,
                      foregroundColor: AppTheme.textDark,
                      minimumSize: const Size(double.infinity, 54),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('ACEITAR', style: GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      ThemeService().setNavBarVisible(true);
                      setState(() {
                        _newTripRequest = null;
                        _proposalPoints = [];
                        _proposalPickupMetrics = null;
                        _proposalTripMetrics = null;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 54),
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('REJEITAR', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMetric(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 4),
        Text(
          value,
          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textDark),
        ),
      ],
    );
  }

  Widget _buildMapActionButton(IconData icon, VoidCallback onTap, {bool isPrimary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.primaryYellow : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Icon(icon, color: AppTheme.textDark, size: 24),
      ),
    );
  }

  Widget _buildMetric(IconData icon, String label, String dist, String time, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.manrope(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$dist • $time',
          style: GoogleFonts.manrope(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _buildPickupMarker() {
    final distance = _proposalPickupMetrics != null 
        ? '${(_proposalPickupMetrics!['distance'] as double? ?? 0).toStringAsFixed(1)}km' 
        : '--km';
        
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primaryYellow,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
              )
            ],
          ),
          child: Text(
            'Busca em $distance',
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppTheme.textDark,
            ),
          ),
        ),
        Icon(LucideIcons.mapPin, color: AppTheme.primaryYellow, size: 40),
      ],
    );
  }

  Widget _buildDriverCarMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
        ),
        // Ícone de Navegação Estilo Uber
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
              )
            ],
            border: Border.all(color: Colors.blue, width: 2),
          ),
          child: Center(
            child: Icon(
              _isMoto ? LucideIcons.bike : LucideIcons.navigation, 
              color: Colors.blue, 
              size: 18
            ),
          ),
        ),
      ],
    );
  }
}
