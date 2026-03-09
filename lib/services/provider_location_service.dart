// lib/services/provider_location_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';

class ProviderLocationService {
  static final _locationController = BehaviorSubject<Position>();

  static Stream<Position> get locationStream => _locationController.stream;

  /// Obtém a localização atual uma vez
  static Future<Position?> getCurrentLocation() async {
    try {
      // Verificar permissões
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('❌ Permissão de localização negada');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('❌ Permissão permanentemente negada');
        return null;
      }

      // Obter posição atual
      // Aumentamos o timeout pois o primeiro fix do GPS pode demorar,
      // especialmente em ambientes fechados ou no início do app.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );

      return position;
    } catch (e) {
      debugPrint(
        '⚠️ Timeout/Erro no GPS, tentando última posição conhecida: $e',
      );
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (e2) {
        debugPrint('❌ Falha total na localização: $e2');
        return null;
      }
    }
  }

  /// Inicia o streaming de localização em tempo real
  static StreamSubscription<Position>? startLocationStreaming({
    required void Function(Position) onUpdate,
    Duration interval = const Duration(seconds: 10),
  }) {
    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Atualiza a cada 10 metros
    );

    return Geolocator.getPositionStream(locationSettings: settings).listen((
      Position position,
    ) {
      _locationController.add(position);
      onUpdate(position);
    }, onError: (error) => debugPrint('❌ Erro no stream: $error'));
  }

  /// Para o streaming de localização
  static void stopLocationStreaming(StreamSubscription? subscription) {
    subscription?.cancel();
    _locationController.close();
  }

  /// Calcula distância entre duas coordenadas (em metros)
  static double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }
}
