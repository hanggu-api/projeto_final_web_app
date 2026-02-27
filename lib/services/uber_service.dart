import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'api_service.dart';

class UberService {
  final ApiService _api = ApiService();

  static final UberService _instance = UberService._internal();
  factory UberService() => _instance;
  UberService._internal();

  Timer? _simulationTimer;
  StreamController<int>? _simulationProgressController;

  Stream<int>? get simulationProgress => _simulationProgressController?.stream;

  /// Verifica se o módulo Uber está habilitado nas configurações globais
  Future<bool> isModuleEnabled() async {
    try {
      final config = await _api.getAppConfig();
      return config['uber_module_enabled'] == 'true' || config['uber_module_enabled'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Calcula o preço estimado da viagem
  Future<dynamic> calculateFare({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required int vehicleTypeId,
  }) async {
    return await _api.calculateUberFare(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
      vehicleTypeId: vehicleTypeId,
    );
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
    required String paymentMethod,
    double? fare,
  }) async {
    final client = Supabase.instance.client;
    
    if (fare == null || fare == 0) {
      debugPrint('⚠️ [DB_SAVE] ATENÇÃO: A tarifa está sendo enviada como $fare');
    }

    final tripData = {
      'client_id': _api.userId,
      'vehicle_type_id': vehicleTypeId,
      'pickup_lat': pickupLat,
      'pickup_lon': pickupLng,
      'pickup_address': pickupAddress,
      'dropoff_lat': dropoffLat,
      'dropoff_lon': dropoffLng,
      'dropoff_address': dropoffAddress,
      'status': 'searching',
      'fare_estimated': fare,
    };

    debugPrint('💾 [DB_SAVE] Tentando salvar nova viagem no banco:');
    debugPrint(const JsonEncoder.withIndent('  ').convert(tripData));

    try {
      final response = await client.from('trips').insert(tripData).select().single().timeout(const Duration(seconds: 15));
      debugPrint('✅ [DB_SAVE] Viagem salva com sucesso! ID: ${response['id']}');
      return {'trip_id': response['id'], 'success': true, ...response};
    } on TimeoutException {
      throw ApiException(message: 'Tempo esgotado ao solicitar viagem. Verifique sua conexão.', statusCode: 408);
    } catch (e) {
      debugPrint('❌ [DB_SAVE] Erro ao salvar viagem: $e');
      throw ApiException(message: 'Erro ao processar sua solicitação de viagem. Tente novamente.', statusCode: 500);
    }
  }

  /// Motorista: Alterna entre online e offline
  Future<void> toggleDriverStatus({
    required bool isOnline,
    required int driverId,
    double? latitude,
    double? longitude,
  }) async {
    final client = Supabase.instance.client;
    
    await client.from('users').update({
      'is_online': isOnline,
      'last_seen_at': DateTime.now().toIso8601String(),
    }).eq('id', driverId);

    if (latitude != null && longitude != null) {
      await updateDriverLocation(
        driverId: driverId,
        latitude: latitude,
        longitude: longitude,
        forceHistory: true, // Força registro no histórico ao entrar/sair de online
      );
    }
  }

  // Controle de throttle para histórico (evitar sobrecarga)
  final Map<int, DateTime> _lastHistoryLog = {};

  /// Motorista: Atualiza localização em tempo real
  Future<void> updateDriverLocation({
    required int driverId,
    required double latitude,
    required double longitude,
    bool forceHistory = false,
  }) async {
    try {
      final client = Supabase.instance.client;
      final now = DateTime.now();

      // 1. Atualiza localização em tempo real (Upsert)
      await client.from('driver_locations').upsert({
        'driver_id': driverId,
        'latitude': latitude,
        'longitude': longitude,
        'updated_at': now.toIso8601String(),
      }, onConflict: 'driver_id');

      // 2. Salva no histórico de longa data para Heatmaps
      // Salva se for forçado ou se passaram mais de 60 segundos desde a última gravação
      final lastLog = _lastHistoryLog[driverId];
      if (forceHistory || lastLog == null || now.difference(lastLog).inSeconds >= 60) {
        await client.from('driver_location_history').insert({
          'driver_id': driverId,
          'latitude': latitude,
          'longitude': longitude,
          'recorded_at': now.toIso8601String(),
        });
        _lastHistoryLog[driverId] = now;
        debugPrint('📈 [GPS_HISTORY] Localização persistida para histórico/heatmap');
      }
      
    } catch (e) {
      debugPrint('❌ [GPS] Erro ao atualizar localização: $e');
    }
  }

  /// Motorista: Escuta novas corridas disponíveis para o seu tipo de veículo
  Stream<List<Map<String, dynamic>>> streamAvailableTrips(int vehicleTypeId) {
    return Supabase.instance.client
        .from('trips')
        .stream(primaryKey: ['id'])
        .map((trips) {
          final filtered = trips.where((trip) => 
            trip['status'] == 'searching' && 
            trip['vehicle_type_id'] == vehicleTypeId
          ).toList();
          
          filtered.sort((a, b) {
            final dateA = DateTime.tryParse(a['requested_at'] ?? '') ?? DateTime(0);
            final dateB = DateTime.tryParse(b['requested_at'] ?? '') ?? DateTime(0);
            return dateB.compareTo(dateA);
          });
          
          return filtered;
        });
  }

  /// Motorista: Aceita uma corrida
  Future<void> acceptTrip(String tripId, int driverId) async {
    final client = Supabase.instance.client;
    
    // Captura localização atual para o marco de aceite
    LatLng? currentPos;
    try {
      final pos = await Geolocator.getCurrentPosition();
      currentPos = LatLng(pos.latitude, pos.longitude);
    } catch (_) {}

    final Map<String, dynamic> updates = {
      'status': 'accepted',
      'driver_id': driverId,
      'accepted_at': DateTime.now().toIso8601String(),
    };

    if (currentPos != null) {
      updates['accepted_lat'] = currentPos.latitude;
      updates['accepted_lon'] = currentPos.longitude;
    }

    await client.from('trips').update(updates).eq('id', tripId);
  }

  /// Busca o veículo do motorista para saber o tipo (carro/moto)
  Future<int?> getDriverVehicleTypeId(int driverId) async {
    try {
      final response = await Supabase.instance.client
          .from('vehicles')
          .select('vehicle_type_id')
          .eq('driver_id', driverId)
          .maybeSingle();
      return response?['vehicle_type_id'] as int?;
    } catch (e) {
      return null;
    }
  }

  /// Busca dados de qualquer usuário (cliente ou motorista)
  Future<Map<String, dynamic>?> getUserProfile(int userId) async {
    try {
      debugPrint('🔎 [UberService] Buscando perfil do usuário: $userId');
      final response = await Supabase.instance.client
          .from('users')
          .select('full_name, avatar_url, role')
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('❌ [UberService] ERRO CRÍTICO ao buscar perfil do usuário $userId: $e');
      if (e.toString().contains('Failed host lookup')) {
        debugPrint('🌐 [UberService] DICA: Verifique a conexão com a internet ou as configurações de DNS do Supabase.');
      }
      return null;
    }
  }

  /// Motorista ou Cliente: Atualiza o status de uma viagem
  Future<void> updateTripStatus(String tripId, String status, {int? clientId}) async {
    final client = Supabase.instance.client;
    final Map<String, dynamic> updates = {'status': status};
    final now = DateTime.now();

    // Captura localização atual para os marcos de embarque e desembarque
    LatLng? currentPos;
    try {
      final pos = await Geolocator.getCurrentPosition();
      currentPos = LatLng(pos.latitude, pos.longitude);
    } catch (_) {}
    
    if (status == 'in_progress') {
      updates['started_at'] = now.toIso8601String();
      if (currentPos != null) {
        updates['boarding_lat'] = currentPos.latitude;
        updates['boarding_lon'] = currentPos.longitude;
      }
    } else if (status == 'completed') {
      updates['completed_at'] = now.toIso8601String();
      if (currentPos != null) {
        updates['actual_dropoff_lat'] = currentPos.latitude;
        updates['actual_dropoff_lon'] = currentPos.longitude;
      }
    } else if (status == 'cancelled') {
      updates['cancelled_at'] = now.toIso8601String();
    }

    var query = client.from('trips').update(updates).eq('id', tripId);
    
    if (clientId != null) {
      query = query.eq('client_id', clientId);
    }

    await query;
  }

  /// Stream de acompanhamento em tempo real via Supabase
  Stream<Map<String, dynamic>> watchTrip(String tripId) {
    return Supabase.instance.client
        .from('trips')
        .stream(primaryKey: ['id'])
        .eq('id', tripId)
        .map((snapshot) => snapshot.isNotEmpty ? snapshot.first : {});
  }

  /// Stream para acompanhar a localização do motorista em tempo real
  /// Stream para acompanhar a localização do motorista em tempo real.
  /// Aceita [int] driverId para performance máxima ou [String] tripId para compatibilidade.
  Stream<List<Map<String, dynamic>>> watchDriverLocation(dynamic identifier) {
    if (identifier is int) {
      return Supabase.instance.client
          .from('driver_locations')
          .stream(primaryKey: ['driver_id'])
          .eq('driver_id', identifier);
    }
    
    // Fallback para tripId (String) - Mantém compatibilidade com telas antigas
    final tripId = identifier.toString();
    return Supabase.instance.client
        .from('trips')
        .stream(primaryKey: ['id'])
        .eq('id', tripId)
        .asyncMap((trips) async {
          if (trips.isEmpty || trips.first['driver_id'] == null) return [];
          final driverId = trips.first['driver_id'];
          final locations = await Supabase.instance.client
              .from('driver_locations')
              .select()
              .eq('driver_id', driverId);
          return (locations as List).map((e) => e as Map<String, dynamic>).toList();
        });
  }

  /// Busca a viagem ativa do cliente
  Future<Map<String, dynamic>?> getActiveTripForClient(int clientId) async {
    try {
      debugPrint('🔎 [DB_QUERY] Buscando viagem ativa para o cliente: $clientId');
      
      final dayAgo = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

      final response = await Supabase.instance.client
          .from('trips')
          .select('*, vehicle_types(display_name)')
          .eq('client_id', clientId)
          .filter('status', 'in', '("searching", "accepted", "arrived", "in_progress")')
          .gte('requested_at', dayAgo) // Ignora viagens fantasmas antigas
          .order('requested_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (response != null) {
        debugPrint('✅ [DB_QUERY] Viagem ativa recuperada para cliente: ${response['id']} (Status: ${response['status']})');
      }
      return response;
    } catch (e) {
      debugPrint('❌ [DB_QUERY] Erro ao consultar viagem ativa cliente: $e');
      return null;
    }
  }

  /// Busca a viagem ativa do motorista
  Future<Map<String, dynamic>?> getActiveTripForDriver(int driverId) async {
    try {
      debugPrint('🔎 [DB_QUERY] Buscando viagem ativa para o motorista: $driverId');
      
      final dayAgo = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

      final response = await Supabase.instance.client
          .from('trips')
          .select('*, vehicle_types(display_name)')
          .eq('driver_id', driverId)
          .filter('status', 'in', '("accepted", "arrived", "in_progress")')
          .gte('requested_at', dayAgo) // Ignora viagens fantasmas antigas
          .order('requested_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (response != null) {
        debugPrint('✅ [DB_QUERY] Viagem ativa recuperada para motorista: ${response['id']} (Status: ${response['status']})');
      }
      return response;
    } catch (e) {
      debugPrint('❌ [DB_QUERY] Erro ao consultar viagem ativa motorista: $e');
      return null;
    }
  }

  /// Recupera o histórico de viagens do usuário (Cliente)
  Future<List<Map<String, dynamic>>> getUserTrips(int userId) async {
    try {
      final response = await Supabase.instance.client
          .from('trips')
          .select('*, vehicle_types(display_name)')
          .eq('client_id', userId)
          .filter('status', 'in', '("completed", "cancelled")')
          .order('requested_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ [UberService] Erro ao buscar histórico: $e');
      return [];
    }
  }

  /// Salva a avaliação de uma viagem
  Future<void> rateTrip({
    required String tripId,
    required double rating,
    String? comment,
  }) async {
    try {
      // Usaremos as colunas 'rating' e 'rating_comment' que assumimos existir na tabela trips
      await Supabase.instance.client.from('trips').update({
        'rating': rating,
        'rating_comment': comment,
      }).eq('id', tripId);
      debugPrint('✅ [UberService] Avaliação salva com sucesso para a viagem $tripId');
    } catch (e) {
      debugPrint('❌ [UberService] Erro ao salvar avaliação: $e');
      // Não lançar erro crítico para não travar a UI, apenas logamos
    }
  }

  /// Inicia uma simulação de movimento seguindo uma polilinha
  void startRouteSimulation({
    required int driverId,
    required List<LatLng> polyline,
    Duration interval = const Duration(seconds: 1),
  }) {
    stopRouteSimulation(); // Para qualquer simulação anterior

    _simulationProgressController = StreamController<int>.broadcast();
    int currentIndex = 0;

    _simulationTimer = Timer.periodic(interval, (timer) async {
      if (currentIndex >= polyline.length) {
        stopRouteSimulation();
        return;
      }

      final point = polyline[currentIndex];
      await updateDriverLocation(
        driverId: driverId,
        latitude: point.latitude,
        longitude: point.longitude,
      );

      _simulationProgressController?.add(currentIndex);
      currentIndex++;
    });

    debugPrint('🚀 [Simulador] Iniciado para o motorista $driverId com ${polyline.length} pontos');
  }

  /// Para a simulação de movimento
  void stopRouteSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _simulationProgressController?.close();
    _simulationProgressController = null;
    debugPrint('🛑 [Simulador] Parado');
  }
}
