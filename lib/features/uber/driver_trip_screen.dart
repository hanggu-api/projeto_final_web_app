import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart' hide Size;
import 'package:flutter/material.dart' as material show Size;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../shared/chat_screen.dart';

import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/uber_service.dart';
import '../../services/app_config_service.dart';
import '../../services/api_service.dart';
import '../../services/data_gateway.dart';
import '../../services/notification_service.dart';
import '../../services/map_service.dart';
import '../../services/provider_location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/navigation_apps_helper.dart';
import 'widgets/snap_pin_marker.dart';
import 'widgets/car_marker_widget.dart';
import 'utils/navigation_math.dart';
import 'utils/navigation_tuning.dart';
import '../../utils/pix_generator.dart';
import 'package:qr_flutter/qr_flutter.dart';

class DriverTripScreen extends StatefulWidget {
  final String tripId;
  const DriverTripScreen({super.key, required this.tripId});

  @override
  State<DriverTripScreen> createState() => _DriverTripScreenState();
}

class _DriverTripScreenState extends State<DriverTripScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final UberService _uberService = UberService();
  final ApiService _apiService = ApiService();
  MapboxMap? _mapboxMap;
  PolylineAnnotationManager? _polylineAnnotationManager;
  PointAnnotationManager? _pointAnnotationManager;
  Timer? _locationTimer;
  ll.LatLng? _currentLocation;
  bool _isLoading = false;
  bool _isChatOpen = false;
  int _chatMessageCount = 0;
  bool _isDisposed = false;
  Map<String, dynamic>? _tripData;

  List<ll.LatLng> _routePoints = [];
  List<ll.LatLng> _destinationRoutePoints = [];
  String? _passengerName;
  bool _hasFetchedPickupRoute = false;
  bool _hasFetchedDestinationRoute = false;
  StreamSubscription<geo.Position>? _positionStream;
  bool _isMapReady = false;
  bool _missingTripHandled = false;

  // Variáveis de Rendering Mapbox
  bool _isMoto = false;
  Offset? _carPixelPosition;
  Offset? _pickupPixelPosition;
  Offset? _dropoffPixelPosition;
  double _currentHeading = 0.0;

  // Variáveis de Simulação
  bool _isSimulating = false;
  bool _isHeadingUp = true;
  final bool _autoNavigationProfile = true;
  NavigationProfile _navigationProfile = NavigationProfile.urban;
  NavigationTuning _tuning = NavigationTuning.urban;
  StreamSubscription<int>? _simulationSubscription;

  // Variáveis do Cronômetro de Espera
  Timer? _waitTimer;
  int _waitingSeconds = 0;
  bool _hasRated = false;
  bool _isLoadingPix = false;
  String? _pixPayload;
  String? _driverPixKey;

  // Estatísticas de Viagem
  String _travelTimeStr = '--:--';
  String _waitTimeStr = '--:--';
  StreamSubscription<List<dynamic>>? _chatSub;
  int? _myUserId;
  int? _lastHandledIncomingMessageId;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  final GlobalKey _panelContentKey = GlobalKey();
  double _panelMeasuredHeight = 0;

  // Helper para parsing seguro
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _myUserId = _apiService.userId;
    _initDriver();
    _checkLocationPermission();
    _initChatMonitoring();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;

    // Se o app voltar a ficar visível após ficar em segundo plano, garantimos que
    // o stream de chat esteja ativo (Supabase pode ter fechado a conexão).
    if (state == AppLifecycleState.resumed && mounted) {
      _restartChatMonitoring();
    }
  }

  void _restartChatMonitoring() {
    // Cancela a subscription anterior (para evitar múltiplos listeners)
    _chatSub?.cancel();
    _chatSub = null;
    _lastHandledIncomingMessageId = null;
    _initChatMonitoring();
  }

  void _handleMissingTrip() {
    if (!mounted || _missingTripHandled) return;
    _missingTripHandled = true;
    _stopWaitTimer();
    _locationTimer?.cancel();
    _simulationSubscription?.cancel();
    _positionStream?.cancel();
    _chatSub?.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A corrida foi removida do banco. Voltando ao painel.'),
        ),
      );
      context.go('/uber-driver');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationTimer?.cancel();
    _simulationSubscription?.cancel();
    _positionStream?.cancel();
    _waitTimer?.cancel();
    _chatSub?.cancel();
    _isDisposed = true;
    super.dispose();
  }

  void _initChatMonitoring() {
    _chatSub = DataGateway().watchChat(widget.tripId).listen((rows) {
      unawaited(_processChatRows(rows));
    });
  }

  Future<void> _processChatRows(List<dynamic> rows) async {
    if (!mounted || rows.isEmpty) return;

    if (_chatMessageCount != rows.length) {
      if (mounted) setState(() => _chatMessageCount = rows.length);
    }

    final unreadRows = rows.where(_isIncomingUnread).toList();
    if (unreadRows.isNotEmpty) {
      if (!_isChatOpen && mounted) {
        setState(() => _isChatOpen = true);
      }
      await _markChatMessagesRead(unreadRows);
      final latestUnread = unreadRows.first;
      final latestId = _extractMessageId(_rowToMap(latestUnread)['id']);
      final preview = _buildIncomingMessagePreview(latestUnread);
      if (_appLifecycleState != AppLifecycleState.resumed &&
          latestId != null &&
          preview.isNotEmpty) {
        NotificationService().showChatMessageNotification(
          serviceId: widget.tripId,
          messageId: latestId,
          senderName: _passengerName ?? 'Nova mensagem',
          message: preview.length > 120
              ? '${preview.substring(0, 120)}...'
              : preview,
        );
      }
      if (latestId != null) {
        _lastHandledIncomingMessageId = latestId;
      }
      return;
    }

    final latest = rows.first;
    final latestId = _extractMessageId(_rowToMap(latest)['id']);
    if (latestId == null || _lastHandledIncomingMessageId == latestId) return;

    final latestMap = _rowToMap(latest);
    final readAt = latestMap['read_at'] ?? latestMap['readAt'];
    final senderId = latestMap['sender_id'];
    final isOwn =
        _myUserId != null && senderId != null && '$senderId' == '$_myUserId';
    if (readAt != null || isOwn) {
      _lastHandledIncomingMessageId = latestId;
      return;
    }

    if (!_isChatOpen && mounted) {
      setState(() => _isChatOpen = true);
    }

    final preview = _buildIncomingMessagePreview(latest);
    if (_appLifecycleState != AppLifecycleState.resumed && preview.isNotEmpty) {
      NotificationService().showChatMessageNotification(
        serviceId: widget.tripId,
        messageId: latestId,
        senderName: _passengerName ?? 'Nova mensagem',
        message: preview.length > 120
            ? '${preview.substring(0, 120)}...'
            : preview,
      );
    }

    unawaited(DataGateway().markChatMessageRead(latestId));
    _lastHandledIncomingMessageId = latestId;
  }

  Map<String, dynamic> _rowToMap(dynamic row) {
    if (row is Map) {
      return Map<String, dynamic>.from(row);
    }
    return <String, dynamic>{};
  }

  bool _isIncomingUnread(dynamic row) {
    final map = _rowToMap(row);
    final readAt = map['read_at'] ?? map['readAt'];
    if (readAt != null) return false;
    final senderId = map['sender_id'];
    if (_myUserId != null && senderId != null && '$senderId' == '$_myUserId') {
      return false;
    }
    return true;
  }

  int? _extractMessageId(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<void> _markChatMessagesRead(List<dynamic> rows) async {
    for (final row in rows) {
      final rowMap = _rowToMap(row);
      final messageId = _extractMessageId(rowMap['id']);
      if (messageId != null) {
        await DataGateway().markChatMessageRead(messageId);
      }
    }
  }

  double _chatPanelHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final deviceHeight =
        media.size.height - media.padding.top - media.padding.bottom - keyboard;
    final maxHeight = (deviceHeight - 28).clamp(320.0, deviceHeight * 0.96);
    final minHeight = (deviceHeight * 0.62).clamp(320.0, maxHeight);
    final boundedCount = _chatMessageCount.clamp(0, 28);
    final growth = (boundedCount * 20.0).clamp(0.0, maxHeight - minHeight);
    final fallback = (minHeight + growth).clamp(minHeight, maxHeight);
    double baseHeight;
    if (_panelMeasuredHeight > 0) {
      baseHeight = _panelMeasuredHeight.clamp(minHeight, maxHeight);
    } else {
      baseHeight = fallback;
    }

    if (_isChatOpen) {
      final inlineHeight = _inlineChatHeight(context);
      // Add extra space for spacing/margins between the inline chat and rest of panel
      const extraSpacing = 32.0;
      baseHeight = (baseHeight + inlineHeight + extraSpacing).clamp(
        minHeight,
        maxHeight,
      );
    }
    return baseHeight;
  }

  double _collapsedPanelHeight(BuildContext context) {
    final deviceHeight =
        MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top;
    return (deviceHeight * 0.42).clamp(320.0, 520.0).toDouble();
  }

  double _inlineChatHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final deviceHeight = media.size.height - media.padding.top - keyboard;
    final maxHeight = (deviceHeight - 80).clamp(
      280.0,
      (deviceHeight * 0.85).clamp(300.0, 620.0),
    );
    final base = (deviceHeight * 0.34).clamp(240.0, maxHeight);
    final boundedCount = _chatMessageCount.clamp(0, 26);
    final growth = (boundedCount * 18.0).clamp(0.0, maxHeight - base);
    return (base + growth).clamp(base, maxHeight);
  }

  void _schedulePanelMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measurePanelHeight());
  }

  void _measurePanelHeight() {
    if (!mounted) return;
    final context = _panelContentKey.currentContext;
    if (context == null) return;
    final size = context.size?.height ?? 0;
    if (size <= 0) return;
    final total = size;
    if ((_panelMeasuredHeight - total).abs() > 4) {
      setState(() => _panelMeasuredHeight = total);
    }
  }

  String _buildIncomingMessagePreview(dynamic row) {
    final map = row is Map
        ? Map<String, dynamic>.from(row)
        : <String, dynamic>{};
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

  Future<void> _initDriver() async {
    final driverId = int.tryParse(_apiService.userId?.toString() ?? '');
    if (driverId != null) {
      try {
        final vehicleTypeId = await _uberService.getDriverVehicleTypeId(
          driverId,
        );
        if (mounted && vehicleTypeId != null) {
          setState(() {
            _isMoto = (vehicleTypeId == 2);
          });
        }
      } catch (e) {
        debugPrint(
          '⚠️ [DriverTrip] Erro ao buscar tipo de veículo do motorista: $e',
        );
      }
    }
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    geo.LocationPermission permission;

    serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) return;
    }

    if (permission == geo.LocationPermission.deniedForever) return;

    _startTracking();
  }

  void _startTracking() {
    _locationTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_isSimulating) return;

      final loc = await ProviderLocationService.getCurrentLocation();
      if (loc != null && mounted && !_isDisposed) {
        final rawLocation = ll.LatLng(loc.latitude, loc.longitude);
        final nextLocation = _snapLocationToRoute(rawLocation);
        final nextHeading = _resolveHeading(
          previousLocation: _currentLocation,
          newLocation: nextLocation,
          gpsHeading: loc.heading,
          speedMps: loc.speed,
        );

        setState(() {
          _currentLocation = nextLocation;
          _currentHeading = nextHeading;
          _isLoading = false;
        });

        // Ensure location is updated on Mapbox location component
        if (_mapboxMap != null && _isMapReady) {
          try {
            _mapboxMap?.setCamera(
              CameraOptions(
                center: Point(
                  coordinates: Position(
                    loc.longitude.isFinite ? loc.longitude : 0.0,
                    loc.latitude.isFinite ? loc.latitude : 0.0,
                  ),
                ),
                zoom: 17.0,
                bearing: (_isHeadingUp && _currentHeading.isFinite)
                    ? _currentHeading
                    : 0.0,
              ),
            );

            // Atualizar Marcadores Pixel Positions (Carro, Origem, Destino)
            _updatePixelPositions();
          } catch (e) {
            debugPrint('Erro ao atualizar camera: $e');
          }
        }
      }
    });
  }

  double _driverMarkerHeading() {
    // Quando o mapa já está em heading-up, a frente do carro deve ficar fixa para cima.
    if (_isHeadingUp) return 0.0;
    return _currentHeading;
  }

  List<ll.LatLng> _activeRouteForSnap() {
    final status = (_tripData?['status'] ?? '').toString();
    if (status == 'in_progress' && _destinationRoutePoints.isNotEmpty) {
      return _destinationRoutePoints;
    }
    if (_routePoints.isNotEmpty) return _routePoints;
    return _destinationRoutePoints;
  }

  double _snapMaxDistanceMeters() {
    return _navigationProfile == NavigationProfile.highway ? 55.0 : 35.0;
  }

  ll.LatLng _snapLocationToRoute(ll.LatLng rawLocation) {
    final route = _activeRouteForSnap();
    if (route.length < 2) return rawLocation;

    ll.LatLng? bestPoint;
    double bestDistance = double.infinity;

    for (int i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];
      final projected = _projectPointToSegment(rawLocation, a, b);
      final distance = geo.Geolocator.distanceBetween(
        rawLocation.latitude,
        rawLocation.longitude,
        projected.latitude,
        projected.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPoint = projected;
      }
    }

    if (bestPoint == null || bestDistance > _snapMaxDistanceMeters()) {
      return rawLocation;
    }
    return bestPoint;
  }

  ll.LatLng _projectPointToSegment(ll.LatLng p, ll.LatLng a, ll.LatLng b) {
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;
    final px = p.longitude;
    final py = p.latitude;

    final abx = bx - ax;
    final aby = by - ay;
    final ab2 = abx * abx + aby * aby;
    if (ab2 == 0) return a;

    final apx = px - ax;
    final apy = py - ay;
    final t = ((apx * abx + apy * aby) / ab2).clamp(0.0, 1.0);

    return ll.LatLng(ay + aby * t, ax + abx * t);
  }

  double _resolveHeading({
    required ll.LatLng? previousLocation,
    required ll.LatLng newLocation,
    required double? gpsHeading,
    required double speedMps,
  }) {
    _maybeSwitchNavigationProfile(speedMps.isFinite ? speedMps : 0.0);
    final course = previousLocation == null
        ? null
        : NavigationMath.courseBetween(
            from: previousLocation,
            to: newLocation,
            minDistanceMeters: _tuning.courseMinDistanceMeters,
          );
    final normalizedGps = _normalizedHeadingOrNull(gpsHeading);
    final validSpeed = speedMps.isFinite ? speedMps : 0.0;
    final preferCourse =
        validSpeed >= _tuning.courseSpeedThresholdMps || course != null;
    final target = preferCourse
        ? (course ?? normalizedGps)
        : (normalizedGps ?? course);

    if (target == null) return _currentHeading;

    final base = _currentHeading.isFinite
        ? _currentHeading
        : NavigationMath.normalizeDegrees(target);
    final alpha = validSpeed >= 8.0
        ? _tuning.headingSmoothingFast
        : (validSpeed >= 3.0
              ? _tuning.headingSmoothingCruise
              : _tuning.headingSmoothingLowSpeed);
    return NavigationMath.lerpAngleDegrees(base, target, alpha);
  }

  double? _normalizedHeadingOrNull(double? heading) {
    if (heading == null || !heading.isFinite || heading < 0) return null;
    return NavigationMath.normalizeDegrees(heading);
  }

  void _maybeSwitchNavigationProfile(double speedMps) {
    if (!_autoNavigationProfile) return;

    if (_navigationProfile == NavigationProfile.urban &&
        speedMps >= _tuning.highwayEnterSpeedMps) {
      _setNavigationProfile(NavigationProfile.highway);
      return;
    }
    if (_navigationProfile == NavigationProfile.highway &&
        speedMps <= _tuning.highwayExitSpeedMps) {
      _setNavigationProfile(NavigationProfile.urban);
    }
  }

  void _setNavigationProfile(NavigationProfile profile) {
    if (_navigationProfile == profile) return;
    _navigationProfile = profile;
    _tuning = profile == NavigationProfile.urban
        ? NavigationTuning.urban
        : NavigationTuning.highway;
  }

  Future<void> _updatePixelPositions() async {
    if (_mapboxMap == null || kIsWeb) return;
    try {
      Offset? newCarPos;
      Offset? newPickupPos;
      Offset? newDropoffPos;

      // Carro
      if (_currentLocation != null) {
        final pixel = await _mapboxMap!.pixelForCoordinate(
          Point(
            coordinates: Position(
              _currentLocation!.longitude,
              _currentLocation!.latitude,
            ),
          ),
        );
        newCarPos = Offset(pixel.x, pixel.y);
      }

      // Embarque (Origem)
      final pickupLat = _toDouble(_tripData?['pickup_lat']);
      final pickupLon = _toDouble(_tripData?['pickup_lon']);
      if (pickupLat != 0 && pickupLon != 0) {
        final pixel = await _mapboxMap!.pixelForCoordinate(
          Point(coordinates: Position(pickupLon, pickupLat)),
        );
        newPickupPos = Offset(pixel.x, pixel.y);
      }

      // Destino
      final dropoffLat = _toDouble(_tripData?['dropoff_lat']);
      final dropoffLon = _toDouble(_tripData?['dropoff_lon']);
      if (dropoffLat != 0 && dropoffLon != 0) {
        final pixel = await _mapboxMap!.pixelForCoordinate(
          Point(coordinates: Position(dropoffLon, dropoffLat)),
        );
        newDropoffPos = Offset(pixel.x, pixel.y);
      }

      if (mounted) {
        setState(() {
          _carPixelPosition = newCarPos;
          _pickupPixelPosition = newPickupPos;
          _dropoffPixelPosition = newDropoffPos;
        });
      }
    } catch (e) {
      debugPrint("❌ Erro ao converter coordenada para pixel: $e");
    }
  }

  void _updateMapboxRouteAndMarkers() async {
    if (_mapboxMap == null || !_isMapReady) {
      debugPrint('⚠️ [DriverTrip] Mapbox não está pronto para atualização.');
      return;
    }

    final pickupLat = _toDouble(_tripData?['pickup_lat']);
    final pickupLon = _toDouble(_tripData?['pickup_lon']);

    final effectiveLocation =
        _currentLocation ??
        (pickupLat != 0 ? ll.LatLng(pickupLat, pickupLon) : null);

    if (effectiveLocation == null) {
      debugPrint(
        '⚠️ [DriverTrip] Localização indisponível, abortando desenho.',
      );
      return;
    }

    // 1. VANISHING ROUTE: Recalcula a rota visível a partir da posição do motorista
    if (_routePoints.length >= 2) {
      int closestIndex = 0;
      double minDistance = double.infinity;

      for (int i = 0; i < _routePoints.length; i++) {
        final dist = geo.Geolocator.distanceBetween(
          effectiveLocation.latitude,
          effectiveLocation.longitude,
          _routePoints[i].latitude,
          _routePoints[i].longitude,
        );
        if (dist < minDistance) {
          minDistance = dist;
          closestIndex = i;
        }
      }

      final visibleRoute = _routePoints.sublist(closestIndex);
      if (visibleRoute.isNotEmpty && visibleRoute.first != effectiveLocation) {
        visibleRoute.insert(0, effectiveLocation);
      }

      if (_polylineAnnotationManager != null && visibleRoute.length >= 2) {
        await _polylineAnnotationManager!.deleteAll();

        final dynamic status = _tripData?['status'];
        final routeColor = (status == 'in_progress')
            ? Colors.blueAccent.toARGB32()
            : Colors.green.toARGB32();

        await _polylineAnnotationManager!.create(
          PolylineAnnotationOptions(
            geometry: LineString(
              coordinates: visibleRoute
                  .map((p) => Position(p.longitude, p.latitude))
                  .toList(),
            ),
            lineColor: routeColor,
            lineWidth: 5.0,
          ),
        );
      }
    }
  }

  // Método para mostrar QR Code PIX
  void _calculateTripStats() {
    if (_tripData == null) return;

    final arrivedAt = _tripData!['arrived_at'] != null
        ? DateTime.tryParse(_tripData!['arrived_at'].toString())
        : null;
    final startedAt = _tripData!['started_at'] != null
        ? DateTime.tryParse(_tripData!['started_at'].toString())
        : null;
    final completedAt = _tripData!['completed_at'] != null
        ? DateTime.tryParse(_tripData!['completed_at'].toString())
        : null;

    if (startedAt != null && completedAt != null) {
      final diff = completedAt.difference(startedAt);
      final mins = diff.inMinutes;
      final secs = diff.inSeconds % 60;
      _travelTimeStr =
          '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }

    if (arrivedAt != null && startedAt != null) {
      final diff = startedAt.difference(arrivedAt);
      final mins = diff.inMinutes;
      final secs = diff.inSeconds % 60;
      _waitTimeStr =
          '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
  }

  void _showPixQRCode(double amount, String tripId) async {
    setState(() => _isLoading = true);
    final driverId = int.tryParse(_apiService.userId?.toString() ?? '');
    if (driverId != null && _driverPixKey == null) {
      _driverPixKey = await _uberService.getDriverPixKey(driverId);
    }
    final driverProfile = driverId != null
        ? await _uberService.getUserProfile(driverId)
        : null;
    final driverName = driverProfile?['full_name'] as String? ?? 'Motorista';

    setState(() => _isLoading = false);

    if (_driverPixKey == null || _driverPixKey!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chave PIX não cadastrada no seu perfil.'),
          ),
        );
      }
      return;
    }

    final pixPayload = PixGenerator.generatePayload(
      pixKey: _driverPixKey!,
      merchantName: driverName,
      merchantCity: 'Imperatriz', // Cidade padrão ou buscar do perfil
      amount: amount,
      txid: tripId.replaceAll('-', '').substring(0, 25),
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(LucideIcons.qrCode, color: Colors.blue),
            const SizedBox(width: 12),
            Text(
              'Pagamento PIX',
              style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Valor: R\$ ${amount.toStringAsFixed(2)}',
              style: GoogleFonts.manrope(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: QrImageView(
                data: pixPayload,
                version: QrVersions.auto,
                size: 200.0,
                gapless: false,
                embeddedImageStyle: const QrEmbeddedImageStyle(
                  size: material.Size(40, 40),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Peça ao passageiro para escanear o código acima para pagar diretamente na sua conta.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: Colors.grey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'FECHAR',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w900,
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startWaitTimer() {
    _stopWaitTimer();
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _tripData == null || _tripData!['arrived_at'] == null) {
        return;
      }
      final arrivedAtDateTime = DateTime.tryParse(_tripData!['arrived_at']);
      if (arrivedAtDateTime != null) {
        setState(() {
          _waitingSeconds = DateTime.now()
              .toUtc()
              .difference(arrivedAtDateTime.toUtc())
              .inSeconds;
        });
      }
    });
  }

  void _stopWaitTimer() {
    _waitTimer?.cancel();
    _waitTimer = null;
  }

  Future<void> _updateStatus(String status) async {
    // Validação de Proximidade (GPS) para Chegada
    if (status == 'arrived') {
      final pickupLat = _toDouble(_tripData?['pickup_lat']);
      final pickupLon = _toDouble(_tripData?['pickup_lon']);

      if (_currentLocation != null && pickupLat != 0 && pickupLon != 0) {
        final distanceInMeters = geo.Geolocator.distanceBetween(
          _currentLocation?.latitude ?? 0,
          _currentLocation?.longitude ?? 0,
          pickupLat,
          pickupLon,
        );

        // Bloqueia se estiver a mais de 100 metros
        if (distanceInMeters > 100) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Você ainda não chegou ao local de embarque. Aproxime-se para confirmar a chegada.',
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return; // Interrompe a atualização do status
        }
      }
    }

    setState(() {
      _isLoading = true;
      if (_isSimulating) {
        UberService().stopRouteSimulation();
        _simulationSubscription?.cancel();
        _isSimulating = false;
      }
    });

    try {
      await _uberService.updateTripStatus(widget.tripId, status);
      // Não redirecionamos mais imediatamente para mostrar o resumo de pagamento
      // if (status == 'completed') {
      //   if (mounted) context.go('/uber-driver');
      // }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao atualizar status: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleSimulation(String tripStatus) {
    if (_isSimulating) {
      UberService().stopRouteSimulation();
      _simulationSubscription?.cancel();
      setState(() {
        _isSimulating = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Simulação parada')));
    } else {
      // Decide qual rota simular baseado no status
      List<ll.LatLng> pointsToSimulate = [];
      if (tripStatus == 'accepted') {
        pointsToSimulate = _routePoints;
      } else if (tripStatus == 'in_progress') {
        pointsToSimulate = _destinationRoutePoints;
      }

      if (pointsToSimulate.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rota não disponível para simulação neste status.'),
          ),
        );
        return;
      }

      setState(() {
        _isSimulating = true;
      });

      final userIdStr = _apiService.userId?.toString();
      final driverId = int.tryParse(userIdStr ?? '') ?? 0;
      UberService().startRouteSimulation(
        driverId: driverId,
        polyline: pointsToSimulate,
      );

      _simulationSubscription = UberService().simulationProgress?.listen((
        index,
      ) {
        if (mounted) {
          final nextLocation = pointsToSimulate[index];
          final nextHeading = _resolveHeading(
            previousLocation: _currentLocation,
            newLocation: nextLocation,
            gpsHeading: null,
            speedMps: 8.0,
          );
          setState(() {
            _currentLocation = nextLocation;
            _currentHeading = nextHeading;
          });
          // Opcional: mover mapa para a nova posição do simulador
          if (_mapboxMap != null) {
            _mapboxMap!.setCamera(
              CameraOptions(
                center: Point(
                  coordinates: Position(
                    _currentLocation?.longitude ?? 0.0,
                    _currentLocation?.latitude ?? 0.0,
                  ),
                ),
                zoom: 17.0, // Fixed zoom or retrieve current
                bearing: _isHeadingUp ? _currentHeading : 0.0,
              ),
            );
          }
        }
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Simulação iniciada')));
    }
  }

  @override
  Widget build(BuildContext context) {
    _schedulePanelMeasurement();
    return Scaffold(
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _uberService.watchTrip(widget.tripId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data == null) {
            _handleMissingTrip();
            return const SizedBox.shrink();
          }

          if (_tripData != snapshot.data) {
            _tripData = snapshot.data;
            debugPrint('🚗 [DriverTrip] Dados da Corrida Recebidos:');
            debugPrint(JsonEncoder.withIndent('  ').convert(_tripData));

            // Log específico do passageiro se disponível (assumindo que client_id ou dados do cliente venham no join)
            if (_tripData?['client_id'] != null) {
              debugPrint(
                '👤 [DriverTrip] Passageiro ID: ${_tripData!['client_id']}',
              );
            }

            // Gerencia o timer de espera se o motorista chegou
            final currentStatus = _tripData?['status'];
            if (currentStatus == 'arrived' && _waitTimer == null) {
              Future.microtask(_startWaitTimer);
            } else if (currentStatus != 'arrived') {
              Future.microtask(_stopWaitTimer);
            }
          }

          final status = _tripData?['status'] ?? 'accepted';
          final pickupAddress = _tripData?['pickup_address'] ?? '';
          final dropoffAddress = _tripData?['dropoff_address'] ?? '';
          final fare =
              double.tryParse(
                _tripData?['fare_estimated']?.toString() ?? '0.00',
              ) ??
              0.0;
          final paymentMethod =
              _tripData?['payment_method'] ?? 'NÃO ESPECIFICADO';

          // Se a viagem foi cancelada pelo passageiro
          if (status == 'cancelled') {
            final router = GoRouter.of(context);
            Future.microtask(() {
              if (mounted) {
                final hadArrived = _tripData?['arrived_at'] != null;
                final fee = hadArrived
                    ? AppConfigService().cancellationFee
                    : 0.0;

                router.go(
                  '/uber-driver',
                  extra: {
                    'cancellationMessage': 'O passageiro cancelou a corrida.',
                    'cancellationFee': fee,
                  },
                );
              }
            });
            return const Center(child: Text('Corrida Cancelada'));
          }

          // Se a viagem foi concluída, mostra o resumo de pagamento
          if (status == 'completed') {
            _calculateTripStats();
            if (paymentMethod.toString().contains('PIX') &&
                _pixPayload == null &&
                !_isLoadingPix) {
              Future.microtask(() => _generatePixPayloadForSummary(fare));
            }
            return _buildPaymentSummary(fare, paymentMethod.toString());
          }

          // 🏁 LOGICA RESILIENTE DE ROTAS
          final pickupLat = _toDouble(_tripData?['pickup_lat']);
          final pickupLon = _toDouble(_tripData?['pickup_lon']);
          final dropoffLat = _toDouble(_tripData?['dropoff_lat']);
          final dropoffLon = _toDouble(_tripData?['dropoff_lon']);

          // Rota 2: Passageiro -> Destino (AZUL) - Não depende do motorista
          if (!_hasFetchedDestinationRoute &&
              pickupLat != 0 &&
              dropoffLat != 0) {
            _hasFetchedDestinationRoute = true;
            Future.microtask(() async {
              try {
                final destinationRes = await MapService().getRoute(
                  ll.LatLng(pickupLat, pickupLon),
                  ll.LatLng(dropoffLat, dropoffLon),
                );
                if (mounted) {
                  setState(() {
                    final List<ll.LatLng> points =
                        destinationRes['points'] as List<ll.LatLng>;
                    if (points.isNotEmpty) {
                      final pickup = ll.LatLng(pickupLat, pickupLon);
                      final dropoff = ll.LatLng(dropoffLat, dropoffLon);
                      if (points.first != pickup) points.insert(0, pickup);
                      if (points.last != dropoff) points.add(dropoff);
                    }
                    _destinationRoutePoints = points;
                  });
                  _fitRoute([..._routePoints, ..._destinationRoutePoints]);
                }
              } catch (e) {
                debugPrint('❌ Erro ao buscar rota de destino: $e');
              }
            });
          }

          // Rota 1: Motorista -> Passageiro (ROXO) - Depende do motorista
          if (!_hasFetchedPickupRoute &&
              _currentLocation != null &&
              pickupLat != 0) {
            _hasFetchedPickupRoute = true;
            Future.microtask(() async {
              try {
                if (_currentLocation == null) return;
                final pickupRes = await MapService().getRoute(
                  _currentLocation!,
                  ll.LatLng(pickupLat, pickupLon),
                );
                if (mounted) {
                  setState(() {
                    final List<ll.LatLng> points =
                        pickupRes['points'] as List<ll.LatLng>;
                    if (points.isNotEmpty) {
                      final pickup = ll.LatLng(pickupLat, pickupLon);
                      if (points.first != _currentLocation) {
                        points.insert(0, _currentLocation!);
                      }
                      if (points.last != pickup) points.add(pickup);
                    }
                    _routePoints = points;
                  });
                  _fitRoute([..._routePoints, ..._destinationRoutePoints]);
                }
              } catch (e) {
                debugPrint('❌ Erro ao buscar rota de pickup: $e');
              }
            });
          }

          // Busca nome do passageiro (mantido)
          if (_tripData?['client_id'] != null && _passengerName == null) {
            _passengerName = "Carregando..."; // Previne re-entrada
            Future.microtask(() async {
              try {
                final clientProfile = await _uberService.getUserProfile(
                  _tripData!['client_id'],
                );
                if (mounted && clientProfile != null) {
                  setState(() => _passengerName = clientProfile['full_name']);
                } else if (mounted) {
                  setState(
                    () => _passengerName =
                        "Passageiro #${_tripData!['client_id']}",
                  );
                }
              } catch (e) {
                if (mounted) setState(() => _passengerName = "Passageiro");
              }
            });
          }

          return Stack(
            children: [
              // MAPA
              if (_currentLocation == null && pickupLat == 0)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                  ),
                )
              else
                Stack(
                  children: [
                    MapWidget(
                      key: const ValueKey("mapboxMap"),
                      onCameraChangeListener: (cameraChangedEvent) {
                        _updatePixelPositions();
                      },
                      onMapCreated: (MapboxMap mapboxMap) async {
                        _mapboxMap = mapboxMap;
                        mapboxMap.location.updateSettings(
                          LocationComponentSettings(
                            enabled: false,
                            pulsingEnabled: false,
                            puckBearingEnabled: false,
                          ),
                        );
                        _polylineAnnotationManager = await mapboxMap.annotations
                            .createPolylineAnnotationManager();
                        _pointAnnotationManager = await mapboxMap.annotations
                            .createPointAnnotationManager();
                        setState(() {
                          _isMapReady = true;
                        });

                        // Desenha a rota e marcadores imediatamente
                        _updateMapboxRouteAndMarkers();
                        _updatePixelPositions();

                        Future.delayed(Duration.zero, () {
                          if (mounted) _fitRoute(_routePoints);
                        });
                      },
                      styleUri: MapboxStyles.MAPBOX_STREETS,
                      cameraOptions: CameraOptions(
                        center: Point(
                          coordinates: Position(
                            _currentLocation?.longitude ??
                                pickupLon, // Fallback safely to pickup
                            _currentLocation?.latitude ?? pickupLat,
                          ),
                        ),
                        zoom: 15.0,
                      ),
                    ),
                    // Marcador Origem
                    if (!kIsWeb && _pickupPixelPosition != null)
                      Positioned(
                        left:
                            _pickupPixelPosition!.dx -
                            100, // Centraliza lateral (largura 200/2)
                        top:
                            _pickupPixelPosition!.dy -
                            100, // Sobe toda a altura (haste aponta para o pixel)
                        child: SizedBox(
                          width: 200,
                          height: 100,
                          child: _buildLabelMarker(
                            label: 'Origem',
                            color: const Color(0xFF2196F3),
                            isPickup: true,
                          ),
                        ),
                      ),
                    // Marcador Destino
                    if (!kIsWeb && _dropoffPixelPosition != null)
                      Positioned(
                        left: _dropoffPixelPosition!.dx - 100,
                        top: _dropoffPixelPosition!.dy - 100,
                        child: SizedBox(
                          width: 200,
                          height: 100,
                          child: _buildLabelMarker(
                            label: 'Destino',
                            color: const Color(0xFFFF2D55),
                            isPickup: false,
                          ),
                        ),
                      ),
                    // Marcador Carro
                    if (!kIsWeb &&
                        _carPixelPosition != null &&
                        _currentLocation != null)
                      Positioned(
                        left: _carPixelPosition!.dx - 30, // Centro
                        top: _carPixelPosition!.dy - 30, // Centro
                        child: PremiumDriverMarker(
                          heading: _driverMarkerHeading(),
                          isMoto: _isMoto,
                          size: 44,
                        ),
                      ),
                  ],
                ),

              // HEADER STITCH: PANORAMA GLASS
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        MediaQuery.of(context).padding.top + 8,
                        16,
                        16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // FLOATING MAP CONTROLS
              Positioned(
                right: 16,
                top: MediaQuery.of(context).padding.top + 100,
                child: Column(
                  children: [
                    _buildMapControl(LucideIcons.plus, () async {
                      if (_isMapReady && _mapboxMap != null) {
                        final state = await _mapboxMap!.getCameraState();
                        _mapboxMap!.setCamera(
                          CameraOptions(zoom: state.zoom + 1),
                        );
                      }
                    }),
                    const SizedBox(height: 8),
                    _buildMapControl(LucideIcons.minus, () async {
                      if (_isMapReady && _mapboxMap != null) {
                        final state = await _mapboxMap!.getCameraState();
                        _mapboxMap!.setCamera(
                          CameraOptions(zoom: state.zoom - 1),
                        );
                      }
                    }),
                    const SizedBox(height: 16),
                    _buildMapControl(
                      LucideIcons.navigation2,
                      () => _openExternalNavigation(),
                      color: AppTheme.primaryYellow,
                    ),
                    const SizedBox(height: 8),
                    // BOTÃO DE BÚSSOLA (HEADING UP)
                    _buildMapControl(
                      LucideIcons.compass,
                      () {
                        setState(() {
                          _isHeadingUp = !_isHeadingUp;
                          if (!_isHeadingUp &&
                              _isMapReady &&
                              _mapboxMap != null) {
                            _mapboxMap!.setCamera(
                              CameraOptions(bearing: 0),
                            ); // Volta para o norte fixo
                          }
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _isHeadingUp
                                  ? 'Navegação por bússola ativada'
                                  : 'Navegação por bússola desativada',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      color: _isHeadingUp ? Colors.blue : Colors.grey,
                    ),
                  ],
                ),
              ),

              // PANEL: PASSENGER & ACTIONS (BOTTOM SHEET STITCH)
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  left: false,
                  right: false,
                  bottom: true,
                  child: Transform.translate(
                    offset: Offset(0, _isChatOpen ? -14 : -6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      width: double.infinity,
                      height: _isChatOpen
                          ? _chatPanelHeight(context)
                          : _collapsedPanelHeight(context),
                      padding: EdgeInsets.fromLTRB(
                        24,
                        12,
                        24,
                        16 + MediaQuery.of(context).padding.bottom,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(32),
                        ),
                        boxShadow: kIsWeb
                            ? []
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Column(
                        key: _panelContentKey,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Handle
                          Container(
                            width: 40,
                            height: 5,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                          Flexible(
                            fit: FlexFit.loose,
                            child: SingleChildScrollView(
                              padding: EdgeInsets.only(
                                bottom:
                                    12 + MediaQuery.of(context).padding.bottom,
                              ),
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Passenger Info Section
                                  _buildPassengerInfoStitch(),
                                  const SizedBox(height: 24),
                                  // Address Card Detail
                                  _buildAddressDetailCard(
                                    status,
                                    pickupAddress,
                                    dropoffAddress,
                                  ),
                                  const SizedBox(height: 24),
                                  // Action Button
                                  _buildActionPanelStitch(status),
                                ],
                              ),
                            ),
                          ),
                          if (_isChatOpen) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: _inlineChatHeight(context),
                              child: ChatScreen(
                                serviceId: widget.tripId,
                                otherName: _passengerName ?? 'Passageiro',
                                otherAvatar: _tripData?['client_avatar'],
                                isInline: true,
                                onClose: () {
                                  debugPrint(
                                    '[DriverTripScreen] Chat onClose called',
                                  );
                                  setState(() => _isChatOpen = false);
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              if (_isLoading)
                Container(
                  color: Colors.black45,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryYellow,
                    ),
                  ),
                ),

              // Botão de Simulação (Apenas em estados de movimento: aceito ou em curso)
              if (status == 'accepted' || status == 'in_progress')
                Positioned(
                  top: 110, // Logo abaixo do painel de destino atual
                  right: 20,
                  child: _buildSimulationBadge(status),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openChat() {
    debugPrint(
      '[DriverTripScreen] _openChat called. Current _isChatOpen: $_isChatOpen',
    );
    setState(() {
      _isChatOpen = !_isChatOpen;
      debugPrint(
        '[DriverTripScreen] Chat toggled. New _isChatOpen: $_isChatOpen',
      );
    });
  }

  Future<void> _openExternalNavigation({bool forceChooser = false}) async {
    final status = (_tripData?['status'] ?? '').toString();
    final isGoingToPickup = status == 'accepted' || status == 'arrived';
    final targetLat = isGoingToPickup
        ? _toDouble(_tripData?['pickup_lat'])
        : _toDouble(_tripData?['dropoff_lat']);
    final targetLon = isGoingToPickup
        ? _toDouble(_tripData?['pickup_lon'])
        : _toDouble(_tripData?['dropoff_lon']);

    if (targetLat == 0 || targetLon == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Destino da navegação indisponível')),
        );
      }
      return;
    }

    await NavigationAppsHelper.openNavigation(
      context,
      lat: targetLat,
      lon: targetLon,
      forceChooser: forceChooser,
    );
  }

  Future<void> _makePhoneCall() async {
    // Para efeito de demonstração, mostra um alerta, já que não temos a dep de url_launcher instalada ou garantida
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Iniciando chamada para o passageiro...')),
    );
  }

  void _fitRoute(List<ll.LatLng> points) async {
    if (points.isEmpty || !mounted || _mapboxMap == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    try {
      final camera = await _mapboxMap!.cameraForCoordinatesPadding(
        [
          Point(coordinates: Position(minLng, minLat)),
          Point(coordinates: Position(maxLng, maxLat)),
        ],
        CameraOptions(),
        MbxEdgeInsets(top: 100.0, left: 50.0, bottom: 350.0, right: 50.0),
        null,
        null,
      );

      _mapboxMap!.flyTo(camera, MapAnimationOptions(duration: 1500));

      // Update or create polylines and points on route fit
      if (_polylineAnnotationManager != null) {
        await _polylineAnnotationManager!.deleteAll();
        final positions = points
            .map((p) => Position(p.longitude, p.latitude))
            .toList();
        await _polylineAnnotationManager!.create(
          PolylineAnnotationOptions(
            geometry: LineString(coordinates: positions),
            lineColor: Colors.blueAccent.toARGB32(),
            lineWidth: 5.0,
          ),
        );
      }

      if (_pointAnnotationManager != null) {
        await _pointAnnotationManager!.deleteAll();
        final lastPoint = points.last;
        await _pointAnnotationManager!.create(
          PointAnnotationOptions(
            geometry: Point(
              coordinates: Position(lastPoint.longitude, lastPoint.latitude),
            ),
            iconImage: 'marker-15',
            iconSize: 2.0,
          ),
        );
      }
    } catch (e) {
      debugPrint("🚕 [DriverTrip] Erro ao enquadrar rota: $e");
    }
  }

  Widget _buildLabelMarker({
    required String label,
    required Color color,
    String? info,
    required bool isPickup,
  }) {
    final Color markerColor = isPickup
        ? const Color(0xFF2196F3)
        : const Color(0xFFFF2D55);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: markerColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (info != null) ...[
                Container(
                  width: 1,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                Text(
                  info,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 2),
        SnapPinMarker(
          color: markerColor,
          size: 40,
          type: isPickup ? SnapMarkerType.pickup : SnapMarkerType.destination,
        ),
      ],
    );
  }

  String _getFormattedDistance() {
    if (_currentLocation == null) return '--';

    // Alvo depende do status
    ll.LatLng? target;
    if (_tripData?['status'] == 'in_progress') {
      target = ll.LatLng(
        _toDouble(_tripData?['dropoff_lat']),
        _toDouble(_tripData?['dropoff_lon']),
      );
    } else {
      target = ll.LatLng(
        _toDouble(_tripData?['pickup_lat']),
        _toDouble(_tripData?['pickup_lon']),
      );
    }

    if (target.latitude == 0) return '--';

    if (_currentLocation == null) return '--';

    final distanceMeters = geo.Geolocator.distanceBetween(
      _currentLocation?.latitude ?? 0,
      _currentLocation?.longitude ?? 0,
      target.latitude,
      target.longitude,
    );

    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)}m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
  }

  String _getFormattedTime() {
    if (_currentLocation == null) return '--';

    ll.LatLng? target;
    if (_tripData?['status'] == 'in_progress') {
      target = ll.LatLng(
        _toDouble(_tripData?['dropoff_lat']),
        _toDouble(_tripData?['dropoff_lon']),
      );
    } else {
      target = ll.LatLng(
        _toDouble(_tripData?['pickup_lat']),
        _toDouble(_tripData?['pickup_lon']),
      );
    }

    if (target.latitude == 0) return '--';

    if (_currentLocation == null) return '--';

    final distanceMeters = geo.Geolocator.distanceBetween(
      _currentLocation?.latitude ?? 0,
      _currentLocation?.longitude ?? 0,
      target.latitude,
      target.longitude,
    );

    final minutes = (distanceMeters / 450).ceil(); // ~27km/h media cidade
    if (minutes <= 0) return 'Chegando';
    return '$minutes min';
  }

  Widget _buildMapControl(IconData icon, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: kIsWeb
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Icon(icon, color: AppTheme.textDark, size: 24),
      ),
    );
  }

  Widget _buildPassengerInfoStitch() {
    return Row(
      children: [
        Stack(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                shape: BoxShape.circle,
                image: _tripData?['client_avatar'] != null
                    ? DecorationImage(
                        image: NetworkImage(_tripData!['client_avatar']),
                        fit: BoxFit.cover,
                      )
                    : null,
                border: Border.all(
                  color: AppTheme.primaryYellow.withValues(alpha: 0.3),
                  width: 3,
                ),
              ),
              child: _tripData?['client_avatar'] == null
                  ? const Icon(
                      LucideIcons.user,
                      color: AppTheme.textMuted,
                      size: 32,
                    )
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryYellow,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: AppTheme.textDark,
                  size: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _passengerName ?? 'Carregando...',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              Row(
                children: [
                  Text(
                    '4.8',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '• Passageiro Premium',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Row(
          children: [
            _buildCircleActionBtn(LucideIcons.messageSquare, _openChat),
            const SizedBox(width: 12),
            _buildCircleActionBtn(LucideIcons.phone, _makePhoneCall),
          ],
        ),
      ],
    );
  }

  Widget _buildCircleActionBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.primaryYellow.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppTheme.textDark, size: 22),
      ),
    );
  }

  Widget _buildAddressDetailCard(String status, String pickup, String dropoff) {
    final isGoingToPickup = status == 'accepted' || status == 'arrived';
    final targetAddress = isGoingToPickup ? pickup : dropoff;
    final label = isGoingToPickup ? 'LOCAL DE EMBARQUE' : 'DESTINO DA VIAGEM';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppTheme.primaryYellow,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryYellow.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              Container(
                width: 2,
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryYellow,
                      AppTheme.primaryYellow.withValues(alpha: 0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryYellow,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  targetAddress,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Distância: ${_getFormattedDistance()}',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                _getFormattedTime(),
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              Text(
                _getFormattedDistance(),
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionPanelStitch(String status) {
    if (status == 'arrived') {
      // Contagem crescente desde arrived_at
      final elapsed = _waitingSeconds.clamp(0, 999999);
      final mins = (elapsed / 60).floor();
      final secs = (elapsed % 60);
      final timerText =
          '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

      Color timerColor = Colors.green.shade700;
      if (elapsed >= 120) {
        timerColor = Colors.red.shade700; // Crítico: passou dos 2 minutos
      } else if (elapsed >= 60) {
        timerColor = Colors.orange.shade700; // Alerta
      }

      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.clock, color: timerColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  'AGUARDANDO: $timerText',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: timerColor,
                  ),
                ),
              ],
            ),
          ),

          if (_waitingSeconds >=
              120) // Se passou de 2 min, mostra botão de cancelar especial
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: () =>
                    _updateStatus('cancelled'), // TODO: Chamar função com taxa
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade200, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const material.Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.warning_amber_rounded, size: 20),
                label: Text(
                  'CANCELAR COM TAXA',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                ),
              ),
            ),

          _buildPrimaryButton(
            'PASSAGEIRO EMBARCOU',
            () => _updateStatus('in_progress'),
          ),
        ],
      );
    }

    String actionText = status == 'accepted'
        ? 'CHEGUEI AO LOCAL'
        : 'FINALIZAR VIAGEM';
    String nextSt = status == 'accepted' ? 'arrived' : 'completed';

    return _buildPrimaryButton(actionText, () => _updateStatus(nextSt));
  }

  Widget _buildPrimaryButton(String text, VoidCallback onTap) {
    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryYellow.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryYellow,
          minimumSize: const material.Size(double.infinity, 56),
          foregroundColor: AppTheme.textDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.checkCircle, size: 24),
            const SizedBox(width: 12),
            Text(
              text.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSummary(double fare, String selectedPaymentMethod) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.backgroundDark,
            AppTheme.backgroundDark.withValues(alpha: 0.95),
            Colors.black,
          ],
        ),
      ),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Icon(
                    LucideIcons.checkCircle,
                    color: AppTheme.primaryYellow,
                    size: 80,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              'VIAGEM CONCLUÍDA',
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Text(
                    'VALOR TOTAL',
                    style: GoogleFonts.manrope(
                      color: Colors.white60,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'R\$ ${fare.toStringAsFixed(2)}',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: Colors.white10),
                  ),
                  _buildSummaryLine(
                    'SEU GANHO LÍQUIDO',
                    'R\$ ${AppConfigService().calculateNetGain(fare).toStringAsFixed(2)}',
                    isBold: true,
                    isGreen: true,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: Colors.white10),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatMiniItem('TEMPO VIAGEM', _travelTimeStr),
                      _buildStatMiniItem('TEMPO ESPERA', _waitTimeStr),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (selectedPaymentMethod.contains('PIX')) ...[
              if (_isLoadingPix)
                const CircularProgressIndicator()
              else if (_pixPayload != null)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: _pixPayload!,
                        version: QrVersions.auto,
                        size: 180.0,
                        gapless: false,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'QR CODE PIX PARA RECEBIMENTO',
                      style: GoogleFonts.manrope(
                        color: AppTheme.primaryYellow,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _buildPaymentOption(
                  LucideIcons.qrCode,
                  'PIX',
                  isSelected: selectedPaymentMethod.contains('PIX'),
                  onTap: () => _showPixQRCode(fare, widget.tripId),
                ),
                _buildPaymentOption(
                  LucideIcons.creditCard,
                  'CARTÃO',
                  isSelected: selectedPaymentMethod.contains('Cartão'),
                ),
                _buildPaymentOption(
                  LucideIcons.banknote,
                  'DINHEIRO',
                  isSelected: selectedPaymentMethod == 'DINHEIRO',
                ),
                _buildPaymentOption(
                  LucideIcons.smartphone,
                  'MÁQUINA',
                  isSelected: selectedPaymentMethod == 'MÁQUINA',
                ),
              ],
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: () async {
                  setState(() => _isLoading = true);
                  try {
                    await _uberService.updateTripStatus(
                      widget.tripId,
                      'completed',
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Pagamento confirmado com sucesso!'),
                        ),
                      );
                      if (!_hasRated) {
                        _showRatingModal();
                      } else {
                        context.go('/uber-driver');
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro ao confirmar: $e')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryYellow,
                  foregroundColor: AppTheme.textDark,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: Text(
                  'CONFIRMAR E CONCLUIR',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _generatePixPayloadForSummary(double amount) async {
    if (_isLoadingPix || _pixPayload != null) return;

    final driverId = int.tryParse(_apiService.userId?.toString() ?? '');
    if (driverId == null) return;

    if (mounted) setState(() => _isLoadingPix = true);
    try {
      _driverPixKey ??= await _uberService.getDriverPixKey(driverId);

      final driverProfile = await _uberService.getUserProfile(driverId);
      final driverName = driverProfile?['full_name'] as String? ?? 'Motorista';

      if (_driverPixKey != null && _driverPixKey!.isNotEmpty) {
        _pixPayload = PixGenerator.generatePayload(
          pixKey: _driverPixKey!,
          merchantName: driverName,
          merchantCity: 'Imperatriz',
          amount: amount,
          txid: widget.tripId.replaceAll('-', '').substring(0, 25),
        );
      }
    } catch (e) {
      debugPrint('Erro ao gerar PIX: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPix = false);
    }
  }

  Widget _buildStatMiniItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.manrope(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  void _showRatingModal() {
    int rating = 5;
    final TextEditingController commentController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Column(
              children: [
                Text(
                  'Avalie o Passageiro',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sua nota ajuda a manter a comunidade segura',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: Colors.white60,
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
                            ? AppTheme.primaryYellow
                            : Colors.white24,
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
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Deixe um comentário (opcional)',
                    hintStyle: GoogleFonts.manrope(
                      fontSize: 14,
                      color: Colors.white30,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
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
                  Navigator.pop(context);
                  context.go('/uber-driver');
                },
                child: Text(
                  'PULAR',
                  style: GoogleFonts.manrope(
                    color: Colors.white60,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final reviewerId = _tripData?['driver_id'] as int;
                    final revieweeId = _tripData?['client_id'] as int;

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
                      context.go('/uber-driver');
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

  Widget _buildPaymentOption(
    IconData icon,
    String label, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryYellow.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryYellow : Colors.white10,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryLine(
    String label,
    String value, {
    bool isBold = false,
    bool isGreen = false,
    bool isYellow = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.manrope(
              color: isYellow ? AppTheme.primaryYellow : Colors.white60,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.manrope(
              color: isGreen
                  ? Colors.greenAccent
                  : (isYellow ? AppTheme.primaryYellow : Colors.white),
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationBadge(String status) {
    return InkWell(
      onTap: () => _toggleSimulation(status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _isSimulating ? Colors.red : AppTheme.primaryBlue,
          borderRadius: BorderRadius.circular(20),
          boxShadow: kIsWeb
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isSimulating ? Icons.stop : Icons.play_arrow,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              _isSimulating ? 'PARAR TESTE' : 'SIMULAR GPS',
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
