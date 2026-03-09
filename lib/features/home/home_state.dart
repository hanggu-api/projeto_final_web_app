import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

mixin HomeStateMixin<T extends StatefulWidget> on State<T> {
  // --- MAP & LOCATION ---
  final MapController mapController = MapController();
  LatLng currentPosition = const LatLng(-5.5262, -47.4746);
  bool isMapReady = false;
  bool isLocating = false;
  String? locationError;

  // --- TRIP MODE (CLIENT) ---
  bool isInTripMode = false;
  bool isSearchExpanded = false;
  bool isPickingOnMap = false;
  bool isMapAnimating = false;

  LatLng? pickupLocation;
  LatLng? dropoffLocation;
  LatLng? pickedLocation;

  final TextEditingController pickupController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();
  final FocusNode pickupFocus = FocusNode();
  final FocusNode destinationFocus = FocusNode();

  List<dynamic> searchResults = [];
  bool isSearching = false;

  List<LatLng> routePolyline = [];
  List<LatLng> arrivalPolyline = []; // Rota Verde (Motorista -> Pickup)
  String? routeDistance;
  String? routeDuration;

  Map<String, dynamic>? fareEstimate = {};
  final Map<int, dynamic> fareEstimatesByVehicle = {};
  int selectedVehicleTypeId = 1; // Default
  String selectedPaymentMethod = 'PIX';
  bool isRequestingTrip = false;

  // --- ACTIVE TRIP ---
  Map<String, dynamic>? activeTrip;
  String? activeTripStatus;
  StreamSubscription? tripSubscription;
  StreamSubscription? driverLocationSubscription;
  double? distanceToDriver;
  LatLng? driverLatLng;

  // --- SERVICE MODE (AI / TASK) ---
  bool isInServiceMode = false;
  final TextEditingController servicePromptController = TextEditingController();
  bool isServiceAiClassifying = false;

  String? aiProfessionName;
  String? aiTaskName;
  double? aiTaskPrice;
  String? aiServiceType;

  bool isLoadingServiceCandidates = false;
  bool isCreatingService = false;
  List<Map<String, dynamic>> serviceCandidates = [];
  int? aiCategoryId;
  Timer? serviceAiDebounce;

  // --- SERVICES LIST & NOTIFICATIONS ---
  List<dynamic> servicesList = [];
  bool isLoadingServices = true;
  Map<String, String> lastStatuses = {};
  int unreadCountCount = 0;
  final List<Map<String, dynamic>> notificationsList = [];
  late AnimationController bellController;

  Timer? refreshTimer;
  Timer? debouncer;

  // --- VEHICLE TYPES ---
  final List<Map<String, dynamic>> vehicleTypesList = [
    {
      'id': 1,
      'name': 'economic',
      'display_name': 'Carro',
      'icon': Icons.directions_car,
      'asset': 'assets/icons/036-car.png',
    },
    {
      'id': 3,
      'name': 'moto',
      'display_name': 'Moto',
      'icon': Icons.directions_bike,
      'asset': 'assets/icons/034-motorbike.png',
    },
  ];

  // --- SAVED PLACES ---
  List<Map<String, dynamic>> savedPlacesList = [];

  // --- DISPOSE LOGIC ---
  void disposeHomeState() {
    bellController.dispose();
    refreshTimer?.cancel();
    debouncer?.cancel();
    pickupController.dispose();
    destinationController.dispose();
    servicePromptController.dispose();
    pickupFocus.dispose();
    destinationFocus.dispose();
    tripSubscription?.cancel();
    driverLocationSubscription?.cancel();
    serviceAiDebounce?.cancel();
  }
}
