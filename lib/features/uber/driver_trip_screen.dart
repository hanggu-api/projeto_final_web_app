import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/uber_service.dart';
import '../../services/api_service.dart';
import '../../services/map_service.dart';
import '../../services/compass_service.dart';
import '../../core/theme/app_theme.dart';

class DriverTripScreen extends StatefulWidget {
  final String tripId;
  const DriverTripScreen({super.key, required this.tripId});

  @override
  State<DriverTripScreen> createState() => _DriverTripScreenState();
}

class _DriverTripScreenState extends State<DriverTripScreen> {
  final UberService _uberService = UberService();
  final ApiService _apiService = ApiService();
  final MapController _mapController = MapController();
  final CompassService _compassService = CompassService();
  StreamSubscription<double>? _compassSubscription;
  
  Map<String, dynamic>? _tripData;
  LatLng? _currentLocation;
  List<LatLng> _pickupRoutePoints = [];
  List<LatLng> _destinationRoutePoints = [];
  String? _passengerName;
  bool _hasFetchedPickupRoute = false;
  bool _hasFetchedDestinationRoute = false;
  StreamSubscription<Position>? _positionStream;
  bool _isLoading = false;

  // Variáveis de Simulação
  bool _isSimulating = false;
  int _simulationIndex = 0;
  bool _isHeadingUp = true; 
  StreamSubscription<int>? _simulationSubscription;

  // Helper para parsing seguro
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  void initState() {
    super.initState();
    _compassService.start();
    _initCompassListener();
    _checkLocationPermission();
  }

  void _initCompassListener() {
    _compassSubscription = _compassService.headingStream.listen((heading) {
      if (_isHeadingUp && mounted) {
        // Rotação suave da bússola monitorada no listener de posição
      }
    });
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    // Obtém posição inicial rapidamente para evitar o "default" em São Paulo
    try {
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted && _currentLocation == null) {
        setState(() => _currentLocation = LatLng(lastPos.latitude, lastPos.longitude));
      }
      
      final currentPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() => _currentLocation = LatLng(currentPos.latitude, currentPos.longitude));
      }
    } catch (e) {
      debugPrint('⚠️ [DriverTrip] Falha ao obter posição rápida: $e');
    }

    _startTracking();
  }

  @override
  void dispose() {
    _compassService.stop();
    _compassSubscription?.cancel();
    _positionStream?.cancel();
    _simulationSubscription?.cancel();
    UberService().stopRouteSimulation();
    super.dispose();
  }

  void _startTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // Filtro menor para mais precisão
      ),
    ).listen((Position position) {
      debugPrint('📍 [DriverTrip] GPS: (${position.latitude}, ${position.longitude}), Heading: ${position.heading}');
      final newPos = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentLocation = newPos;
        });

        // 🧭 LÓGICA HÍBRIDA DE ROTAÇÃO (Estilo Google Maps)
        if (_isHeadingUp) {
          double targetRotation;
          
          // Se estiver movendo acima de ~5km/h (1.4 m/s), usa o GPS (Course)
          // Abaixo disso, usa a Bússola (Heading)
          if (position.speed > 1.4 && position.heading != 0) {
            targetRotation = position.heading;
          } else {
            targetRotation = _compassService.currentHeading;
          }

          // Aplica rotação suavizada (usando normalize para evitar saltos)
          _mapController.rotate(-targetRotation);
        }
        
        final userIdStr = _apiService.userId?.toString();
        if (userIdStr != null) {
          final dId = int.parse(userIdStr);
          debugPrint('📤 [DriverTrip] Enviando GPS para Supabase: (${position.latitude}, ${position.longitude}) para Driver: $dId');
          _uberService.updateDriverLocation(
            driverId: dId,
            latitude: position.latitude,
            longitude: position.longitude,
          );
        }
      }
    });
  }

  Future<void> _updateStatus(String status) async {
    setState(() => _isLoading = true);
    try {
      await _uberService.updateTripStatus(widget.tripId, status);
      // Não redirecionamos mais imediatamente para mostrar o resumo de pagamento
      // if (status == 'completed') {
      //   if (mounted) context.go('/uber-driver');
      // }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar status: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleSimulation(String tripStatus) {
    if (_isSimulating) {
      UberService().stopRouteSimulation();
      _simulationSubscription?.cancel();
      setState(() {
        _isSimulating = false;
        _simulationIndex = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Simulação parada')),
      );
    } else {
      // Decide qual rota simular baseado no status
      List<LatLng> pointsToSimulate = [];
      if (tripStatus == 'accepted') {
        pointsToSimulate = _pickupRoutePoints;
      } else if (tripStatus == 'in_progress') {
        pointsToSimulate = _destinationRoutePoints;
      }

      if (pointsToSimulate.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rota não disponível para simulação neste status.')),
        );
        return;
      }

      setState(() {
        _isSimulating = true;
      });

      final userIdStr = _apiService.userId?.toString();
      final driverId = int.tryParse(userIdStr ?? '') ?? 0;
      UberService().startRouteSimulation(
        driverId: driverId,
        polyline: pointsToSimulate,
      );

      _simulationSubscription = UberService().simulationProgress?.listen((index) {
        if (mounted) {
          setState(() {
            _simulationIndex = index;
            _currentLocation = pointsToSimulate[index];
          });
          // Opcional: mover mapa para a nova posição do simulador
          _mapController.move(_currentLocation!, 16);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Simulação iniciada')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _uberService.watchTrip(widget.tripId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          if (_tripData != snapshot.data) {
            _tripData = snapshot.data;
            debugPrint('🚗 [DriverTrip] Dados da Corrida Recebidos:');
            debugPrint(JsonEncoder.withIndent('  ').convert(_tripData));
            
            // Log específico do passageiro se disponível (assumindo que client_id ou dados do cliente venham no join)
            if (_tripData?['client_id'] != null) {
               debugPrint('👤 [DriverTrip] Passageiro ID: ${_tripData!['client_id']}');
            }
          }

          final status = _tripData?['status'] ?? 'accepted';
          final pickupAddress = _tripData?['pickup_address'] ?? '';
          final dropoffAddress = _tripData?['dropoff_address'] ?? '';
          final fare = double.tryParse(_tripData?['fare_estimated']?.toString() ?? '0.00') ?? 0.0;
          final paymentMethod = _tripData?['payment_method'] ?? 'NÃO ESPECIFICADO';

          // Se a viagem foi cancelada pelo passageiro
          if (status == 'cancelled') {
            Future.microtask(() {
              if (mounted) {
                 showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => AlertDialog(
                    title: const Text('Corrida Cancelada'),
                    content: const Text('O passageiro cancelou esta solicitação.'),
                    actions: [
                      TextButton(
                        onPressed: () => context.go('/uber-driver-home'),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              }
            });
            return const Center(child: Text('Corrida Cancelada'));
          }

          // Se a viagem foi concluída, mostra o resumo de pagamento
          if (status == 'completed') {
            return _buildPaymentSummary(fare, paymentMethod);
          }

          // 🏁 LOGICA RESILIENTE DE ROTAS
          final pickupLat = _toDouble(_tripData?['pickup_lat']);
          final pickupLon = _toDouble(_tripData?['pickup_lon']);
          final dropoffLat = _toDouble(_tripData?['dropoff_lat']);
          final dropoffLon = _toDouble(_tripData?['dropoff_lon']);

          // Rota 2: Passageiro -> Destino (AZUL) - Não depende do motorista
          if (!_hasFetchedDestinationRoute && pickupLat != 0 && dropoffLat != 0) {
            _hasFetchedDestinationRoute = true;
            Future.microtask(() async {
              try {
                final destinationRes = await MapService().getRoute(
                  LatLng(pickupLat, pickupLon),
                  LatLng(dropoffLat, dropoffLon),
                );
                if (mounted) {
                  setState(() {
                    _destinationRoutePoints = destinationRes['points'] as List<LatLng>;
                  });
                  _fitRoute([..._pickupRoutePoints, ..._destinationRoutePoints]);
                }
              } catch (e) {
                debugPrint('❌ Erro ao buscar rota de destino: $e');
              }
            });
          }

          // Rota 1: Motorista -> Passageiro (ROXO) - Depende do motorista
          if (!_hasFetchedPickupRoute && _currentLocation != null && pickupLat != 0) {
            _hasFetchedPickupRoute = true;
            Future.microtask(() async {
              try {
                final pickupRes = await MapService().getRoute(
                  _currentLocation!,
                  LatLng(pickupLat, pickupLon),
                );
                if (mounted) {
                  setState(() {
                    _pickupRoutePoints = pickupRes['points'] as List<LatLng>;
                  });
                  _fitRoute([..._pickupRoutePoints, ..._destinationRoutePoints]);
                }
              } catch (e) {
                debugPrint('❌ Erro ao buscar rota de pickup: $e');
              }
            });
          }

          // Busca nome do passageiro (mantido)
          if (_tripData?['client_id'] != null && _passengerName == null) {
            _passengerName = "Carregando..."; // Previne re-entrada
            Future.microtask(() async {
              try {
                final clientProfile = await _uberService.getUserProfile(_tripData!['client_id']);
                if (mounted && clientProfile != null) {
                  setState(() => _passengerName = clientProfile['full_name']);
                } else if (mounted) {
                  setState(() => _passengerName = "Passageiro #${_tripData!['client_id']}");
                }
              } catch (e) {
                if (mounted) setState(() => _passengerName = "Passageiro");
              }
            });
          }

          return Stack(
            children: [
              // MAPA
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation ?? (
                    pickupLat != 0 
                      ? LatLng(pickupLat, pickupLon) 
                      : const LatLng(-23.5505, -46.6333)
                  ),
                  initialZoom: 15.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=${dotenv.env["MAPBOX_TOKEN"] ?? ""}',
                    userAgentPackageName: 'com.play101.app',
                    tileSize: 512,
                    zoomOffset: -1,
                    maxZoom: 22,
                  ),
                  PolylineLayer(
                    polylines: [
                      if (_pickupRoutePoints.isNotEmpty)
                        Polyline(
                          points: _pickupRoutePoints,
                          strokeWidth: 6,
                          color: const Color(0xFF4CAF50), // VERDE PAZ
                          borderColor: Colors.black.withOpacity(0.1),
                          borderStrokeWidth: 1,
                        ),
                      if (_destinationRoutePoints.isNotEmpty)
                        Polyline(
                          points: _destinationRoutePoints,
                          strokeWidth: 6,
                          color: AppTheme.primaryYellow,
                          borderColor: Colors.black.withOpacity(0.1),
                          borderStrokeWidth: 1,
                        ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      if (_currentLocation != null)
                        Marker(
                          point: _currentLocation!,
                          width: 48,
                          height: 48,
                          child: _buildDriverMarker(),
                        ),
                      if (status == 'accepted' || status == 'arrived')
                        if (pickupLat != 0)
                          Marker(
                            point: LatLng(pickupLat, pickupLon),
                            width: 120,
                            height: 60,
                            child: _buildLocationMarker(isPickup: true),
                          ),
                      if (status == 'in_progress')
                        if (dropoffLat != 0)
                          Marker(
                            point: LatLng(dropoffLat, dropoffLon),
                            width: 120,
                            height: 60,
                            child: _buildLocationMarker(isPickup: false),
                          ),
                    ],
                  ),
                ],
              ),

              // HEADER STITCH: PANORAMA GLASS
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        border: Border(
                          bottom: BorderSide(color: Colors.black.withOpacity(0.05)),
                        ),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => context.go('/uber-driver-home'),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.arrowLeft, size: 20, color: AppTheme.textDark),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  status == 'accepted' || status == 'arrived' ? 'A CAMINHO DO PASSAGEIRO' : 'EM VIAGEM',
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textDark,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  '101 Service Premium',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.helpCircle, size: 20, color: AppTheme.textDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // FLOATING MAP CONTROLS
              Positioned(
                right: 16,
                top: MediaQuery.of(context).padding.top + 100,
                child: Column(
                  children: [
                    _buildMapControl(LucideIcons.plus, () {
                      _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
                    }),
                    const SizedBox(height: 8),
                    _buildMapControl(LucideIcons.minus, () {
                      _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
                    }),
                    const SizedBox(height: 16),
                    _buildMapControl(LucideIcons.navigation2, () {
                      if (_currentLocation != null) {
                        _mapController.move(_currentLocation!, 17.0);
                      }
                    }, color: AppTheme.primaryYellow),
                    const SizedBox(height: 8),
                    // BOTÃO DE BÚSSOLA (HEADING UP)
                    _buildMapControl(
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
                      color: _isHeadingUp ? Colors.blue : Colors.grey,
                    ),
                  ],
                ),
              ),

              // PANEL: PASSENGER & ACTIONS (BOTTOM SHEET STITCH)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      )
                    ],
                    border: Border.all(color: Colors.black.withOpacity(0.05)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle
                      Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),

                      // Passenger Info Section
                      _buildPassengerInfoStitch(),

                      const SizedBox(height: 24),

                      // Address Card Detail
                      _buildAddressDetailCard(status, pickupAddress, dropoffAddress),

                      const SizedBox(height: 24),

                      // Action Button
                      _buildActionPanelStitch(status),
                    ],
                  ),
                ),
              ),
              
              if (_isLoading)
                Container(
                  color: Colors.black45,
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primaryYellow)),
                ),

              // Botão de Simulação (Apenas em estados de movimento: aceito ou em curso)
              if (status == 'accepted' || status == 'in_progress')
                Positioned(
                  top: 110, // Logo abaixo do painel de destino atual
                  right: 20,
                  child: _buildSimulationBadge(status),
                ),
            ],
          );
        },
      ),
    );
  }

  LatLngBounds? _fitBounds;

  void _openChat() {
    if (_tripData?['id'] == null) return;
    context.push('/chat/${_tripData!['id']}', extra: {
      'otherName': _passengerName ?? 'Passageiro',
      'otherAvatar': _tripData?['client_avatar'],
    });
  }

  Future<void> _makePhoneCall() async {
    // Para efeito de demonstração, mostra um alerta, já que não temos a dep de url_launcher instalada ou garantida
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Iniciando chamada para o passageiro...')),
    );
  }

  void _fitRoute(List<LatLng> points) {
    if (points.isEmpty) return;
    
    double minLat = points[0].latitude;
    double maxLat = points[0].latitude;
    double minLng = points[0].longitude;
    double maxLng = points[0].longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(70),
      ),
    );
  }

  Widget _buildPassengerInfo() {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: AppTheme.backgroundLight, borderRadius: BorderRadius.circular(16)),
          child: const Icon(LucideIcons.user, color: AppTheme.textDark, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _passengerName ?? 'Carregando...',
                style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textDark),
              ),
              Text(
                'Nota: 5.0 • Pagamento via App',
                style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _openChat,
          child: _buildCircleButton(LucideIcons.messageSquare, Colors.blue),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _makePhoneCall,
          child: _buildCircleButton(LucideIcons.phone, Colors.green),
        ),
      ],
    );
  }

  Widget _buildCircleButton(IconData icon, Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
      child: Center(child: Icon(icon, color: color, size: 20)),
    );
  }

  Widget _buildActionPanel(String status) {
    if (status == 'arrived') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'AGUARDANDO PASSAGEIRO',
            style: GoogleFonts.manrope(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppTheme.textDark,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton(
              onPressed: () => _updateStatus('in_progress'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textDark,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                'PASSAGEIRO EMBARCOU',
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _updateStatus('cancelled'),
            child: Text(
              'CANCELAR VIAGEM',
              style: GoogleFonts.manrope(
                color: AppTheme.textDark.withOpacity(0.6),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    }

    String buttonText = '';
    String nextStatus = '';
    Color buttonColor = AppTheme.textDark;
    Color textColor = Colors.white;

    if (status == 'accepted') {
      buttonText = 'CHEGUEI AO LOCAL';
      nextStatus = 'arrived';
      buttonColor = Colors.blue.shade700;
    } else if (status == 'in_progress') {
      buttonText = 'FINALIZAR VIAGEM';
      nextStatus = 'completed';
      buttonColor = AppTheme.primaryYellow;
      textColor = AppTheme.textDark;
    }

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: () => _updateStatus(nextStatus),
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          buttonText,
          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
      ),
    );
  }

  Widget _buildDriverMarker() {
    // 🧭 O marcador sempre aponta para onde o carro está indo/olhando
    // Se o mapa já está rotacionado (Heading Up), o ícone deve ser compensado?
    // Em apps profissionais, o ícone fica fixo pra cima se o mapa gira, 
    // mas aqui vamos rotacionar o ÍCONE se o mapa estiver fixo (Norte Up).
    
    double rotationDegrees = _isHeadingUp ? 0 : _compassService.currentHeading;

    return Transform.rotate(
      angle: rotationDegrees * pi / 180,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ],
          border: Border.all(color: AppTheme.primaryYellow, width: 2),
        ),
        child: Image.asset(
          'assets/images/car_marker.png',
          width: 32,
          height: 32,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.directions_car,
            color: AppTheme.primaryYellow,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildLocationMarker({required bool isPickup}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isPickup ? AppTheme.primaryYellow : AppTheme.textDark,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
              )
            ],
          ),
          child: Text(
            isPickup ? 'PASSAGEIRO' : 'DESTINO',
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: isPickup ? AppTheme.textDark : Colors.white,
            ),
          ),
        ),
        Icon(
          LucideIcons.mapPin,
          color: isPickup ? AppTheme.primaryYellow : AppTheme.textDark,
          size: 32,
        ),
      ],
    );
  }

  Widget _buildMapControl(IconData icon, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
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


  Widget _buildPassengerInfoStitch() {
    return Row(
      children: [
        Stack(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                shape: BoxShape.circle,
                image: _tripData?['client_avatar'] != null
                    ? DecorationImage(
                        image: NetworkImage(_tripData!['client_avatar']),
                        fit: BoxFit.cover,
                      )
                    : null,
                border: Border.all(color: AppTheme.primaryYellow.withOpacity(0.3), width: 3),
              ),
              child: _tripData?['client_avatar'] == null
                  ? const Icon(LucideIcons.user, color: AppTheme.textMuted, size: 32)
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryYellow,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.star_rounded, color: AppTheme.textDark, size: 12),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _passengerName ?? 'Carregando...',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
              Row(
                children: [
                  Text(
                    '4.8',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '• Passageiro Premium',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Row(
          children: [
            _buildCircleActionBtn(LucideIcons.messageSquare, _openChat),
            const SizedBox(width: 12),
            _buildCircleActionBtn(LucideIcons.phone, _makePhoneCall),
          ],
        ),
      ],
    );
  }

  Widget _buildCircleActionBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.primaryYellow.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppTheme.textDark, size: 22),
      ),
    );
  }

  Widget _buildAddressDetailCard(String status, String pickup, String dropoff) {
    final isGoingToPickup = status == 'accepted' || status == 'arrived';
    final targetAddress = isGoingToPickup ? pickup : dropoff;
    final label = isGoingToPickup ? 'LOCAL DE EMBARQUE' : 'DESTINO DA VIAGEM';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppTheme.primaryYellow,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppTheme.primaryYellow.withOpacity(0.3), blurRadius: 8)
                  ],
                ),
              ),
              Container(
                width: 2,
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryYellow, AppTheme.primaryYellow.withOpacity(0)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryYellow,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  targetAddress,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Distância aproximada: 1.2 km',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                '4 min',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              Text(
                '1.2 km',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionPanelStitch(String status) {
    if (status == 'arrived') {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'AGUARDANDO PASSAGEIRO',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppTheme.textDark,
              ),
            ),
          ),
          _buildPrimaryButton('PASSAGEIRO EMBARCOU', () => _updateStatus('in_progress')),
        ],
      );
    }

    String actionText = status == 'accepted' ? 'CHEGUEI AO LOCAL' : 'FINALIZAR VIAGEM';
    String nextSt = status == 'accepted' ? 'arrived' : 'completed';

    return _buildPrimaryButton(actionText, () => _updateStatus(nextSt));
  }

  Widget _buildPrimaryButton(String text, VoidCallback onTap) {
    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryYellow.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryYellow,
          foregroundColor: AppTheme.textDark,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.checkCircle, size: 24),
            const SizedBox(width: 12),
            Text(
              text.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSummary(double fare, String selectedPaymentMethod) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.backgroundDark,
            AppTheme.backgroundDark.withOpacity(0.95),
            Colors.black,
          ],
        ),
      ),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Icon(LucideIcons.checkCircle, color: AppTheme.primaryYellow, size: 100),
              );
            },
          ),
          const SizedBox(height: 32),
          Text(
            'VIAGEM CONCLUÍDA',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                Text(
                  'VALOR TOTAL',
                  style: GoogleFonts.manrope(color: Colors.white60, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'R\$ ${fare.toStringAsFixed(2)}',
                  style: GoogleFonts.manrope(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          Text(
            'FORMA DE RECEBIMENTO',
            style: GoogleFonts.manrope(color: AppTheme.primaryYellow, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 2),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _buildPaymentOption(LucideIcons.qrCode, 'PIX', isSelected: selectedPaymentMethod == 'PIX'),
              _buildPaymentOption(LucideIcons.creditCard, 'CARTÃO', isSelected: selectedPaymentMethod == 'CARTÃO'),
              _buildPaymentOption(LucideIcons.banknote, 'DINHEIRO', isSelected: selectedPaymentMethod == 'DINHEIRO'),
              _buildPaymentOption(LucideIcons.smartphone, 'MÁQUINA', isSelected: selectedPaymentMethod == 'MÁQUINA'),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              onPressed: () => context.go('/uber-driver'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryYellow,
                foregroundColor: AppTheme.textDark,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: Text(
                'CONCLUIR E SAIR',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOption(IconData icon, String label, {bool isSelected = false}) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryYellow.withOpacity(0.2) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? AppTheme.primaryYellow : Colors.white10, width: 2),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.manrope(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationBadge(String status) {
    return InkWell(
      onTap: () => _toggleSimulation(status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _isSimulating ? Colors.red : AppTheme.primaryBlue,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isSimulating ? Icons.stop : Icons.play_arrow,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              _isSimulating ? 'PARAR TESTE' : 'SIMULAR GPS',
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
