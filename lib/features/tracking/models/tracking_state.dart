import 'package:latlong2/latlong.dart' as ll;
import '../utils/navigation_tuning.dart';

enum NavigationProfile { urban, highway }
// ignore: constant_identifier_names
enum TripStatus { searching, accepted, driverEnRoute, arrived, inProgress, completed, cancelled, noDrivers, pending_payment }

class TrackingState {
  final String tripId;
  final Map<String, dynamic>? tripData;
  final bool isService;
  final TripStatus status;
  final ll.LatLng? driverLocation;
  final ll.LatLng? previousLocation;
  final ll.LatLng? pickupLocation;
  final ll.LatLng? dropoffLocation;
  final List<ll.LatLng> pickupToDropoffPoints;
  final List<ll.LatLng> driverToPickupPoints;
  final double? dropoffDistanceKm;
  final double? dropoffDurationMin;
  final String currentRouteMode;
  final double bearing;
  final NavigationProfile navigationProfile;
  final NavigationTuning tuning;
  final Map<String, dynamic>? driverProfile;
  final bool isLoadingDriver;
  final bool isTracking;
  final double? distanceToPickup;
  final int waitingSeconds;
  final bool alert500mShow;
  final bool alert100mShow;
  final bool alertArrivedShow;
  final bool isPaid;
  final bool hasRated;
  final bool isLoading;
  final bool tripLoadError;
  final bool showPulse;
  final bool isPaymentProcessing;
  final double speed;
  final String? pixPayload;
  final String? pixQrCode;
  final bool isLoadingPix;

  final bool requiresCVV;
  final bool isNearDestination;
  final bool usePixDirectWithDriver;
  final bool showPixDirectPaymentPrompt;

  TrackingState({
    required this.tripId,
    this.tripData,
    this.isService = false,
    this.status = TripStatus.searching,
    this.driverLocation,
    this.previousLocation,
    this.pickupLocation,
    this.dropoffLocation,
    this.pickupToDropoffPoints = const [],
    this.driverToPickupPoints = const [],
    this.dropoffDistanceKm,
    this.dropoffDurationMin,
    this.currentRouteMode = 'none',
    this.bearing = 0.0,
    this.navigationProfile = NavigationProfile.urban,
    NavigationTuning? tuning,
    this.driverProfile,
    this.isLoadingDriver = false,
    this.isTracking = true,
    this.distanceToPickup,
    this.waitingSeconds = 0,
    this.alert500mShow = false,
    this.alert100mShow = false,
    this.alertArrivedShow = false,
    this.isPaid = false,
    this.hasRated = false,
    this.isLoading = false,
    this.requiresCVV = false,
    this.tripLoadError = false,
    this.showPulse = false,
    this.isPaymentProcessing = false,
    this.speed = 0.0,
    this.pixPayload,
    this.pixQrCode,
    this.isLoadingPix = false,
    this.isNearDestination = false,
    this.usePixDirectWithDriver = false,
    this.showPixDirectPaymentPrompt = false,
  }) : tuning = tuning ?? NavigationTuning.urban;

  TrackingState copyWith({
    Map<String, dynamic>? tripData,
    bool? isService,
    TripStatus? status,
    ll.LatLng? driverLocation,
    ll.LatLng? previousLocation,
    ll.LatLng? pickupLocation,
    ll.LatLng? dropoffLocation,
    List<ll.LatLng>? pickupToDropoffPoints,
    List<ll.LatLng>? driverToPickupPoints,
    double? dropoffDistanceKm,
    double? dropoffDurationMin,
    String? currentRouteMode,
    double? bearing,
    NavigationProfile? navigationProfile,
    NavigationTuning? tuning,
    Map<String, dynamic>? driverProfile,
    bool? isLoadingDriver,
    bool? isTracking,
    double? distanceToPickup,
    int? waitingSeconds,
    bool? alert500mShow,
    bool? alert100mShow,
    bool? alertArrivedShow,
    bool? isPaid,
    bool? hasRated,
    bool? isLoading,
    bool? requiresCVV,
    bool? tripLoadError,
    bool? showPulse,
    bool? isPaymentProcessing,
    double? speed,
    String? pixPayload,
    String? pixQrCode,
    bool? isLoadingPix,
    bool? isNearDestination,
    bool? usePixDirectWithDriver,
    bool? showPixDirectPaymentPrompt,
  }) {
    return TrackingState(
      tripId: tripId,
      tripData: tripData ?? this.tripData,
      isService: isService ?? this.isService,
      status: status ?? this.status,
      driverLocation: driverLocation ?? this.driverLocation,
      previousLocation: previousLocation ?? this.previousLocation,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      dropoffLocation: dropoffLocation ?? this.dropoffLocation,
      pickupToDropoffPoints: pickupToDropoffPoints ?? this.pickupToDropoffPoints,
      driverToPickupPoints: driverToPickupPoints ?? this.driverToPickupPoints,
      dropoffDistanceKm: dropoffDistanceKm ?? this.dropoffDistanceKm,
      dropoffDurationMin: dropoffDurationMin ?? this.dropoffDurationMin,
      currentRouteMode: currentRouteMode ?? this.currentRouteMode,
      bearing: bearing ?? this.bearing,
      navigationProfile: navigationProfile ?? this.navigationProfile,
      tuning: tuning ?? this.tuning,
      driverProfile: driverProfile ?? this.driverProfile,
      isLoadingDriver: isLoadingDriver ?? this.isLoadingDriver,
      isTracking: isTracking ?? this.isTracking,
      distanceToPickup: distanceToPickup ?? this.distanceToPickup,
      waitingSeconds: waitingSeconds ?? this.waitingSeconds,
      alert500mShow: alert500mShow ?? this.alert500mShow,
      alert100mShow: alert100mShow ?? this.alert100mShow,
      alertArrivedShow: alertArrivedShow ?? this.alertArrivedShow,
      isPaid: isPaid ?? this.isPaid,
      hasRated: hasRated ?? this.hasRated,
      isLoading: isLoading ?? this.isLoading,
      requiresCVV: requiresCVV ?? this.requiresCVV,
      tripLoadError: tripLoadError ?? this.tripLoadError,
      showPulse: showPulse ?? this.showPulse,
      isPaymentProcessing: isPaymentProcessing ?? this.isPaymentProcessing,
      speed: speed ?? this.speed,
      pixPayload: pixPayload ?? this.pixPayload,
      pixQrCode: pixQrCode ?? this.pixQrCode,
      isLoadingPix: isLoadingPix ?? this.isLoadingPix,
      isNearDestination: isNearDestination ?? this.isNearDestination,
      usePixDirectWithDriver:
          usePixDirectWithDriver ?? this.usePixDirectWithDriver,
      showPixDirectPaymentPrompt:
          showPixDirectPaymentPrompt ?? this.showPixDirectPaymentPrompt,
    );
  }
}
