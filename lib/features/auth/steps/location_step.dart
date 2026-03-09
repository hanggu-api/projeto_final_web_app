import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../core/theme/app_theme.dart';

class LocationStep extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController addressController;
  final Function(double lat, double lng)? onLocationChanged;
  final double? initialLat;
  final double? initialLng;

  const LocationStep({
    super.key,
    required this.formKey,
    required this.addressController,
    this.onLocationChanged,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<LocationStep> {
  final MapController _mapController = MapController();
  LatLng _currentCenter = const LatLng(-5.5265, -47.4761); // Imperatriz Default
  bool _locating = false;
  bool _isGeocoding = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _currentCenter = LatLng(widget.initialLat!, widget.initialLng!);
      // Optionally reverse geocode initial position if address is empty
      if (widget.addressController.text.isEmpty) {
        _reverseGeocode(_currentCenter);
      }
    } else {
      _locateUser();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _reverseGeocode(LatLng latLng) async {
    if (!mounted) return;
    setState(() => _isGeocoding = true);

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // Format: Rua X, 123, Bairro, Cidade - UF
        final street = place.thoroughfare ?? '';
        final number = place.subThoroughfare ?? '';
        final subLocality = place.subLocality ?? '';
        final locality = place.subAdministrativeArea ?? place.locality ?? '';
        final adminArea = place.administrativeArea ?? '';
        final postalCode = place.postalCode ?? '';

        String formattedAddress = '';
        if (street.isNotEmpty) formattedAddress += street;
        if (number.isNotEmpty) formattedAddress += ', $number';
        if (subLocality.isNotEmpty) formattedAddress += ' - $subLocality';
        if (locality.isNotEmpty) formattedAddress += ', $locality';
        if (adminArea.isNotEmpty) formattedAddress += ' - $adminArea';
        if (postalCode.isNotEmpty) formattedAddress += ' ($postalCode)';

        // Remove leading comma/dash if street is empty
        if (formattedAddress.startsWith(', ') ||
            formattedAddress.startsWith(' - ')) {
          formattedAddress = formattedAddress.substring(2);
        }

        // Fallback if address is very short (e.g. just city)
        if (formattedAddress.trim().isEmpty) {
          formattedAddress =
              'Endereço aproximado: ${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
        }

        if (mounted) {
          setState(() {
            widget.addressController.text = formattedAddress;
          });
        }
      } else {
        if (mounted) {
          debugPrint(
            'No placemarks found for ${latLng.latitude}, ${latLng.longitude}',
          );
          // Fallback to coordinates
          setState(() {
            widget.addressController.text =
                'Loc: ${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
          });
        }
      }
    } catch (e) {
      // Suppress specific platform/library errors common on emulators
      if (e.toString().contains("Null check operator")) {
        debugPrint('Geocoding internal error (likely emulator issue): $e');
      } else {
        debugPrint('Error reverse geocoding: $e');
      }

      if (mounted) {
        // Fallback to coordinates on error
        setState(() {
          widget.addressController.text =
              'Loc: ${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
        });
      }
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  void _onMapMoved(LatLng pos) {
    widget.onLocationChanged?.call(pos.latitude, pos.longitude);

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      _reverseGeocode(pos);
    });
  }

  Future<void> _locateUser() async {
    if (!mounted) return;
    setState(() => _locating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Optionally ask to enable
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      // Check mounted before long async call
      if (!mounted) return;

      Position position = await Geolocator.getCurrentPosition();

      // Check mounted again after async call
      if (!mounted) return;

      final latLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentCenter = latLng;
      });
      _mapController.move(latLng, 15);

      // Update location and address immediately
      widget.onLocationChanged?.call(position.latitude, position.longitude);
      _reverseGeocode(latLng);
    } catch (e) {
      debugPrint('Error locating user: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Localização do Estabelecimento',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Ajuste o pino no mapa para a localização exata',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // MAP SECTION
            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentCenter,
                        initialZoom: 15.0,
                        onPositionChanged: (pos, hasGesture) {
                          if (hasGesture) {
                            _onMapMoved(pos.center);
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=${dotenv.env['MAPBOX_TOKEN'] ?? ''}',
                          userAgentPackageName: 'com.play101.app',
                          tileDimension: 512,
                          zoomOffset: -1,
                          maxZoom: 22,
                        ),
                        // Fixed marker at center
                        // Note: MarkerLayer with a fixed marker at center is tricky if we want the map to move under it.
                        // Actually, the previous implementation had a "Center" widget with an Icon over the map.
                        // This implies the "pin" is always at the center of the view.
                        // So dragging the map changes the coordinates under the pin.
                        // This is correct behavior for "Adjust pin".
                      ],
                    ),
                    const Center(
                      child: Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: FloatingActionButton(
                        heroTag: 'locate_btn',
                        onPressed: _locateUser,
                        backgroundColor: Colors.white,
                        child: _locating
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(
                                Icons.my_location,
                                color: Colors.black,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // "Use My Location" Button (Explicit)
            OutlinedButton.icon(
              onPressed: _locateUser,
              icon: const Icon(Icons.my_location),
              label: const Text('Usar minha localização atual'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black),
              ),
            ),

            const SizedBox(height: 24),

            // ADDRESS FIELD
            TextFormField(
              controller: widget.addressController,
              decoration:
                  AppTheme.inputDecoration(
                    'Endereço Completo',
                    Icons.map,
                  ).copyWith(
                    suffixIcon: _isGeocoding
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    helperText: 'Rua, Número, Bairro, Cidade - UF',
                  ),
              maxLines: 2,
              validator: (v) =>
                  v?.isEmpty == true ? 'Informe o endereço completo' : null,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
