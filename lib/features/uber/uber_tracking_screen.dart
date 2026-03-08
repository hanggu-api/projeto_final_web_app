import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Size;
import 'package:flutter/material.dart' as material show Size;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:latlong2/latlong.dart' as ll;
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/config/supabase_config.dart';
import 'widgets/uber_map_overlay.dart';
import '../shared/chat_screen.dart';

import '../../services/uber_service.dart';
import '../../services/map_service.dart';
import '../../services/theme_service.dart';
import '../../services/api_service.dart';
import '../../services/data_gateway.dart';
import '../../services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../utils/pix_generator.dart';
import 'dart:math' show atan2, sin, cos, pi;
import '../shared/chat/widgets/chat_quick_alert_modal.dart';

class UberTrackingScreen extends StatefulWidget {
  final String tripId;

  const UberTrackingScreen({super.key, required this.tripId});

  @override
  State<UberTrackingScreen> createState() => _UberTrackingScreenState();
}

class _UberTrackingScreenState extends State<UberTrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final UberService _uberService = UberService();
  mapbox.MapboxMap? _mapboxMap;
  late final MapController _mapController;
  late AnimationController _pulseController;

  StreamSubscription<List<Map<String, dynamic>>>? _driverLocationSub;
  StreamSubscription<Map<String, dynamic>>? _tripSub;

  mapbox.PolylineAnnotationManager? _polylineAnnotationManager;
  mapbox.PointAnnotationManager? _pointAnnotationManager;

  ll.LatLng? _driverLocation;
  ll.LatLng? _previousLocation;
  ll.LatLng? _pickupLocation;
  ll.LatLng? _dropoffLocation;
  List<ll.LatLng> _pickupToDropoffPoints = [];
  String _currentRouteMode = 'none'; // 'to_pickup', 'to_dropoff'
  double _bearing = 0.0;
  // Inicializa com '' para evitar piscar o card "Procurando motoristas"
  // antes dos dados reais chegarem do Supabase
  String _status = '';

  // Alertas de Proximidade
  double? _distanceToPickup;
  bool _alert500mShow = false;
  bool _alert100mShow = false;
  bool _alertArrivedShow = false;
  bool _hasTriggered500m = false;
  bool _hasTriggered100m = false;
  bool _hasTriggeredArrived = false;

  // Tempo de Espera
  Timer? _waitTimer;
  int _waitingSeconds = 0;

  Map<String, dynamic>? _driverProfile;
  bool _isLoadingDriver = false;
  bool _isLoading = false;
  String? _pixPayload;
  bool _tripLoadError = false;
  bool _isTracking = true; // Auto-zoom ativado por padrão

  bool _showPulse = false;
  Timer? _pulseFeedbackTimer;
  bool _isChatOpen = false;
  StreamSubscription<List<dynamic>>? _chatSub;
  int? _myUserId;
  int? _lastHandledIncomingMessageId;
  bool _isChatAlertVisible = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  int _chatMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _mapController = MapController();

    // Garante que a barra continue oculta durante o rastreio
    ThemeService().setNavBarVisible(false);

    _loadInitialMapCenter();
    _startListening();
    _initChatMonitoring();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }

  Future<void> _initChatMonitoring() async {
    _myUserId = ApiService().userId;
    if (_myUserId == null) {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        try {
          final me = await Supabase.instance.client
              .from('users')
              .select('id')
              .eq('supabase_uid', currentUser.id)
              .maybeSingle();
          _myUserId = me?['id'] as int?;
        } catch (_) {}
      }
    }

    _chatSub = DataGateway().watchChat(widget.tripId).listen((rows) {
      if (!mounted || rows.isEmpty) return;
      if (_chatMessageCount != rows.length) {
        setState(() => _chatMessageCount = rows.length);
      }
      final latest = rows.first;
      final latestId = latest['id'];
      final latestIdInt = latestId is int ? latestId : int.tryParse('$latestId');
      if (latestIdInt == null) return;
      if (_lastHandledIncomingMessageId == latestIdInt) return;

      final senderId = latest['sender_id'];
      if (_myUserId != null && senderId != null && '$senderId' == '$_myUserId') {
        _lastHandledIncomingMessageId = latestIdInt;
        return;
      }

      _lastHandledIncomingMessageId = latestIdInt;
      final preview = _buildIncomingMessagePreview(latest);
      if (preview.isEmpty) return;
      final wasChatClosed = !_isChatOpen;

      if (mounted && wasChatClosed) {
        setState(() => _isChatOpen = true);
      }

      if (_appLifecycleState == AppLifecycleState.resumed) {
        if (wasChatClosed) {
          _showIncomingChatAlert(latestIdInt, preview);
        }
      } else {
        NotificationService().showChatMessageNotification(
          serviceId: widget.tripId,
          messageId: latestIdInt,
          senderName:
              _driverProfile?['full_name']?.toString() ?? 'Nova mensagem',
          message: preview.length > 120 ? '${preview.substring(0, 120)}...' : preview,
        );
      }
    });
  }

  String _buildIncomingMessagePreview(dynamic row) {
    final map = row is Map ? Map<String, dynamic>.from(row) : <String, dynamic>{};
    final type = (map['type'] ?? 'text').toString();
    final content = (map['content'] ?? '').toString().trim();
    if (content.isEmpty) return '';

    if (type == 'image') return 'Imagem';
    if (type == 'video') return 'Video';
    if (type == 'audio') return 'Audio';
    if (type == 'schedule_proposal') return 'Nova proposta de agendamento';

    if (content.startsWith('{') && content.contains('"date"')) {
      try {
        final decoded = jsonDecode(content);
        if (decoded is Map && decoded.containsKey('date')) {
          return 'Nova proposta de agendamento';
        }
      } catch (_) {}
    }
    return content;
  }

  double _chatPanelHeight(BuildContext context) {
    final deviceHeight =
        MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top;
    final minHeight = deviceHeight * 0.44;
    final growth = (_chatMessageCount * 26.0).clamp(0.0, deviceHeight * 0.48);
    return (minHeight + growth).clamp(minHeight, deviceHeight - 12);
  }

  Widget _buildChatContextCompact() {
    final withName = _driverProfile?['full_name']?.toString() ?? 'Motorista';
    final pickup = _tripData?['pickup_address']?.toString() ?? '';
    final dropoff = _tripData?['dropoff_address']?.toString() ?? '';
    final summary = pickup.isNotEmpty && dropoff.isNotEmpty
        ? '$pickup -> $dropoff'
        : pickup;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conversa com $withName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          if (summary.isNotEmpty)
            Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black.withValues(alpha: 0.75),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showIncomingChatAlert(int messageId, String message) async {
    if (_isChatAlertVisible || !mounted) return;
    _isChatAlertVisible = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ChatQuickAlertModal(
        senderName: _driverProfile?['full_name']?.toString() ?? 'Nova mensagem',
        message: message,
        onMarkRead: () async {
          await DataGateway().markChatMessageRead(messageId);
        },
        onReply: (text) async {
          await DataGateway().sendChatMessage(widget.tripId, text, 'text');
          await DataGateway().markChatMessageRead(messageId);
          if (mounted) setState(() => _isChatOpen = true);
        },
        onOpenChat: () {
          if (mounted) setState(() => _isChatOpen = true);
        },
      ),
    );

    _isChatAlertVisible = false;
  }

  void _startWatchingDriverLocation(int driverId) {
    if (_driverLocationSub != null) return;

    _driverLocationSub = _uberService.watchDriverLocation(driverId).listen((
      snapshot,
    ) {
      if (snapshot.isNotEmpty && mounted) {
        final data = snapshot.first;
        final newLocation = ll.LatLng(
          data['latitude'] ?? 0.0,
          data['longitude'] ?? 0.0,
        );

        setState(() {
          if (_driverLocation != null && _driverLocation != newLocation) {
            _previousLocation = _driverLocation;
            _bearing = _calculateBearing(_previousLocation!, newLocation);
          }

          // Se for a primeira vez recebendo local e já estivermos no modo to_pickup, busca a rota
          if (_driverLocation == null &&
              _currentRouteMode == 'to_pickup' &&
              _tripData != null &&
              _tripData!['pickup_lat'] != null) {
            _fetchRoute(
              newLocation,
              ll.LatLng(_tripData!['pickup_lat'], _tripData!['pickup_lon']),
            );
          }

          _driverLocation = newLocation;
        });

        // Lógica de Proximidade
        _checkProximity();

        if (mounted && _driverLocation != null && _isTracking) {
          _animatedMapMove(_driverLocation!, 17.5, -_bearing);
        }
      }
    });
  }

  void _startListening() {
    _tripSub = _uberService.watchTrip(widget.tripId).listen((data) {
      if (data.isNotEmpty && mounted) {
        if (mounted) {
          final oldStatus = _status;
          _status = data['status'] ?? '';
          _tripData = data;

          if (_status == 'in_progress') {
            _alert500mShow = false;
            _alert100mShow = false;
            _alertArrivedShow = false;
            _hasTriggered500m = true;
            _hasTriggered100m = true;
            _hasTriggeredArrived = true;
          }

          // Lógica de Feedback Visual (Pulso)
          if (_status == 'searching' || _status == 'search_driver') {
            _showPulse = true;
            _pulseFeedbackTimer?.cancel();
          } else if (_status == 'accepted' && oldStatus != 'accepted') {
            // Motorista Aceitou: Mantém azul por 3 segundos
            _showPulse = true;
            _pulseFeedbackTimer?.cancel();
            _pulseFeedbackTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) setState(() => _showPulse = false);
            });
          } else if ((_status == 'cancelled' || _status == 'no_drivers') &&
              (oldStatus == 'searching' || oldStatus == 'search_driver')) {
            // Motorista Indisponível: Pulsa vermelho por 5 segundos
            _showPulse = true;
            _pulseFeedbackTimer?.cancel();
            _pulseFeedbackTimer = Timer(const Duration(seconds: 5), () {
              if (mounted) setState(() => _showPulse = false);
            });
          }

          // update locations if available
          if (data['pickup_lat'] != null && data['pickup_lon'] != null) {
            _pickupLocation = ll.LatLng(
              double.parse(data['pickup_lat'].toString()),
              double.parse(data['pickup_lon'].toString()),
            );
          }
          if (data['dropoff_lat'] != null && data['dropoff_lon'] != null) {
            _dropoffLocation = ll.LatLng(
              double.parse(data['dropoff_lat'].toString()),
              double.parse(data['dropoff_lon'].toString()),
            );
          }
        }

        // Configura o timer de espera se estiver chegado
        if (_status == 'arrived' && _waitTimer == null) {
          _startWaitTimer();
        } else if (_status != 'arrived') {
          _stopWaitTimer();
        }

        // Busca perfil do motorista assim que for atribuído
        if (data['driver_id'] != null) {
          if (_driverProfile == null) {
            _fetchDriverProfile(data['driver_id']);
          }
          _startWatchingDriverLocation(data['driver_id']);
        }

        // Determina qual rota exibir
        String newRouteMode = 'none';
        if (_status == 'accepted' ||
            _status == 'driver_en_route' ||
            _status == 'driver_found' ||
            _status == 'arrived') {
          newRouteMode = 'to_pickup';
        } else if (_status == 'in_progress' ||
            _status == 'requested' ||
            _status == 'searching' ||
            _status == 'pending' ||
            data['driver_id'] == null) {
          newRouteMode = 'to_dropoff';
        }

        if (newRouteMode != _currentRouteMode ||
            (_pickupToDropoffPoints.isEmpty && data['dropoff_lat'] != null)) {
          _currentRouteMode = newRouteMode;
          _updateRoutes(data);
        }
      }
    });
  }

  Future<void> _drawRouteOnMapbox(List<ll.LatLng> points, Color color) async {
    if (_mapboxMap == null) return;

    if (_polylineAnnotationManager == null) {
      _polylineAnnotationManager = await _mapboxMap!.annotations
          .createPolylineAnnotationManager();
    } else {
      await _polylineAnnotationManager!.deleteAll();
    }

    if (points.isEmpty) return;

    final positions = points
        .map((p) => mapbox.Position(p.longitude, p.latitude))
        .toList();

    final polylineOptions = mapbox.PolylineAnnotationOptions(
      geometry: mapbox.LineString(coordinates: positions),
      lineColor: color.value,
      lineWidth: 5.0,
      lineJoin: mapbox.LineJoin.ROUND,
    );

    await _polylineAnnotationManager!.create(polylineOptions);
  }

  void travarCameraNoCarro() {
    if (_mapboxMap == null || _driverLocation == null) return;

    _mapboxMap!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            _driverLocation!.longitude,
            _driverLocation!.latitude,
          ),
        ),
        zoom: 17.5,
        bearing: -_bearing,
        pitch: kIsWeb ? 0.0 : 45.0,
      ),
      mapbox.MapAnimationOptions(duration: 1000),
    );
  }

  Future<void> _drawMarkersOnMapbox() async {
    if (_mapboxMap == null) return;

    if (_pointAnnotationManager == null) {
      _pointAnnotationManager = await _mapboxMap!.annotations
          .createPointAnnotationManager();
    } else {
      await _pointAnnotationManager!.deleteAll();
    }

    final List<mapbox.PointAnnotationOptions> annotations = [];

    // Pickup Marker
    if (_pickupLocation != null) {
      annotations.add(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(
              _pickupLocation!.longitude,
              _pickupLocation!.latitude,
            ),
          ),
          // We can use a custom image here if we load it to the style, but for now we can
          // just use standard text or a loaded icon if available in your Mapbox style.
          // For now, let's use circle annotations or standard pins if available.
          // Mapbox Flutter usually requires loading the image first. We will handle imagery soon if needed
          iconImage: 'marker-15', // a default mapbox style marker
          iconSize: 2.0,
        ),
      );
    }

    // Dropoff Marker
    if (_dropoffLocation != null) {
      annotations.add(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(
              _dropoffLocation!.longitude,
              _dropoffLocation!.latitude,
            ),
          ),
          iconImage: 'marker-15', // a default mapbox style marker
          iconSize: 2.0,
        ),
      );
    }

    if (annotations.isNotEmpty) {
      await _pointAnnotationManager!.createMulti(annotations);
    }
  }

  Future<void> _updateRoutes(Map<String, dynamic> data) async {
    final pickupLat = data['pickup_lat'];
    final pickupLon = data['pickup_lon'];
    final dropoffLat = data['dropoff_lat'];
    final dropoffLon = data['dropoff_lon'];

    if (pickupLat == null || pickupLon == null) return;

    final pickup = ll.LatLng(pickupLat, pickupLon);

    // 1. Sempre busca a rota de destino (Azul) se disponível
    if (dropoffLat != null && dropoffLon != null) {
      final dropoff = ll.LatLng(dropoffLat, dropoffLon);
      final points = await MapService().getRoutePoints(pickup, dropoff);
      if (points.isNotEmpty) {
        if (points.first != pickup) points.insert(0, pickup);
        if (points.last != dropoff) points.add(dropoff);
      }
      if (mounted) {
        setState(() => _pickupToDropoffPoints = points);
        if (_mapboxMap != null) {
          _drawRouteOnMapbox(points, const Color(0xFF2196F3));
        }
        _fitRoute(); // Enquadra quando a rota principal carrega
      }
    }

    // 2. Busca rota do motorista até o embarque (Verde) se estiver nessa fase
    if (_currentRouteMode == 'to_pickup' && _driverLocation != null) {
      final points = await MapService().getRoutePoints(
        _driverLocation!,
        pickup,
      );
      if (points.isNotEmpty) {
        if (points.first != _driverLocation) points.insert(0, _driverLocation!);
        if (points.last != pickup) points.add(pickup);
      }
      if (mounted) {
        if (_mapboxMap != null) _drawRouteOnMapbox(points, Colors.green);
        _fitRoute(); // Enquadra quando a rota do motorista carrega
      }
    }
  }

  Future<void> _fetchRoute(ll.LatLng start, ll.LatLng end) async {
    final points = await MapService().getRoutePoints(start, end);
    if (mounted) {
      setState(() {
        if (_currentRouteMode != 'to_pickup') {
          _pickupToDropoffPoints = points;
        }
      });
      if (_mapboxMap != null) {
        _drawRouteOnMapbox(
          points,
          _currentRouteMode == 'to_pickup'
              ? Colors.green
              : const Color(0xFF2196F3),
        );
        _drawMarkersOnMapbox();
      }
      // Enquadra a rota assim que os pontos chegam
      _fitRoute();
    }
  }

  void _animatedMapMove(
    ll.LatLng destLocation,
    double destZoom,
    double destRotation,
  ) async {
    if (!mounted) return;

    if (kIsWeb) {
      _mapController.move(destLocation, destZoom);
      return;
    }

    if (_mapboxMap == null) return;

    // We can use Mapbox's built-in flyTo instead of our custom animation controller
    _mapboxMap!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            destLocation.longitude,
            destLocation.latitude,
          ),
        ),
        zoom: destZoom,
        bearing: destRotation,
        pitch: 45.0, // standard 3D tracking pitch
      ),
      mapbox.MapAnimationOptions(duration: 500),
    );
  }

  void _fitRoute() async {
    if (!mounted || _mapboxMap == null) return;

    final List<ll.LatLng> points = [];
    if (_driverLocation != null) points.add(_driverLocation!);
    if (_pickupLocation != null) points.add(_pickupLocation!);
    if (_dropoffLocation != null) points.add(_dropoffLocation!);

    if (points.length < 2) return;

    try {
      double minLat = points.first.latitude;
      double maxLat = points.first.latitude;
      double minLng = points.first.longitude;
      double maxLng = points.first.longitude;

      for (var p in points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }

      final camera = await _mapboxMap!.cameraForCoordinates(
        [
          mapbox.Point(coordinates: mapbox.Position(minLng, minLat)),
          mapbox.Point(coordinates: mapbox.Position(maxLng, maxLat)),
        ],
        mapbox.MbxEdgeInsets(
          top: 150.0,
          left: 50.0,
          bottom: 350.0,
          right: 50.0,
        ),
        null,
        null,
      );

      _mapboxMap!.setCamera(camera);
      setState(() => _isTracking = false);
    } catch (e) {
      debugPrint('Erro ao enquadrar rota Mapbox: $e');
    }
  }

  Future<void> _loadInitialMapCenter() async {
    if (mounted) setState(() => _tripLoadError = false);
    try {
      final trip = await Supabase.instance.client
          .from('trips')
          .select('*')
          .eq('id', widget.tripId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        if (trip != null) {
          setState(() {
            _tripData = trip; // Populate initial data
            _pickupLocation = ll.LatLng(
              double.parse(trip['pickup_lat'].toString()),
              double.parse(trip['pickup_lon'].toString()),
            );
            if (trip['dropoff_lat'] != null && trip['dropoff_lon'] != null) {
              _dropoffLocation = ll.LatLng(
                double.parse(trip['dropoff_lat'].toString()),
                double.parse(trip['dropoff_lon'].toString()),
              );
            }
            _status = trip['status'] ?? ''; // Sync status too
            _tripLoadError = false;
          });
          // Inicialmente, se não temos motorista, enquadra pickup e dropoff
          if (trip['driver_id'] == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
          }
          if (trip['driver_id'] != null && _driverProfile == null) {
            final dId = int.parse(trip['driver_id'].toString());
            debugPrint(
              '🎯 [UberTracking] Encontrado driver_id: $dId na carga inicial. Buscando perfil...',
            );
            _fetchDriverProfile(dId);
          } else if (trip['driver_id'] == null) {
            debugPrint(
              '⚠️ [UberTracking] O driver_id veio NULO na carga inicial.',
            );
          }
        } else {
          setState(() => _tripLoadError = true);
        }
      }
    } catch (e) {
      debugPrint('Error loading trip: $e');
      if (mounted) setState(() => _tripLoadError = true);
    }
  }

  void _startWaitTimer() {
    _stopWaitTimer();
    bool firstTick = true;
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _tripData == null || _tripData!['arrived_at'] == null) {
        return;
      }
      final arrivedAtDateTime = DateTime.tryParse(_tripData!['arrived_at']);
      if (arrivedAtDateTime != null) {
        final elapsed = DateTime.now()
            .toUtc()
            .difference(arrivedAtDateTime.toUtc())
            .inSeconds;

        debugPrint(
          '⏱️ [TIMER] TripId: ${widget.tripId} | arrived_at: ${_tripData!['arrived_at']} | elapsed: ${elapsed}s',
        );

        // Se o arrived_at estiver > 5 minutos no passado na primeira execução,
        // é dado antigo de sessão anterior → reseta contagem local
        if (firstTick && elapsed > 300) {
          debugPrint(
            '⚠️ [TIMER] arrived_at obsoleto detectado (${elapsed}s). Resetando timer local para 0.',
          );
          firstTick = false;
          setState(() => _waitingSeconds = 0);
          return;
        }
        firstTick = false;

        setState(() {
          _waitingSeconds = elapsed;
        });
      }
    });
  }

  void _stopWaitTimer() {
    _waitTimer?.cancel();
    _waitTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _driverLocationSub?.cancel();
    _tripSub?.cancel();
    _chatSub?.cancel();
    // Restaura a barra de navegação ao sair do rastreio (viagem concluída ou cancelada)
    ThemeService().setNavBarVisible(true);
    super.dispose();
  }

  double _calculateBearing(ll.LatLng start, ll.LatLng end) {
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

  Map<String, dynamic>? _tripData;
  bool _hasRated = false;

  void _checkProximity() {
    if (_driverLocation == null || _tripData == null) return;
    if (_status != 'accepted' &&
        _status != 'driver_found' &&
        _status != 'driver_en_route') {
      return;
    }

    final pickupLat = _tripData!['pickup_lat'];
    final pickupLon = _tripData!['pickup_lon'];
    if (pickupLat == null || pickupLon == null) return;

    final pickupLocation = ll.LatLng(pickupLat, pickupLon);
    final distance = ll.Distance().as(
      ll.LengthUnit.Meter,
      _driverLocation!,
      pickupLocation,
    );

    setState(() {
      _distanceToPickup = distance.toDouble();
    });

    // Gatilhos de Alerta
    if (distance <= 500 && !_hasTriggered500m) {
      _hasTriggered500m = true;
      _showAlert('500m');
    } else if (distance <= 100 && !_hasTriggered100m) {
      _hasTriggered100m = true;
      _showAlert('100m');
    }

    // Alerta de Chegada (quando status muda ou distância < 30m)
    if ((distance <= 30 || _status == 'arrived') && !_hasTriggeredArrived) {
      _hasTriggeredArrived = true;
      _showAlert('arrived');
    }
  }

  void _showAlert(String type) {
    setState(() {
      _alert500mShow = type == '500m';
      _alert100mShow = type == '100m';
      _alertArrivedShow = type == 'arrived';
    });

    // Oculta após 5 segundos, exceto 'arrived' que pode ser mais persistente
    if (type != 'arrived') {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            if (type == '500m') _alert500mShow = false;
            if (type == '100m') _alert100mShow = false;
          });
        }
      });
    }
  }

  Future<void> _fetchDriverProfile(dynamic driverIdRaw) async {
    final int? driverId = int.tryParse(driverIdRaw.toString());
    if (driverId == null) return;

    if (_isLoadingDriver ||
        (_driverProfile != null && _driverProfile!['id'] == driverId)) {
      return;
    }

    setState(() => _isLoadingDriver = true);
    try {
      debugPrint(
        '🚕 [UberTracking] Iniciando _fetchDriverProfile para driverIdRaw: $driverIdRaw. Resolvido para integer: $driverId',
      );
      final res = await Supabase.instance.client
          .from('users')
          .select('id, full_name, avatar_url, phone')
          .eq('id', driverId)
          .maybeSingle();

      debugPrint(
        '🚕 [UberTracking] Resposta Supabase para usuario (driverId: $driverId): $res',
      );

      if (mounted && res != null) {
        final Map<String, dynamic> mergedProfile = Map<String, dynamic>.from(
          res,
        );
        final fullName = mergedProfile['full_name']?.toString() ?? 'Motorista';
        mergedProfile['first_name'] = fullName.split(' ').first;
        mergedProfile['rating'] =
            5.0; // TODO: Fetch from actual ratings table if exists

        // Fetch driver's active vehicle
        try {
          debugPrint(
            '🚕 [UberTracking] Buscando veiculo para driverId: $driverId',
          );
          final vehicleRes = await Supabase.instance.client
              .from('vehicles')
              .select('model, color, plate')
              .eq('driver_id', driverId)
              .maybeSingle();

          debugPrint(
            '🚕 [UberTracking] Resposta Supabase para veiculo: $vehicleRes',
          );

          if (vehicleRes != null) {
            final color = vehicleRes['color'] != null
                ? ' - ${vehicleRes['color']}'
                : '';
            mergedProfile['vehicle_model'] =
                '${vehicleRes['model'] ?? 'Veículo'}$color';
            mergedProfile['vehicle_plate'] = vehicleRes['plate'] ?? '---';
          } else {
            mergedProfile['vehicle_model'] = 'Veículo';
            mergedProfile['vehicle_plate'] = '---';
          }
        } catch (ve) {
          debugPrint('Falha ao buscar veículo: $ve');
          mergedProfile['vehicle_model'] = 'Veículo';
          mergedProfile['vehicle_plate'] = '---';
        }

        setState(() => _driverProfile = mergedProfile);
      } else if (mounted) {
        setState(
          () => _driverProfile = {
            'id': driverId,
            'first_name': 'Motorista',
            'full_name': 'Motorista Desconhecido',
            'rating': 5.0,
            'vehicle_model': 'Veículo',
            'vehicle_plate': '---',
            'avatar_url': null,
          },
        );
      }
    } catch (e) {
      debugPrint('Erro ao buscar perfil do motorista: $e');
      if (mounted) {
        setState(
          () => _driverProfile = {
            'id': driverId,
            'first_name': 'Motorista',
            'rating': 5.0,
            'vehicle_model': 'Veículo',
            'vehicle_plate': '---',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingDriver = false);
    }
  }

  Future<void> _processCancellation([String? reason]) async {
    try {
      // 1. Atualizar o status para cancelado com o motivo
      await _uberService.updateTripStatus(
        widget.tripId,
        'cancelled',
        cancellationReason: reason,
      );

      // 2. Voltar para a Home. Ao ir pra Home, o bloqueio do `getActiveTripForClient`
      // não existirá mais porque a viagem atual foi cancelada.
      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao cancelar a viagem. Tente novamente.'),
          ),
        );
      }
    }
  }

  void _openChat() {
    debugPrint(
      '[UberTrackingScreen] _openChat called. Current _isChatOpen: $_isChatOpen',
    );
    setState(() {
      _isChatOpen = !_isChatOpen;
      debugPrint(
        '[UberTrackingScreen] Chat toggled. New _isChatOpen: $_isChatOpen',
      );
    });
  }

  void _cancelTrip() {
    // Sempre mostra o modal de cancelamento independente do status
    _showCancelDialog();
  }

  void _showCancelDialog() {
    String selectedReason = 'Motorista demorando muito';
    final TextEditingController otherReasonController = TextEditingController();
    bool isOther = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cancelar Viagem',
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Por favor, informe o motivo do cancelamento:',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ...[
                        'Motorista demorando muito',
                        'Pedi por engano',
                        'Encontrei outra opção',
                        'Outro',
                      ].map((reason) {
                        return RadioListTile<String>(
                          title: Text(
                            reason,
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textDark,
                            ),
                          ),
                          value: reason,
                          groupValue: selectedReason,
                          activeColor: AppTheme.primaryYellow,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (value) {
                            if (value != null) {
                              setModalState(() {
                                selectedReason = value;
                                isOther = selectedReason == 'Outro';
                              });
                            }
                          },
                        );
                      }),
                      if (isOther) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: otherReasonController,
                          decoration: InputDecoration(
                            hintText: 'Digite o motivo...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppTheme.primaryYellow,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'VOLTAR',
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textDark,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final reason = isOther
                                    ? otherReasonController.text
                                    : selectedReason;
                                Navigator.pop(context);
                                _processCancellation(
                                  reason.isEmpty
                                      ? 'Sem motivo informado'
                                      : reason,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'CANCELAR',
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // MAPA VIVO
          if (_driverLocation == null && _pickupLocation == null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_tripLoadError) ...[
                    const Icon(
                      LucideIcons.alertTriangle,
                      size: 48,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Erro ao carregar os dados da viagem',
                      style: GoogleFonts.manrope(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => context.go('/home'),
                          icon: const Icon(LucideIcons.arrowLeft, size: 18),
                          label: const Text('Voltar'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _loadInitialMapCenter,
                          icon: const Icon(LucideIcons.refreshCw, size: 18),
                          label: const Text('Tentar Novamente'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryYellow,
                            foregroundColor: AppTheme.textDark,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Buscando localização...',
                      style: GoogleFonts.manrope(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else if (kIsWeb)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    _driverLocation ?? _pickupLocation ?? const ll.LatLng(0, 0),
                initialZoom: 15.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=${SupabaseConfig.mapboxToken}',
                  tileSize: 512,
                  zoomOffset: -1,
                ),
                UberMapOverlay(
                  routePoints: _pickupToDropoffPoints,
                  pickupLocation: _pickupLocation,
                  dropoffLocation: _dropoffLocation,
                  driverLocation: _driverLocation,
                  driverHeading: _bearing,
                  mode: MapOverlayMode.tracking,
                  showPulse: _showPulse,
                  pulseColor: AppTheme.primaryYellow,
                  pulseController: _pulseController,
                ),
              ],
            )
          else
            mapbox.MapWidget(
              cameraOptions: mapbox.CameraOptions(
                center: mapbox.Point(
                  coordinates: mapbox.Position(
                    ((_driverLocation ?? _pickupLocation!).longitude).isFinite
                        ? (_driverLocation ?? _pickupLocation!).longitude
                        : 0.0,
                    ((_driverLocation ?? _pickupLocation!).latitude).isFinite
                        ? (_driverLocation ?? _pickupLocation!).latitude
                        : 0.0,
                  ),
                ),
                zoom: 15.0,
                pitch: kIsWeb ? 0.0 : 45.0,
              ),
              styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
              onMapCreated: (mapboxMap) {
                _mapboxMap = mapboxMap;
                mapboxMap.location.updateSettings(
                  mapbox.LocationComponentSettings(
                    enabled: true,
                    pulsingEnabled: true,
                    puckBearingEnabled: true,
                  ),
                );
                // Inicia o seguimento se já estivermos rastreando
                if (_isTracking && _driverLocation != null) {
                  travarCameraNoCarro();
                }
                // Draw markers if already available
                _drawMarkersOnMapbox();
              },
              onScrollListener: (context) {
                if (_isTracking) {
                  setState(() => _isTracking = false);
                }
              },
            ),

          // MAP CONTROLS (Floating)
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 100,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: null,
                  onPressed: () async {
                    if (_mapboxMap == null) return;
                    final cameraState = await _mapboxMap!.getCameraState();
                    _mapboxMap!.setCamera(
                      mapbox.CameraOptions(zoom: cameraState.zoom + 1),
                    );
                  },
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  child: const Icon(LucideIcons.plus),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: null,
                  onPressed: () async {
                    if (_mapboxMap == null) return;
                    final cameraState = await _mapboxMap!.getCameraState();
                    _mapboxMap!.setCamera(
                      mapbox.CameraOptions(zoom: cameraState.zoom - 1),
                    );
                  },
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  child: const Icon(LucideIcons.minus),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: null,
                  onPressed: _fitRoute,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                  child: const Icon(LucideIcons.maximize),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: null,
                  onPressed: () {
                    if (_driverLocation != null &&
                        _mapboxMap != null &&
                        _driverLocation!.latitude.isFinite &&
                        _driverLocation!.longitude.isFinite) {
                      _mapboxMap!.setCamera(
                        mapbox.CameraOptions(
                          center: mapbox.Point(
                            coordinates: mapbox.Position(
                              _driverLocation!.longitude,
                              _driverLocation!.latitude,
                            ),
                          ),
                          zoom: 17.5,
                        ),
                      );
                      setState(() => _isTracking = true);
                    }
                  },
                  backgroundColor: _isTracking ? Colors.blue : Colors.white,
                  foregroundColor: _isTracking ? Colors.white : Colors.blue,
                  child: const Icon(LucideIcons.navigation),
                ),
              ],
            ),
          ),

          // Top Header Overlay
          _buildTopHeader(),

          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              height: _isChatOpen
                  ? _chatPanelHeight(context)
                  : null,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: kIsWeb
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, -5),
                        ),
                      ],
              ),
              child: Column(
                mainAxisSize: _isChatOpen ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 12),
                      width: 48,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (_isChatOpen)
                    Expanded(
                      child: Column(
                        children: [
                          _buildChatContextCompact(),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChatScreen(
                                serviceId: widget.tripId,
                                otherName:
                                    _driverProfile?['full_name'] ?? 'Motorista',
                                otherAvatar: _driverProfile?['avatar_url'],
                                isInline: true,
                                onClose: () {
                                  debugPrint(
                                    '[UberTrackingScreen] Chat onClose called',
                                  );
                                  setState(() => _isChatOpen = false);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _tripData == null
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 48),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _status == 'completed'
                          ? _buildPaymentSummary()
                          : (_status == 'searching' ||
                                _status == 'pending' ||
                                _tripData!['driver_id'] == null)
                          ? _buildSearchingState()
                          : _buildTripProgressContent(),
                        ),
                ],
              ),
            ),
          ),

          // Alertas de Proximidade (Top Banner)
          _buildProximityAlerts(),
        ],
      ),
    );
  }

  Widget _buildProximityAlerts() {
    bool show = _alert500mShow || _alert100mShow || _alertArrivedShow;
    if (!show) return const SizedBox.shrink();

    String message = '';
    Color color = AppTheme.primaryYellow;
    IconData icon = LucideIcons.navigation;

    if (_alert500mShow) {
      message = 'O motorista está a caminho! (500m)';
      color = Colors.blue;
      icon = LucideIcons.navigation;
    } else if (_alert100mShow) {
      message = 'Prepare-se! O motorista está chegando.';
      color = AppTheme.primaryYellow;
      icon = LucideIcons.bell;
    } else if (_alertArrivedShow) {
      message = 'O motorista está no local de embarque!';
      color = Colors.green;
      icon = LucideIcons.checkCircle;
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 80,
      left: 20,
      right: 20,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, (1 - value) * -50),
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: kIsWeb
                ? []
                : [
                    BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.textDark, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.manrope(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _alert500mShow = false;
                  _alert100mShow = false;
                  _alertArrivedShow = false;
                }),
                child: const Icon(
                  LucideIcons.x,
                  color: AppTheme.textDark,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentSummary() {
    final fare =
        double.tryParse(_tripData?['fare_estimated']?.toString() ?? '0') ?? 0.0;

    if (_pixPayload == null && !_isLoading) {
      _generatePixPayloadForSummary(fare);
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.check, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            'VIAGEM CONCLUÍDA',
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Text(
                  'VALOR TOTAL A PAGAR',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'R\$ ${fare.toStringAsFixed(2)}',
                  style: GoogleFonts.manrope(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_pixPayload != null) ...[
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                children: [
                  Text(
                    'PIX COPIA E COLA',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _pixPayload!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _pixPayload!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Código PIX copiado!')),
                      );
                    },
                    icon: const Icon(LucideIcons.copy, size: 16),
                    label: const Text('COPIAR CÓDIGO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                if (!_hasRated) {
                  _showRatingModal();
                } else {
                  context.go('/home');
                }
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                foregroundColor: AppTheme.textDark,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('RETORNAR PARA HOME'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showRatingModal() {
    int rating = 5;
    final TextEditingController commentController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible:
          true, // Usuário pode clicar fora para fechar (não bloqueante)
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Column(
              children: [
                Text(
                  'Como foi sua viagem?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sua avaliação ajuda a melhorar o serviço',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: index < rating
                            ? Colors.amber
                            : Colors.grey.shade300,
                        size: 40,
                      ),
                      onPressed: () => setModalState(() => rating = index + 1),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Deixe um comentário (opcional)',
                    hintStyle: GoogleFonts.manrope(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Fecha modal
                  context.go('/home'); // Vai para home (não bloqueante)
                },
                child: Text(
                  'AGORA NÃO',
                  style: GoogleFonts.manrope(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final currentUser =
                        Supabase.instance.client.auth.currentUser;
                    if (currentUser == null) return;

                    // Buscar o id ( BIGINT) do usuário na tabela public.users
                    final userRes = await Supabase.instance.client
                        .from('users')
                        .select('id')
                        .eq('supabase_uid', currentUser.id)
                        .single();

                    final reviewerId = userRes['id'] as int;
                    final revieweeId = _tripData?['driver_id'] as int;

                    await _uberService.submitTripReview(
                      tripId: widget.tripId,
                      reviewerId: reviewerId,
                      revieweeId: revieweeId,
                      rating: rating,
                      comment: commentController.text,
                    );

                    if (context.mounted) {
                      setState(() => _hasRated = true);
                      Navigator.pop(context);
                      context.go('/home');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Erro ao enviar avaliação'),
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryYellow,
                  foregroundColor: AppTheme.textDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'ENVIAR',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _generatePixPayloadForSummary(double amount) async {
    final driverId = _tripData?['driver_id'];
    if (driverId == null) return;

    // Use a flag local para evitar múltiplas chamadas simultâneas
    if (_isLoading) return;

    Future.microtask(() async {
      try {
        if (mounted) setState(() => _isLoading = true);
        final driverPixKey = await _uberService.getDriverPixKey(driverId);
        final driverProfile = await _uberService.getUserProfile(driverId);
        final driverName =
            driverProfile?['full_name'] as String? ?? 'Motorista';

        if (driverPixKey != null && driverPixKey.isNotEmpty) {
          final payload = PixGenerator.generatePayload(
            pixKey: driverPixKey,
            merchantName: driverName,
            merchantCity: 'Imperatriz',
            amount: amount,
            txid: widget.tripId.replaceAll('-', '').substring(0, 25),
          );
          if (mounted) {
            setState(() {
              _pixPayload = payload;
              _isLoading = false;
            });
          }
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  Widget _buildTopHeader() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Botão Voltar
          GestureDetector(
            onTap: () => context.go('/home'),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: kIsWeb
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: const Icon(
                LucideIcons.arrowLeft,
                color: Colors.black87,
                size: 20,
              ),
            ),
          ),

          // 101 Service Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              boxShadow: kIsWeb
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.shieldCheck,
                  color: Colors.black87,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  '101 Service',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          // Botão SOS
          GestureDetector(
            onTap: () {
              // Ação SOS
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: kIsWeb
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Center(
                child: Text(
                  'SOS',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripProgressContent() {
    String title = 'Procurando motoristas...';
    String address = _tripData?['pickup_address'] ?? 'Aguarde um momento';
    IconData statusIcon = LucideIcons.search;

    final isArrived = _status == 'arrived';
    Color headerBgColor = Colors.transparent;
    Color headerTextColor = AppTheme.textDark;
    Color iconBgColor = Colors.blue.withOpacity(0.1);
    Color iconColor = Colors.blueAccent;
    String timerText = '';

    if (_status == 'searching' || _status == 'search_driver') {
      title = _showPulse
          ? 'Notificando motoristas...'
          : 'Aguardando resposta...';
      address = 'Buscando o melhor motorista para você';
      statusIcon = LucideIcons.search;
      iconColor = Colors.blueAccent;
      iconBgColor = Colors.blue.withOpacity(0.1);
    } else if (_status == 'cancelled' || _status == 'no_drivers') {
      title = 'Motorista Indisponível';
      address = 'Tente novamente em alguns instantes';
      statusIcon = LucideIcons.alertCircle;
      iconColor = Colors.redAccent;
      iconBgColor = Colors.red.withOpacity(0.1);
    } else if (_status == 'driver_en_route' ||
        _status == 'accepted' ||
        _status == 'driver_found') {
      final minAway = _distanceToPickup != null && _distanceToPickup! > 0
          ? (_distanceToPickup! / 250).toStringAsFixed(0)
          : '3';
      title = 'Chegada em $minAway min';
      address = _tripData?['pickup_address'] ?? 'Carregando destino';
      statusIcon = LucideIcons.navigation;
    } else if (_status == 'in_progress') {
      title = 'A caminho do destino';
      address = _tripData?['dropoff_address'] ?? 'Destino da viagem';
      statusIcon = LucideIcons.mapPin;
    } else if (isArrived) {
      statusIcon = LucideIcons.clock;

      // Contagem crescente desde arrived_at
      final elapsed = _waitingSeconds.clamp(0, 999999);
      final mins = (elapsed / 60).floor();
      final secs = (elapsed % 60);
      timerText =
          '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

      if (elapsed < 60) {
        // Verde — menos de 1 minuto
        headerBgColor = Colors.green.shade50;
        headerTextColor = Colors.green.shade800;
        iconBgColor = Colors.green.shade100;
        iconColor = Colors.green.shade700;
        title = 'Motorista aguardando';
      } else if (elapsed < 105) {
        // Amarelo — entre 1 e ~1:45
        headerBgColor = Colors.orange.shade50;
        headerTextColor = Colors.orange.shade800;
        iconBgColor = Colors.orange.shade100;
        iconColor = Colors.orange.shade700;
        title = 'Apresse-se, por favor';
      } else {
        // Vermelho — mais de 1:45
        headerBgColor = Colors.red.shade50;
        headerTextColor = Colors.red.shade800;
        iconBgColor = Colors.red.shade100;
        iconColor = Colors.red.shade700;
        title = elapsed >= 120 ? 'Tempo esgotado!' : 'Tempo quase esgotado';
      }
      address = 'Encontre o motorista no local de embarque';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header (Chegada em X min + Icon) ou Header do Temporizador
        if (isArrived)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: headerBgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: iconBgColor, width: 2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: headerTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Taxa de espera em breve',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: headerTextColor.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: kIsWeb
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: iconColor, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        timerText,
                        style: GoogleFonts.manrope(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: headerTextColor,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.mapPin,
                          size: 16,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            address,
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(statusIcon, color: iconColor, size: 28),
              ),
            ],
          ),
        if (_isLoadingDriver || _driverProfile == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Column(
            children: [
              // Driver Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar with yellow border & rating
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.primaryYellow,
                            width: 3,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: _driverProfile!['avatar_url'] != null
                              ? Image.network(
                                  _driverProfile!['avatar_url'],
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    LucideIcons.user,
                                    size: 28,
                                    color: AppTheme.textDark,
                                  ),
                                )
                              : const Icon(
                                  LucideIcons.user,
                                  size: 28,
                                  color: AppTheme.textDark,
                                ),
                        ),
                      ),
                      Positioned(
                        bottom: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: kIsWeb
                                ? []
                                : [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                    ),
                                  ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'star ',
                                style: GoogleFonts.manrope(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '${(_driverProfile!['rating'] ?? 5.0).toStringAsFixed(1)}',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1B1B1B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),

                  // Text Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _driverProfile!['first_name'] ??
                              _driverProfile!['full_name'] ??
                              'Motorista',
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1B1B1B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_driverProfile!['vehicle_model'] ?? 'Carro'}',
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: const Color.fromARGB(255, 0, 0, 0),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // ETA Pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryYellow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.schedule,
                                size: 12,
                                color: Colors.black87,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${_driverProfile!['vehicle_plate'] ?? 'ABC-1234'}',
                                style: GoogleFonts.manrope(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: const Color.fromARGB(221, 0, 0, 0),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Phone Button
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryYellow.withOpacity(
                        0.2,
                      ), // Light yellow bg from mockup
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.call,
                        color: Color(0xFF1B1B1B),
                        size: 20,
                      ),
                      onPressed: () {
                        // Ação de ligar
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Action Buttons Row & Quick Replies
              if (isArrived)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Respostas rápidas:',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildQuickReplyButton('Estou indo'),
                          const SizedBox(width: 8),
                          _buildQuickReplyButton('Espere mais 1 minuto'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _openChat,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryYellow,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.chat_bubble, size: 18),
                      label: Text(
                        'Chat',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cancelTrip,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1B1B1B),
                        backgroundColor: Colors.transparent,
                        side: BorderSide(color: Colors.grey.shade200, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(
                        'Cancel',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildQuickReplyButton(String text) {
    return ActionChip(
      label: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.textDark,
        ),
      ),
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(color: Colors.grey.shade300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () async {
        try {
          await DataGateway().sendChatMessage(widget.tripId, text, 'text');
          if (mounted) {
            setState(() => _isChatOpen = true);
          }
        } catch (_) {}
      },
    );
  }

  // `_buildDriverMarker` deprecated and replaced by Mapbox location puck

  // `_buildDriverMarker` deprecated and replaced by Mapbox location puck

  Widget _buildSearchingState() {
    final pickupAddress = _tripData?['pickup_address'] ?? 'Seu local';
    final dropoffAddress = _tripData?['dropoff_address'] ?? 'Destino';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Procurando seu motorista...',
                    style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                    ),
                  ),
                  Text(
                    'Localizando veículos próximos na sua área',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '101 X',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.blueAccent,
                  ),
                ),
                Text(
                  'CATEGORIA',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Progress Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryYellow),
          ),
        ),
        const SizedBox(height: 24),

        // "Buscando motoristas próximos..." info
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.car, color: Color(0xFF00C896), size: 16),
            const SizedBox(width: 8),
            Text(
              'BUSCANDO MOTORISTAS PRÓXIMOS...',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF00C896),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Locations
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.mapPin,
                color: Colors.blueAccent,
                size: 16,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PARTIDA',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  Text(
                    pickupAddress,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.flag, color: Colors.grey, size: 16),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DESTINO',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  Text(
                    dropoffAddress,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),

        // Cancel Button
        ElevatedButton(
          onPressed: _cancelTrip,
          style: ElevatedButton.styleFrom(
            minimumSize: const material.Size.fromHeight(56),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: const Text('CANCELAR VIAGEM'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
