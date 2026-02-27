import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/uber_service.dart';
import '../../services/map_service.dart';
import '../../services/theme_service.dart';
import '../../core/theme/app_theme.dart';
import 'dart:math' show atan2, sin, cos, pi;

class UberTrackingScreen extends StatefulWidget {
  final String tripId;

  const UberTrackingScreen({super.key, required this.tripId});

  @override
  State<UberTrackingScreen> createState() => _UberTrackingScreenState();
}

class _UberTrackingScreenState extends State<UberTrackingScreen> with SingleTickerProviderStateMixin {
  final UberService _uberService = UberService();
  final MapController _mapController = MapController();
  late AnimationController _pulseController;
  
  LatLng? _driverLocation;
  LatLng? _previousLocation;
  List<LatLng> _routePoints = [];
  bool _hasFetchedRoute = false;
  double _bearing = 0.0;
  String _status = 'searching';

  // Alertas de Proximidade
  double? _distanceToPickup;
  bool _alert500mShow = false;
  bool _alert100mShow = false;
  bool _alertArrivedShow = false;
  bool _hasTriggered500m = false;
  bool _hasTriggered100m = false;
  bool _hasTriggeredArrived = false;

  Map<String, dynamic>? _driverProfile;
  bool _isLoadingDriver = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    // Garante que a barra continue oculta durante o rastreio
    ThemeService().setNavBarVisible(false);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    // Restaura a barra de navegação ao sair do rastreio (viagem concluída ou cancelada)
    ThemeService().setNavBarVisible(true);
    super.dispose();
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double startLat = start.latitude * (pi / 180);
    double startLng = start.longitude * (pi / 180);
    double endLat = end.latitude * (pi / 180);
    double endLng = end.longitude * (pi / 180);

    double dLng = endLng - startLng;
    double y = sin(dLng) * cos(endLat);
    double x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(dLng);
    double brng = atan2(y, x);
    return (brng * (180 / pi) + 360) % 360;
  }

  Map<String, dynamic>? _tripData;

  void _checkProximity() {
    if (_driverLocation == null || _tripData == null) return;
    if (_status != 'accepted' && _status != 'driver_found' && _status != 'driver_en_route') return;

    final pickupLat = _tripData!['pickup_lat'];
    final pickupLon = _tripData!['pickup_lon'];
    if (pickupLat == null || pickupLon == null) return;

    final pickupLocation = LatLng(pickupLat, pickupLon);
    final distance = const Distance().as(LengthUnit.Meter, _driverLocation!, pickupLocation);

    setState(() {
      _distanceToPickup = distance.toDouble();
    });

    // Gatilhos de Alerta
    if (distance <= 500 && !_hasTriggered500m) {
      _hasTriggered500m = true;
      _showAlert('500m');
    } else if (distance <= 100 && !_hasTriggered100m) {
      _hasTriggered100m = true;
      _showAlert('100m');
    }
    
    // Alerta de Chegada (quando status muda ou distância < 30m)
    if ((distance <= 30 || _status == 'arrived') && !_hasTriggeredArrived) {
      _hasTriggeredArrived = true;
      _showAlert('arrived');
    }
  }

  void _showAlert(String type) {
    setState(() {
      _alert500mShow = type == '500m';
      _alert100mShow = type == '100m';
      _alertArrivedShow = type == 'arrived';
    });

    // Oculta após 5 segundos, exceto 'arrived' que pode ser mais persistente
    if (type != 'arrived') {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            if (type == '500m') _alert500mShow = false;
            if (type == '100m') _alert100mShow = false;
          });
        }
      });
    }
  }

  Future<void> _fetchDriverProfile(int driverId) async {
    if (_isLoadingDriver || (_driverProfile != null && _driverProfile!['id'] == driverId)) return;
    
    setState(() => _isLoadingDriver = true);
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('*')
          .eq('id', driverId)
          .maybeSingle();

      if (mounted && res != null) {
        setState(() => _driverProfile = res);
      }
    } catch (e) {
      debugPrint('Erro ao buscar perfil do motorista: $e');
    } finally {
      if (mounted) setState(() => _isLoadingDriver = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // MAPA VIVO
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _uberService.watchDriverLocation(widget.tripId),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                final data = snapshot.data!.first;
                final newLocation = LatLng(
                  data['latitude'] ?? 0.0,
                  data['longitude'] ?? 0.0,
                );
                
                if (_driverLocation != null && _driverLocation != newLocation) {
                  _previousLocation = _driverLocation;
                  _bearing = _calculateBearing(_previousLocation!, newLocation);
                  
                  // 🧭 Rotaciona o mapa para seguir a direção do carro
                  if (_bearing != 0) {
                    _mapController.rotate(-_bearing);
                  }
                  
                  // Lógica de Proximidade
                  final tripData = snapshot.data!.first; // Assumindo snapshot watchDriverLocation
                  // No UberService, watchDriverLocation retorna List<Map<String, dynamic>>
                  // O tripId está disponível em widget.tripId
                }
                _driverLocation = newLocation;

                // Calculamos a distância se tivermos os dados do pickup (buscados via watchTrip mais abaixo)
                // Para simplificar, vou mover a lógica de vigilância para um lugar comum ou usar um listener de _status
                _checkProximity();

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_driverLocation != null) {
                    _mapController.move(_driverLocation!, 15.0);
                  }
                });
              }

              return FlutterMap(
                mapController: _mapController,
                options: const MapOptions(
                  initialCenter: LatLng(-23.5505, -46.6333),
                  initialZoom: 15.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=${dotenv.env['MAPBOX_TOKEN'] ?? ''}',
                    userAgentPackageName: 'com.play101.app',
                    tileSize: 512,
                    zoomOffset: -1,
                    maxZoom: 22,
                  ),
                  if (_routePoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          strokeWidth: 5,
                          color: Colors.blue.withValues(alpha: 0.6),
                          borderColor: Colors.blue.shade900,
                          borderStrokeWidth: 1,
                        ),
                      ],
                    ),
                  if (_driverLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _driverLocation!,
                          width: 60,
                          height: 60,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: _bearing, end: _bearing),
                            duration: const Duration(milliseconds: 500),
                            builder: (context, angle, child) {
                              return Transform.rotate(
                                angle: angle * (pi / 180),
                                child: _buildDriverMarker(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
          
          // CABEÇALHO GLASS (STITCH)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ColorFilter.mode(Colors.white.withValues(alpha: 0.8), BlendMode.srcOver),
                child: Container(
                  padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 10, 20, 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    border: Border(
                      bottom: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
                    ),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/home'),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                              )
                            ],
                          ),
                          child: const Icon(LucideIcons.arrowLeft, size: 20, color: AppTheme.textDark),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '101 Service',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 40), // Balanço do botão de voltar
                    ],
                  ),
                ),
              ),
            ),
          ),

          StreamBuilder<Map<String, dynamic>>(
            stream: _uberService.watchTrip(widget.tripId),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                final data = snapshot.data!;
                _tripData = data; // Atualiza a referência global para o cálculo de proximidade
                _status = data['status'] ?? 'searching';

                // Busca perfil do motorista assim que for atribuído
                if (data['driver_id'] != null && _driverProfile == null) {
                   _fetchDriverProfile(data['driver_id'] as int);
                }

                // Busca a rota uma única vez quando os dados da viagem chegam
                if (!_hasFetchedRoute && data['pickup_lat'] != null && data['dropoff_lat'] != null) {
                  _hasFetchedRoute = true;
                  Future.microtask(() async {
                    final points = await MapService().getRoutePoints(
                      LatLng(data['pickup_lat'], data['pickup_lon']),
                      LatLng(data['dropoff_lat'], data['dropoff_lon']),
                    );
                    if (mounted) {
                      setState(() => _routePoints = points);
                    }
                  });
                }
              }

              return Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      _buildStatusHeader(_status),
                      const SizedBox(height: 24),
                      
                      const Divider(),
                      const SizedBox(height: 24),

                      // Driver Info - Exibe apenas se houver motorista atribuído
                      if (_status != 'searching') 
                        if (_isLoadingDriver)
                           const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator()),
                           )
                        else if (_driverProfile != null)
                          Row(
                            children: [
                              Stack(
                                children: [
                                  Container(
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryYellow.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: AppTheme.primaryYellow.withValues(alpha: 0.3), width: 2),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: _driverProfile!['avatar_url'] != null
                                          ? Image.network(_driverProfile!['avatar_url'], fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(LucideIcons.user, size: 35, color: AppTheme.textDark))
                                          : const Icon(LucideIcons.user, size: 35, color: AppTheme.textDark),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 2,
                                    right: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.1),
                                            blurRadius: 4,
                                          )
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                                          const SizedBox(width: 2),
                                          Text(
                                            (_driverProfile!['rating'] ?? 5.0).toStringAsFixed(1),
                                            style: GoogleFonts.manrope(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: AppTheme.textDark,
                                            ),
                                          ),
                                        ],
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
                                      _driverProfile!['first_name'] ?? _driverProfile!['full_name'] ?? 'Motorista Parceiro',
                                      style: GoogleFonts.manrope(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.textDark,
                                      ),
                                    ),
                                    Text(
                                      _driverProfile!['vehicle_model'] ?? 'Veículo padrão',
                                      style: GoogleFonts.manrope(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryYellow.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(32),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(LucideIcons.clock, size: 12, color: AppTheme.textDark),
                                          const SizedBox(width: 6),
                                          Text(
                                            _distanceToPickup != null && _distanceToPickup! > 0
                                              ? '${(_distanceToPickup! / 250).toStringAsFixed(0)} min away'
                                              : 'A caminho',
                                            style: GoogleFonts.manrope(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.textDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  // Ligar
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryYellow.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(LucideIcons.phone, size: 24, color: AppTheme.textDark),
                                ),
                              ),
                            ],
                          ),
                          
                      if (_status != 'searching')
                        const SizedBox(height: 32),

                      // Quick Actions (Stitch Grid)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                // Chat
                              },
                              icon: const Icon(LucideIcons.messageSquare, size: 20),
                              label: const Text('Chat'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryYellow,
                                foregroundColor: AppTheme.textDark,
                                minimumSize: const Size(double.infinity, 56),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                // Cancelar
                              },
                              icon: const Icon(LucideIcons.x, size: 20),
                              label: const Text('Cancelar'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[100],
                                foregroundColor: Colors.grey[600],
                                minimumSize: const Size(double.infinity, 56),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
           
          // Alertas de Proximidade (Top Banner)
          _buildProximityAlerts(),
        ],
      ),
    );
  }

  Widget _buildProximityAlerts() {
    bool show = _alert500mShow || _alert100mShow || _alertArrivedShow;
    if (!show) return const SizedBox.shrink();

    String message = '';
    Color color = AppTheme.primaryYellow;
    IconData icon = LucideIcons.navigation;

    if (_alert500mShow) {
      message = 'O motorista está a caminho! (500m)';
      color = Colors.blue;
      icon = LucideIcons.navigation;
    } else if (_alert100mShow) {
      message = 'Prepare-se! O motorista está chegando.';
      color = AppTheme.primaryYellow;
      icon = LucideIcons.bell;
    } else if (_alertArrivedShow) {
      message = 'O motorista está no local de embarque!';
      color = Colors.green;
      icon = LucideIcons.checkCircle;
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 80,
      left: 20,
      right: 20,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, (1 - value) * -50),
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              )
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.textDark, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.manrope(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _alert500mShow = false;
                  _alert100mShow = false;
                  _alertArrivedShow = false;
                }),
                child: const Icon(LucideIcons.x, color: AppTheme.textDark, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeader(String status) {
    String title = 'Procurando motorista...';
    String subtitle = 'Isso pode levar alguns minutos';
    IconData icon = LucideIcons.search;
    Color color = Colors.orange;

    switch (status) {
      case 'searching':
        title = 'Procurando motoristas...';
        subtitle = 'Aguarde um momento';
        icon = LucideIcons.search;
        color = Colors.orange;
        break;
      case 'accepted':
      case 'driver_found':
        title = 'Motorista Encontrado';
        subtitle = 'Ricardo está a caminho';
        icon = LucideIcons.checkCircle;
        color = Colors.green;
        break;
      case 'driver_en_route':
        title = 'Motorista a caminho';
        subtitle = 'Chega em 3 min';
        icon = LucideIcons.navigation;
        color = Colors.blue;
        break;
      case 'arrived':
        title = 'O motorista chegou!';
        subtitle = 'Vá ao local de encontro';
        icon = LucideIcons.mapPin;
        color = AppTheme.primaryYellow;
        break;
      case 'in_progress':
        title = 'Em viagem';
        subtitle = 'Chegada prevista às 10:45';
        icon = LucideIcons.trendingUp;
        color = Colors.indigo;
        break;
      case 'completed':
        title = 'Viagem concluída';
        subtitle = 'Espero que tenha gostado!';
        icon = LucideIcons.check;
        color = Colors.green;
        break;
    }

    return Row(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            ScaleTransition(
              scale: Tween(begin: 1.0, end: 1.8).animate(
                CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
              ),
              child: FadeTransition(
                opacity: Tween(begin: 0.5, end: 0.0).animate(
                  CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
                ),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, {Color? color}) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color ?? AppTheme.textDark),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color ?? AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Efeito de Pulso (Mapa)
        ScaleTransition(
          scale: Tween(begin: 1.0, end: 2.2).animate(
            CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
          ),
          child: FadeTransition(
            opacity: Tween(begin: 0.6, end: 0.0).animate(
              CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
            ),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        // Ícone do Carro
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
            border: Border.all(color: Colors.blue, width: 2),
          ),
          child: const Center(
            child: Icon(LucideIcons.navigation, color: Colors.blue, size: 20),
          ),
        ),
      ],
    );
  }
}
