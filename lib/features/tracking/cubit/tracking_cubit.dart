import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../../core/constants/trip_statuses.dart';
import '../../../services/data_gateway.dart';
import '../../../services/central_service.dart';
import '../../../services/api_service.dart';
import '../../../services/map_service.dart';
import '../../../services/app_config_service.dart';
import '../models/tracking_state.dart';
import '../utils/navigation_helpers.dart';
import '../utils/navigation_math.dart';

class TrackingCubit extends Cubit<TrackingState> {
  final CentralService _uberService;
  // ignore: unused_field
  final ApiService _apiService;
  final AppConfigService _appConfig = AppConfigService();
  final DataGateway _dataGateway = DataGateway();
  final String tripId;

  StreamSubscription<List<Map<String, dynamic>>>? _driverLocationSub;
  StreamSubscription<Map<String, dynamic>?>? _tripSub;
  Timer? _waitTimer;
  Timer? _pulseFeedbackTimer;
  Timer? _pixAutoRefreshTimer;
  String? _lastHandledDriverCancellationAt;
  bool _missingTripHandled = false;
  bool _hasTriggered500m = false;
  bool _hasTriggered100m = false;
  bool _hasTriggeredArrived = false;
  bool _hasFetchedPickupRoute = false;
  bool _hasFetchedDropoffRoute = false;
  bool _hasTriggeredPixGeneration = false;
  DateTime? _pixRetryNotBefore;
  int _pixConsecutiveFailures = 0;

  TrackingCubit({
    required this.tripId,
    required CentralService uberService,
    required ApiService apiService,
  }) : _uberService = uberService,
       _apiService = apiService,
       super(TrackingState(tripId: tripId));

  Future<void> initialize() async {
    await _loadInitialTripData();
    _startListening();
  }

  Future<void> _loadInitialTripData() async {
    emit(state.copyWith(tripLoadError: false));
    try {
      final service = await _apiService
          .getServiceDetails(tripId, scope: ServiceDataScope.mobileOnly)
          .timeout(const Duration(seconds: 10));

      final pickupLocation =
          (service['latitude'] != null && service['longitude'] != null)
          ? ll.LatLng(
              double.parse(service['latitude'].toString()),
              double.parse(service['longitude'].toString()),
            )
          : null;

      final mapped = <String, dynamic>{
        ...service,
        // Normaliza campos usados pelo tracking do atendimento
        'pickup_lat': service['latitude'],
        'pickup_lon': service['longitude'],
        'pickup_address': service['address'],
        'dropoff_address': 'Local do Serviço',
        'driver_id': service['provider_id'],
        'fare_estimated': service['price_estimated'],
        'fare_final': service['price_upfront'] ?? service['price_estimated'],
      };

      final currentStatus = _mapStatus(service['status'] ?? '');
      emit(
        state.copyWith(
          isService: true,
          tripData: mapped,
          status: currentStatus,
          pickupLocation: pickupLocation,
          dropoffLocation: null,
          tripLoadError: false,
          isPaid:
              (service['payment_status']?.toString().toLowerCase() == 'paid'),
          currentRouteMode: _getRouteMode(currentStatus),
          requiresCVV: false,
        ),
      );
      _syncPixAutoRefresh();

      final providerId = service['provider_id'];
      if (providerId != null) {
        await fetchDriverProfile(providerId);
      }
      return;
    } catch (e) {
      debugPrint('Error loading service tracking data: $e');
      emit(state.copyWith(tripLoadError: true));
    }
  }

  void _startListening() {
    final Stream<Map<String, dynamic>?> source = _dataGateway
        .watchService(tripId)
        .map((e) => e);

    _tripSub = source.listen((data) {
      if (data == null) {
        _handleMissingTrip();
        return;
      }

      final oldStatus = state.status;
      final newStatus = _resolveStatusFromTrip(data);

      _handleStatusChange(data, oldStatus, newStatus);
      _updateLocations(data);
      _handleDriverAssignment(data);

      // Se a forma de pagamento deixou de ser PIX (ex: mudou para dinheiro direto),
      // limpamos o payload/QR antigo para a UI não continuar exibindo copia-cola.
      final paymentLabel =
          (data['payment_method'] ?? data['payment_method_id'] ?? '')
              .toString()
              .toUpperCase();
      final isPixNow =
          paymentLabel.contains('PIX') &&
          !paymentLabel.contains('PIX_DIRECT') &&
          !paymentLabel.contains('DIRETO') &&
          !paymentLabel.contains('CARD') &&
          !paymentLabel.contains('CART');

      emit(
        state.copyWith(
          tripData: state.isService
              ? {
                  ...data,
                  'pickup_lat': data['latitude'],
                  'pickup_lon': data['longitude'],
                  'pickup_address': data['address'],
                  'dropoff_address': 'Local do Serviço',
                  'driver_id': data['provider_id'],
                  'fare_estimated': data['price_estimated'],
                  'fare_final':
                      data['price_upfront'] ?? data['price_estimated'],
                }
              : data,
          status: newStatus,
          isPaid: data['payment_status'] == 'paid',
          requiresCVV: data['payment_requires_cvv'] == true,
          currentRouteMode: _getRouteMode(newStatus),
          pixPayload: isPixNow ? state.pixPayload : null,
          pixQrCode: isPixNow ? state.pixQrCode : null,
        ),
      );
    });
  }

  String _getRouteMode(TripStatus status) {
    if (status == TripStatus.accepted ||
        status == TripStatus.driverEnRoute ||
        status == TripStatus.arrived) {
      return 'to_pickup';
    } else if (status == TripStatus.inProgress) {
      return 'to_dropoff';
    }
    return 'none';
  }

  void _handleStatusChange(
    Map<String, dynamic> data,
    TripStatus oldStatus,
    TripStatus newStatus,
  ) {
    if (newStatus == TripStatus.inProgress) {
      emit(
        state.copyWith(
          alert500mShow: false,
          alert100mShow: false,
          alertArrivedShow: false,
        ),
      );
      _hasTriggered500m = true;
      _hasTriggered100m = true;
      _hasTriggeredArrived = true;
    }

    bool showPulse = state.showPulse;
    if (newStatus == TripStatus.searching ||
        newStatus == TripStatus.noDrivers) {
      showPulse = true;
    } else if (newStatus == TripStatus.accepted &&
        oldStatus != TripStatus.accepted) {
      showPulse = true;
      _pulseFeedbackTimer?.cancel();
      _pulseFeedbackTimer = Timer(const Duration(seconds: 3), () {
        emit(state.copyWith(showPulse: false));
      });
    } else if ((newStatus == TripStatus.cancelled ||
            newStatus == TripStatus.noDrivers) &&
        (oldStatus == TripStatus.searching ||
            oldStatus == TripStatus.noDrivers)) {
      showPulse = true;
      _pulseFeedbackTimer?.cancel();
      _pulseFeedbackTimer = Timer(const Duration(seconds: 5), () {
        emit(state.copyWith(showPulse: false));
      });
    }

    emit(state.copyWith(showPulse: showPulse));

    if (newStatus == TripStatus.arrived) {
      _startWaitTimer(data);
    } else {
      _stopWaitTimer();
    }

    if (newStatus == TripStatus.completed &&
        oldStatus != TripStatus.completed) {
      // Opcional: Busca final se não buscou antes
    }
    _syncPixAutoRefresh();
  }

  Future<void> _fetchPixData({bool silent = false, bool force = false}) async {
    if (state.isLoadingPix) return;
    if (!force &&
        _pixRetryNotBefore != null &&
        DateTime.now().isBefore(_pixRetryNotBefore!)) {
      final secondsLeft = _pixRetryNotBefore!
          .difference(DateTime.now())
          .inSeconds
          .clamp(1, 60);
      debugPrint(
        '⏳ [TrackingCubit] PIX cooldown ativo, ignorando nova tentativa por ${secondsLeft}s',
      );
      return;
    }
    if (!silent) {
      emit(state.copyWith(isLoadingPix: true));
    }
    try {
      final pixData = await _uberService.getPixData(
        tripId,
        entityType: state.isService ? 'service' : 'trip',
      );
      if (pixData['error'] != null) {
        final step = (pixData['step'] ?? '').toString().trim();
        final reasonCode = (pixData['reason_code'] ?? '').toString().trim();
        final traceId = (pixData['trace_id'] ?? '').toString().trim();
        _pixConsecutiveFailures += 1;
        final cooldownSeconds = (_pixConsecutiveFailures >= 3) ? 30 : 20;
        _pixRetryNotBefore = DateTime.now().add(
          Duration(seconds: cooldownSeconds),
        );
        debugPrint(
          '❌ [TrackingCubit] Falha ao buscar PIX: '
          'error=${pixData['error']} step=$step reason_code=$reasonCode trace_id=$traceId '
          'cooldown=${cooldownSeconds}s',
        );
        return;
      }
      final payloadRaw =
          pixData['copy_and_paste'] ??
          pixData['payload'] ??
          pixData['pix_payload'] ??
          pixData['copyAndPaste'] ??
          pixData['qr_code'];
      final payload = payloadRaw?.toString().trim();

      final qrCodeRaw =
          pixData['encodedImage'] ??
          pixData['image_url'] ??
          pixData['qr_code_base64'];
      final qrCode = qrCodeRaw?.toString().trim();
      final amountRaw = pixData['amount'];
      final amount = amountRaw is num
          ? amountRaw.toDouble()
          : double.tryParse(amountRaw?.toString() ?? '');
      final nextTripData = <String, dynamic>{...?state.tripData};
      if (amount != null && amount > 0) {
        nextTripData['fare_final'] = amount;
      }
      emit(
        state.copyWith(
          tripData: nextTripData,
          pixPayload: (payload != null && payload.isNotEmpty)
              ? payload
              : state.pixPayload,
          pixQrCode: (qrCode != null && qrCode.isNotEmpty)
              ? qrCode
              : state.pixQrCode,
        ),
      );

      // Se era pending_payment e agora temos o PIX, podemos considerar que o usuário vai pagar.
      // Mas o status real da viagem só muda no DB via Webhook.

      _pixConsecutiveFailures = 0;
      _pixRetryNotBefore = null;
    } catch (e) {
      debugPrint('❌ [TrackingCubit] Erro ao buscar PIX: $e');
      _pixConsecutiveFailures += 1;
      final cooldownSeconds = (_pixConsecutiveFailures >= 3) ? 30 : 20;
      _pixRetryNotBefore = DateTime.now().add(
        Duration(seconds: cooldownSeconds),
      );
    } finally {
      if (!silent) {
        emit(state.copyWith(isLoadingPix: false));
      }
      _syncPixAutoRefresh();
    }
  }

  Future<void> retryPixData() async {
    await _fetchPixData(force: true);
  }

  Future<Map<String, dynamic>> simulatePixPaid() async {
    final result = await _uberService.simulatePixPaid(tripId);
    if (result['success'] == true) {
      final nextTripData = <String, dynamic>{
        ...?state.tripData,
        'payment_status': 'paid',
        'payment_method_id': 'pix',
      };
      emit(state.copyWith(tripData: nextTripData, isPaid: true));
      await _loadInitialTripData();
    }
    return result;
  }

  bool _isPixTrip() {
    final paymentMethod =
        (state.tripData?['payment_method']?.toString() ??
                state.tripData?['payment_method_id']?.toString() ??
                '')
            .toUpperCase();
    if (paymentMethod.contains('PIX_DIRECT') ||
        (paymentMethod.contains('PIX') && paymentMethod.contains('DIRETO'))) {
      return false; // PIX direto ao motorista não usa PIX da plataforma
    }
    return paymentMethod.contains('PIX') || paymentMethod.isEmpty;
  }

  bool _shouldAutoRefreshPix() {
    if (!_isPixTrip()) return false;
    if (state.isPaid) return false;
    // Se já temos o payload, não precisa atualizar
    if (state.pixPayload != null && state.pixPayload!.trim().isNotEmpty) {
      return false;
    }
    return true;
  }

  void _syncPixAutoRefresh() {
    if (_shouldAutoRefreshPix()) {
      _pixAutoRefreshTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        if (isClosed) return;
        if (state.isLoadingPix) return;
        _fetchPixData(silent: true);
      });
      return;
    }
    _pixAutoRefreshTimer?.cancel();
    _pixAutoRefreshTimer = null;
  }

  void _updateLocations(Map<String, dynamic> data) {
    ll.LatLng? pickupLocation = state.pickupLocation;
    ll.LatLng? dropoffLocation = state.dropoffLocation;

    if (data['pickup_lat'] != null && data['pickup_lon'] != null) {
      pickupLocation = ll.LatLng(
        double.parse(data['pickup_lat'].toString()),
        double.parse(data['pickup_lon'].toString()),
      );
    }

    if (data['dropoff_lat'] != null && data['dropoff_lon'] != null) {
      dropoffLocation = ll.LatLng(
        double.parse(data['dropoff_lat'].toString()),
        double.parse(data['dropoff_lon'].toString()),
      );
    }

    emit(
      state.copyWith(
        pickupLocation: pickupLocation,
        dropoffLocation: dropoffLocation,
      ),
    );
  }

  void _handleDriverAssignment(Map<String, dynamic> data) {
    debugPrint(
      '🔔 [TrackingCubit] Status: ${state.status} | ProviderID: ${data['driver_id']}',
    );
    if (data['driver_id'] != null) {
      if (state.driverProfile == null) {
        debugPrint(
          '🚕 [TrackingCubit] Prestador atribuído! Iniciando carregamento de perfil e localização.',
        );
        fetchDriverProfile(data['driver_id']);
      }
      _startWatchingDriverLocation(data['driver_id']);
    } else if (data['driver_id'] == null &&
        state.status == TripStatus.searching) {
      _resetDriverAssignmentState();
    }

    final driverWaitCancellation =
        state.status == TripStatus.searching &&
        data['driver_id'] == null &&
        (data['last_driver_cancellation_at']?.toString().trim().isNotEmpty ??
            false);

    if (driverWaitCancellation) {
      _handleDriverWaitCancellation(data);
    }
  }

  void _startWatchingDriverLocation(dynamic driverId) {
    if (_driverLocationSub != null) {
      debugPrint(
        '⚠️ [TrackingCubit] Já existe uma inscrição ativa para localização do prestador.',
      );
      return;
    }

    debugPrint(
      '📡 [TrackingCubit] Iniciando watchDriverLocation para o prestador: $driverId',
    );
    _driverLocationSub = _uberService.watchDriverLocation(driverId).listen((
      snapshot,
    ) {
      if (snapshot.isNotEmpty) {
        final data = snapshot.first;
        // debugPrint('📍 [TrackingCubit] Nova localização recebida do DB para motorista $driverId');
        final rawLocation = ll.LatLng(
          double.parse(data['latitude'].toString()),
          double.parse(data['longitude'].toString()),
        );

        _updateDriverLocation(rawLocation, data);
      } else {
        debugPrint(
          '❓ [TrackingCubit] Snapshot de localização vazio para o prestador $driverId',
        );
      }
    });
  }

  void _updateDriverLocation(ll.LatLng rawLocation, Map<String, dynamic> data) {
    final newLocation = NavigationHelpers.snapLocationToRoute(
      rawLocation: rawLocation,
      route: _activeRouteForSnap(),
      maxDistanceMeters: _snapMaxDistanceMeters(),
    );

    final backendSpeed = NavigationHelpers.safeDouble(data['speed']) ?? 0.0;
    double newBearing = state.bearing;

    if (state.driverLocation != null) {
      final course = NavigationMath.courseBetween(
        from: state.driverLocation!,
        to: newLocation,
        minDistanceMeters: state.tuning.courseMinDistanceMeters,
      );

      final backendHeading = NavigationHelpers.safeDouble(data['heading']);
      final preferCourse =
          backendSpeed >= state.tuning.courseSpeedThresholdMps ||
          course != null;
      final targetBearing = preferCourse
          ? (course ?? backendHeading)
          : (backendHeading ?? course);

      if (targetBearing != null) {
        final alpha = backendSpeed >= 8.0
            ? state.tuning.headingSmoothingFast
            : (backendSpeed >= 3.0
                  ? state.tuning.headingSmoothingCruise
                  : state.tuning.headingSmoothingLowSpeed);
        newBearing = NavigationMath.lerpAngleDegrees(
          state.bearing,
          targetBearing,
          alpha,
        );
      }
    }

    emit(
      state.copyWith(
        previousLocation: state.driverLocation,
        driverLocation: newLocation,
        bearing: newBearing,
        speed: backendSpeed,
      ),
    );

    // debugPrint('🚗 [TrackingCubit] Localização atualizada: ${newLocation.latitude}, ${newLocation.longitude} | Bearing: $newBearing');

    // MÁGICA: Buscar Rota Motorista -> Passageiro
    if (!_hasFetchedPickupRoute && state.pickupLocation != null) {
      _hasFetchedPickupRoute = true;
      Future.microtask(() async {
        try {
          final pickupRes = await MapService().getRoute(
            newLocation,
            state.pickupLocation!,
          );
          if (isClosed) return;
          final List<ll.LatLng> points = pickupRes['points'] as List<ll.LatLng>;
          if (points.isNotEmpty) {
            emit(state.copyWith(driverToPickupPoints: points));
          }
        } catch (e) {
          debugPrint('❌ Erro ao buscar rota de pickup no Cubit: $e');
        }
      });
    }

    // MÁGICA: Buscar Rota Passageiro -> Destino
    if (!_hasFetchedDropoffRoute &&
        state.pickupLocation != null &&
        state.dropoffLocation != null) {
      _hasFetchedDropoffRoute = true;
      Future.microtask(() async {
        try {
          final dropoffRes = await MapService().getRoute(
            state.pickupLocation!,
            state.dropoffLocation!,
          );
          if (isClosed) return;
          final List<ll.LatLng> points =
              dropoffRes['points'] as List<ll.LatLng>;
          if (points.isNotEmpty) {
            emit(state.copyWith(pickupToDropoffPoints: points));
          }
        } catch (e) {
          debugPrint('❌ Erro ao buscar rota de destino no Cubit: $e');
        }
      });
    }

    _checkProximity();
  }

  Future<void> fetchDriverProfile(dynamic driverIdRaw) async {
    // driver_id pode ser UUID (String) ou int legado — ambos são válidos
    final driverId = driverIdRaw?.toString().trim();
    if (driverId == null || driverId.isEmpty || state.isLoadingDriver) return;

    emit(state.copyWith(isLoadingDriver: true));

    try {
      final res = await _uberService.getTripPartyProfile(
        tripId: tripId,
        partyRole: 'driver',
      );

      if (res != null) {
        final mergedProfile = Map<String, dynamic>.from(res);
        final fullName = mergedProfile['full_name']?.toString() ?? 'Motorista';
        mergedProfile['first_name'] = fullName.split(' ').first;
        mergedProfile['rating'] = 5.0;

        // Garante que o avatar_url venha do perfil operacional carregado
        if (mergedProfile['avatar_url'] == null &&
            mergedProfile['profile_image'] != null) {
          mergedProfile['avatar_url'] = mergedProfile['profile_image'];
        }

        final vehicleModel =
            mergedProfile['vehicle_model']?.toString().trim() ?? 'Veículo';
        final vehicleColor =
            mergedProfile['vehicle_color']?.toString().trim() ?? '';
        mergedProfile['vehicle_model'] = vehicleColor.isNotEmpty
            ? '$vehicleModel - $vehicleColor'
            : vehicleModel;
        mergedProfile['vehicle_plate'] =
            mergedProfile['vehicle_plate']?.toString().trim().isNotEmpty == true
            ? mergedProfile['vehicle_plate']
            : '---';

        emit(state.copyWith(driverProfile: mergedProfile));
      }
    } catch (e) {
      debugPrint('Erro ao buscar perfil do prestador: $e');
    } finally {
      emit(state.copyWith(isLoadingDriver: false));
    }
  }

  Future<void> cancelTrip(String reason) async {
    try {
      await _uberService.cancelTripByClient(tripId, reason: reason);
    } catch (e) {
      debugPrint('Erro ao cancelar viagem: $e');
    }
  }

  void updateTracking(bool isTracking) {
    emit(state.copyWith(isTracking: isTracking));
  }

  void updateAlerts({bool? alert500m, bool? alert100m, bool? alertArrived}) {
    emit(
      state.copyWith(
        alert500mShow: alert500m ?? state.alert500mShow,
        alert100mShow: alert100m ?? state.alert100mShow,
        alertArrivedShow: alertArrived ?? state.alertArrivedShow,
      ),
    );
  }

  void updateRating(bool hasRated) {
    emit(state.copyWith(hasRated: hasRated));
  }

  void updatePaymentProcessing(bool isProcessing) {
    emit(state.copyWith(isPaymentProcessing: isProcessing));
  }

  void updatePaid(bool isPaid) {
    emit(state.copyWith(isPaid: isPaid));
  }

  Future<Map<String, dynamic>> resolvePaymentMethodDetails(
    String methodId,
  ) async {
    return _uberService.resolvePaymentMethodDetails(methodId);
  }

  Future<void> submitCVV(String cvv) async {
    if (cvv.length < 3) return;

    emit(state.copyWith(isPaymentProcessing: true));
    try {
      final res = await _uberService.processCardPayment(
        tripId: tripId,
        securityCode: cvv,
      );

      if (res['success'] == true) {
        // O backend resetará a flag payment_requires_cvv no DB
        emit(
          state.copyWith(
            requiresCVV: false,
            isPaid: true,
            isPaymentProcessing: false,
          ),
        );
      } else {
        // Se falhar de novo, mantém flag ou mostra erro
        emit(state.copyWith(isPaymentProcessing: false));
        final error = res['error'] ?? 'Falha ao processar CVV.';
        throw Exception(error);
      }
    } catch (e) {
      emit(state.copyWith(isPaymentProcessing: false));
      rethrow;
    }
  }

  @override
  Future<void> close() {
    _driverLocationSub?.cancel();
    _tripSub?.cancel();
    _waitTimer?.cancel();
    _pulseFeedbackTimer?.cancel();
    _pixAutoRefreshTimer?.cancel();
    return super.close();
  }

  // Private helpers
  TripStatus _mapStatus(String status) {
    final normalized = normalizeServiceStatus(status);
    switch (normalized) {
      // Serviços (service_requests_new) - mapeamento para o mesmo state machine
      case 'waiting_payment':
      case 'waiting_payment_upfront':
      case 'waiting_payment_entry':
      case 'awaiting_payment':
      case 'pending_payment':
        return TripStatus.pending_payment;
      case ServiceStatusAliases.searchingProvider:
      case ServiceStatusAliases.searchProvider:
      case ServiceStatusAliases.waitingProvider:
      case TripStatuses.searching:
      case 'search_driver':
        return TripStatus.searching;
      case TripStatuses.accepted:
      case 'driver_found':
        return TripStatus.accepted;
      case 'on_the_way':
      case 'on_way':
      case 'a_caminho':
      case 'driver_en_route':
        return TripStatus.driverEnRoute;
      case TripStatuses.arrived:
      case 'chegou':
        return TripStatus.arrived;
      case TripStatuses.inProgress:
      case 'started':
        return TripStatus.inProgress;
      case TripStatuses.completed:
      case 'finished':
        return TripStatus.completed;
      case TripStatuses.cancelled:
      case TripStatuses.canceled:
        return TripStatus.cancelled;
      case 'no_providers':
      case 'no_drivers':
        return TripStatus.noDrivers;
      default:
        return TripStatus.searching;
    }
  }

  TripStatus _resolveStatusFromTrip(Map<String, dynamic> trip) {
    final rawStatus = trip['status']?.toString() ?? '';
    final hasCompletedAt = trip['completed_at'] != null;
    final paymentStatus = trip['payment_status']
        ?.toString()
        .trim()
        .toLowerCase();

    // Fallback defensivo:
    // se o backend já marcou finalização temporal, forçamos completed
    // mesmo que o campo status venha inconsistente/atrasado.
    if (hasCompletedAt) return TripStatus.completed;
    if (paymentStatus == 'paid' &&
        rawStatus.trim().toLowerCase() == 'completed') {
      return TripStatus.completed;
    }

    return _mapStatus(rawStatus);
  }

  List<ll.LatLng> _activeRouteForSnap() {
    if (state.currentRouteMode == 'to_pickup' &&
        state.driverToPickupPoints.isNotEmpty) {
      return state.driverToPickupPoints;
    }
    return state.pickupToDropoffPoints;
  }

  double _snapMaxDistanceMeters() {
    return state.navigationProfile == NavigationProfile.highway ? 55.0 : 35.0;
  }

  void _checkProximity() {
    if (state.driverLocation == null || state.tripData == null) return;
    if (![
      TripStatus.accepted,
      TripStatus.driverEnRoute,
      TripStatus.arrived,
      TripStatus.inProgress,
    ].contains(state.status)) {
      return;
    }

    final pickupLat = state.tripData!['pickup_lat'];
    final pickupLon = state.tripData!['pickup_lon'];
    if (pickupLat == null || pickupLon == null) return;

    final pickupLocation = ll.LatLng(
      double.parse(pickupLat.toString()),
      double.parse(pickupLon.toString()),
    );
    final distance = const ll.Distance().as(
      ll.LengthUnit.Meter,
      state.driverLocation!,
      pickupLocation,
    );

    emit(state.copyWith(distanceToPickup: distance.toDouble()));

    if (distance <= 500 && !_hasTriggered500m) {
      _hasTriggered500m = true;
      emit(state.copyWith(alert500mShow: true));
      Future.delayed(const Duration(seconds: 5), () {
        emit(state.copyWith(alert500mShow: false));
      });
    } else if (distance <= 50 && !_hasTriggered100m) {
      _hasTriggered100m = true;
      emit(state.copyWith(alert100mShow: true));
      Future.delayed(const Duration(seconds: 5), () {
        emit(state.copyWith(alert100mShow: false));
      });
    }

    if ((distance <= 30 || state.status == TripStatus.arrived) &&
        !_hasTriggeredArrived) {
      _hasTriggeredArrived = true;
      emit(state.copyWith(alertArrivedShow: true));
    }
  }

  void checkProximityToDestination(ll.LatLng currentPosition) {
    if (state.driverLocation == null) return;

    final dropoffLat = state.tripData?['dropoff_lat'];
    final dropoffLon = state.tripData?['dropoff_lon'];

    if (dropoffLat != null && dropoffLon != null) {
      final dropoffLocation = ll.LatLng(
        double.parse(dropoffLat.toString()),
        double.parse(dropoffLon.toString()),
      );

      // Distância em metros
      final distanceToDropoff = const ll.Distance().as(
        ll.LengthUnit.Meter,
        state.driverLocation!,
        dropoffLocation,
      );

      // Regra: PIX direto com motorista é automático quando o motorista aceita PIX direto.
      // Não deve aparecer como opção separada; só mostramos o aviso perto de 500m do destino.
      final driverAcceptsPixDirect =
          state.driverProfile?['accepts_pix_direct'] == true;

      // Marcamos "perto do destino" num raio maior para ajustes de UI,
      // mas a geração do PIX via plataforma deve acontecer só bem próximo
      // do fim da corrida (configurável) para evitar PIX expirado/cancelado.
      if (distanceToDropoff <= 3000) {
        if (!state.isNearDestination) {
          emit(state.copyWith(isNearDestination: true));
          debugPrint('🎯 Proximidade do destino detectada (<3km)');
        }

        // Se for PIX e ainda não tiver os dados, busca agora
        if (state.status == TripStatus.inProgress) {
          final data = state.tripData;
          if (data != null) {
            final paymentMethodLabel =
                (data['payment_method'] ?? data['payment_method_id'] ?? '')
                    .toString()
                    .toUpperCase();

            final isPix =
                paymentMethodLabel.contains('PIX') &&
                !paymentMethodLabel.contains('DIRETO') &&
                !paymentMethodLabel.contains('CARD') &&
                !paymentMethodLabel.contains('CART');

            final wantsPixDirectWithDriver = driverAcceptsPixDirect && isPix;
            if (state.usePixDirectWithDriver != wantsPixDirectWithDriver) {
              emit(
                state.copyWith(
                  usePixDirectWithDriver: wantsPixDirectWithDriver,
                ),
              );
            }

            // Aviso perto de 500m do destino (somente se PIX direto com motorista).
            final shouldShowPixDirectPrompt =
                wantsPixDirectWithDriver && distanceToDropoff <= 500;
            if (state.showPixDirectPaymentPrompt != shouldShowPixDirectPrompt) {
              emit(
                state.copyWith(
                  showPixDirectPaymentPrompt: shouldShowPixDirectPrompt,
                ),
              );
            }

            // Gera o PIX somente quando estiver realmente chegando (ex.: <= 500m).
            final pixRadiusM = _appConfig.pixGenerateRadiusMeters;
            final shouldGeneratePlatformPixNow =
                distanceToDropoff <= pixRadiusM;

            if (shouldGeneratePlatformPixNow &&
                paymentMethodLabel.contains('PIX') &&
                !paymentMethodLabel.contains('PIX_DIRECT') &&
                !paymentMethodLabel.contains('DIRETO') &&
                !wantsPixDirectWithDriver &&
                state.pixPayload == null &&
                !_hasTriggeredPixGeneration &&
                !state.isLoadingPix) {
              _hasTriggeredPixGeneration = true;
              _fetchPixData();
            }
          }
        }
      } else {
        if (state.isNearDestination) {
          emit(state.copyWith(isNearDestination: false));
        }
        if (state.usePixDirectWithDriver || state.showPixDirectPaymentPrompt) {
          emit(
            state.copyWith(
              usePixDirectWithDriver: false,
              showPixDirectPaymentPrompt: false,
            ),
          );
        }
      }
    }
  }

  void _startWaitTimer(Map<String, dynamic> data) {
    _stopWaitTimer();
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.tripData?['arrived_at'] == null) return;

      final arrivedAtDateTime = DateTime.tryParse(
        state.tripData!['arrived_at'],
      );
      if (arrivedAtDateTime != null) {
        final elapsed = DateTime.now()
            .toUtc()
            .difference(arrivedAtDateTime.toUtc())
            .inSeconds;
        emit(state.copyWith(waitingSeconds: elapsed));
      }
    });
  }

  void _stopWaitTimer() {
    _waitTimer?.cancel();
    _waitTimer = null;
  }

  void _resetDriverAssignmentState() {
    _driverLocationSub?.cancel();
    _driverLocationSub = null;
    _hasFetchedPickupRoute = false;
    _hasFetchedDropoffRoute = false;
    emit(
      state.copyWith(
        driverLocation: null,
        previousLocation: null,
        driverProfile: null,
        distanceToPickup: null,
        currentRouteMode: 'none',
      ),
    );
  }

  void _handleDriverWaitCancellation(Map<String, dynamic> tripData) {
    final cancellationAt = tripData['last_driver_cancellation_at']
        ?.toString()
        .trim();
    if (cancellationAt == null || cancellationAt.isEmpty) return;
    if (_lastHandledDriverCancellationAt == cancellationAt) return;

    _lastHandledDriverCancellationAt = cancellationAt;
    _resetDriverAssignmentState();
  }

  void _handleMissingTrip() {
    if (_missingTripHandled) return;
    _missingTripHandled = true;
    _stopWaitTimer();
  }
}
