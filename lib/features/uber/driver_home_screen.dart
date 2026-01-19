import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/uber_service.dart';
import '../../core/theme/app_theme.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final UberService _uberService = UberService();
  final MapController _mapController = MapController();
  
  bool _isOnline = false;
  bool _isLoading = false;
  LatLng? _currentLocation;
  StreamSubscription<Position>? _positionStream;

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() => _isLoading = true);
    
    try {
      if (value) {
        // Solicitar permissão de localização
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) return;
        }

        final position = await Geolocator.getCurrentPosition();
        setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
        
        // Ativar tracking
        _startTracking();
      } else {
        _stopTracking();
      }

      await _uberService.toggleDriverStatus(
        isOnline: value,
        driverId: 10, // TO-DO: Usar ID real
        latitude: _currentLocation?.latitude,
        longitude: _currentLocation?.longitude,
      );

      setState(() {
        _isOnline = value;
      });
    } catch (e) {
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
        distanceFilter: 10, // Notificar a cada 10 metros
      ),
    ).listen((Position position) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      
      // TO-DO: Enviar para o backend/Firestore o tracking
      // print('📍 Nova posição: ${position.latitude}, ${position.longitude}');
    });
  }

  void _stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Motorista'),
        backgroundColor: AppTheme.primaryYellow,
        actions: [
          Row(
            children: [
              Text(_isOnline ? 'Online' : 'Offline', style: const TextStyle(color: Colors.black)),
              Switch(
                value: _isOnline,
                activeColor: Colors.green,
                onChanged: _isLoading ? null : _toggleOnline,
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(-23.5505, -46.6333),
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=\${dotenv.env[\'MAPBOX_TOKEN\'] ?? \'\'}',
                userAgentPackageName: 'com.service101.app',
              ),
              MarkerLayer(
                markers: [
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 50,
                      height: 50,
                      child: const Icon(Icons.directions_car, color: Colors.blue, size: 50),
                    ),
                ],
              ),
            ],
          ),
          
          if (!_isOnline)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 80, color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'VOCÊ ESTÁ OFFLINE',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Fique online para receber corridas',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            
          // Exemplo de Proposta de Viagem (Mocked)
          if (_isOnline)
            _buildTripProposalOverlay(),
        ],
      ),
    );
  }

  Widget _buildTripProposalOverlay() {
    // Apenas para demonstração visual
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: FadeInUp(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('NOVA VIAGEM DISPONÍVEL', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              const Divider(),
              const Row(
                children: [
                  Icon(Icons.location_on, color: Colors.green),
                  SizedBox(width: 10),
                  Expanded(child: Text('Av. Paulista, 1000', overflow: TextOverflow.ellipsis)),
                ],
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.flag, color: Colors.red),
                  SizedBox(width: 10),
                  Expanded(child: Text('Parque Ibirapuera', overflow: TextOverflow.ellipsis)),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('3.5 km', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('R\$ 15,50', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      child: const Text('IGNORAR'),
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      child: const Text('ACEITAR'),
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Widget simples para animação (substituir por Lottie ou similar se quiser)
class FadeInUp extends StatelessWidget {
  final Widget child;
  const FadeInUp({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return child; // Simplificado
  }
}
