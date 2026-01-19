import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/uber_service.dart';
import '../../services/analytics_service.dart';
import '../../core/theme/app_theme.dart';

class UberRequestScreen extends StatefulWidget {
  const UberRequestScreen({super.key});

  @override
  State<UberRequestScreen> createState() => _UberRequestScreenState();
}

class _UberRequestScreenState extends State<UberRequestScreen> {
  final UberService _uberService = UberService();
  final MapController _mapController = MapController();
  
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;
  bool _selectingPickup = true;
  bool _isLoading = false;
  Map<String, dynamic>? _fareEstimate;

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      if (_selectingPickup) {
        _pickupLocation = point;
      } else {
        _dropoffLocation = point;
        _calculateFare();
      }
    });
  }

  Future<void> _calculateFare() async {
    if (_pickupLocation == null || _dropoffLocation == null) return;

    setState(() => _isLoading = true);
    try {
      final fare = await _uberService.calculateFare(
        pickupLat: _pickupLocation!.latitude,
        pickupLng: _pickupLocation!.longitude,
        dropoffLat: _dropoffLocation!.latitude,
        dropoffLng: _dropoffLocation!.longitude,
        vehicleTypeId: 1, // Default UberX
      );
      setState(() => _fareEstimate = fare);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao calcular tarifa: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _requestRide() async {
    if (_pickupLocation == null || _dropoffLocation == null) return;

    setState(() => _isLoading = true);
    try {
      final trip = await _uberService.requestTrip(
        pickupLat: _pickupLocation!.latitude,
        pickupLng: _pickupLocation!.longitude,
        pickupAddress: 'Local de Partida',
        dropoffLat: _dropoffLocation!.latitude,
        dropoffLng: _dropoffLocation!.longitude,
        dropoffAddress: 'Destino',
        vehicleTypeId: 1,
      );

      if (mounted) {
        AnalyticsService().logEvent('REQUEST_SERVICE', details: {
           'pickup_lat': _pickupLocation!.latitude,
           'pickup_lng': _pickupLocation!.longitude,
           'dropoff_lat': _dropoffLocation!.latitude,
           'dropoff_lng': _dropoffLocation!.longitude,
           'vehicle_type_id': 1,
           'estimated_price': _fareEstimate != null ? _fareEstimate!['estimated'] : null,
           'estimated_distance_km': _fareEstimate != null ? _fareEstimate!['distance_km'] : null,
        });

        // Navegar para rastreamento
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Viagem solicitada com sucesso!')),
        );
        // TO-DO: Navigator.push para UberTrackingScreen
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao solicitar viagem: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Solicitar Viagem',
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
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _pickupLocation ?? const LatLng(-23.5505, -46.6333),
                initialZoom: 15.0,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=\${dotenv.env[\'MAPBOX_TOKEN\'] ?? \'\'}',
                  userAgentPackageName: 'com.service101.app',
                ),
                MarkerLayer(
                  markers: [
                    if (_pickupLocation != null)
                      Marker(
                        point: _pickupLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on, color: Colors.blue, size: 40),
                      ),
                    if (_dropoffLocation != null)
                      Marker(
                        point: _dropoffLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Alça visual
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectingPickup ? AppTheme.primaryYellow : Colors.grey[200],
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => setState(() => _selectingPickup = true),
                        child: const Text('Partida', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !_selectingPickup ? AppTheme.primaryYellow : Colors.grey[200],
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => setState(() => _selectingPickup = false),
                        child: const Text('Destino', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_fareEstimate != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Valor Estimado:',
                        style: TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                      Text(
                        'R\$ ${_fareEstimate!['estimated']}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Distância:', style: TextStyle(color: Colors.black54)),
                      Text('${_fareEstimate!['distance_km']} km', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: (_pickupLocation != null && _dropoffLocation != null && !_isLoading)
                        ? _requestRide
                        : null,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'PEDIR AGORA',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
