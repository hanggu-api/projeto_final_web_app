import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

import 'package:latlong2/latlong.dart';
import '../home_state.dart';
import '../../../services/api_service.dart';

mixin HomeLocationMixin<T extends StatefulWidget>
    on State<T>, HomeStateMixin<T> {
  final ApiService _apiService = ApiService();
  bool _isDisposed = false;

  void _safeMoveMap(LatLng target, double zoom) {
    if (!mounted || isInTripMode || !isMapReady) return;
    try {
      mapController.move(target, zoom);
    } catch (e) {
      debugPrint('🗺️ [HomeMap] move ignorado (mapa ainda não pronto): $e');
    }
  }

  Future<void> checkLocationPermission() async {
    if (!mounted || _isDisposed) return;
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

        if (mounted && !_isDisposed) {
          final lat = posRaw.latitude;
          final lon = posRaw.longitude;
          setState(() {
            currentPosition = LatLng(lat, lon);
            pickupLocation = currentPosition;
            locationError = null;
            isLocating = false;
          });
          _safeMoveMap(currentPosition, 15);
          await updateCurrentAddress(lat, lon);
        }
      } catch (e) {
        debugPrint('🌐 [HomeGPS Web] Falhou (normal): $e');
      } finally {
        if (mounted && !_isDisposed) setState(() => isLocating = false);
      }
      return; // Não bloqueia mais nada no web
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted || _isDisposed) return;
        setState(() {
          locationError = 'Localização desativada no sistema.';
          isLocating = false;
        });
        if (mounted && !_isDisposed) {
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
        if (!mounted || _isDisposed) return;
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
          if (lastPos != null && mounted && !_isDisposed) {
            setState(() {
              currentPosition = LatLng(lastPos.latitude, lastPos.longitude);
              pickupLocation = currentPosition;
            });
            _safeMoveMap(currentPosition, 15);
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
          if (mounted && !_isDisposed) {
            setState(() {
              locationError = 'Não foi possível obter sua localização exata.';
              isLocating = false;
            });
          }
          return;
        }

        if (posRaw != null && mounted && !_isDisposed) {
          final double lat = posRaw.latitude;
          final double lon = posRaw.longitude;

          setState(() {
            currentPosition = LatLng(lat, lon);
            pickupLocation = currentPosition;
            locationError = null;
          });
          _safeMoveMap(currentPosition, 15);
          await updateCurrentAddress(lat, lon);
        }
      }
    } catch (e) {
      debugPrint('Erro Fatal Localização: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          locationError = 'Erro ao obter localização. Tente manualmente.';
        });
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => isLocating = false);
      }
    }
  }

  Future<void> updateCurrentAddress(double lat, double lon) async {
    try {
      final res = await _apiService.reverseGeocode(lat, lon);
      if (mounted && !_isDisposed) {
        setState(() {
          try {
            pickupController.text =
                res['main_text'] ?? res['display_name'] ?? 'Meu Local';
          } catch (_) {}
          pickupLocation = LatLng(lat, lon);
        });
      }
    } catch (e) {
      debugPrint('Erro ao obter endereço: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          try {
            pickupController.text = 'Localização Atual';
          } catch (_) {}
        });
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
