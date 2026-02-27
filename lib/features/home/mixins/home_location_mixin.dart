import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../home_state.dart';
import '../../../services/api_service.dart';

mixin HomeLocationMixin<T extends StatefulWidget> on State<T>, HomeStateMixin<T> {
  final ApiService _apiService = ApiService();

  Future<void> checkLocationPermission() async {
    if (isLocating) return;
    setState(() {
      isLocating = true;
      locationError = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          locationError = 'Localização desativada no sistema.';
          isLocating = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Por favor, habilite o GPS.')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          locationError = 'Permissão de localização negada.';
          isLocating = false;
        });
        return;
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        // Tenta pegar a última conhecida primeiro (mais rápido)
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null && mounted) {
          setState(() {
            currentPosition = LatLng(lastPos.latitude, lastPos.longitude);
            pickupLocation = currentPosition;
          });
          if (!isInTripMode) {
            mapController.move(currentPosition, 15);
          }
        }

        // Busca posição atual com timeout
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );

        if (mounted) {
          setState(() {
            currentPosition = LatLng(pos.latitude, pos.longitude);
            pickupLocation = currentPosition;
            locationError = null;
          });
          if (!isInTripMode) {
            mapController.move(currentPosition, 15);
          }
          await updateCurrentAddress(pos.latitude, pos.longitude);
        }
      }
    } catch (e) {
      debugPrint('Erro ao obter localização: $e');
      if (mounted) {
        setState(() {
          locationError = 'Erro ao obter localização. Tente novamente.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => isLocating = false);
      }
    }
  }

  Future<void> updateCurrentAddress(double lat, double lon) async {
    try {
      final res = await _apiService.reverseGeocode(lat, lon);
      if (mounted) {
        setState(() {
          pickupController.text =
              res['main_text'] ?? res['display_name'] ?? 'Meu Local';
          pickupLocation = LatLng(lat, lon);
        });
      }
    } catch (e) {
      debugPrint('Erro ao obter endereço: $e');
      if (mounted) {
        setState(() {
          pickupController.text = 'Localização Atual';
        });
      }
    }
  }
}
