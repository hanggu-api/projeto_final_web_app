import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

mixin HomeStateMixin<T extends StatefulWidget> on State<T> {
  // --- CORE UI & STATE ---
  final MapController mapController = MapController();
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();
  final FocusNode pickupFocus = FocusNode();
  final FocusNode destinationFocus = FocusNode();
  
  bool isMapReady = false;
  LatLng currentPosition = const LatLng(-5.5262, -47.4747);
  List<LatLng> routePolyline = [];
  List<LatLng> arrivalPolyline = [];
  
  LatLng? pickupLocation;
  LatLng? dropoffLocation;

  // --- LOCATION STATUS ---
  bool isLocating = false;
  String? locationError;

  // --- TRIP & DRIVER STATE ---
  Map<String, dynamic>? activeTrip;
  String? activeTripStatus;
  StreamSubscription? tripSubscription;
  StreamSubscription? driverLocationSubscription;
  double? distanceToDriver;
  bool isPickingOnMap = false;
  LatLng? driverLatLng;

  // --- SERVICE MODE (AI / TASK) ---
  String? aiCategoryId;
  String? aiSubCategoryId;
  String? aiPrompt;
  bool isInTripMode = false;
  bool isInServiceMode = false;
  bool isCreatingService = false;
  String? aiServiceType;
  String? aiProfessionName;
  String? aiTaskId;
  double? aiTaskPrice;
  String? aiTaskName;
  bool isFixedService = false;
  bool isMatchingAI = false;
  
  // -- Variaveis de Candidatos IA --
  String? aiLogId;
  List<Map<String, dynamic>> serviceCandidates = [];
  bool isLoadingServiceCandidates = false;
  
  final TextEditingController servicePromptController = TextEditingController();

  // Compatibilidade com callbacks da interface de IA e Realtime
  Timer? serviceAiDebounce;
  bool isServiceAiClassifying = false;
  
  // -- Variaveis de Estado da Lista de Servicos --
  List<Map<String, dynamic>> servicesList = [];
  bool isLoadingServices = false;
  Timer? refreshTimer;
  LatLng? pickedLocation;
  bool isMapAnimating = false;
  int unreadCountCount = 0;
  
  // --- SEARCH & AUTOCOMPLETE ---
  List<Map<String, dynamic>> searchResults = [];
  List<Map<String, dynamic>> savedPlacesList = [];
  bool isSearchExpanded = false;
  bool isSearching = false;
  Timer? debouncer;

  // --- MISC ---
  late AnimationController bellController;

  // --- CONFIG ---
  bool get enableUberRuntime => false;

  @override
  void dispose() {
    debouncer?.cancel();
    tripSubscription?.cancel();
    driverLocationSubscription?.cancel();
    pickupController.dispose();
    destinationController.dispose();
    servicePromptController.dispose();
    pickupFocus.dispose();
    destinationFocus.dispose();
    super.dispose();
  }

  void disposeHomeState() {
    debouncer?.cancel();
    tripSubscription?.cancel();
    driverLocationSubscription?.cancel();
    pickupController.dispose();
    destinationController.dispose();
    servicePromptController.dispose();
    pickupFocus.dispose();
    destinationFocus.dispose();
  }
}
