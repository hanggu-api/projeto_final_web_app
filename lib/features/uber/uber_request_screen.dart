import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';

import '../../services/uber_service.dart';
import '../../services/map_service.dart';
import '../../services/theme_service.dart';
import '../../services/api_service.dart';
import '../../core/theme/app_theme.dart';
import './widgets/car_marker_widget.dart';
import './widgets/uber_map_overlay.dart';
import 'dart:math' show sin, cos, atan2;

class UberRequestScreen extends StatefulWidget {
  const UberRequestScreen({super.key});

  @override
  State<UberRequestScreen> createState() => _UberRequestScreenState();
}

class _UberRequestScreenState extends State<UberRequestScreen> {
  final UberService _uberService = UberService();
  final MapController _mapController = MapController();
  final ApiService _api = ApiService();

  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropoffController = TextEditingController();
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _dropoffFocus = FocusNode();
  Timer? _debouncer;
  List<dynamic> _searchResults = [];
  bool _isSearchingLocation = false;
  bool _isPickingOnMap = false;
  bool _isMapReady = false;
  bool _selectingPickup = true;
  bool _isLoading = false;
  LatLng? _lastKnownGps; // GPS do dispositivo como refência de busca
  int _selectedVehicleId = 1;
  String _selectedPaymentMethod = 'PIX Direto';
  bool _isPaymentExpanded = false;
  bool _hasCreditCardLoaded = false;
  bool _hasCreditCard = false;

  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;
  List<LatLng> _routePoints = [];
  StreamSubscription<List<Map<String, dynamic>>>? _onlineDriversSubscription;
  List<Map<String, dynamic>> _onlineDrivers = [];
  final Map<int, int> _driverVehicleTypes =
      {}; // Cache driverId -> vehicleTypeId
  final Map<int, Map<String, bool>> _driverPaymentMethods =
      {}; // Cache driverId -> {pix_direct: bool, card_machine: bool}
  Map<int, dynamic> _vehicleFares =
      {}; // Cache de tarifas: vehicleTypeId -> data
  Map<String, dynamic>?
  _fareEstimate; // Mantido para compatibilidade se necessário, mas usarei _vehicleFares
  final Map<int, double> _driverBearings = {};
  final Map<int, LatLng> _lastDriverLocations = {};
  double? _routeDistance;
  double? _routeDuration;
  String _lastSearchQuery = ''; // Controla enriquecimento em background

  final List<Map<String, dynamic>> predefinedVehicles = [
    {
      'id': 1,
      'name': 'Carro',
      'icon': Icons.directions_car,
      'asset': 'assets/icons/036-car.png',
    },
    {
      'id': 3,
      'name': 'Moto',
      'icon': Icons.directions_bike,
      'asset': 'assets/icons/034-motorbike.png',
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ThemeService().setNavBarVisible(false);

      // Auto focar o destino ao abrir a tela de corrida após a animação da rota
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          _dropoffFocus.requestFocus();
        }
      });
    });

    _pickupFocus.addListener(_onFocusChange);
    _dropoffFocus.addListener(_onFocusChange);

    _getCurrentLocation();
    _startWatchingOnlineDrivers();
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() {
      if (_dropoffFocus.hasFocus) {
        _selectingPickup = false;
      } else if (_pickupFocus.hasFocus) {
        _selectingPickup = true;
      }
    });
  }

  void _onPickingLocationChanged(LatLng location) {
    if (_debouncer?.isActive ?? false) _debouncer!.cancel();
    _debouncer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final addressData = await _api.reverseGeocode(
          location.latitude,
          location.longitude,
        );
        if (mounted) {
          String address = 'Local selecionado';
          if (addressData['display_name'] != null) {
            address = addressData['display_name'].toString();
          } else if (addressData['address'] != null &&
              addressData['address'] is Map) {
            final addr = addressData['address'] as Map;
            final road = addr['road'] ?? '';
            final suburb = addr['suburb'] ?? addr['neighbourhood'] ?? '';
            if (road.isNotEmpty) {
              address = road + (suburb.isNotEmpty ? ', $suburb' : '');
            } else {
              address = suburb.isNotEmpty ? suburb : 'Local selecionado';
            }
          }

          setState(() {
            if (_selectingPickup) {
              _pickupLocation = location;
              _pickupController.text = address;
            } else {
              _dropoffLocation = location;
              _dropoffController.text = address;
            }
          });
        }
      } catch (e) {
        debugPrint('Erro no reverse geocode ao mover: $e');
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    if (mounted) {
      setState(() {
        _pickupController.text = 'Buscando sua localização...';
      });
    }

    if (kIsWeb) {
      await _getCurrentLocationWeb();
      return;
    }

    Position? pos;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _pickupController.clear();
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _pickupController.clear();
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _pickupController.clear();
          });
        }
        return;
      }

      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      ).timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('GPS Error ($e)');
      if (mounted) {
        setState(() {
          _pickupController.clear();
        });
      }
      return;
    }

    if (!mounted) return;

    final double lat = pos.latitude;
    final double lng = pos.longitude;

    setState(() {
      _pickupLocation = LatLng(lat, lng);
      _lastKnownGps = _pickupLocation; // Salva o GPS para usar como bias
      if (_isMapReady) {
        _mapController.move(_pickupLocation!, 15);
      }
      _pickupController.text = 'Identificando endereço...';
    });

    try {
      final res = await _api.reverseGeocode(lat, lng);
      if (mounted) {
        setState(() {
          String address = 'Meu Local';
          if (res['display_name'] != null) {
            address = res['display_name'].toString();
          } else if (res['address'] != null && res['address'] is Map) {
            final addr = res['address'] as Map;
            final road = addr['road'] ?? '';
            final suburb = addr['suburb'] ?? addr['neighbourhood'] ?? '';
            if (road.isNotEmpty) {
              address = road + (suburb.isNotEmpty ? ', $suburb' : '');
            } else {
              address = suburb.isNotEmpty ? suburb : 'Meu Local';
            }
          }
          _pickupController.text = address;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pickupController.text =
              'Meu Local (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
        });
      }
    }
  }

  Future<void> _getCurrentLocationWeb() async {
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      ).timeout(const Duration(seconds: 21));
    } catch (e) {
      if (mounted) _enableManualPickup();
      return;
    }

    if (!mounted) {
      _enableManualPickup();
      return;
    }

    final double lat = pos.latitude;
    final double lng = pos.longitude;

    setState(() {
      _pickupLocation = LatLng(lat, lng);
      _mapController.move(_pickupLocation!, 15);
      _pickupController.text = 'Identificando endereço...';
    });

    try {
      final res = await _api.reverseGeocode(lat, lng);
      if (mounted) {
        final address = res['display_name']?.toString() ?? 'Meu Local';
        setState(() => _pickupController.text = address);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _pickupController.text =
              'Meu Local (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})',
        );
      }
    }
  }

  void _enableManualPickup() {
    setState(() {
      _pickupController.text = '';
    });
    _pickupFocus.requestFocus();
  }

  void _onSearchQueryChanged(String query) {
    if (_debouncer?.isActive ?? false) _debouncer!.cancel();
    _debouncer = Timer(const Duration(milliseconds: 600), () async {
      final text = query.trim();
      if (text.length < 3) {
        if (mounted) setState(() => _searchResults = []);
        return;
      }
      if (mounted) setState(() => _isSearchingLocation = true);
      try {
        // Usa _pickupLocation como bias principal;
        // se nulo (usuário limpou origem), usa GPS salvo como referência
        final biasLat = _pickupLocation?.latitude ?? _lastKnownGps?.latitude;
        final biasLon = _pickupLocation?.longitude ?? _lastKnownGps?.longitude;
        final rawResults = await _api.searchAddress(
          text,
          lat: biasLat,
          lon: biasLon,
        );
        final initialResults = _quickParseTomTomResults(rawResults);
        if (mounted) {
          _lastSearchQuery = text;
          setState(() => _searchResults = initialResults);
          // Inicia a busca de bairros em background
          _backgroundEnrichNeighborhoods(text);
        }
      } catch (e) {
        debugPrint('Erro na busca: $e');
      } finally {
        if (mounted) setState(() => _isSearchingLocation = false);
      }
    });
  }

  IconData _getCategoryIcon(String? category) {
    if (category == null) return Icons.location_on_rounded;
    final cat = category.toUpperCase();
    if (cat.contains('MARKET') || cat.contains('SHOPPING')) {
      return Icons.shopping_cart_rounded;
    }
    if (cat.contains('RESTAURANT') ||
        cat.contains('FOOD') ||
        cat.contains('EAT')) {
      return Icons.restaurant_rounded;
    }
    if (cat.contains('GAS') || cat.contains('FUEL')) {
      return Icons.local_gas_station_rounded;
    }
    if (cat.contains('PHARMACY') || cat.contains('HEALTH')) {
      return Icons.local_pharmacy_rounded;
    }
    if (cat.contains('PARK') || cat.contains('SQUARE')) {
      return Icons.park_rounded;
    }
    if (cat.contains('HOSPITAL')) return Icons.local_hospital_rounded;
    if (cat.contains('BANK') || cat.contains('ATM')) {
      return Icons.account_balance_outlined;
    }
    if (cat.contains('HOTEL')) return Icons.hotel_rounded;
    if (cat.contains('SCHOOL') || cat.contains('UNIVERSITY')) {
      return Icons.school_rounded;
    }
    if (cat.contains('CHURCH')) return Icons.church_rounded;
    if (cat.contains('BAR')) return Icons.local_bar_rounded;
    return Icons.business_rounded;
  }

  Color _getCategoryColor(String? category) {
    if (category == null) return const Color(0xFF427CF0);
    final cat = category.toUpperCase();
    if (cat.contains('MARKET') || cat.contains('SHOPPING')) {
      return const Color(0xFF4CAF50);
    }
    if (cat.contains('RESTAURANT') ||
        cat.contains('FOOD') ||
        cat.contains('EAT')) {
      return const Color(0xFFFF9800);
    }
    if (cat.contains('GAS') || cat.contains('FUEL')) {
      return const Color(0xFFFFC107);
    }
    if (cat.contains('PHARMACY') || cat.contains('HEALTH')) {
      return const Color(0xFFF44336);
    }
    if (cat.contains('PARK') || cat.contains('SQUARE')) {
      return const Color(0xFF4CAF50);
    }
    if (cat.contains('HOSPITAL')) return const Color(0xFFF44336);
    if (cat.contains('BANK') || cat.contains('ATM')) {
      return const Color(0xFF2196F3);
    }
    if (cat.contains('HOTEL')) return const Color(0xFF3F51B5);
    if (cat.contains('TRANSPORT')) return const Color(0xFF427CF0);
    return const Color(0xFF7D8FB3);
  }

  List<Map<String, dynamic>> _quickParseTomTomResults(List<dynamic> data) {
    return data.map<Map<String, dynamic>>((item) {
      final address = item['address'] ?? {};
      final poi = item['poi'];
      final lat = item['position']?['lat'];
      final lon = item['position']?['lon'];
      final dist = item['dist'];
      final category = item['poi']?['categories']?.isNotEmpty == true
          ? item['poi']['categories'][0].split('/').last
          : null;

      String mainTitle = poi != null
          ? poi['name']
          : (address['streetName'] ?? "Endereço");

      // Bairro inicial direto do TomTom (rápido)
      String? bairro =
          address['municipalitySubdivision'] ??
          address['neighbourhood'] ??
          address['subdivisionName'];

      // Formatação básica do secundário
      String secondary = '';
      if (address['streetName'] != null) {
        secondary = address['streetName'];
        if (address['streetNumber'] != null) {
          secondary += ' ${address['streetNumber']}';
        }
      }

      if (bairro != null && bairro.isNotEmpty) {
        secondary = secondary.isNotEmpty ? '$secondary - $bairro' : bairro;
      } else if (secondary.isEmpty && address['municipality'] != null) {
        secondary = address['municipality'].toString();
      }

      double distKm = (dist ?? 0) / 1000.0;
      int timeMin = (distKm * 1.5 + 2).ceil();

      return {
        'main_text': mainTitle,
        'secondary_text': secondary,
        'bairro': bairro,
        'is_poi': poi != null,
        'display_name': '$mainTitle - $secondary',
        'lat': lat,
        'lon': lon,
        'dist_text': '${distKm.toStringAsFixed(1)} km',
        'time_text': '$timeMin min',
        'category': category,
        'raw_address': address, // Guardado para refinar depois
        'needs_enrichment': true,
      };
    }).toList();
  }

  Future<void> _backgroundEnrichNeighborhoods(String query) async {
    final currentResults = List<Map<String, dynamic>>.from(_searchResults);

    // Processa um por um para não sobrecarregar
    for (int i = 0; i < currentResults.length; i++) {
      // Se a query mudou ou a tela fechou, cancela
      if (!mounted || _searchResults.isEmpty || _lastSearchQuery != query) {
        return;
      }

      final item = currentResults[i];
      if (item['needs_enrichment'] != true) continue;

      final lat = item['lat'];
      final lon = item['lon'];
      if (lat == null || lon == null) continue;

      try {
        String? novoBairro;
        final double pLat = double.tryParse(lat.toString()) ?? 0.0;
        final double pLon = double.tryParse(lon.toString()) ?? 0.0;

        if (kIsWeb) {
          final geoData = await _api.reverseGeocode(pLat, pLon);
          if (geoData.isNotEmpty && geoData['address'] != null) {
            final addr = geoData['address'] as Map;
            novoBairro =
                addr['suburb'] ??
                addr['neighbourhood'] ??
                addr['city_district'];
          }
        } else {
          final url = Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?lat=$pLat&lon=$pLon&format=json&addressdetails=1&zoom=14&accept-language=pt-BR',
          );
          final resp = await http
              .get(url, headers: {'User-Agent': 'Service101-App'})
              .timeout(const Duration(seconds: 3));
          if (resp.statusCode == 200) {
            final geo = json.decode(resp.body);
            final addr = geo['address'] as Map?;
            if (addr != null) {
              novoBairro =
                  addr['suburb'] ??
                  addr['neighbourhood'] ??
                  addr['city_district'] ??
                  addr['district'];
            }
          }
        }

        if (novoBairro != null && novoBairro.isNotEmpty) {
          if (!mounted) return;

          setState(() {
            // Verifica se o item ainda está na mesma posição ou busca pelo lat/lon
            if (i < _searchResults.length && _searchResults[i]['lat'] == lat) {
              final updatedItem = Map<String, dynamic>.from(_searchResults[i]);
              updatedItem['bairro'] = novoBairro;
              updatedItem['needs_enrichment'] = false;

              // Atualiza secondary_text com o novo bairro se mudou
              String street = updatedItem['raw_address']['streetName'] ?? '';
              if (updatedItem['raw_address']['streetNumber'] != null) {
                street += ' ${updatedItem['raw_address']['streetNumber']}';
              }

              updatedItem['secondary_text'] = street.isNotEmpty
                  ? '$street - $novoBairro'
                  : novoBairro;
              _searchResults[i] = updatedItem;
            }
          });
        }
      } catch (e) {
        debugPrint('⚠️ [LazyEnrich] Erro no item $i: $e');
      }

      // Pequeno respiro entre requisições
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _selectSearchResult(dynamic result) {
    FocusScope.of(context).unfocus();
    final latObj = result['lat'];
    final lonObj = result['lon'];
    final display = result['display_name'] ?? result['main_text'] ?? '';

    double? lat = latObj is num
        ? latObj.toDouble()
        : double.tryParse(latObj?.toString() ?? '');
    double? lon = lonObj is num
        ? lonObj.toDouble()
        : double.tryParse(lonObj?.toString() ?? '');

    if (lat != null && lon != null) {
      setState(() {
        if (_selectingPickup) {
          _pickupLocation = LatLng(lat, lon);
          _pickupController.text = display;
          _mapController.move(_pickupLocation!, 15);
        } else {
          _dropoffLocation = LatLng(lat, lon);
          _dropoffController.text = display;
          _mapController.move(_dropoffLocation!, 16);
        }
        _searchResults = [];
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _calculateFare();
      });
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) async {
    if (_isPickingOnMap) return;
    setState(() {
      _selectingPickup = false;
      _dropoffLocation = point;
      _dropoffController.text = 'Buscando destino...';
      _searchResults = [];
      _calculateFare();
    });
    FocusScope.of(context).unfocus();
    try {
      final res = await _api.reverseGeocode(point.latitude, point.longitude);
      if (mounted) {
        setState(() {
          final address = res['display_name'] ?? 'Endereço selecionado';
          _dropoffController.text = address.toString();
        });
      }
    } catch (_) {}
  }

  Future<void> _calculateAllFares() async {
    if (_pickupLocation == null || _dropoffLocation == null) return;
    setState(() => _isLoading = true);
    try {
      double dist = _routeDistance ?? 0.0;
      double dur = _routeDuration ?? 0.0;

      if (_routePoints.isEmpty || _routeDistance == null) {
        final routeData = await MapService().getRoute(
          _pickupLocation!,
          _dropoffLocation!,
        );
        dist = (routeData['distance'] as num?)?.toDouble() ?? 0.0;
        dur = (routeData['duration'] as num?)?.toDouble() ?? 0.0;

        setState(() {
          _routePoints = routeData['points'] as List<LatLng>;
          _routeDistance = dist;
          _routeDuration = dur;

          // Snap visual apenas na renderização, sem sobrescrever as variáveis originais
          if (_routePoints.isNotEmpty) {
            // Injeta o destino real como último ponto da polilinha para garantir snap visual perfeito
            if (_routePoints.last != _dropoffLocation) {
              _routePoints.add(_dropoffLocation!);
            }
            if (_routePoints.first != _pickupLocation) {
              _routePoints.insert(0, _pickupLocation!);
            }
          }
        });
      }

      // Calcula para todos os veículos pré-definidos
      final Map<int, dynamic> newFares = {};
      for (final vehicle in predefinedVehicles) {
        final vId = vehicle['id'] as int;
        try {
          final fareData = await _uberService.calculateFare(
            pickupLat: _pickupLocation!.latitude,
            pickupLng: _pickupLocation!.longitude,
            dropoffLat: _dropoffLocation!.latitude,
            dropoffLng: _dropoffLocation!.longitude,
            vehicleTypeId: vId,
            distanceKm: dist,
            durationMin: dur,
          );
          newFares[vId] = fareData is Map ? fareData : {'fare': fareData};
        } catch (e) {
          debugPrint('Erro fare vId $vId: $e');
        }
      }

      setState(() {
        _vehicleFares = newFares;
        // Legacy support
        if (newFares.containsKey(_selectedVehicleId)) {
          _fareEstimate = newFares[_selectedVehicleId];
        }
      });
      _fitMapToRoute();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao calcular tarifa: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateFare() async {
    await _calculateAllFares();
  }

  void _fitMapToRoute() {
    if (_pickupLocation == null || _dropoffLocation == null) return;
    final validPoints = [_pickupLocation!, _dropoffLocation!, ..._routePoints];
    try {
      final bounds = LatLngBounds.fromPoints(validPoints);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(
            top: 100,
            left: 50,
            right: 50,
            bottom: 300,
          ),
        ),
      );
    } catch (_) {
      _mapController.move(_dropoffLocation!, 14);
    }
  }

  double _extractFareValue(dynamic data) {
    if (data == null) return 0.0;
    if (data is num) return data.toDouble();
    if (data is Map) {
      final value = data['estimated'] ?? data['fare'] ?? data['total'] ?? 0;
      return double.tryParse(value.toString()) ?? 0.0;
    }
    return 0.0;
  }

  Future<void> _requestRide() async {
    if (_pickupLocation == null || _dropoffLocation == null) return;
    setState(() => _isLoading = true);
    try {
      final baseFare = _extractFareValue(_fareEstimate);
      final finalFare = _uberService.calculateFareWithFees(
        baseFare,
        _selectedPaymentMethod,
      );

      final trip = await _uberService.requestTrip(
        pickupLat: _pickupLocation!.latitude,
        pickupLng: _pickupLocation!.longitude,
        pickupAddress: _pickupController.text,
        dropoffLat: _dropoffLocation!.latitude,
        dropoffLng: _dropoffLocation!.longitude,
        dropoffAddress: _dropoffController.text,
        vehicleTypeId: _selectedVehicleId,
        fare: finalFare,
        paymentMethod: _selectedPaymentMethod,
      );
      if (mounted) context.go('/uber-tracking/${trip['trip_id']}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao solicitar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startWatchingOnlineDrivers() {
    _onlineDriversSubscription = _uberService.watchAllOnlineDrivers().listen((
      drivers,
    ) {
      if (mounted) {
        setState(() {
          _onlineDrivers = drivers;
        });
        _fetchMissingVehicleTypes();
      }
    });
  }

  Future<void> _fetchMissingVehicleTypes() async {
    for (final driver in _onlineDrivers) {
      final driverId = driver['driver_id'] as int;

      // Busca tipo de veículo se não estiver no cache
      if (!_driverVehicleTypes.containsKey(driverId)) {
        final typeId = await _uberService.getDriverVehicleTypeId(driverId);
        if (mounted && typeId != null) {
          setState(() => _driverVehicleTypes[driverId] = typeId);
        }
      }

      // Busca preferências de pagamento se não estiver no cache
      if (!_driverPaymentMethods.containsKey(driverId)) {
        final prefs = await _uberService.getDriverPaymentPreferences(driverId);
        if (mounted) {
          setState(() => _driverPaymentMethods[driverId] = prefs);
        }
      }
    }
  }

  Future<void> _checkHasCreditCard() async {
    if (_hasCreditCardLoaded) return;
    try {
      final userId = _api.userId;
      if (userId == null) return;

      final res = await Supabase.instance.client
          .from('payment_methods')
          .select('id')
          .eq('client_id', userId)
          .eq('type', 'credit_card')
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _hasCreditCard = res != null;
          _hasCreditCardLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Erro ao verificar cartao: $e');
      if (mounted) setState(() => _hasCreditCardLoaded = true);
    }
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double startLat = start.latitude * (pi / 180);
    double startLng = start.longitude * (pi / 180);
    double endLat = end.latitude * (pi / 180);
    double endLng = end.longitude * (pi / 180);

    double dLng = endLng - startLng;
    double y = sin(dLng) * cos(endLat);
    double x =
        cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(dLng);
    double brng = atan2(y, x);
    return (brng * (180 / pi) + 360) % 360;
  }

  @override
  void dispose() {
    _onlineDriversSubscription?.cancel();
    _debouncer?.cancel();
    _pickupController.dispose();
    _dropoffController.dispose();
    _pickupFocus.dispose();
    _dropoffFocus.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ThemeService().setNavBarVisible(true);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    _pickupLocation ?? const LatLng(-5.5263, -47.4764),
                initialZoom: 15.0,
                onTap: _onMapTap,
                onMapReady: () {
                  setState(() => _isMapReady = true);
                },
                onPositionChanged: (pos, hasGesture) {
                  if (_isPickingOnMap && hasGesture) {
                    _onPickingLocationChanged(pos.center);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=${SupabaseConfig.mapboxToken}',
                  userAgentPackageName: 'com.play101.app',
                  tileDimension: 512,
                  zoomOffset: -1,
                  maxZoom: 22,
                ),
                UberMapOverlay(
                  routePoints: _routePoints,
                  pickupLocation: _pickupLocation,
                  dropoffLocation: _dropoffLocation,
                  dropoffInfo: _routeDistance != null && _routeDuration != null
                      ? '${_routeDistance!.toStringAsFixed(1)}km | ${(_routeDuration!).toInt()} min'
                      : null,
                ),
                MarkerLayer(
                  markers: [
                    ..._onlineDrivers.map((driver) {
                      final driverId = driver['driver_id'];
                      final isMoto = _driverVehicleTypes[driverId] == 3;
                      final currentPos = LatLng(
                        double.parse(driver['latitude'].toString()),
                        double.parse(driver['longitude'].toString()),
                      );

                      // Atualiza bearing se a localização mudou
                      if (_lastDriverLocations.containsKey(driverId) &&
                          _lastDriverLocations[driverId] != currentPos) {
                        _driverBearings[driverId] = _calculateBearing(
                          _lastDriverLocations[driverId]!,
                          currentPos,
                        );
                      }
                      _lastDriverLocations[driverId] = currentPos;

                      return Marker(
                        point: currentPos,
                        width: 48,
                        height: 48,
                        child: PremiumDriverMarker(
                          heading: _driverBearings[driverId] ?? 0,
                          isMoto: isMoto,
                          size: 40,
                        ),
                      );
                    }),
                  ],
                ),
                if (_isPickingOnMap)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeInOut,
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(
                                  0,
                                  -10 * (1 - (value - 0.5).abs() * 2),
                                ),
                                child: child,
                              );
                            },
                            onEnd: () => setState(
                              () {},
                            ), // Trigger rebuild to loop (simple way)
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF427CF0),
                                shape: BoxShape.circle,
                                boxShadow: kIsWeb
                                    ? []
                                    : [
                                        const BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 20,
                                          offset: Offset(0, 10),
                                        ),
                                      ],
                              ),
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 10,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Address Selection UI (Full Screen Overlay)
          if (!_isPickingOnMap && _dropoffLocation == null)
            Positioned.fill(
              child: Container(
                color: const Color(
                  0xFFF6F6F8,
                ).withValues(alpha: 0.9), // Slightly transparent to see map
                child: SafeArea(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Row(
                            children: [
                              _buildFloatingCircleButton(
                                icon: Icons.arrow_back,
                                onPressed: () => context.pop(),
                              ),
                              const SizedBox(width: 16),
                              const Text(
                                'Para onde vamos ?',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF101622),
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Search Card (Premium HTML/Tailwind Style)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.grey.shade200.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              boxShadow: kIsWeb
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.04,
                                        ),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                            ),
                            child: Stack(
                              children: [
                                // Dashed Line Connecting Dots
                                Positioned(
                                  left: 17.5,
                                  top: 30,
                                  bottom: 30,
                                  child: CustomPaint(
                                    size: const Size(1, double.infinity),
                                    painter: DashedLinePainter(),
                                  ),
                                ),
                                Column(
                                  children: [
                                    // Pickup Input
                                    Row(
                                      children: [
                                        Container(
                                          width: 20,
                                          height: 20,
                                          margin: const EdgeInsets.only(
                                            right: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 3,
                                            ),
                                          ),
                                          child: Center(
                                            child: Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade400,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3F4F6),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: TextField(
                                              controller: _pickupController,
                                              focusNode: _pickupFocus,
                                              onTap: () {
                                                setState(
                                                  () => _selectingPickup = true,
                                                );
                                                _onSearchQueryChanged(
                                                  _pickupController.text,
                                                );
                                              },
                                              onChanged: (val) {
                                                setState(
                                                  () => _selectingPickup = true,
                                                );
                                                _onSearchQueryChanged(val);
                                              },
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: 'Origem',
                                                border: InputBorder.none,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                suffixIcon:
                                                    _pickupController
                                                        .text
                                                        .isNotEmpty
                                                    ? IconButton(
                                                        icon: Icon(
                                                          Icons.cancel,
                                                          size: 18,
                                                          color: Colors
                                                              .grey
                                                              .shade400,
                                                        ),
                                                        onPressed: () {
                                                          _pickupController
                                                              .clear();
                                                          setState(() {
                                                            _pickupLocation =
                                                                null;
                                                            _selectingPickup =
                                                                true;
                                                          });
                                                          _onSearchQueryChanged(
                                                            '',
                                                          );
                                                        },
                                                      )
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Dropoff Input
                                    Row(
                                      children: [
                                        Container(
                                          width: 20,
                                          height: 20,
                                          margin: const EdgeInsets.only(
                                            right: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryYellow
                                                .withValues(alpha: 0.2),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 3,
                                            ),
                                          ),
                                          child: Center(
                                            child: Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryYellow,
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                                boxShadow: kIsWeb
                                                    ? []
                                                    : [
                                                        BoxShadow(
                                                          color: AppTheme
                                                              .primaryYellow
                                                              .withValues(
                                                                alpha: 0.5,
                                                              ),
                                                          blurRadius: 4,
                                                        ),
                                                      ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3F4F6),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: TextField(
                                              controller: _dropoffController,
                                              focusNode: _dropoffFocus,
                                              onTap: () {
                                                setState(
                                                  () =>
                                                      _selectingPickup = false,
                                                );
                                                _onSearchQueryChanged('');
                                              },
                                              onChanged: _onSearchQueryChanged,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Color(0xFF111827),
                                              ),
                                              decoration: InputDecoration(
                                                hintText: 'Para onde Vamos ?',
                                                hintStyle: TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.grey.shade500,
                                                ),
                                                border: InputBorder.none,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                suffixIcon:
                                                    _dropoffController
                                                        .text
                                                        .isNotEmpty
                                                    ? IconButton(
                                                        icon: Icon(
                                                          Icons.cancel,
                                                          size: 18,
                                                          color: Colors
                                                              .grey
                                                              .shade400,
                                                        ),
                                                        onPressed: () {
                                                          _dropoffController
                                                              .clear();
                                                          _onSearchQueryChanged(
                                                            '',
                                                          );
                                                        },
                                                      )
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Set location on map button
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'SUGESTÕES',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade400,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Results List (Premium Style)
                        if (_isSearchingLocation)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (_searchResults.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(40),
                              ),
                              boxShadow: kIsWeb
                                  ? []
                                  : [
                                      const BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 20,
                                        offset: Offset(0, -5),
                                      ),
                                    ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 24),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Text(
                                    'SUGESTÕES',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.grey.shade400,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount:
                                      _searchResults.length +
                                      1, // +1 para a opção de mapa no final
                                  itemBuilder: (context, index) {
                                    if (index == _searchResults.length) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: InkWell(
                                          onTap: () {
                                            setState(() {
                                              _isPickingOnMap = true;
                                              _searchResults = [];
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.fromLTRB(
                                              20,
                                              8,
                                              20,
                                              24,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: Colors.transparent,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: BoxDecoration(
                                                    color: AppTheme
                                                        .primaryYellow
                                                        .withValues(alpha: 0.1),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    LucideIcons.map,
                                                    color:
                                                        AppTheme.primaryYellow,
                                                    size: 24,
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        'Definir no mapa',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                          color: Color(
                                                            0xFF111827,
                                                          ),
                                                        ),
                                                      ),
                                                      Text(
                                                        'Arraste para escolher o local exato',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .grey
                                                              .shade500,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.chevron_right,
                                                  color: Colors.grey.shade400,
                                                  size: 20,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }

                                    final item = _searchResults[index];
                                    final categoryColor = _getCategoryColor(
                                      item['category']?.toString(),
                                    );

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: InkWell(
                                        onTap: () => _selectSearchResult(item),
                                        borderRadius: BorderRadius.circular(16),
                                        splashColor: categoryColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.transparent,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  color: categoryColor
                                                      .withValues(alpha: 0.1),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  _getCategoryIcon(
                                                    item['category']
                                                        ?.toString(),
                                                  ),
                                                  color: categoryColor,
                                                  size: 24,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item['main_text'] ?? '',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                        color: Color(
                                                          0xFF111827,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      item['secondary_text'] ??
                                                          '',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: Colors
                                                            .grey
                                                            .shade500,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    if (item['bairro'] !=
                                                            null &&
                                                        item['bairro']
                                                            .toString()
                                                            .isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 4,
                                                            ),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .grey
                                                                .shade100,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            item['bairro']
                                                                .toString()
                                                                .toUpperCase(),
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: Colors
                                                                  .grey
                                                                  .shade600,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    item['dist_text'] ?? '',
                                                    style: TextStyle(
                                                      color: AppTheme
                                                          .primaryYellow,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  Text(
                                                    item['time_text'] ?? '',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade400,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),

                        // Mini Map Preview Footer (Live background logic)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: kIsWeb
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.08,
                                          ),
                                          blurRadius: 20,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryYellow,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Buscando rotas...',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF101622),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // New Picking Mode Top Bar
          if (_isPickingOnMap)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildFloatingCircleButton(
                    icon: Icons.arrow_back,
                    onPressed: () => setState(() => _isPickingOnMap = false),
                  ),
                  const Text(
                    'Definir destino',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  _buildFloatingCircleButton(
                    icon: Icons.help_outline,
                    onPressed: () {},
                  ),
                ],
              ),
            ),

          // Ride Mode Back Button (Corrected)
          if (_dropoffLocation != null && !_isPickingOnMap)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              child: _buildFloatingCircleButton(
                icon: Icons.arrow_back,
                onPressed: () {
                  setState(() {
                    _dropoffLocation = null;
                    _fareEstimate = null;
                    _isPickingOnMap = false;
                  });
                },
              ),
            ),

          // Map Controls (Right Side)
          if (_isPickingOnMap || (_dropoffLocation != null && !_isPickingOnMap))
            Positioned(
              right: 16,
              top: MediaQuery.of(context).size.height * 0.4,
              child: Column(
                children: [
                  _buildMapControlButton(
                    icon: Icons.add,
                    onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildMapControlButton(
                    icon: Icons.remove,
                    onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildMapControlButton(
                    icon: Icons.my_location,
                    color: const Color(0xFF427CF0),
                    onPressed: _getCurrentLocation,
                  ),
                ],
              ),
            ),

          // Redesigned Bottom Sheet (Picking Mode)
          if (_isPickingOnMap)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: kIsWeb
                      ? []
                      : [
                          const BoxShadow(
                            color: Colors.black12,
                            blurRadius: 40,
                            offset: Offset(0, -10),
                          ),
                        ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag Handle
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 24,
                        right: 24,
                        bottom: 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Styled Search Bar inside card
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.search,
                                  color: Color(0xFF427CF0),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _selectingPickup
                                        ? _pickupController
                                        : _dropoffController,
                                    readOnly: true,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      hintText: 'Buscar endereço...',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Selected Location Info Card
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF427CF0,
                              ).withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(
                                  0xFF427CF0,
                                ).withValues(alpha: 0.1),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF427CF0),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.map,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectingPickup
                                            ? 'Local de partida'
                                            : 'Destino',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        _selectingPickup
                                            ? _pickupController.text
                                            : _dropoffController.text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Confirm Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _dropoffLocation =
                                      _mapController.camera.center;
                                  _isPickingOnMap = false;
                                  _searchResults = [];
                                });
                                _calculateFare();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryYellow,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.all(18),
                                elevation: kIsWeb ? 0 : 4,
                                shadowColor: kIsWeb
                                    ? Colors.transparent
                                    : AppTheme.primaryYellow.withValues(
                                        alpha: 0.4,
                                      ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Confirmar destino'),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward, size: 20),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: TextButton(
                              onPressed: () {},
                              child: Text(
                                'Escolher dos favoritos',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Vehicle Selection (Ride Mode)
          if (_dropoffLocation != null &&
              !_isPickingOnMap &&
              _searchResults.isEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                  boxShadow: kIsWeb
                      ? []
                      : [
                          const BoxShadow(
                            color: Colors.black12,
                            blurRadius: 40,
                            offset: Offset(0, -10),
                          ),
                        ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Novo Layout do Stitch (Escolha uma viagem + Lista Vertical)
                    if (_vehicleFares.isNotEmpty) ...[
                      // Drag Handle
                      Center(
                        child: Container(
                          width: 48,
                          height: 6,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),

                      const SizedBox(height: 4),
                      // Seleção de Veículos (Vertical Compacto para economizar espaço)
                      Column(
                        children: predefinedVehicles.map((v) {
                          return _buildVehicleCardVertical(v);
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      // Seção de Pagamento Integrada (Design Premium Stitch)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                            child: Text(
                              'Forma de pagamento',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                          _buildPremiumPaymentSection(),
                        ],
                      ),
                      const Divider(height: 8, color: Color(0xFFF1F5F9)),
                      // Footer: Promo Only (Payment moved up)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.sell,
                                size: 14,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Promoção aplicada',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Confirmar Botão
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _requestRide,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(
                              0xFFFFD700,
                            ), // accent-yellow do Stitch
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.black,
                                    ),
                                  ),
                                )
                              : Builder(
                                  builder: (context) {
                                    final fareData =
                                        _vehicleFares[_selectedVehicleId];
                                    final baseFare = _extractFareValue(
                                      fareData,
                                    );
                                    final finalFare = _uberService
                                        .calculateFareWithFees(
                                          baseFare,
                                          _selectedPaymentMethod,
                                        );
                                    final vehicleName = predefinedVehicles
                                        .firstWhere(
                                          (v) => v['id'] == _selectedVehicleId,
                                          orElse: () =>
                                              predefinedVehicles.first,
                                        )['name']
                                        .toString()
                                        .toUpperCase();

                                    return Text(
                                      'CONFIRMAR $vehicleName • R\$ ${finalFare.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ] else ...[
                      const Center(
                        child: Column(
                          children: [
                            SizedBox(height: 32),
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Calculando opções...'),
                            SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFloatingCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: kIsWeb
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.black, size: 22),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: kIsWeb
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color ?? Colors.black87, size: 20),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildVehicleCardVertical(Map<String, dynamic> v) {
    bool isSelected = _selectedVehicleId == v['id'];
    const Color primaryBlue = Color(0xFF427CF0);

    final fareData = _vehicleFares[v['id']];
    final baseFare = _extractFareValue(fareData);
    // Preço baseado no método de pagamento ATUALMENTE selecionado
    final finalFare = _uberService.calculateFareWithFees(
      baseFare,
      _selectedPaymentMethod,
    );

    return GestureDetector(
      onTap: () {
        if (_selectedVehicleId != v['id']) {
          setState(() {
            _selectedVehicleId = v['id'];
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryBlue.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryBlue : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected && !kIsWeb
              ? [
                  BoxShadow(
                    color: primaryBlue.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Image.asset(v['asset'], height: 40, width: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        v['name'],
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.person, size: 12, color: Colors.grey),
                      Text(
                        v['id'] == 3 ? ' 1' : ' 4',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${v['id'] == 3 ? "2" : "3"} min de espera',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'R\$ ${finalFare.toStringAsFixed(2)}',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: isSelected
                        ? const Color(0xFF2E7D32)
                        : AppTheme.textDark,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF427CF0),
                    size: 20,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumPaymentSection() {
    final fareData = _vehicleFares[_selectedVehicleId];
    final baseFare = _extractFareValue(fareData);
    if (baseFare <= 0) return const SizedBox.shrink();

    // Lista de todas as opções para o expansor
    final options = _getPaymentOptions(baseFare);
    final selectedOption = options.firstWhere(
      (o) => o['id'] == _selectedPaymentMethod,
      orElse: () => options.first,
    );

    return Column(
      children: [
        // Card Principal (Selecionado)
        _buildPaymentMethodCard(selectedOption, isSelected: true),

        // Botão "OUTRAS OPÇÕES"
        Center(
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _isPaymentExpanded = !_isPaymentExpanded),
            icon: Icon(
              _isPaymentExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.grey.shade600,
              size: 18,
            ),
            label: Text(
              'OUTRAS OPÇÕES',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

        // Lista Expandida
        if (_isPaymentExpanded)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            child: Column(
              children: options
                  .where((o) => o['id'] != _selectedPaymentMethod)
                  .map(
                    (o) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildPaymentMethodCard(o, isSelected: false),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _getPaymentOptions(double baseFare) {
    return [
      {
        'id': 'PIX Direto',
        'name': 'PIX Direto (Motorista)',
        'sub': 'Pague direto no app',
        'icon': Icons.pix,
        'color': const Color(0xFF00BFA5),
        'badge': 'MAIS BARATO',
        'fee': 0.0,
        'available': true, // Sempre disponível como fallback ou pix direto
      },
      {
        'id': 'Dinheiro',
        'name': 'Dinheiro',
        'sub': 'Pague ao motorista',
        'icon': Icons.payments_outlined,
        'color': Colors.green,
        'fee': 0.0,
        'available': true,
      },
      {
        'id': 'PIX Plataforma',
        'name': 'PIX App',
        'sub': 'Pague via plataforma',
        'icon': Icons.pix_outlined,
        'color': Colors.blue.shade600,
        'badge': '+2%',
        'fee': 0.02,
        'available': true,
      },
      {
        'id': 'Cartão (Plataforma)',
        'name': 'Cartão de Crédito',
        'sub': 'Salvo no app',
        'icon': Icons.credit_card,
        'color': Colors.purple.shade600,
        'badge': '+5%',
        'fee': 0.05,
        'check_registration': true,
        'available': true,
      },
      {
        'id': 'Cartão (Máquina)',
        'name': 'Cartão Maquininha',
        'sub': 'Pague no carro',
        'icon': Icons.smartphone,
        'color': Colors.orange.shade700,
        'badge': '+5%',
        'fee': 0.05,
        'available': _onlineDrivers.any(
          (d) =>
              _driverPaymentMethods[d['driver_id']]?['card_machine'] ?? false,
        ),
      },
    ];
  }

  Widget _buildPaymentMethodCard(
    Map<String, dynamic> option, {
    bool isSelected = false,
  }) {
    final fareData = _vehicleFares[_selectedVehicleId];
    final baseFare = _extractFareValue(fareData);
    final finalFare = _uberService.calculateFareWithFees(
      baseFare,
      option['id'],
    );
    final bool isAvailable = option['available'] ?? true;

    return GestureDetector(
      onTap: isAvailable
          ? () async {
              if (option['check_registration'] == true) {
                await _checkHasCreditCard();
                if (!_hasCreditCard) {
                  if (mounted) {
                    _showAddCardModal();
                  }
                  return;
                }
              }
              setState(() {
                _selectedPaymentMethod = option['id'];
                if (isSelected) {
                  _isPaymentExpanded = !_isPaymentExpanded;
                } else {
                  _isPaymentExpanded = false;
                }
              });
            }
          : null,
      child: Opacity(
        opacity: isAvailable ? 1.0 : 0.5,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? const Color(0xFFE5E7EB) : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: isSelected && !kIsWeb
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (option['color'] as Color).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(option['icon'], color: option['color'], size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            option['name'],
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (option['badge'] != null)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: option['id'] == 'PIX Direto'
                                  ? const Color(0xFFE8F5E9)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              option['badge'],
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: option['id'] == 'PIX Direto'
                                    ? const Color(0xFF2E7D32)
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!isAvailable)
                      Text(
                        'Indisponível no momento',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red.shade400,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Text(
                    'R\$ ${finalFare.toStringAsFixed(2)}',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppTheme.textDark,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF427CF0),
                      size: 18,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddCardModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 32),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.creditCard,
                  size: 64,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Cadastre um cartão',
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Para pagar com cartão diretamente na plataforma, você precisa cadastrar um método de pagamento válido primeiro.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  color: AppTheme.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Aqui iria a navegação para tela de cadastro de cartão
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Navegando para cadastro de cartão (Simulado)',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'CADASTRAR AGORA',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'TALVEZ MAIS TARDE',
                  style: GoogleFonts.manrope(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    double dashHeight = 5, dashSpace = 3, startY = 0;
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    while (startY < size.height) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + dashHeight), paint);
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
