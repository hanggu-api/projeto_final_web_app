import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/data_gateway.dart';
import '../../services/uber_service.dart';
import '../../services/remote_config_service.dart';
import 'dart:math';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/media_service.dart';
import '../../services/notification_service.dart';
import '../../services/realtime_service.dart';
import '../client/widgets/provider_arrived_modal.dart';
import 'widgets/service_card.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../widgets/skeleton_loader.dart';
import '../profile/provider_profile_screen.dart';
import '../../widgets/ad_carousel.dart';
import '../../services/photon_autocomplete_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _media = MediaService();
  final _photonService = PhotonAutocompleteService();
  List<dynamic> _services = [];
  bool _isLoading = true;
  String _userName = 'Cliente';
  Uint8List? _avatarBytes;
  Map<String, String> _lastStatuses = {};
  int _unreadCount = 0;
  bool _uberEnabled = false;

  final List<Map<String, dynamic>> _notifications = [];
  late AnimationController _bellController;
  Timer? _refreshTimer;
  final _mapController = MapController();
  LatLng _currentPosition = const LatLng(-23.5505, -46.6333); // Default SP
  bool _isMapReady = false;

  // Trip Mode State
  bool _isInTripMode = false;
  
  // Service Mode State
  bool _isInServiceMode = false;
  final TextEditingController _servicePromptController = TextEditingController();
  
  bool _isServiceAiClassifying = false;
  String? _aiProfessionName;
  String? _aiTaskName;
  double? _aiTaskPrice;
  String? _aiServiceType;
  bool _isLoadingServiceCandidates = false;
  bool _isCreatingService = false;
  List<Map<String, dynamic>> _serviceCandidates = [];
  Timer? _serviceAiDebounce;
  
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  Map<String, dynamic>? _fareEstimate;
  bool _isRequestingTrip = false;
  Timer? _debounce;
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _destinationFocus = FocusNode();
  bool _selectingPickup = false;
  String? _sessionToken;
  List<LatLng> _routePolyline = [];
  String? _routeDistance;
  String? _routeDuration;
  final Map<String, List<Map<String, dynamic>>> _autocompleteCache = {};
  final Map<String, LatLng> _detailsCache = {};
  int _selectedVehicleTypeId = 1; // Default: UberX/Econômico
  Map<int, Map<String, dynamic>> _fareEstimatesByVehicle = {};
  final List<Map<String, dynamic>> _vehicleTypes = [
    {
      'id': 1,
      'name': 'uberx',
      'display_name': 'Econômico',
      'icon': Icons.directions_car,
      'asset': 'assets/images/uber_car_eco.png'
    },
    {
      'id': 2,
      'name': 'comfort',
      'display_name': 'Conforto',
      'icon': Icons.weekend,
      'asset': 'assets/images/uber_car_comfort.png'
    },
    {
      'id': 3,
      'name': 'moto',
      'display_name': 'Moto',
      'icon': Icons.directions_bike,
      'asset': 'assets/images/uber_moto.png'
    },
  ];

  void _generateSessionToken() {
    if (_sessionToken == null) {
      _sessionToken = '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(100000)}';
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      poly.add(LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble()));
    }
    return poly;
  }

  @override
  void initState() {
    super.initState();
    _bellController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _checkLocationPermission();
    _loadProfile();
    // Real-time notifications handled by DataGateway
    _loadServices();
    _loadAvatar();
    _checkUberEnabled();
    final rt = RealtimeService();
    rt.connect();
    rt.onEvent('service.created', (_) => _loadServices());
    rt.onEvent('service.status', (data) async {
      // Filter out test1 status updates if possible
      if (data['provider_name']?.toString().toLowerCase().contains('test1') ==
          true) {
        return;
      }

      try {
        final status = (data['status'] != null)
            ? data['status'].toString()
            : null;
        if (!kIsWeb && status != null) {
          // If schedule_proposed, the backend sends a specific Push Notification.
          // We can either suppress the generic local notification here, or show a better one.
          // For now, let's suppress the GENERIC "update" for this specific status to avoid
          // "Atualização de Serviço: Novo status schedule_proposed" which is ugly.
          if (status != 'schedule_proposed') {
             final payload = data;
             await NotificationService().showFromService(payload, event: status);
          }
        }

        // Add to local notification list
        if (mounted) {
          String title = 'Atualização de Serviço';
          String body = 'Novo status: $status';
          
          if (status == 'schedule_proposed') {
             title = 'Proposta de Agendamento';
             body = 'O prestador enviou uma proposta de horário. Toque para ver.';
          }

          setState(() {
            _unreadCount++;
            _bellController.forward(from: 0.0);
            _notifications.insert(0, {
              'title': title,
              'body': body,
              'time': DateTime.now(),
              'isRead': false,
            });
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title: $body'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              action: status == 'schedule_proposed' ? SnackBarAction(
                label: 'VER',
                onPressed: () {
                   final id = data['id'] ?? data['service_id'];
                   if (id != null) _handleServiceRedirection(id.toString(), data);
                },
              ) : null,
            ),
          );
        }
      } catch (_) {}
      _loadServices();
    });

    // Listen specifically for provider_arrived event to show payment modal immediately
    rt.onEvent('provider_arrived', (data) {
      if (!mounted) return;
      final serviceId = data['service_id'] ?? data['id'];
      if (serviceId != null) {
        showDialog(
          context: context,
          builder: (context) => ProviderArrivedModal(
            serviceId: serviceId.toString(),
            initialData: data,
          ),
        );
      }
      _loadServices();
    });

    // Listen for generic notifications (simulated or real)
    rt.onEvent('notification', (data) {
      // Filter out test1 notifications
      final title = (data['title'] ?? '').toString().toLowerCase();
      final body = (data['body'] ?? '').toString().toLowerCase();
      if (title.contains('test1') || body.contains('test1')) return;

      if (mounted) {
        // Add to local list
        setState(() {
          _unreadCount++;
          _bellController.forward(from: 0.0);
          _notifications.insert(0, {
            'title': data['title'] ?? 'Notificação',
            'body': data['body'] ?? '',
            'time': DateTime.now(),
            'isRead': false,
            'id': data['id'], // Service ID
            'type': data['type'],
          });
        });

        // Show Local Notification (System Banner)
        NotificationService().showNotification(
          data['title'] ?? 'Notificação',
          data['body'] ?? '',
        );

        // Also show SnackBar for in-app feedback
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${data['title'] ?? 'Notificação'}: ${data['body'] ?? ''}',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
        );
      }
      _loadServices(); // Force refresh service list on any notification
    });

    // Listen for chat messages
    void handleChatMessage(dynamic data) {
      if (!mounted) return;
      setState(() {
        _unreadCount++;
        _bellController.forward(from: 0.0);
        _notifications.insert(0, {
          'title': 'Nova Mensagem',
          'body': data['message'] ?? 'Nova mensagem recebida',
          'time': DateTime.now(),
          'isRead': false,
          'id': data['service_id'] ?? data['id'],
          'type': 'chat_message',
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nova Mensagem: ${data['message'] ?? ''}'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Ver',
            onPressed: () {
              final id = data['service_id'] ?? data['id'];
              if (id != null) {
                context.push('/chat/${id.toString()}');
              }
            },
          ),
        ),
      );
    }

    rt.onEvent('chat.message', handleChatMessage);
    rt.onEvent('chat_message', handleChatMessage);

    // Listen for general service updates to refresh the list
    rt.onEvent('service.status', (_) => _loadServices());
    rt.onEvent('service.accepted', (_) => _loadServices());
    rt.onEvent('service.updated', (_) => _loadServices());
    rt.onEvent('service.deleted', (_) => _loadServices());
    rt.onEvent('service.arrived', (_) => _loadServices());
    rt.onEvent('provider_arrived', (_) => _loadServices());
    rt.onEvent('service.completed', (_) => _loadServices());
    
    // Listen for completion request
    rt.onEvent('completion_requested', (_) => _loadServices());

    // Listen for payment confirmation to refresh the list immediately
    rt.onEvent('payment_confirmed', (_) {
      _loadServices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pagamento confirmado! O prestador continuará o serviço.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });

    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadServices());
  }

  @override
  void dispose() {
    _bellController.dispose();
    _refreshTimer?.cancel();
    _debounce?.cancel();
    _pickupController.dispose();
    _destinationController.dispose();
    _pickupFocus.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  void _toggleTripMode() {
    setState(() {
      _isInTripMode = !_isInTripMode;
      if (_isInTripMode) {
        // Init logic if needed
        if (_pickupLocation == null) {
           _pickupLocation = _currentPosition;
           _pickupController.text = 'Meu Local';
        }
      } else {
        // Reset logic if needed
        _fareEstimate = null;
        _fareEstimatesByVehicle.clear();
        _searchResults = [];
        _destinationController.clear();
        _dropoffLocation = null;
        _routePolyline = [];
        _routeDistance = null;
        _routeDuration = null;
      }
    });
  }



  void _onSearchChanged(String query, bool isPickup) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final trimmedQuery = query.trim();
      
      // MUDANÇA: Reduzido de 4 para 3 caracteres mínimos
      if (trimmedQuery.length < 3) {
        if (mounted) setState(() => _searchResults = []);
        return;
      }
      
      if (_autocompleteCache.containsKey(trimmedQuery)) {
        if (mounted) setState(() => _searchResults = _autocompleteCache[trimmedQuery]!);
        return;
      }
      
      if (mounted) setState(() => _isSearching = true);
      
      try {
        final response = await _api.get('/location/search?q=${Uri.encodeComponent(trimmedQuery)}');
        
        debugPrint('====== RESPOSTA TOMTOM ======');
        debugPrint(response.toString());
        debugPrint('=============================');
        
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
        }
        
        if (response['success'] == true && response['results'] != null) {
          final List<dynamic> data = response['results'];
          // Inicialmente converte e varre para preencher bairros faltantes via Nominatim
          final rawResults = data.map<Map<String, dynamic>>((item) {
            return {
               'item': item,
               'address': item['address'] ?? {},
               'poi': item['poi'],
               'lat': item['position']?['lat'],
               'lon': item['position']?['lon'],
               'dist': item['dist'],
            };
          }).toList();

          // Requisições paralelas para resolver os bairros (FORA DO SETSTATE)
          final enrichedResults = await Future.wait(rawResults.map((raw) async {
             final address = raw['address'];
             final poi = raw['poi'];
             String? bairro = address['municipalitySubdivision'];

             // Se a TomTom engoliu o Bairro, usamos nosso backend (Nominatim/OSM geodecoding Reverso)
             if ((bairro == null || bairro.isEmpty) && raw['lat'] != null && raw['lon'] != null) {
                try {
                   final reverseResp = await _api.get('/geo/reverse?lat=${raw['lat']}&lon=${raw['lon']}');
                   if (reverseResp['success'] == true && reverseResp['details'] != null) {
                       bairro = reverseResp['details']['suburb'] ?? reverseResp['details']['neighbourhood'] ?? reverseResp['details']['village'] ?? reverseResp['details']['city_district'];
                   }
                } catch (e) {
                   debugPrint('Falha ao reverter Bairro: \$e');
                }
             }

             String mainTitle = poi != null 
                 ? poi['name'] 
                 : (address['streetName'] ?? "Endereço desconhecido");
             
             if (poi == null && address['freeformAddress'] != null) {
                 mainTitle = address['freeformAddress'].split(',')[0];
             }
             
             String subtitle = '';
             List<String> addressParts = [];
             
             if (address['streetName'] != null && address['streetName'].toString().isNotEmpty) {
                 String rua = address['streetName'];
                 if (address['streetNumber'] != null) {
                     rua += ", ${address['streetNumber']}";
                 }
                 addressParts.add(rua);
             }
             
             if (bairro != null && bairro.isNotEmpty) {
                 addressParts.add(bairro);
             }
             
             addressParts.add(address['municipality'] ?? 'Imperatriz');

             if (addressParts.length > 1) { // Só para garantir q não fica só "Imperatriz" pelado sem motivo
                 subtitle = addressParts.join(' - ');
             } else if (address['freeformAddress'] != null && address['freeformAddress'].toString().isNotEmpty) {
                 subtitle = address['freeformAddress'];
             } else {
                 subtitle = "${address['municipality'] ?? 'Imperatriz'}, ${address['countrySubdivisionCode'] ?? 'MA'}";
             }

             return {
               'main_text': mainTitle,
               'secondary_text': subtitle,
               'is_poi': poi != null, 
               'display_name': '$mainTitle - $subtitle',
               'lat': raw['lat'],
               'lon': raw['lon'],
               'dist': raw['dist'],
             };
          }));

          if (mounted) {
            setState(() {
              _searchResults = enrichedResults;
              _autocompleteCache[trimmedQuery] = enrichedResults;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _searchResults = [];
            });
          }
        }
      } catch (e) {
        debugPrint('Erro na busca encriptada TomTom: $e');
        if (mounted) {
          setState(() {
            _isSearching = false;
            _searchResults = [];
          });
        }
      } finally {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _selectSearchResult(dynamic result, bool isPickup) async {
    final display = result['display_name'] ?? result['address'] ?? '';
    double? lat;
    double? lon;
    
    // Mapbox Geocoding returns lat/lon directly
    if (result['lat'] != null && result['lon'] != null) {
        lat = double.tryParse(result['lat'].toString());
        lon = double.tryParse(result['lon'].toString());
    }
    
    if (lat != null && lon != null) {
      setState(() {
        if (isPickup) {
          _pickupLocation = LatLng(lat!, lon!);
          _pickupController.text = display;
        } else {
          _dropoffLocation = LatLng(lat!, lon!);
          _destinationController.text = display;
        }
        _searchResults = [];
        FocusScope.of(context).unfocus();
        
        // Move map
        _mapController.move(LatLng(lat!, lon!), 16);
      });
        
      // Check for route & fare
      if (_pickupLocation != null && _dropoffLocation != null) {
         await _calculateRouteAndFare();
      }
    }
  }

  Future<void> _calculateRouteAndFare() async {
    if (_pickupLocation == null || _dropoffLocation == null) return;

    setState(() => _isRequestingTrip = true);
    try {
      // 1. Fetch Route (Polyline, Distance, Time)
      final route = await _api.get(
          '/location/route?originLat=${_pickupLocation!.latitude}&originLon=${_pickupLocation!.longitude}&destLat=${_dropoffLocation!.latitude}&destLon=${_dropoffLocation!.longitude}'
      );
      
      if (mounted && route['polyline'] != null) {
          setState(() {
             _routeDistance = route['distance_text'];
             _routeDuration = route['duration_text'];
             _routePolyline = _decodePolyline(route['polyline']);
             // Fit map bounds to polyline
             final bounds = LatLngBounds.fromPoints(_routePolyline);
             _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
          });
      }

      // 2. Fetch Fare Estimates for all vehicles
      await _calculateFare();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao traçar rota/tarifa: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRequestingTrip = false);
    }
  }


  Future<void> _calculateFare() async {
    if (_pickupLocation == null || _dropoffLocation == null) return;

    setState(() {
      _isRequestingTrip = true;
      _fareEstimatesByVehicle.clear();
    });

    try {
      // Fetch fares for all available vehicle types
      final List<Future<void>> fareFutures = _vehicleTypes.map((type) async {
        final typeId = type['id'] as int;
        try {
          final fare = await UberService().calculateFare(
            pickupLat: _pickupLocation!.latitude,
            pickupLng: _pickupLocation!.longitude,
            dropoffLat: _dropoffLocation!.latitude,
            dropoffLng: _dropoffLocation!.longitude,
            vehicleTypeId: typeId,
          );
          if (mounted) {
            setState(() {
              _fareEstimatesByVehicle[typeId] = fare;
              // If it's the currently selected one, also update _fareEstimate for legacy compatibility if needed
              if (_selectedVehicleTypeId == typeId) {
                _fareEstimate = fare;
              }
            });
          }
        } catch (e) {
          debugPrint('Error calculating fare for vehicle type $typeId: $e');
        }
      }).toList();

      await Future.wait(fareFutures);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao calcular tarifas: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRequestingTrip = false);
    }
  }

  Future<void> _requestRide() async {
    if (_pickupLocation == null || _dropoffLocation == null) return;

    setState(() => _isRequestingTrip = true);
    try {
      final trip = await UberService().requestTrip(
        pickupLat: _pickupLocation!.latitude,
        pickupLng: _pickupLocation!.longitude,
        pickupAddress: _pickupController.text,
        dropoffLat: _dropoffLocation!.latitude,
        dropoffLng: _dropoffLocation!.longitude,
        dropoffAddress: _destinationController.text,
        vehicleTypeId: _selectedVehicleTypeId,
      );

      if (mounted) {
        // Toggle off trip mode and go to tracking
        _toggleTripMode();
        final tripId = trip['trip_id'] ?? trip['id'];
        if (tripId != null) {
           _handleServiceRedirection(tripId.toString(), {'location_type': 'uber'});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao solicitar viagem: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRequestingTrip = false);
    }
  }

  Future<void> _handleServiceRedirection(String serviceId, [Map<String, dynamic>? data]) async {
    if (serviceId.isEmpty) {
      context.push('/notifications');
      return;
    }

    // Se já tivermos a info no payload, usamos.
    String? locationType = data?['location_type']?.toString();
    
    // Se não tivermos (ex: evento simplificado), buscamos do backend
    if (locationType == null) {
      try {
        final details = await _api.getServiceDetails(serviceId);
        locationType = details['location_type']?.toString();
      } catch (e) {
        debugPrint('Error fetching service details for redirection: $e');
      }
    }

    if (!mounted) return;

    if (locationType == 'provider') {
      context.push('/scheduled-service/$serviceId');
    } else {
      context.push('/tracking/$serviceId');
    }
  }

  Future<void> _checkLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Option: Show snackbar or dialog to ask user to enable it
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Por favor, habilite a localização.')),
          );
        }
        // return; // or continue to request permission anyway
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissão de localização negada permanentemente.'),
            ),
          );
        }
      }

      // Force get position to activate/warm up
      if (serviceEnabled &&
          (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse)) {
        
        // Tenta pegar a última conhecida imediatamente para evitar o default (SP)
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null && mounted) {
           setState(() {
             _currentPosition = LatLng(lastPos.latitude, lastPos.longitude);
             _isMapReady = true;
           });
           _mapController.move(_currentPosition, 15);
           debugPrint('Last known position: $lastPos');
           _updateCurrentAddress(lastPos.latitude, lastPos.longitude);
        }

        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        if (mounted) {
          setState(() {
            _currentPosition = LatLng(pos.latitude, pos.longitude);
            _isMapReady = true;
          });
          _mapController.move(_currentPosition, 15);
          debugPrint('Location fetched: $pos');
          _updateCurrentAddress(pos.latitude, pos.longitude);
        }
      }
    } catch (_) {}
  }

  Future<void> _updateCurrentAddress(double lat, double lon) async {
    final res = await _api.reverseGeocode(lat, lon);
    if (res != null && mounted) {
      setState(() {
        _pickupController.text = res['main_text'] ?? res['display_name'] ?? 'Meu Local';
        _pickupLocation = LatLng(lat, lon);
      });
      debugPrint('📍 Endereço Atual: ${_pickupController.text}');
    }
  }

  Future<void> _loadProfile() async {
    try {
      final res = await _api.getProfile();
      debugPrint('🔍 Profile response: $res');
      if (res['success'] == true && res['user'] != null) {
        final name = res['user']['full_name'] ?? 'Cliente';
        final userIdRaw = res['user']['id'];
        debugPrint('👤 Username loaded: $name (ID: $userIdRaw)');
        
        if (userIdRaw != null) {
          final userId = int.tryParse(userIdRaw.toString());
          if (userId != null) {
            RealtimeService().init(userId);
          }
        }

        if (mounted) {
          setState(() {
            _userName = name;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading profile: $e');
    }
  }

  Future<void> _loadAvatar() async {
    try {
      final bytes = await _media.loadMyAvatarBytes();
      if (bytes != null && mounted) setState(() => _avatarBytes = bytes);
    } catch (_) {}
  }

  Future<void> _editAvatar() async {
    if (kIsWeb) {
      final res = await _media.pickImageWeb();
      if (res != null &&
          res.files.isNotEmpty &&
          res.files.first.bytes != null) {
        final file = res.files.first;
        final mime = file.extension != null
            ? 'image/${file.extension}'
            : 'image/jpeg';
        await _media.uploadAvatarBytes(file.bytes!, file.name, mime);
        await _loadAvatar();
      }
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Usar câmera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Escolher avatar rápido'),
              onTap: () => Navigator.pop(ctx, 'preset'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (choice == 'preset') {
      await _choosePresetAvatar();
      return;
    }

    final source = choice == 'camera'
        ? ImageSource.camera
        : ImageSource.gallery;
    final xfile = await _media.pickImageMobile(source);
    if (xfile != null) {
      final bytes = await xfile.readAsBytes();
      await _media.uploadAvatarBytes(bytes, xfile.name, 'image/jpeg');
      await _loadAvatar();
    }
  }

  Future<void> _choosePresetAvatar() async {
    // Lista simples de avatares públicos. Pode trocar pelos seus próprios assets/URLs.
    final presets = List.generate(
      8,
      (i) => 'https://i.pravatar.cc/300?img=${i + 1}',
    );
    final picked = await showDialog<String?>(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 320,
          height: 420,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: const Text(
                  'Escolha um avatar rápido',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: presets.length,
                  itemBuilder: (context, idx) {
                    final url = presets[idx];
                    return InkWell(
                      onTap: () => Navigator.of(ctx).pop(url),
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          memCacheWidth: 200, // Avatars are small
                          maxWidthDiskCache: 400,
                          placeholder: (context, url) => BaseSkeleton(width: 80, height: 80, borderRadius: BorderRadius.all(Radius.circular(40))),
                          errorWidget: (context, url, error) => const Icon(Icons.error),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    try {
      final resp = await http.get(Uri.parse(picked));
      if (resp.statusCode == 200) {
        await _media.uploadAvatarBytes(
          resp.bodyBytes,
          'preset.png',
          'image/png',
        );
        await _loadAvatar();
      }
    } catch (_) {}
  }

  Future<void> _handleCleanup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar Testes'),
        content: const Text('Deseja deletar todos os seus serviços para um teste limpo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Sim, Limpar', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      // We can use a custom endpoint or just run the script via a background call if we exposed it
      // For now, let's assume we have a DELETE /services/all or similar.
      // Or we can just cancel them all. 
      // Given the user is an admin/dev, let's try a dedicated cleanup endpoint if it exists
      // If not, we'll just loop and cancel (safer for now without backend change)
      for (final s in _services) {
        final id = s['id']?.toString();
        if (id != null) await _api.cancelService(id);
      }
      
      await _loadServices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ambiente resetado (serviços cancelados)')),
        );
      }
    } catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao resetar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCancelService(String serviceId) async {
    try {
      await ApiService().cancelService(serviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Serviço cancelado com sucesso')),
        );
        _loadServices();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao cancelar serviço: $e')));
      }
    }
  }

  Future<void> _loadServices() async {
    try {
      final services = await _api.getMyServices();
      final prev = Map<String, String>.from(_lastStatuses);
      if (mounted) {
        setState(() {
          _services = services.where((s) {
            final st = s['status']?.toString().toLowerCase();
            if (st == 'cancelled' || st == 'canceled') return false;
            
            // FILTRO: Se o serviço foi arquivado/dispensado pelo usuário, remove da Home.
            final isDismissed = s['is_dismissed'] == 1 || s['is_dismissed'] == true;
            if (isDismissed) return false;

            // FILTRO: Se o serviço está concluído e já foi avaliado, remove da Home.
            // Ele continuará disponível apenas no Histórico nas Configurações.
            if (st == 'completed') {
              final reviews = s['reviews'] as List?;
              if (reviews != null && reviews.isNotEmpty) return false;
            }

            // FILTRO DE AGENDAMENTO VENCIDO (Strict)
            // Se for um agendamento (scheduled/pending/accepted) e a data já passou, esconde.
            // Solicitação do usuário: "Agendado as 20:00, as 20:30 não deve estar visível".
            if (['scheduled', 'pending', 'accepted'].contains(st) && s['scheduled_at'] != null) {
               final scheduledAt = _toDate(s['scheduled_at']); // Helper method handles parsing
               if (scheduledAt != null) {
                  // Buffer mínimo de 15 min apenas para evitar desaparecimento instantâneo no segundo exato
                  // Mas atendendo ao exemplo de "20:00 -> 20:30 sumiu".
                  final expiryTime = scheduledAt.add(const Duration(minutes: 15));
                  
                  if (DateTime.now().isAfter(expiryTime)) {
                     // Se ainda não começou (accepted/arrived), considera "vencido"
                     if (s['arrived_at'] == null) {
                        return false; 
                     }
                  }
               }
            }
            
            return true;
          }).toList();

          // ORDENAÇÃO: Etapa mais avançada no topo
          _services.sort((a, b) {
             int getWeight(Map<String, dynamic> s) {
                final st = s['status']?.toString().toLowerCase();
                final arrived = s['arrived_at'] != null;
                
                if (st == 'in_progress') return 0; // Executando (Topo)
                if (st == 'accepted' && arrived) return 1; // Chegou
                if (st == 'accepted') return 2; // A caminho
                if (st == 'waiting_payment') return 3; // Pagamento
                if (st == 'pending' || st == 'offered') return 4; // Buscando
                if (st == 'completed') return 5; // Avaliação
                return 10;
             }
             
             final wa = getWeight(a);
             final wb = getWeight(b);
             return wa.compareTo(wb);
          });
          _isLoading = false;
          _lastStatuses = {
            for (final s in services)
              (s['id']?.toString() ?? '${services.indexOf(s)}'):
                  (s['status']?.toString() ?? 'pending'),
          };
        });
        for (final s in services) {
          final id = s['id']?.toString();
          final newStatus = s['status']?.toString();
          final oldStatus = id != null ? prev[id] : null;

          // Only notify if we knew about this service before (not first load)
          // and the status actually changed to accepted
          if (oldStatus != null &&
              oldStatus != newStatus &&
              newStatus == 'accepted') {
            if (kIsWeb) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Seu pedido foi aceito')),
              );
            } else {
              await NotificationService().showAccepted();
            }
            break;
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Silently fail or show snackbar in real app
      }
    }
  }

  Future<void> _checkUberEnabled() async {
    try {
      final config = await _api.get('/config');
      if (mounted) {
        setState(() {
          _uberEnabled = config['config']?['uber_module_enabled'] == true;
        });
      }
    } catch (_) {}
  }

  // Helper para parsing de datas (Copiado do ServiceCard para consistência)
  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) {
      String s = v.trim();
      if (s.contains(' ') && !s.contains('T') && !s.contains('Z')) {
        s = '${s.replaceFirst(' ', 'T')}Z';
      }
      return DateTime.tryParse(s)?.toLocal();
    }
    if (v is num) {
      final n = v.toInt();
      return DateTime.fromMillisecondsSinceEpoch(n > 1000000000000 ? n : n * 1000, isUtc: true).toLocal();
    }
    return null;
  }

  Widget _buildCategoryItem(String label, IconData icon, VoidCallback onTap, {Color? color, Color? iconColor}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color ?? Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor ?? Colors.black87, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow() {
    final showPackages = RemoteConfigService.enablePackages;
    final showReserve = RemoteConfigService.enableReserve;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: (showPackages || showReserve) ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
        children: [
          _buildCategoryItem(
            'Viagem',
            LucideIcons.car,
            () {
               setState(() {
                 _isInTripMode = true;
                 _isInServiceMode = false;
               });
            },
            color: AppTheme.primaryYellow.withOpacity(0.3), // Fundo amarelo translúcido
            iconColor: Colors.black87,
          ),
          if (!showPackages && !showReserve) const SizedBox(width: 20),
          _buildCategoryItem(
            'Serviço',
            LucideIcons.hammer,
            () {
               setState(() {
                 _isInServiceMode = true;
                 _isInTripMode = false;
               });
            },
            color: AppTheme.primaryBlue.withOpacity(0.15), // Fundo azul claro translúcido
            iconColor: AppTheme.primaryBlue, // Ícone Azul Forte
          ),
          if (showPackages)
            _buildCategoryItem(
              'Pacote',
              LucideIcons.box,
              () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Em breve: Entrega de pacotes')),
                );
              },
              color: AppTheme.categoryPackageBg,
            ),
          if (showReserve)
            _buildCategoryItem(
              'Reservar',
              LucideIcons.calendar,
              () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Em breve: Reservas programadas')),
                );
              },
              color: AppTheme.categoryReserveBg,
            ),
          if (!showPackages && !showReserve) ...[
            const Spacer(),
            const Spacer(),
          ]
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. Map de Fundo
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition,
                initialZoom: 15.0,
                onMapReady: () => setState(() => _isMapReady = true),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=\${dotenv.env[\'MAPBOX_TOKEN\'] ?? \'\'}',
                  userAgentPackageName: 'com.service101.app',
                ),
                if (_routePolyline.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePolyline,
                        strokeWidth: 4.0,
                        color: AppTheme.primaryBlue,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (!_isInTripMode)
                      Marker(
                        point: _currentPosition,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          LucideIcons.mapPin,
                          color: Colors.blue,
                          size: 30,
                        ),
                      ),
                    if (_pickupLocation != null)
                      Marker(
                        point: _pickupLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                      ),
                    if (_dropoffLocation != null)
                      Marker(
                        point: _dropoffLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on, color: Colors.orange, size: 40),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Header (Trip Mode, Service Mode or Normal)
          if (_isInTripMode)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTripHeader(),
                  if (_isSearching || _searchResults.isNotEmpty)
                    _buildSearchResultsList(),
                ],
              ),
            )
          else if (_isInServiceMode)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildServiceHeader(),
                ],
              ),
            )
          else
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildHeader(),
            ),



          // 4. Panel (Trip Panel, Service Panel, or Normal Scrollable Sheet)
          if (_isInTripMode)
             Align(
               alignment: Alignment.bottomCenter,
               child: AnimatedSize(
                 duration: const Duration(milliseconds: 300),
                 curve: Curves.easeInOut,
                 child: _buildTripPanel(),
               ),
             )
          else if (_isInServiceMode)
             Positioned(
               top: MediaQuery.of(context).padding.top + 100, // Altura estimada do Service Header
               left: 0,
               right: 0,
               bottom: 0,
               child: AnimatedAlign(
                 duration: const Duration(milliseconds: 400),
                 curve: Curves.easeInOut,
                 alignment: (_aiProfessionName != null && !_isServiceAiClassifying) 
                            ? Alignment.topCenter 
                            : Alignment.bottomCenter,
                 child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      alignment: (_aiProfessionName != null && !_isServiceAiClassifying) 
                                 ? Alignment.topCenter 
                                 : Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: (_aiProfessionName != null && !_isServiceAiClassifying) ? 16.0 : 0.0,
                          bottom: (_aiProfessionName != null && !_isServiceAiClassifying) ? 0.0 : 16.0,
                        ),
                        child: _buildServicePanel(),
                      ),
                    ),
                 ),
               ),
             )
          else
             DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.18,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Alça
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 8),

                      // Categorias
                      _buildCategoryRow(),

                      if (_isLoading || _services.isNotEmpty) ...[
                        const SizedBox(height: 24),

                        // Meus Serviços Header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Meus serviços',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              TextButton(
                                onPressed: () => context.push('/my-services'),
                                child: const Text('Ver todos'),
                              ),
                            ],
                          ),
                        ),

                        // Services List
                        if (_isLoading)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: List.generate(
                                3,
                                (index) => const Padding(
                                  padding: EdgeInsets.only(bottom: 16),
                                  child: CardSkeleton(),
                                ),
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _services.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 16),
                                  itemBuilder: (context, index) {
                                    final service = _services[index];
                                    return ServiceCard(
                                      key: ValueKey(service['id']?.toString() ?? index.toString()),
                                      status: service['status'] ?? 'pending',
                                      providerName: service['provider_name'] ?? service['providers']?['users']?['full_name'] ?? 'Aguardando...',
                                      distance: '---',
                                      category: service['profession'] ?? service['category_name'] ?? service['description'] ?? 'Serviço',
                                      details: service,
                                      onRefreshNeeded: _loadServices,
                                      onTrack: () {
                                        final id = service['id']?.toString();
                                        if (id != null) context.push('/tracking/$id');
                                      },
                                      onCancel: () {
                                        final id = service['id']?.toString();
                                        if (id != null) _handleCancelService(id);
                                      },
                                      onPay: () {
                                        final id = service['id']?.toString();
                                        if (id == null) return;
                                        final arrivedAt = service['arrived_at'];
                                        final type = arrivedAt != null ? 'remaining' : 'deposit';
                                        final priceTotal = double.tryParse(service['price_estimated']?.toString() ?? '0') ?? 0.0;
                                        final priceUpfront = double.tryParse(service['price_upfront']?.toString() ?? '0') ?? 0.0;
                                        final amount = type == 'remaining' ? (priceTotal - priceUpfront) : priceUpfront;
                                         context.push('/payment/$id', extra: {
                                           'serviceId': id,
                                           'type': type,
                                           'amount': amount,
                                           'total': priceTotal,
                                           'serviceType': service['service_type'],
                                           'professionName': service['profession'] ?? service['category_name'],
                                           'providerName': service['provider_name'] ?? service['providers']?['users']?['full_name'],
                                         });
                                      },
                                      onRate: () {
                                        final id = service['id']?.toString();
                                        if (id != null) context.push('/review/$id');
                                      },
                                    );
                                  },
                                ),
                      ],
                      
                      const SizedBox(height: 24),

                      // Publicidade
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24.0),
                        child: AdCarousel(height: 180),
                      ),
                      
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primaryYellow,
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 24,
        right: 24,
        bottom: 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              InkWell(
                onTap: _editAvatar,
                borderRadius: BorderRadius.circular(40),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: _avatarBytes == null
                        ? const Center(
                            child: Icon(
                              LucideIcons.user,
                              color: Colors.grey,
                              size: 20,
                            ),
                          )
                        : Image.memory(
                            _avatarBytes!,
                            fit: BoxFit.cover,
                            width: 40,
                            height: 40,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bem-vindo(a),',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  Text(
                    _userName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client.auth.currentUser?.id != null
                ? DataGateway().watchNotifications(Supabase.instance.client.auth.currentUser!.id)
                : const Stream.empty(),
            builder: (context, snapshot) {
              final notifications = snapshot.data ?? [];
              final unreadCount = notifications.where((n) => n['read'] != true && n['is_read'] != true).length;

              return GestureDetector(
                onTap: () => context.push('/notifications'),
                child: Stack(
                  alignment: Alignment.topRight,
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(
                      LucideIcons.bell,
                      color: Colors.black87,
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            unreadCount > 9 ? '9+' : unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }
          ),
          const SizedBox(width: 8),
          Text(
            '101 Service',
            style: TextStyle(
              color: AppTheme.darkBlueText,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  void _showScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Escaneie o QR Code',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Aponte para o código do profissional',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 30),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 250,
                  height: 250,
                  child: MobileScanner(
                    controller: MobileScannerController(
                      detectionSpeed: DetectionSpeed.noDuplicates,
                    ),
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        final String? code = barcode.rawValue;
                        if (code != null && code.startsWith('service101://profile/')) {
                          final idStr = code.replaceFirst('service101://profile/', '');
                          final id = int.tryParse(idStr);
                          if (id != null) {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProviderProfileScreen(providerId: id),
                              ),
                            );
                            break;
                          }
                        }
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationAccordion() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notificações',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          if (_notifications.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Nenhuma notificação recente',
                style: TextStyle(color: Colors.black54),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _notifications.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final n = _notifications[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      )
                    ,
                    child: const Icon(
                      LucideIcons.bell,
                      size: 16,
                      color: Colors.black,
                    ),
                  ),
                  title: Text(
                    n['title'],
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    n['body'],
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    if (n['type'] == 'chat_message') {
                      context.push('/chat', extra: n['id'].toString());
                    } else if (n['id'] != null) {
                      context.push('/tracking/${n['id']}');
                    }
                  },
                );
              },
            ),
        ],
      ),
    );
  }


  
  void _toggleServiceMode() {
    setState(() {
      _isInServiceMode = !_isInServiceMode;
      _isInTripMode = false;
      if (!_isInServiceMode) {
        FocusScope.of(context).unfocus();
        _servicePromptController.clear();
        _isServiceAiClassifying = false;
        _aiProfessionName = null;
        _aiTaskName = null;
        _aiTaskPrice = null;
        _serviceCandidates.clear();
      }
    });
  }

  bool get _isFixedService {
    final nameLower = (_aiProfessionName ?? '').toLowerCase();
    return _aiServiceType == 'at_provider' || 
           nameLower.contains('barbeiro') || 
           nameLower.contains('cabel');
  }

  void _onServicePromptChanged(String v) {
     _serviceAiDebounce?.cancel();
     if (v.trim().length >= 4) {
        _serviceAiDebounce = Timer(const Duration(milliseconds: 1000), _classifyServiceAi);
     } else {
        setState(() {
           _isServiceAiClassifying = false;
           _aiProfessionName = null;
           _serviceCandidates.clear();
        });
     }
  }

  Future<void> _classifyServiceAi() async {
     final text = _servicePromptController.text.trim();
     if (text.length < 4) return;
     
     setState(() => _isServiceAiClassifying = true);
     try {
        final body = {'text': text};
        final r = await _api.post('/services/ai/classify', body);
        
        if (r['encontrado'] == true && mounted) {
           setState(() {
              _aiProfessionName = r['profissao'];
              _aiServiceType = r['service_type'];
              
              if (r['task'] != null) {
                _aiTaskName = r['task']['name'];
                _aiTaskPrice = double.tryParse(r['task']['unit_price']?.toString() ?? '0');
              } else if (r['candidates'] != null && (r['candidates'] as List).isNotEmpty) {
                 final best = r['candidates'][0];
                 _aiTaskName = best['task_name'];
                 _aiTaskPrice = double.tryParse(best['price']?.toString() ?? '0');
              } else {
                 _aiTaskName = null;
                 _aiTaskPrice = null;
              }
           });
        } else if (mounted) {
           setState(() {
             _aiProfessionName = null;
           });
        }
     } catch (e) {
        debugPrint('AI Error: $e');
     } finally {
        if (mounted) setState(() => _isServiceAiClassifying = false);
     }
     if (_aiProfessionName != null) {
       _fetchNearbyServiceCandidates();
     }
  }

  Future<void> _fetchNearbyServiceCandidates() async {
    if (_aiProfessionName == null) return;
    
    setState(() => _isLoadingServiceCandidates = true);
    try {
      final providers = await _api.searchProviders(
        term: _aiProfessionName,
        lat: _currentPosition.latitude,
        lon: _currentPosition.longitude,
      );
      if (mounted) {
         setState(() {
            _serviceCandidates = providers;
         });
      }
    } catch (e) {
      debugPrint('Error fetching nearby candidates: $e');
    } finally {
      if (mounted) setState(() => _isLoadingServiceCandidates = false);
    }
  }

  // --- Service Mode Widgets ---
  Widget _buildServiceHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 16, 
      ),
      decoration: BoxDecoration(
        color: AppTheme.primaryYellow,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
           BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Back Button + Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
               children: [
                 IconButton(
                   icon: Icon(Icons.arrow_back, color: AppTheme.darkBlueText),
                   onPressed: _toggleServiceMode,
                 ),
                 Text(
                   'Solicitar Serviço', 
                   style: TextStyle(
                     fontSize: 18, 
                     fontWeight: FontWeight.bold,
                     color: AppTheme.darkBlueText,
                   ),
                 ),
               ],
            ),
          ),
          const SizedBox(height: 8),
          // AI Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.sparkles, size: 20, color: AppTheme.primaryBlue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _servicePromptController,
                      autofocus: true,
                      onChanged: _onServicePromptChanged,
                      decoration: const InputDecoration(
                        hintText: 'Ex: Preciso de um encanador...',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (value) {
                         if (value.trim().length >= 4) {
                            FocusScope.of(context).unfocus();
                            _classifyServiceAi();
                         }
                      },
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send, color: AppTheme.primaryBlue),
                    onPressed: () {
                       final value = _servicePromptController.text.trim();
                       if (value.length >= 4) {
                          FocusScope.of(context).unfocus();
                          _classifyServiceAi();
                       }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicePanel() {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isServiceAiClassifying) ...[
               const Padding(
                 padding: EdgeInsets.all(32.0),
                 child: Column(
                   children: [
                     CircularProgressIndicator(),
                     SizedBox(height: 16),
                     Text('Analisando seu pedido...', style: TextStyle(color: Colors.grey)),
                   ],
                 ),
               ),
               const SizedBox(height: 16),
            ] else if (_aiProfessionName != null) ...[
               const SizedBox(height: 16),
               _buildServiceAiResults(),
            ] else ...[
               const Padding(
                 padding: EdgeInsets.all(24.0),
                 child: Column(
                   children: [
                     Icon(LucideIcons.bot, size: 40, color: Colors.grey),
                     SizedBox(height: 12),
                     Text(
                       'A Inteligência Artificial vai encontrar\no melhor profissional para você',
                       textAlign: TextAlign.center,
                       style: TextStyle(
                         fontSize: 14,
                         fontWeight: FontWeight.w600,
                         color: Colors.black87,
                       ),
                     ),
                     SizedBox(height: 8),
                     Text(
                       'Descreva o que preicsa no campo acima.',
                       textAlign: TextAlign.center,
                       style: TextStyle(color: Colors.grey, fontSize: 13),
                     ),
                   ]
                 ),
               ),
               const SizedBox(height: 8),
            ]
          ],
        ),
      );
  }

  Future<void> _createImmediateService() async {
    if (_aiProfessionName == null || _aiTaskPrice == null || _aiTaskPrice! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível identificar o serviço. Tente detalhar mais.')),
      );
      return;
    }

    setState(() => _isCreatingService = true);

    try {
      double price = _aiTaskPrice!;
      double upfront = price * 0.30;
      String desc = _servicePromptController.text.trim();
      
      if (desc.isEmpty) {
        desc = _aiTaskName ?? 'Solicitação de serviço móvel';
      } else if (_aiTaskName != null) {
        desc = "$_aiTaskName\n$desc";
      }

      final result = await _api.createService(
        categoryId: 1, 
        description: desc,
        latitude: _currentPosition.latitude,
        longitude: _currentPosition.longitude,
        address: 'Localização Atual', 
        priceEstimated: price,
        priceUpfront: upfront,
        imageKeys: [],
        videoKey: null,
        audioKeys: [],
        profession: _aiProfessionName,
        professionId: null,
        locationType: 'client',
        providerId: null,
        taskId: null, 
      );

      final serviceId = result['service']?['id']?.toString() ?? result['id']?.toString();
      
      if (serviceId != null) {
        if (mounted) {
           context.push('/payment/$serviceId', extra: {
             'serviceId': serviceId,
             'amount': upfront,
             'total': price,
             'type': 'deposit',
           });
           _toggleServiceMode(); // Fecha o painel da Home
           _servicePromptController.clear();
        }
      } else {
        throw Exception('ID do serviço não retornado.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao criar serviço: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingService = false);
      }
    }
  }

  Widget _buildServiceAiResults() {
     return Padding(
       padding: const EdgeInsets.symmetric(horizontal: 16.0),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
            Row(
              children: [
                const Icon(LucideIcons.checkCircle2, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  '$_aiProfessionName Identificado',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_isFixedService) ...[
               Card(
                 elevation: 0,
                 color: Colors.white,
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
                 child: Padding(
                   padding: const EdgeInsets.all(16.0),
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                     _aiTaskName ?? _aiProfessionName ?? 'Serviço',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                  ),
                                  const Text(
                                    'Valor Estimado',
                                    style: TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _aiTaskPrice != null && _aiTaskPrice! > 0 
                                 ? 'R\$ ${_aiTaskPrice!.toStringAsFixed(2)}' 
                                 : 'A combinar',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.blueAccent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Encontramos prestadores móveis na sua região! O atendimento irá até você.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isCreatingService ? null : _createImmediateService,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isCreatingService
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(LucideIcons.wrench, size: 20, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text('Solicitar Atendimento Imediato', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                                    ],
                                  ),
                          ),
                        ),
                     ],
                   ),
                 ),
               )
            ] else ...[
               if (_isLoadingServiceCandidates)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(),
                  ))
               else if (_serviceCandidates.isEmpty)
                  Card(
                    elevation: 0,
                    color: Colors.grey.shade50,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                           const Icon(LucideIcons.searchX, color: Colors.grey, size: 32),
                           const SizedBox(height: 12),
                           const Text('Nenhum profissional próximo.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
                           const SizedBox(height: 4),
                           const Text('Gostaria de solicitar assim mesmo para profissionais mais distantes?', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
                           const SizedBox(height: 16),
                           SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                 onPressed: () {
                                    context.push('/create-service', extra: {
                                      'initialPrompt': _servicePromptController.text,
                                      'service': {
                                        'name': _aiTaskName ?? _aiProfessionName,
                                        'category': _aiCategoryName,
                                        'price': _aiTaskPrice,
                                      }
                                    });
                                    _toggleServiceMode();
                                 },
                                 style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                                 child: const Text('Solicitar Atendimento'),
                              )
                           )
                        ],
                      ),
                    ),
                  )
               else
                  ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _serviceCandidates.length,
                    itemBuilder: (ctx, idx) {
                      final p = _serviceCandidates[idx];
                      final providerData = p['providers'] ?? p;
                      final name = providerData['commercial_name'] ?? p['full_name'] ?? 'Prestador';
                      final avatar = p['avatar_url'] ?? '';
                      final rating = double.tryParse(providerData['rating_avg']?.toString() ?? '5.0') ?? 5.0;
                      final count = providerData['rating_count'] ?? 0;
                      final distance = p['distance_km'] != null ? '${double.parse(p['distance_km'].toString()).toStringAsFixed(1)} km' : '-- km';
                      final bool isOpen = p['is_open'] == true;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2), width: 2),
                                ),
                                child: CircleAvatar(
                                  radius: 26,
                                  backgroundColor: Colors.grey[200],
                                  backgroundImage: (avatar != null && avatar.isNotEmpty) 
                                      ? CachedNetworkImageProvider(avatar) 
                                      : null,
                                  child: (avatar == null || avatar.isEmpty) 
                                      ? const Icon(Icons.person, color: Colors.grey) 
                                      : null,
                                ),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    _aiTaskName ?? _aiProfessionName ?? 'Serviço Identificado',
                                    style: TextStyle(
                                      color: AppTheme.primaryBlue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, size: 14, color: Colors.amber),
                                      const SizedBox(width: 2),
                                      Text(
                                        '$rating ($count)',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('•', style: TextStyle(color: Colors.grey)),
                                      const SizedBox(width: 8),
                                      Text(
                                        distance,
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: isOpen ? Colors.green.shade50 : Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isOpen ? 'Aberto agora' : 'Fechado',
                                      style: TextStyle(
                                        color: isOpen ? Colors.green.shade700 : Colors.red.shade700,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                               _aiTaskName ?? _aiProfessionName ?? 'Serviço',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            ),
                                            const Text(
                                              'Valor Estimado',
                                              style: TextStyle(color: Colors.grey, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        _aiTaskPrice != null && _aiTaskPrice! > 0 
                                           ? 'R\$ ${_aiTaskPrice!.toStringAsFixed(2)}' 
                                           : 'A combinar',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: () {
                                         context.push('/create-service', extra: {
                                            'initialPrompt': _servicePromptController.text,
                                            'providerId': int.tryParse(p['id'].toString()),
                                            'provider': p,
                                            'service': {
                                              'name': _aiTaskName ?? _aiProfessionName,
                                              'category': _aiCategoryName,
                                              'price': _aiTaskPrice,
                                            }
                                         });
                                         _toggleServiceMode();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryBlue,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(LucideIcons.calendarDays, size: 20, color: Colors.white),
                                          SizedBox(width: 8),
                                          Text('Selecionar para Agendamento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ],
            const SizedBox(height: 16),
         ],
       ),
     );
  }

  // --- Trip Mode Widgets ---

  Widget _buildTripHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 0, 
      ),
      decoration: BoxDecoration(
        color: AppTheme.primaryYellow,
        // Remover o arredondamento da base para o card grudar na lista
        boxShadow: [
           BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Back Button + Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
               children: [
                 IconButton(
                   icon: Icon(Icons.arrow_back, color: AppTheme.darkBlueText),
                   onPressed: _toggleTripMode,
                 ),
                 Text(
                   'Para onde vamos?', 
                   style: TextStyle(
                     fontSize: 18, 
                     fontWeight: FontWeight.bold,
                     color: AppTheme.darkBlueText,
                   ),
                 ),
               ],
            ),
          ),
          const SizedBox(height: 8),
          // Inputs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              // Mantemos quadrado para colar na lista de baixo que também será preta
            ),
            child: Column(
              children: [
                // Pickup
                Row(
                  children: [
                    Icon(Icons.my_location, size: 20, color: Colors.grey[600]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _pickupController,
                        focusNode: _pickupFocus,
                        decoration: const InputDecoration(
                          hintText: 'Ponto de partida',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (val) => _onSearchChanged(val, true),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                // Dropoff
                Row(
                  children: [
                    Icon(Icons.location_on, size: 20, color: Colors.grey[600]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _destinationController,
                        focusNode: _destinationFocus,
                        decoration: InputDecoration(
                          hintText: 'Qual o destino?',
                          border: InputBorder.none,
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _destinationController.clear();
                              if (mounted) {
                                setState(() {
                                  _searchResults = [];
                                  _dropoffLocation = null;
                                  _fareEstimate = null;
                                  _fareEstimatesByVehicle.clear();
                                  _routePolyline = [];
                                  _routeDistance = null;
                                  _routeDuration = null;
                                });
                              }
                            },
                          ),
                        ),
                        onChanged: (val) => _onSearchChanged(val, false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsList() {
    return Container(
       // Elevado para 360 para acomodar perfeitamente os 5 resultados da TomTom + Mapa
       constraints: const BoxConstraints(maxHeight: 400),
       decoration: BoxDecoration(
         color: Colors.white,
         borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
         boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
       ),
       child: _isSearching
         ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
         : ListView.separated(
             padding: EdgeInsets.zero,
             shrinkWrap: true,
             itemCount: _searchResults.length + 1, // Opção 'Identificar no mapa'
             separatorBuilder: (_, __) => const Divider(height: 1),
             itemBuilder: (context, index) {
               if (index == _searchResults.length) {
                  return ListTile(
                     leading: Container(
                       width: 36, height: 36,
                       decoration: const BoxDecoration(color: Color(0xFFF1F3F4), shape: BoxShape.circle),
                       child: const Icon(Icons.map, color: Color(0xFF5F6368), size: 20),
                     ),
                     title: const Text('Identificar no mapa', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF202124))),
                     onTap: () {
                        // Remove teclado e limpa busca para usuario navegar
                        FocusScope.of(context).unfocus();
                        if (mounted) {
                          setState(() {
                             _searchResults = [];
                             _isSearching = false;
                          });
                        }
                     },
                  );
               }
               final item = _searchResults[index];
               
               // Verifica se é Ponto de Referência Comercial (POI)
               final isPoi = item['is_poi'] == true;

               return ListTile(
                 leading: Container(
                   width: 36,
                   height: 36,
                   decoration: const BoxDecoration(
                     color: Color(0xFFF1F3F4), // Fundo cinza claro tipo gmaps
                     shape: BoxShape.circle,
                   ),
                   child: const Icon(
                      Icons.location_on, 
                      color: Color(0xFF5F6368), // Cinza escuro do gmaps
                      size: 20,
                   ),
                 ),
                 title: Text(
                   item['main_text'] ?? item['display_name'] ?? 'Local Desconhecido',
                   maxLines: 1,
                   overflow: TextOverflow.ellipsis,
                   style: const TextStyle(
                     fontSize: 15,
                     fontWeight: FontWeight.w500,
                     color: Color(0xFF202124), // Cinza quase preto gmaps
                   ),
                 ),
                 subtitle: (item['secondary_text']?.toString().isNotEmpty ?? false)
                     ? Padding(
                         padding: const EdgeInsets.only(top: 2.0),
                         child: Text(
                           item['secondary_text'],
                           maxLines: 1,
                           overflow: TextOverflow.ellipsis,
                           style: const TextStyle(
                             fontSize: 13,
                             color: Color(0xFF70757A), // Cinza de rua gmaps
                           ),
                         ),
                       )
                     : null,
                 trailing: item['dist'] != null 
                     ? Column(
                         mainAxisAlignment: MainAxisAlignment.center,
                         crossAxisAlignment: CrossAxisAlignment.end,
                         mainAxisSize: MainAxisSize.min, // <-- ESSENCIAL para a Column não bugar altura do ListTile
                         children: [
                           Text(
                             '${((item['dist'] as num) / 1000).toStringAsFixed(1)} km',
                             style: const TextStyle(fontSize: 12, color: Color(0xFF70757A)),
                           ),
                           const SizedBox(height: 2),
                           Text(
                             '${(((item['dist'] as num) / 1000) * 2.5).round()} min',
                             style: const TextStyle(fontSize: 11, color: Color(0xFF9AA0A6)),
                           ),
                         ],
                       ) 
                     : null,
                 dense: true,
                 contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                 onTap: () => _selectSearchResult(item, _pickupFocus.hasFocus),
               );
             },
           ),
    );
  }

  Widget _buildTripPanel() {
    if (_fareEstimate == null && _fareEstimatesByVehicle.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('Selecione o destino',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
              // Padding extra para não ficar oculto atrás da Navbar Flutuante
              const SizedBox(height: 100),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min, // Faz o painel se ajustar ao conteúdo
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Vehicles List
            ListView.builder(
              shrinkWrap: true, // Importante para Column/SingleChildScrollView
              physics: const NeverScrollableScrollPhysics(), // Scroll controlado pelo pai
              padding: EdgeInsets.zero,
              itemCount: _vehicleTypes.length,
              itemBuilder: (context, index) {
                final type = _vehicleTypes[index];
                final typeId = type['id'] as int;
                final isSelected = _selectedVehicleTypeId == typeId;
                final estimate = _fareEstimatesByVehicle[typeId];

                return _buildVehicleOption(type, isSelected, estimate);
              },
            ),
            
            // Bottom Button
            Padding(
              // Foi adicionado padding bottom (100) para compensar a NavigationBar flutuante (65px height + 20px bottom)
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 100),
              child: _isRequestingTrip
                  ? SizedBox(
                      height: 56,
                      child: Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryBlue),
                      ),
                    )
                  : _SlideToConfirmButton(
                      onConfirm: _requestRide,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleOption(Map<String, dynamic> type, bool isSelected, Map<String, dynamic>? estimate) {
    // Calcular ETA Fake (ex: 3-8 minutos)
    final randomEta = 3 + Random().nextInt(6);
    final etaText = '${randomEta} min';

    // Lógica de Preço: Real ou Fake baseado no nome/tipo
    double displayPrice = 0.0;
    if (estimate != null && estimate['estimated'] > 0) {
      displayPrice = (estimate['estimated'] as num).toDouble();
    } else {
      // Fallback fake logic (ex: 5.0 + distance * factor)
      // Extrair distancia de _routeDistance ou usar fixo se nublado
      double dist = 2.0; 
      if (_routeDistance != null) {
        dist = double.tryParse(_routeDistance!.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 2.0;
      }
      
      if (type['name'] == 'moto') displayPrice = 5.0 + (dist * 1.5);
      else if (type['name'] == 'comfort') displayPrice = 12.0 + (dist * 2.5);
      else displayPrice = 7.0 + (dist * 2.0);
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedVehicleTypeId = type['id'];
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF3F3F3) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Vehicle Image (Simples 2D)
            Image.asset(
              type['asset'],
              width: 60,
              height: 45,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 16),
            // Name and ETA
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type['display_name'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    etaText,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // Price and Radio Indicator
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'R\$ ${displayPrice.toStringAsFixed(2).replaceFirst('.', ',')}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryBlue : Colors.grey[300]!,
                      width: 2,
                    ),
                    color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
                  ),
                  child: isSelected 
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideToConfirmButton extends StatefulWidget {
  final VoidCallback onConfirm;

  const _SlideToConfirmButton({required this.onConfirm});

  @override
  State<_SlideToConfirmButton> createState() => _SlideToConfirmButtonState();
}

class _SlideToConfirmButtonState extends State<_SlideToConfirmButton> {
  double _dragPosition = 0;
  final double _buttonHeight = 56;
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final handleSize = _buttonHeight - 8;
      final maxDrag = maxWidth - handleSize - 8;

      return Container(
        height: _buttonHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              'DESLIZE PARA IR AGORA',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 1.2,
              ),
            ),
            Positioned(
              left: _dragPosition + 4,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  if (_confirmed) return;
                  setState(() {
                    _dragPosition += details.delta.dx;
                    if (_dragPosition < 0) _dragPosition = 0;
                    if (_dragPosition > maxDrag) _dragPosition = maxDrag;
                  });
                },
                onHorizontalDragEnd: (details) {
                  if (_confirmed) return;
                  if (_dragPosition >= maxDrag * 0.9) {
                    setState(() {
                      _dragPosition = maxDrag;
                      _confirmed = true;
                    });
                    widget.onConfirm();
                    // Reset after short delay if needed, or state will change via parent
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted) setState(() {
                        _dragPosition = 0;
                        _confirmed = false;
                      });
                    });
                  } else {
                    setState(() {
                      _dragPosition = 0;
                    });
                  }
                },
                child: Container(
                  width: handleSize,
                  height: handleSize,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                    ],
                  ),
                  child: Icon(
                    LucideIcons.chevronRight,
                    color: AppTheme.primaryBlue,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
