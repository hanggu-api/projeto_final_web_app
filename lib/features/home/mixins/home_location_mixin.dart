import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

import 'package:latlong2/latlong.dart';
import '../home_state.dart';
import '../../../services/api_service.dart';

mixin HomeLocationMixin<T extends StatefulWidget>
    on State<T>, HomeStateMixin<T> {
  final ApiService _apiService = ApiService();

  Future<void> checkLocationPermission() async {
    if (isLocating) return;
    setState(() {
      isLocating = true;
      locationError = null;
    });

    // 🌐 WEB: GPS no Chrome é instável. Tentamos por 8s e continuamos sem bloquear.
    if (kIsWeb) {
      try {
        final posRaw = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        ).timeout(const Duration(seconds: 9));

        if (mounted) {
          final lat = posRaw.latitude;
          final lon = posRaw.longitude;
          setState(() {
            currentPosition = LatLng(lat, lon);
            pickupLocation = currentPosition;
            locationError = null;
            isLocating = false;
          });
          if (!isInTripMode) mapController.move(currentPosition, 15);
          await updateCurrentAddress(lat, lon);
        }
      } catch (e) {
        debugPrint('🌐 [HomeGPS Web] Falhou (normal): $e');
      } finally {
        if (mounted) setState(() => isLocating = false);
      }
      return; // Não bloqueia mais nada no web
    }

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
        try {
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
        } catch (e) {
          debugPrint('Erro ao obter última localização (ignorando): $e');
        }

        dynamic posRaw;
        try {
          posRaw = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          ).timeout(const Duration(seconds: 12));
        } catch (e) {
          debugPrint('Erro GPS Mixin ($e)');
          if (mounted) {
            setState(() {
              locationError = 'Não foi possível obter sua localização exata.';
              isLocating = false;
            });
          }
          return;
        }

        if (posRaw != null && mounted) {
          final double lat = posRaw.latitude;
          final double lon = posRaw.longitude;

          setState(() {
            currentPosition = LatLng(lat, lon);
            pickupLocation = currentPosition;
            locationError = null;
          });
          if (!isInTripMode) {
            mapController.move(currentPosition, 15);
          }
          await updateCurrentAddress(lat, lon);
        }
      }
    } catch (e) {
      debugPrint('Erro Fatal Localização: $e');
      if (mounted) {
        setState(() {
          locationError = 'Erro ao obter localização. Tente manualmente.';
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
