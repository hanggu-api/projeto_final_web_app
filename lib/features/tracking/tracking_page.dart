import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:latlong2/latlong.dart' as ll;
import 'package:service_101/core/config/supabase_config.dart';
import 'package:service_101/core/maps/app_tile_layer.dart';
import 'package:service_101/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/api_service.dart';
import '../../services/central_service.dart';
import '../shared/chat/open_chat_helper.dart';
import 'widgets/service_header.dart';
import 'widgets/service_panel_content.dart';
import 'cubit/tracking_cubit.dart';
import 'models/tracking_state.dart';
import 'services/map_manager.dart';
import 'widgets/cancel_reason_sheet.dart';
import 'widgets/map_controls.dart';
import 'widgets/proximity_alerts.dart';
import 'widgets/rating_modal.dart';

class TrackingPage extends StatelessWidget {
  final String serviceId;

  const TrackingPage({super.key, required this.serviceId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TrackingCubit(
        tripId: serviceId,
        uberService: CentralService(),
        apiService: ApiService(),
      )..initialize(),
      child: TrackingView(serviceId: serviceId),
    );
  }
}

class TrackingView extends StatefulWidget {
  final String serviceId;
  const TrackingView({super.key, required this.serviceId});

  @override
  State<TrackingView> createState() => _TrackingViewState();
}

class _TrackingViewState extends State<TrackingView> {
  final MapManager _mapManager = MapManager();
  bool _isMapReady = false;
  bool _hasPromptedPassengerRating = false;
  bool _isShowingPassengerRating = false;

  Timer? _carAnimationTimer;
  ll.LatLng? _animatedCarPosition;
  double _animatedCarBearing = 0.0;

  Offset? _carPixelPosition;
  Offset? _pickupPixelPosition;
  Offset? _dropoffPixelPosition;

  @override
  void initState() {
    super.initState();
    _startSmoothCarAnimation();
  }

  @override
  void dispose() {
    _carAnimationTimer?.cancel();
    _mapManager.dispose();
    super.dispose();
  }

  void _startSmoothCarAnimation() {
    const duration = Duration(milliseconds: 100);
    _carAnimationTimer?.cancel();
    _carAnimationTimer = Timer.periodic(duration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final state = context.read<TrackingCubit>().state;
      final targetPos = state.driverLocation;
      final targetBearing = state.bearing;

      if (targetPos == null) return;

      setState(() {
        if (_animatedCarPosition == null) {
          _animatedCarPosition = targetPos;
          _animatedCarBearing = targetBearing;
        } else {
          final lerpLat =
              _animatedCarPosition!.latitude +
              (targetPos.latitude - _animatedCarPosition!.latitude) * 0.2;
          final lerpLng =
              _animatedCarPosition!.longitude +
              (targetPos.longitude - _animatedCarPosition!.longitude) * 0.2;
          _animatedCarPosition = ll.LatLng(lerpLat, lerpLng);

          double diff = targetBearing - _animatedCarBearing;
          while (diff < -180) diff += 360;
          while (diff > 180) diff -= 360;
          _animatedCarBearing += diff * 0.15;
        }

        if (state.isTracking) {
          _mapManager.lockCameraToCar(
            location: _animatedCarPosition!,
            bearing: _animatedCarBearing,
          );
        }

        _updatePixelPositions(state);
      });
    });
  }

  Future<void> _updatePixelPositions(TrackingState state) async {
    if (!_isMapReady || _mapManager.mapboxMap == null) return;

    Offset? carPos;
    Offset? pickupPos;
    Offset? dropoffPos;

    if (_animatedCarPosition != null) {
      try {
        final pixel = await _mapManager.mapboxMap!.pixelForCoordinate(
          mapbox.Point(
            coordinates: mapbox.Position(
              _animatedCarPosition!.longitude,
              _animatedCarPosition!.latitude,
            ),
          ),
        );
        carPos = Offset(pixel.x.toDouble(), pixel.y.toDouble());
      } catch (_) {}
    }

    if (state.pickupLocation != null) {
      try {
        final pixel = await _mapManager.mapboxMap!.pixelForCoordinate(
          mapbox.Point(
            coordinates: mapbox.Position(
              state.pickupLocation!.longitude,
              state.pickupLocation!.latitude,
            ),
          ),
        );
        pickupPos = Offset(pixel.x.toDouble(), pixel.y.toDouble());
      } catch (_) {}
    }

    if (state.dropoffLocation != null) {
      try {
        final pixel = await _mapManager.mapboxMap!.pixelForCoordinate(
          mapbox.Point(
            coordinates: mapbox.Position(
              state.dropoffLocation!.longitude,
              state.dropoffLocation!.latitude,
            ),
          ),
        );
        dropoffPos = Offset(pixel.x.toDouble(), pixel.y.toDouble());
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _carPixelPosition = carPos;
        _pickupPixelPosition = pickupPos;
        _dropoffPixelPosition = dropoffPos;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TrackingCubit, TrackingState>(
      listener: (context, state) {
        if (state.status == TripStatus.cancelled) {
          context.go('/home');
          return;
        }

        if (state.status == TripStatus.completed &&
            !_hasPromptedPassengerRating &&
            !state.hasRated) {
          _hasPromptedPassengerRating = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showPassengerRatingModal();
          });
        }

        if (state.requiresCVV && !state.isPaid && !state.isPaymentProcessing) {
          _showCVVAuthDialog(context);
        }

        _mapManager.drawRoute(
          state.currentRouteMode == 'to_pickup'
              ? state.driverToPickupPoints
              : state.pickupToDropoffPoints,
          state.currentRouteMode == 'to_pickup'
              ? Colors.green
              : AppTheme.primaryBlue,
          state.driverLocation,
        );
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              if (kIsWeb)
                _buildWebTrackingMap(state)
              else
                mapbox.MapWidget(
                  key: const ValueKey('mapbox_tracking'),
                  onMapCreated: (map) async {
                    await _mapManager.initializeMap(map);
                    setState(() => _isMapReady = true);
                  },
                  onStyleLoadedListener: (styleLoadedEvent) {
                    _mapManager.onStyleLoaded();
                  },
                  cameraOptions: mapbox.CameraOptions(
                    center: mapbox.Point(
                      coordinates: mapbox.Position(
                        state.pickupLocation?.longitude ??
                            state.driverLocation?.longitude ??
                            -47.4747,
                        state.pickupLocation?.latitude ??
                            state.driverLocation?.latitude ??
                            -5.5262,
                      ),
                    ),
                    zoom: 15.5,
                    pitch: 60.0,
                  ),
                  styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
                  onScrollListener: (gestureContext) {
                    if (state.isTracking) {
                      context.read<TrackingCubit>().updateTracking(false);
                    }
                  },
                ),

              if (!kIsWeb && _isMapReady) ...[
                if (_animatedCarPosition != null && _carPixelPosition != null)
                  Positioned(
                    left: _carPixelPosition!.dx - 18,
                    top: _carPixelPosition!.dy - 18,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryPurple,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryPurple.withOpacity(0.35),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          LucideIcons.user,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),

                if (_pickupPixelPosition != null)
                  Positioned(
                    left: _pickupPixelPosition!.dx - 15,
                    top: _pickupPixelPosition!.dy - 15,
                    child: const Icon(
                      LucideIcons.mapPin,
                      color: Colors.blueAccent,
                      size: 30,
                    ),
                  ),

                if (_dropoffPixelPosition != null)
                  Positioned(
                    left: _dropoffPixelPosition!.dx - 15,
                    top: _dropoffPixelPosition!.dy - 15,
                    child: const Icon(
                      LucideIcons.flag,
                      color: Colors.redAccent,
                      size: 30,
                    ),
                  ),
              ],

              const ServiceHeader(),

              MapControls(
                onZoomIn: _mapManager.zoomIn,
                onZoomOut: _mapManager.zoomOut,
                onRecenter: () {
                  context.read<TrackingCubit>().updateTracking(true);
                  if (_animatedCarPosition != null) {
                    _mapManager.lockCameraToCar(
                      location: _animatedCarPosition!,
                      bearing: _animatedCarBearing,
                    );
                  }
                },
                isTracking: state.isTracking,
              ),

              Builder(
                builder: (_) {
                  final trip = state.tripData;
                  final amountRaw =
                      trip?['fare_final'] ??
                      trip?['fare'] ??
                      trip?['fare_estimated'] ??
                      trip?['amount'] ??
                      0;
                  final amount = amountRaw is num
                      ? amountRaw.toDouble()
                      : double.tryParse(amountRaw.toString()) ?? 0.0;

                  return ProximityAlerts(
                    showAlert500m: state.alert500mShow,
                    showAlert100m: state.alert100mShow,
                    showAlertArrived: state.alertArrivedShow,
                    showPixDirectPaymentPrompt:
                        state.showPixDirectPaymentPrompt,
                    pixDirectAmountLabel: 'R\$ ${amount.toStringAsFixed(2)}',
                  );
                },
              ),

              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 20,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.62,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Flexible(
                            fit: FlexFit.loose,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                              child: ServicePanelContent(
                                state: state,
                                onCall: () async {
                                  final phone = state.driverProfile?['phone'];
                                  if (phone != null) {
                                    final url = 'tel:$phone';
                                    if (await canLaunchUrl(Uri.parse(url))) {
                                      await launchUrl(Uri.parse(url));
                                    }
                                  }
                                },
                                onMessage: () {
                                  OpenChatHelper.push(
                                    context,
                                    serviceId: widget.serviceId,
                                    service: state.tripData,
                                    currentRole: 'client',
                                  );
                                },
                                onCancel: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (ctx) => CancelReasonSheet(
                                      onConfirm: (reason) {
                                        context
                                            .read<TrackingCubit>()
                                            .cancelTrip(reason);
                                      },
                                    ),
                                  );
                                },
                                onSimulatePixPaid: () async {
                                  final res = await context
                                      .read<TrackingCubit>()
                                      .simulatePixPaid();
                                  if (!context.mounted) return;
                                  final ok = res['success'] == true;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok
                                            ? 'PIX marcado como pago LOCALMENTE.'
                                            : (res['error']?.toString() ??
                                                  'Falha ao simular pagamento.'),
                                      ),
                                      backgroundColor: ok
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPassengerRatingModal() async {
    if (!mounted || _isShowingPassengerRating) return;
    final state = context.read<TrackingCubit>().state;
    final revieweeId = state.tripData?['driver_id']?.toString();
    if (revieweeId == null || revieweeId.isEmpty) return;
    _isShowingPassengerRating = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (modalContext) => RatingModal(
        tripId: widget.serviceId,
        onSkip: () {
          if (!mounted) return;
          context.go('/home');
        },
        onSubmit: (rating, comment) async {
          final cubit = context.read<TrackingCubit>();
          try {
            await CentralService().submitTripReview(
              tripId: widget.serviceId,
              revieweeId: revieweeId,
              rating: rating,
              comment: comment.trim().isEmpty ? null : comment.trim(),
            );
            if (!mounted || !modalContext.mounted) return;
            cubit.updateRating(true);
            Navigator.of(modalContext).pop();
            context.go('/home');
          } catch (e) {
            if (!mounted) return;
            context.go('/home');
          }
        },
      ),
    );
    _isShowingPassengerRating = false;
  }

  Widget _buildWebTrackingMap(TrackingState state) {
    final center =
        _animatedCarPosition ??
        state.driverLocation ??
        state.pickupLocation ??
        state.dropoffLocation ??
        ll.LatLng(-5.5262, -47.4747);

    final routePoints = state.currentRouteMode == 'to_pickup'
        ? state.driverToPickupPoints
        : state.pickupToDropoffPoints;

    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 15),
      children: [
        AppTileLayer.standard(mapboxToken: SupabaseConfig.mapboxToken),
        if (routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                strokeWidth: 5,
                color: state.currentRouteMode == 'to_pickup'
                    ? Colors.green
                    : AppTheme.primaryBlue,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (state.pickupLocation != null)
              Marker(
                point: state.pickupLocation!,
                width: 42,
                height: 42,
                child: const Icon(
                  LucideIcons.mapPin,
                  color: Colors.blueAccent,
                  size: 30,
                ),
              ),
            if (state.dropoffLocation != null)
              Marker(
                point: state.dropoffLocation!,
                width: 42,
                height: 42,
                child: const Icon(
                  LucideIcons.flag,
                  color: Colors.redAccent,
                  size: 30,
                ),
              ),
            if ((_animatedCarPosition ?? state.driverLocation) != null)
              Marker(
                point: _animatedCarPosition ?? state.driverLocation!,
                width: 46,
                height: 46,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.primaryYellow,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _showCVVAuthDialog(BuildContext context) async {
    debugPrint('🚩 [TrackingView] CVV Auth ignorado');
  }
}
