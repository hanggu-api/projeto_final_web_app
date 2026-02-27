import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

import '../../services/uber_service.dart';
import '../../services/analytics_service.dart';
import '../../services/map_service.dart';
import '../../services/theme_service.dart';
import '../../services/api_service.dart';
import '../../core/theme/app_theme.dart';

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
  
  LatLng? _pickupLocation;
  
  @override
  void initState() {
    super.initState();
    // Oculta a barra de navegação ao entrar na tela de pedido
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ThemeService().setNavBarVisible(false);
    });

    _pickupFocus.addListener(_onFocusChange);
    _dropoffFocus.addListener(_onFocusChange);
    
    _getCurrentLocation();
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() {
      // Como a partida é fixa no GPS, o foco sempre pertencerá apenas à busca de destino (se houver)
      if (_dropoffFocus.hasFocus) _selectingPickup = false;
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      
      setState(() {
         _pickupLocation = LatLng(pos.latitude, pos.longitude);
         if (_pickupLocation != null) {
            _mapController.move(_pickupLocation!, 15);
         }
         _pickupController.text = 'Buscando endereço...';
      });
      
      final res = await _api.reverseGeocode(pos.latitude, pos.longitude);
      if (mounted) {
         setState(() {
            final address = res['display_name'] is String
                  ? res['display_name']
                  : (res['address'] is String ? res['address'] : 'Meu Local');
            _pickupController.text = address;
         });
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
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
         final rawResults = await _api.searchAddress(
            text,
            lat: _pickupLocation?.latitude,
            lon: _pickupLocation?.longitude,
         );
         if (rawResults != null) {
            final enriched = await _enrichTomTomResults(rawResults);
            if (mounted) setState(() => _searchResults = enriched);
         } else {
            if (mounted) setState(() => _searchResults = []);
         }
      } catch (e) {
         debugPrint('Erro na busca: $e');
      } finally {
         if (mounted) setState(() => _isSearchingLocation = false);
      }
    });
  }

  Future<List<Map<String, dynamic>>> _enrichTomTomResults(List<dynamic> data) async {
    final rawResults = data.map<Map<String, dynamic>>((item) {
      return {
        'address': item['address'] ?? {},
        'poi': item['poi'],
        'lat': item['position']?['lat'],
        'lon': item['position']?['lon'],
        'dist': item['dist'],
      };
    }).toList();

    return Future.wait(rawResults.map((raw) async {
      final address = raw['address'];
      final poi = raw['poi'];
      String? bairro = address['municipalitySubdivision'] ?? address['neighborhood'] ?? address['subDivision'];

      if ((bairro == null || bairro.isEmpty) && raw['lat'] != null && raw['lon'] != null) {
        try {
           final reverseResp = await _api.reverseGeocode(raw['lat'], raw['lon']);
           final revAddress = reverseResp['address'] as Map<String, dynamic>?;
           bairro = revAddress?['suburb'] ?? revAddress?['neighbourhood'] ?? revAddress?['city_district'];
        } catch (_) {}
      }

      String mainTitle = poi != null ? poi['name'] : (address['streetName'] ?? "Endereço desconhecido");
      if (poi == null && address['freeformAddress'] != null) mainTitle = address['freeformAddress'].split(',')[0];

      List<String> parts = [];
      if (address['streetName'] != null) {
        String street = address['streetName'];
        if (address['streetNumber'] != null) street += ", ${address['streetNumber']}";
        parts.add(street);
      }
      if (bairro != null) parts.add(bairro);
      parts.add(address['municipality'] ?? 'Imperatriz');

      String subtitle = parts.isNotEmpty ? parts.join(' - ') : (address['freeformAddress'] ?? '');

      String categoryStr = '';
      if (poi != null) {
        categoryStr = '${(poi['categories'] as List?)?.join(' ') ?? ''} ${poi['classifications']?.toString() ?? ''}'.toLowerCase();
      }

      return {
        'main_text': mainTitle,
        'secondary_text': subtitle,
        'is_poi': poi != null,
        'display_name': '$mainTitle - $subtitle',
        'lat': raw['lat'],
        'lon': raw['lon'],
        'dist': raw['dist'],
        'category': categoryStr,
        'street': address['streetName'],
        'number': address['streetNumber'],
        'neighborhood': bairro,
        'city': address['municipality'],
        'state': address['countrySubdivisionCode'],
        'poi_name': poi != null ? poi['name'] : null,
      };
    }));
  }

  void _selectSearchResult(dynamic result) {
    FocusScope.of(context).unfocus();
    final lat = double.tryParse(result['lat']?.toString() ?? '');
    final lon = double.tryParse(result['lon']?.toString() ?? '');
    final display = result['display_name'] ?? '';
    
    if (lat != null && lon != null) {
      setState(() {
        _dropoffLocation = LatLng(lat, lon);
        _dropoffController.text = display;
        _calculateFare();
        _searchResults = [];
        _mapController.move(LatLng(lat, lon), 16);
      });
    }
  }

  @override
  void dispose() {
    _debouncer?.cancel();
    _pickupController.dispose();
    _dropoffController.dispose();
    _pickupFocus.dispose();
    _dropoffFocus.dispose();
    // Restaura a barra de navegação ao sair
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ThemeService().setNavBarVisible(true);
    });
    super.dispose();
  }
  LatLng? _dropoffLocation;
  List<LatLng> _routePoints = [];
  bool _selectingPickup = true;
  bool _isLoading = false;
  int _selectedVehicleId = 1; 
  
  final List<Map<String, dynamic>> predefinedVehicles = [
      {
        'id': 1,
        'name': 'Econômico',
        'icon': Icons.directions_car,
        'asset': 'assets/images/uber_car_eco.png'
      },
      {
        'id': 3,
        'name': 'Moto',
        'icon': Icons.directions_bike,
        'asset': 'assets/images/uber_moto.png'
      }
    ];

  Map<String, dynamic>? _fareEstimate;

  void _onMapTap(TapPosition tapPosition, LatLng point) async {
    // A partida é exclusivamente via GPS. Apenas atualizamos destino via clique no mapa.
    setState(() {
      _selectingPickup = false;
      _dropoffLocation = point;
      _dropoffController.text = 'Buscando destino...';
      _calculateFare();
    });
    
    try {
       final res = await _api.reverseGeocode(point.latitude, point.longitude);
       if (mounted) {
          setState(() {
             final address = res['display_name'] is String
                   ? res['display_name']
                   : (res['address'] is String ? res['address'] : 'Endereço selecionado visualmente');
             _dropoffController.text = address;
          });
       }
    } catch (_) {}
  }

  Future<void> _calculateFare() async {
    if (_pickupLocation == null || _dropoffLocation == null) return;

    setState(() => _isLoading = true);
    try {
      // 1. Calcula a tarifa real via API
      final fareData = await _uberService.calculateFare(
        pickupLat: _pickupLocation!.latitude,
        pickupLng: _pickupLocation!.longitude,
        dropoffLat: _dropoffLocation!.latitude,
        dropoffLng: _dropoffLocation!.longitude,
        vehicleTypeId: _selectedVehicleId,
      );
      
      // 2. Busca o traçado da rota
      final routePoints = await MapService().getRoutePoints(_pickupLocation!, _dropoffLocation!);
      
      setState(() {
        _fareEstimate = fareData;
        _routePoints = routePoints;
      });

      // 3. Ajusta o enquadramento do mapa
      _fitMapToRoute();

    } catch (e) {
      debugPrint('Erro ao calcular tarifa/rota: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao traçar rota: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _fitMapToRoute() {
    if (_pickupLocation == null || _dropoffLocation == null) return;
    
    // Calcula o bounding box e ajusta a câmera
    final bounds = LatLngBounds.fromPoints([_pickupLocation!, _dropoffLocation!, ..._routePoints]);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  double _extractFareValue(dynamic data) {
    if (data == null) return 0.0;
    if (data is num) return data.toDouble();
    if (data is Map) {
      final value = data['estimated'] ?? data['fare'] ?? data['total'] ?? data['price'] ?? data['amount'] ?? data['estimated_fare'] ?? 0;
      if (value is Map) return _extractFareValue(value);
      return double.tryParse(value.toString()) ?? 0.0;
    }
    return 0.0;
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
        vehicleTypeId: _selectedVehicleId,
        fare: _extractFareValue(_fareEstimate),
        paymentMethod: 'PIX', // Default por enquanto nesta tela
      );

      if (mounted) {
        AnalyticsService().logEvent('REQUEST_SERVICE', details: {
           'pickup_lat': _pickupLocation!.latitude,
           'pickup_lng': _pickupLocation!.longitude,
           'dropoff_lat': _dropoffLocation!.latitude,
           'dropoff_lng': _dropoffLocation!.longitude,
           'vehicle_type_id': _selectedVehicleId,
           'estimated_price': _fareEstimate != null ? _fareEstimate!['estimated'] : null,
        });

        if (context.mounted) {
          context.go('/uber-tracking/${trip['trip_id']}');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao solicitar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // MAPA
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _pickupLocation ?? const LatLng(-23.5505, -46.6333),
                initialZoom: 15.0,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=${dotenv.env['MAPBOX_TOKEN'] ?? ''}',
                  userAgentPackageName: 'com.play101.app',
                  tileSize: 512,
                  zoomOffset: -1,
                  maxZoom: 22,
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 5,
                        color: Colors.blue.withValues(alpha: 0.8),
                        borderColor: Colors.blue.shade900,
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_pickupLocation != null)
                      Marker(
                        point: _pickupLocation!,
                        width: 40,
                        height: 40,
                        child: _buildMarker(isPickup: true),
                      ),
                    if (_dropoffLocation != null)
                      Marker(
                        point: _dropoffLocation!,
                        width: 40,
                        height: 40,
                        child: _buildMarker(isPickup: false),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // INTERFACE DE VEÍCULOS E SOLICITAÇÃO (Aparece apenas quando há destino)
          if (_dropoffLocation != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_fareEstimate != null) ...[
                       // Veículos
                       SingleChildScrollView(
                         scrollDirection: Axis.horizontal,
                         child: Row(
                            children: predefinedVehicles.map((v) => _buildVehicleCard(v)).toList(),
                         ),
                       ),
                       const SizedBox(height: 24),
                       SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _requestRide,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryYellow,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isLoading 
                            ? const CircularProgressIndicator(color: AppTheme.textDark)
                            : const Text('SOLICITAR AGORA', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ] else
                      // Carregando Tarifa...
                      Padding(
                         padding: const EdgeInsets.symmetric(vertical: 32),
                         child: Center(
                            child: CircularProgressIndicator(color: AppTheme.primaryYellow),
                         ),
                      ),
                  ],
                ),
              ),
            ),

          // CABEÇALHO E BARRA SUPERIOR DE BUSCA
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Header (Seta e Título)
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: const Icon(Icons.arrow_back, size: 24, color: Colors.black87),
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Para onde?', 
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)
                        ),
                      ),
                    ),
                    const SizedBox(width: 40), // Balance to keep title centered
                  ]
                ),
                
                const SizedBox(height: 16),
                
                // Box de Inputs com Shadow
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                       BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))
                    ],
                  ),
                  child: IntrinsicHeight(
                     child: Row(
                       crossAxisAlignment: CrossAxisAlignment.stretch,
                       children: [
                         // Ícones de conexão vertical
                         Column(
                           mainAxisAlignment: MainAxisAlignment.center,
                           children: [
                             const SizedBox(height: 8),
                             const Icon(Icons.adjust, size: 16, color: Colors.blue),
                             Expanded(
                               child: Container(
                                 width: 1.5,
                                 margin: const EdgeInsets.symmetric(vertical: 4),
                                 color: Colors.grey.shade300
                               )
                             ),
                             const Icon(Icons.location_on, size: 16, color: Colors.orange),
                             const SizedBox(height: 8),
                           ],
                         ),
                         const SizedBox(width: 16),
                         Expanded(
                           child: Column(
                             children: [
                             // TextField de Partida (Read-Only via GPS)
                               SizedBox(
                                 height: 40,
                                 child: TextField(
                                   controller: _pickupController,
                                   readOnly: true, // Travado pelo GPS
                                   style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black54),
                                   decoration: InputDecoration(
                                     hintText: 'Buscando localização...',
                                     hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                                     border: InputBorder.none,
                                     contentPadding: EdgeInsets.zero,
                                   ),
                                 ),
                               ),
                               const Divider(height: 1),
                               // TextField de Destino
                               SizedBox(
                                 height: 40,
                                 child: TextField(
                                   controller: _dropoffController,
                                   focusNode: _dropoffFocus,
                                   enabled: _pickupLocation != null, // Só libera quando GPS encontra partida
                                   onChanged: _onSearchQueryChanged,
                                   onTap: () {
                                     setState(() => _selectingPickup = false);
                                     if (_dropoffController.text.isEmpty && _dropoffFocus.hasFocus) {
                                       _onSearchQueryChanged(''); // force initial search or just wait
                                     }
                                   },
                                   style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                   decoration: InputDecoration(
                                     hintText: _pickupLocation == null ? 'Aguarde o GPS...' : 'Para onde vamos?',
                                     hintStyle: TextStyle(color: _pickupLocation == null ? Colors.grey.shade400 : Colors.black87, fontSize: 15, fontWeight: FontWeight.w600),
                                     border: InputBorder.none,
                                     contentPadding: EdgeInsets.zero,
                                   ),
                                 ),
                               ),
                             ],
                           ),
                         )
                       ],
                     ),
                  )
                ),
              ],
            )
          ),

          // OVERLAY DE RESULTADOS DE BUSCA
          if (_pickupFocus.hasFocus || _dropoffFocus.hasFocus)
             if (_isSearchingLocation || _searchResults.isNotEmpty)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 160 + 16, // Logo abaixo do Card de Inputs
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Container(
                     decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                           BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 10))
                        ],
                     ),
                     child: _isSearchingLocation
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) => Padding(
                               padding: const EdgeInsets.symmetric(horizontal: 16),
                               child: Divider(height: 1, color: Colors.grey.shade100)
                            ),
                            itemBuilder: (context, index) {
                               final item = _searchResults[index];
                               
                               // Extração de Textos
                               final mainText = item['main_text'] ?? 'Localização';
                               final subText = item['secondary_text'] ?? '';
                               
                               // Calcula a distância dinamicamente se não estiver na API de autocomplete
                               double distKm = 0;
                               if (item['dist'] != null) {
                                  distKm = (item['dist'] as num).toDouble() / 1000;
                               } else if (item['lat'] != null && item['lon'] != null && _pickupLocation != null) {
                                  final latDest = double.tryParse(item['lat'].toString()) ?? 0;
                                  final lonDest = double.tryParse(item['lon'].toString()) ?? 0;
                                  distKm = const Distance().as(LengthUnit.Kilometer, _pickupLocation!, LatLng(latDest, lonDest));
                               }
                               
                               // Formatação
                               final distMeters = distKm * 1000;
                               final distFormatted = distMeters < 1000 && distMeters > 0
                                   ? '${distMeters.toStringAsFixed(0)} m' 
                                   : '${distKm.toStringAsFixed(1)} km';
                               final timeMin = (distKm / 20 * 60).round(); // Avg speed 20km/h
                               final timeFormatted = timeMin > 0 ? '$timeMin min' : '< 1 min';
                               
                               IconData iconData = Icons.place;
                               Color iconColor = Colors.orange;
                               
                               // Lógica de ícones baseada em categoria
                               final cat = item['category']?.toString().toLowerCase() ?? '';
                               if (cat.contains('shop') || cat.contains('market') || cat.contains('store')) {
                                  iconData = Icons.shopping_cart;
                               } else if (cat.contains('restaurant') || cat.contains('food')) {
                                  iconData = Icons.restaurant;
                                  iconColor = Colors.red;
                               } else if (cat.contains('health') || cat.contains('hospital')) {
                                  iconData = Icons.local_hospital;
                                  iconColor = Colors.teal;
                               } else if (item['is_poi'] == true) {
                                  iconData = Icons.storefront;
                               }

                               return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  leading: CircleAvatar(
                                     backgroundColor: iconColor.withValues(alpha: 0.1),
                                     child: Icon(iconData, color: iconColor, size: 20),
                                  ),
                                  title: Text(mainText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                                  subtitle: subText.isNotEmpty ? Text(subText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)) : null,
                                  trailing: Column(
                                     mainAxisAlignment: MainAxisAlignment.center,
                                     crossAxisAlignment: CrossAxisAlignment.end,
                                     children: [
                                        Text(distFormatted, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
                                        const SizedBox(height: 2),
                                        Text(timeFormatted, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                                     ],
                                  ),
                                  onTap: () => _selectSearchResult(item),
                               );
                            }
                        ),
                  ),
                ),

        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v) {
    bool isSelected = _selectedVehicleId == v['id'];
    return GestureDetector(
      onTap: () => setState(() => _selectedVehicleId = v['id']),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(16),
        width: 130,
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryYellow.withValues(alpha: 0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primaryYellow : Colors.grey.shade200, width: 2),
        ),
        child: Column(
          children: [
            Image.asset(v['asset'], width: 60),
            const SizedBox(height: 8),
            Text(v['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('R\$ ${_fareEstimate!['estimated']}', style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildMarker({required bool isPickup}) {
    return Container(
      decoration: BoxDecoration(
        color: isPickup ? Colors.blue : Colors.orange,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Icon(isPickup ? Icons.my_location : Icons.location_on, color: Colors.white, size: 20),
    );
  }
}
