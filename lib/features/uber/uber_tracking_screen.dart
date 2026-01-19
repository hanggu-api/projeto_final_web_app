import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/uber_service.dart';
import '../../core/theme/app_theme.dart';
import 'dart:math' show pi, atan2, sin, cos;


class UberTrackingScreen extends StatefulWidget {
  final String tripId;

  const UberTrackingScreen({super.key, required this.tripId});

  @override
  State<UberTrackingScreen> createState() => _UberTrackingScreenState();
}

class _UberTrackingScreenState extends State<UberTrackingScreen> {
  final UberService _uberService = UberService();
  final MapController _mapController = MapController();
  
  LatLng? _driverLocation;
  LatLng? _previousLocation;
  double _bearing = 0.0;
  String _status = 'Aguardando...';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Acompanhando Viagem',
          style: TextStyle(
            color: AppTheme.darkBlueText,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.primaryYellow,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.darkBlueText),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
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
                }
                _driverLocation = newLocation;

                // Centralizar mapa se for a primeira vez
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
                      urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${dotenv.env['MAPBOX_TOKEN'] ?? ''}',
                      userAgentPackageName: 'com.service101.app',
                    ),
                  if (_driverLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _driverLocation!,
                          width: 80,
                          height: 80,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: _bearing, end: _bearing),
                            duration: const Duration(milliseconds: 500),
                            builder: (context, angle, child) {
                              return Transform.rotate(
                                angle: angle * (pi / 180),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 45,
                                      height: 45,
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.navigation,
                                      color: Colors.blue,
                                      size: 35,
                                    ),
                                  ],
                                ),
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
          
          // Painel de Status
          StreamBuilder<Map<String, dynamic>>(
            stream: _uberService.watchTrip(widget.tripId),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                final data = snapshot.data!;
                _status = data['status'] ?? 'searching';
              }

              return Positioned(
                bottom: 32,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      _buildStatusIndicator(_status),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: AppTheme.primaryYellow,
                            child: const Icon(Icons.person, color: Colors.black),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('João Motorista', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('Toyota Corolla - ABC-1234', style: TextStyle(color: Colors.black54)),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.star, color: Colors.amber, size: 18),
                                  SizedBox(width: 4),
                                  Text('4.9', style: TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 40),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildActionButton(Icons.phone, 'Ligar'),
                          _buildActionButton(Icons.chat_bubble, 'Mensagem'),
                          _buildActionButton(Icons.warning, 'SOS', Colors.red),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String status) {
    String text = '';
    Color color = Colors.grey;

    switch (status) {
      case 'searching':
        text = 'Procurando motoristas...';
        color = Colors.orange;
        break;
      case 'driver_found':
        text = 'Motorista encontrado!';
        color = Colors.green;
        break;
      case 'driver_en_route':
        text = 'Motorista a caminho';
        color = Colors.blue;
        break;
      case 'arrived':
        text = 'Motorista chegou!';
        color = Colors.purple;
        break;
      case 'in_progress':
        text = 'Viagem em curso';
        color = Colors.indigo;
        break;
      case 'completed':
        text = 'Viagem concluída';
        color = Colors.green;
        break;
      default:
        text = 'Status desconhecido';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, [Color? color]) {
    return InkWell(
      onTap: () {}, // Funcionalidades a implementar
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color ?? Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
