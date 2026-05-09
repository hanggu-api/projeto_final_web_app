import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/maps/app_tile_layer.dart';
import '../../../services/api_service.dart';

class LocationStep extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController addressController;
  final Function(double lat, double lng)? onLocationChanged;
  final double? initialLat;
  final double? initialLng;
  final bool isMobileProvider;

  const LocationStep({
    super.key,
    required this.formKey,
    required this.addressController,
    this.onLocationChanged,
    this.initialLat,
    this.initialLng,
    this.isMobileProvider = false,
  });

  @override
  State<LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<LocationStep> {
  final MapController _mapController = MapController();
  final ApiService _api = ApiService();
  LatLng _currentCenter = const LatLng(-5.5265, -47.4761); // Imperatriz Default
  bool _locating = false;
  bool _isGeocoding = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _currentCenter = LatLng(widget.initialLat!, widget.initialLng!);
      // Sempre resolve endereço no carregamento para evitar mostrar apenas coords.
      _reverseGeocode(_currentCenter);
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
      // Use Edge Function (Mapbox) via ApiService
      debugPrint(
        '[LocationStep] reverse request lat=${latLng.latitude.toStringAsFixed(6)} lon=${latLng.longitude.toStringAsFixed(6)}',
      );
      final result = await _api.reverseGeocode(
        latLng.latitude,
        latLng.longitude,
      );
      if (kDebugMode) {
        final debugPayload = {
          'street': result['street'],
          'house_number': result['house_number'],
          'neighborhood': result['neighborhood'] ?? result['suburb'],
          'city': result['city'],
          'state_code': result['state_code'],
          'display_name': result['display_name'],
        };
        debugPrint('[LocationStep] reverse payload: ${jsonEncode(debugPayload)}');
      }

      String formattedAddress = widget.isMobileProvider
          ? 'Região não identificada'
          : 'Endereço não identificado';

      if (result.isNotEmpty) {
        String readAny(List<String> keys) {
          for (final k in keys) {
            final v = result[k];
            if (v != null && v.toString().trim().isNotEmpty) {
              return v.toString().trim();
            }
          }
          return '';
        }

        final street = readAny([
          'street',
          'road',
          'street_name',
          'address_line1',
          'address_line',
        ]);
        final number = readAny(['house_number', 'street_number', 'number']);
        final neighborhood = readAny([
          'neighborhood',
          'neighbourhood',
          'suburb',
          'district',
        ]);
        final city = readAny([
          'city',
          'town',
          'municipality',
          'county',
        ]);
        final state = readAny(['state_code', 'state']);
        final displayName = readAny(['display_name']);

        String firstLine = '';
        if (street.isNotEmpty) {
          firstLine = number.isNotEmpty ? '$street, $number' : street;
        }
        if (firstLine.isEmpty && displayName.isNotEmpty) {
          firstLine = displayName.split(',').first.trim();
        }
        if (firstLine.isEmpty && neighborhood.isNotEmpty) {
          firstLine = neighborhood;
        }

        final secondLineParts = <String>[];
        if (neighborhood.isNotEmpty && neighborhood != firstLine) {
          secondLineParts.add(neighborhood);
        }
        if (city.isNotEmpty) {
          secondLineParts.add(city);
        }
        final secondLineCore = secondLineParts.join(', ');
        final secondLine = state.isNotEmpty
            ? (secondLineCore.isEmpty ? state : '$secondLineCore - $state')
            : secondLineCore;

        if (firstLine.isNotEmpty || secondLine.isNotEmpty) {
          formattedAddress = [firstLine, secondLine]
              .where((line) => line.trim().isNotEmpty)
              .join('\n');
        } else if (displayName.isNotEmpty) {
          final parts = displayName
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .take(3)
              .toList();
          if (parts.isNotEmpty) {
            formattedAddress = parts.join(', ');
          }
        }
      }

      if (mounted) {
        setState(() {
          widget.addressController.text = formattedAddress;
        });
        debugPrint('[LocationStep] endereço formatado="$formattedAddress"');
      }
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
      if (mounted) {
        setState(() {
          widget.addressController.text = widget.isMobileProvider
              ? 'Região não identificada'
              : 'Endereço não identificado';
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
    final title = widget.isMobileProvider
        ? 'Região onde você prefere receber notificações'
        : 'Localização do Estabelecimento';
    final subtitle = widget.isMobileProvider
        ? 'Ajuste o pino no mapa. O sistema vai priorizar notificações próximas de você.'
        : 'Ajuste o pino no mapa para a localização exata';
    final addressLabel =
        widget.isMobileProvider ? 'Região de Referência' : 'Endereço Completo';
    final addressHelper = widget.isMobileProvider
        ? 'Seu endereço não é visível para outros prestadores nem para clientes.'
        : 'Rua, Número, Bairro, Cidade - UF';

    return SingleChildScrollView(
      child: Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (widget.isMobileProvider) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.privacy_tip_outlined,
                      size: 18,
                      color: Color(0xFF1565C0),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Seu endereço é privado. Essa localização é usada apenas para priorizar chamadas na sua região.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1E3A8A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                        AppTileLayer.standard(
                          mapboxToken: SupabaseConfig.mapboxToken,
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
                    addressLabel,
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
                    helperText: addressHelper,
                  ),
              maxLines: 2,
              validator: (v) => v?.isEmpty == true
                  ? (widget.isMobileProvider
                        ? 'Informe uma região de referência'
                        : 'Informe o endereço completo')
                  : null,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
