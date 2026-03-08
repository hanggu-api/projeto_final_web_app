import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_theme.dart';
import '../../services/theme_service.dart';
import '../../services/api_service.dart';
import '../../services/uber_service.dart';
import '../../services/idle_driver_simulator.dart';
import 'home_state.dart';
import 'mixins/home_location_mixin.dart';
import 'mixins/home_search_mixin.dart';
import 'mixins/home_trip_mixin.dart';
import 'mixins/home_realtime_mixin.dart';
import 'mixins/home_service_mixin.dart';

import 'widgets/home_map_widget.dart';
import 'widgets/home_quick_actions.dart';
import 'widgets/home_saved_places.dart';
import 'widgets/home_search_bar.dart';
import 'widgets/home_services_list.dart';
import '../../widgets/ad_carousel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with
        TickerProviderStateMixin,
        HomeStateMixin,
        HomeLocationMixin,
        HomeSearchMixin,
        HomeTripMixin,
        HomeRealtimeMixin,
        HomeServiceMixin {
  final ApiService _api = ApiService();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  StreamSubscription? _onlineDriversSubscription;
  List<SimulatedCar> _realOnlineDrivers = [];

  @override
  void initState() {
    super.initState();
    bellController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Inicialização delegada aos mixins
    checkLocationPermission();
    _loadProfile();
    _loadServices();
    _loadSavedPlaces();
    _recoverActiveTrip();
    _initRefreshTimer();
    _listenToOnlineDrivers();
  }

  @override
  void dispose() {
    _onlineDriversSubscription?.cancel();
    _sheetController.dispose();
    disposeHomeState();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    // Lógica simplificada de carregamento de perfil
    try {
      await _api.getProfile();
    } catch (_) {}
  }

  Future<void> _loadServices() async {
    setState(() => isLoadingServices = true);
    try {
      final res = await _api.getServices();
      if (mounted) setState(() => servicesList = res);
    } catch (_) {
    } finally {
      if (mounted) setState(() => isLoadingServices = false);
    }
  }

  Future<void> _loadSavedPlaces() async {
    // Lógica de lugares salvos
  }

  Future<void> _recoverActiveTrip() async {
    // Atraso de segurança para garantir que ApiService carregou o userId
    await Future.delayed(const Duration(milliseconds: 800));

    // Se userId ainda estiver null, força o carregamento do token/perfil
    if (_api.userId == null) {
      await _api.loadToken();
    }

    final userId = _api.userId;
    if (userId == null) return;

    try {
      final trip = await UberService().getActiveTripForClient(userId);
      if (trip != null && mounted) {
        debugPrint(
          '✅ [Reconexão] Viagem ativa encontrada: ${trip['id']} (${trip['status']}). Redirecionando...',
        );
        context.go('/uber-tracking/${trip['id']}');
      }
    } catch (e) {
      debugPrint('❌ Erro ao recuperar viagem ativa na home: $e');
    }
  }

  void _initRefreshTimer() {
    refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadServices(),
    );
  }

  void _listenToOnlineDrivers() {
    _onlineDriversSubscription?.cancel();
    _onlineDriversSubscription = UberService().watchAllOnlineDrivers().listen(
      (driversData) {
        if (!mounted) return;

        debugPrint(
          '🗺️ [HomeScreen] Recebido stream com ${driversData.length} motoristas online',
        );

        final List<SimulatedCar> newDriversList = [];
        for (var data in driversData) {
          if (data['latitude'] != null &&
              data['longitude'] != null &&
              data['driver_id'] != null) {
            final lat = (data['latitude'] as num).toDouble();
            final lon = (data['longitude'] as num).toDouble();
            newDriversList.add(
              SimulatedCar(
                id: 'rt_${data['driver_id']}',
                position: LatLng(lat, lon),
                heading: 0,
              ),
            );
          }
        }

        debugPrint(
          '🗺️ [HomeScreen] ${newDriversList.length} carros válidos para exibir no mapa',
        );

        setState(() {
          _realOnlineDrivers = newDriversList;
        });
      },
      onError: (e) {
        debugPrint('Erro no stream de online drivers: $e');
      },
    );
  }

  void _showRatingModal(String tripId) {
    // Modal de avaliação (Widget externo ou inline)
  }

  @override
  Widget build(BuildContext context) {
    final bottomNavHeight = MediaQuery.of(context).padding.bottom + 80;

    return PopScope(
      canPop: !isInTripMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isInTripMode && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conclua ou cancele a viagem antes de sair.'),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        body: Stack(
          children: [
            // 🗺️ MAPA (Base)
            Positioned.fill(
              child: HomeMapWidget(
                mapController: mapController,
                currentPosition: currentPosition,
                routePolyline: routePolyline,
                arrivalPolyline: arrivalPolyline,
                pickupLocation: pickupLocation,
                dropoffLocation: dropoffLocation,
                driverLatLng: driverLatLng,
                tripStatus: activeTripStatus,
                isInTripMode: isInTripMode,
                isPickingOnMap: isPickingOnMap,
                simulatedCars: !isInTripMode ? _realOnlineDrivers : [],
                onPickingLocationChanged: (pos) =>
                    setState(() => pickedLocation = pos),
                onMapReady: () => setState(() => isMapReady = true),
                onAnimationStart: () {
                  setState(() => isMapAnimating = true);
                  ThemeService().setNavBarVisible(false);
                },
                onAnimationEnd: () {
                  setState(() => isMapAnimating = false);
                  if (!isInTripMode) ThemeService().setNavBarVisible(true);
                },
              ),
            ),

            // 📍 UI Dinâmica (Overlays)
            _buildHeader(),
            _buildFloatingControls(),
            _buildBottomPanel(bottomNavHeight),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (isPickingOnMap) return const SizedBox.shrink();
    // Headers migrados para widgets seria o ideal, mas mantendo build logic principal aqui por enquanto
    return SafeStitchHeader(
      unreadCount: unreadCountCount,
      bellController: bellController,
    );
  }

  Widget _buildFloatingControls() {
    return Positioned(
      bottom: isInTripMode ? 360 : 540,
      right: 20,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isMapAnimating ? 0.0 : 1.0,
        child: Column(
          children: [
            _buildZoomButton(
              Icons.add,
              () => mapController.move(
                mapController.camera.center,
                mapController.camera.zoom + 1,
              ),
            ),
            const SizedBox(height: 8),
            _buildZoomButton(
              Icons.remove,
              () => mapController.move(
                mapController.camera.center,
                mapController.camera.zoom - 1,
              ),
            ),
            const SizedBox(height: 12),
            _buildLocationButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Icon(icon, color: AppTheme.textDark),
      ),
    );
  }

  Widget _buildLocationButton() {
    return GestureDetector(
      onTap: () => mapController.move(currentPosition, 16),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withOpacity(0.2),
              blurRadius: 20,
            ),
          ],
        ),
        child: Icon(Icons.my_location, color: AppTheme.primaryBlue),
      ),
    );
  }

  Widget _buildBottomPanel(double offset) {
    if (isInTripMode) {
      return const Align(
        alignment: Alignment.bottomCenter,
        child: Text('Painel de Viagem Ativo'),
      );
    }

    // Painel Padrão (Home)
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize:
          0.58, // Mostra card + banner do AdCarousel desde o início
      minChildSize: 0.30,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.30, 0.58, 0.95],
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                HomeSearchBar(onTap: () => context.push('/uber-request')),
                HomeQuickActions(
                  onTripTap: () => context.push('/uber-request'),
                  onServiceTap: () => setState(() => isInServiceMode = true),
                  onDeliveryTap: () {},
                ),
                const AdCarousel(),
                HomeServicesList(
                  services: servicesList,
                  isLoading: isLoadingServices,
                  onRefreshNeeded: _loadServices,
                ),
                HomeSavedPlaces(
                  savedPlaces: savedPlacesList,
                  onPlaceTap: (place) {},
                ),
                // Espaçamento dinâmico para não cobrir o conteúdo (banner/lista) com a barra de navegação flutuante
                // Somamos a altura média da barra (80) + padding do sistema + margem de segurança (24)
                SizedBox(
                  height: 80 + MediaQuery.of(context).padding.bottom + 24,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SafeStitchHeader extends StatelessWidget {
  final int unreadCount;
  final AnimationController bellController;
  const SafeStitchHeader({
    super.key,
    required this.unreadCount,
    required this.bellController,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildCircleButton(Icons.menu, () {}),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
            ),
            child: const Row(
              children: [
                Icon(Icons.bolt, color: Colors.amber, size: 20),
                SizedBox(width: 8),
                Text(
                  '101 SERVICE',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          _buildCircleButton(
            Icons.notifications_none,
            () {},
            badgeCount: unreadCount,
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton(
    IconData icon,
    VoidCallback onTap, {
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.textDark),
          ),
          if (badgeCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
