import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';

class UberService {
  final ApiService _api = ApiService();

  static final UberService _instance = UberService._internal();
  factory UberService() => _instance;
  UberService._internal();

  /// Verifica se o módulo Uber está habilitado nas configurações globais
  Future<bool> isModuleEnabled() async {
    try {
      final config = await _api.get('/config');
      return config['uber_module_enabled'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Calcula o preço estimado da viagem
  Future<Map<String, dynamic>> calculateFare({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required int vehicleTypeId,
  }) async {
    final response = await _api.post('/uber/calculate-fare', {
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
      'vehicle_type_id': vehicleTypeId,
    });
    
    return response['fare'];
  }

  /// Solicita uma nova viagem
  Future<Map<String, dynamic>> requestTrip({
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double dropoffLat,
    required double dropoffLng,
    required String dropoffAddress,
    required int vehicleTypeId,
  }) async {
    final response = await _api.post('/uber/request', {
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'pickup_address': pickupAddress,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
      'dropoff_address': dropoffAddress,
      'vehicle_type_id': vehicleTypeId,
    });
    
    return response;
  }

  /// Motorista: Alterna entre online e offline
  Future<void> toggleDriverStatus({
    required bool isOnline,
    required int driverId,
    double? latitude,
    double? longitude,
  }) async {
    await _api.post('/uber/driver/toggle', {
      'driver_id': driverId,
      'is_online': isOnline,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// Stream de acompanhamento em tempo real via Supabase
  Stream<Map<String, dynamic>> watchTrip(String tripId) {
    return Supabase.instance.client
        .from('trips')
        .stream(primaryKey: ['id'])
        .eq('id', tripId)
        .map((snapshot) => snapshot.isNotEmpty ? snapshot.first : {});
  }

  /// Stream de localização do motorista em tempo real via Supabase
  Stream<List<Map<String, dynamic>>> watchDriverLocation(String tripId) {
    return Supabase.instance.client
        .from('trip_tracking')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('updated_at', ascending: false)
        .limit(1);
  }
}
