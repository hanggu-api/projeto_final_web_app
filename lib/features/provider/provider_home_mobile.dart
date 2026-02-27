import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/data_gateway.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/utils/navigation_helper.dart';
import 'widgets/provider_profile_widgets.dart';
import 'widgets/provider_service_card.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/media_service.dart';
import '../../services/realtime_service.dart';
import '../../services/notification_service.dart';
import 'utils/travel_helper.dart';
import 'widgets/service_offer_modal.dart';
import '../../widgets/ad_carousel.dart';

class ProviderHomeMobile extends StatefulWidget {
  final bool loadOnInit;
  final bool connectRealtime;
  final List<dynamic>? initialAvailableServices;
  final List<dynamic>? initialMyServices;

  const ProviderHomeMobile({
    super.key,
    this.loadOnInit = true,
    this.connectRealtime = true,
    this.initialAvailableServices,
    this.initialMyServices,
  });

  @override
  State<ProviderHomeMobile> createState() => _ProviderHomeMobileState();
}

class _ProviderHomeMobileState extends State<ProviderHomeMobile>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final _api = ApiService();
  final _media = MediaService();
  
  // Data State
  List<dynamic> _availableServices = [];
  List<dynamic> _myServices = [];
  String? _notifText;
  bool _loadingData = false;
  double _walletBalance = 0.0;
  
  // Travel/Location State
  final Map<String, Map<String, String>> _travelById = {};
  Uint8List? _avatarBytes;
  String? _userName;
  int? _currentUserId;
  final int _unreadCount = 0;
  bool _uberEnabled = false;

  // Notification / Offer State
  final Set<String> _openOfferIds = {};
  
  // Firebase Listeners for auto-refresh
  final List<StreamSubscription> _serviceSubscriptions = [];
  List<String> _myProfessions = []; // Store provider professions for filtering
  
  // UI Notifiers
  final ValueNotifier<bool> _isLoadingVN = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLocationPermission();
    _checkOverlayPermission();
    _tabController = TabController(length: 3, vsync: this);
    
    if (widget.initialAvailableServices != null ||
        widget.initialMyServices != null) {
      _availableServices = widget.initialAvailableServices ?? _availableServices;
      _myServices = widget.initialMyServices ?? _myServices;
      _isLoadingVN.value = false;
      if (_availableServices.isNotEmpty) {
        final first = _availableServices.first;
        _notifText = '${first['category_name'] ?? first['description'] ?? 'Serviço'} - ${first['address'] ?? ''}';
      } else {
        _notifText = null;
      }
    }
    
    
    if (widget.loadOnInit) {
      _initSocket();
      _loadData();
      _checkUberEnabled();
    }
  }

  void _initSocket() {
    final rt = RealtimeService();
    if (_currentUserId != null) {
      rt.init(_currentUserId!);
    }
    rt.on('service.created', _handleServiceCreated);
    rt.on('service.offered', _handleServiceOffered);
    RealtimeService().onEvent('service_cancelled', _handleServiceCancelled);
    RealtimeService().onEvent('service_canceled', _handleServiceCancelled); // Typo safety
    RealtimeService().onEvent('payment_approved', _handlePaymentUpdate); // Ensure this is registered
    rt.on('payment_remaining', _handlePaymentUpdate);
    rt.on('payment_confirmed', _handlePaymentUpdate);
    rt.on('service.status', _handleServiceUpdated);
    rt.on('service.updated', _handleServiceUpdated);
    rt.connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isLoadingVN.dispose();
    _tabController.dispose();
    RealtimeService().stopLocationUpdates();
    if (widget.connectRealtime) {
      final rt = RealtimeService();
      rt.off('service.created', _handleServiceCreated);
      rt.off('service.offered', _handleServiceOffered);
      rt.off('service.cancelled', _handleServiceCancelled);
      rt.off('payment_remaining', _handlePaymentUpdate);
      rt.off('payment_confirmed', _handlePaymentUpdate);
      rt.off('service.status', _handleServiceUpdated);
      rt.off('service.updated', _handleServiceUpdated);
    }
    super.dispose();
  }

  Future<void> _checkUberEnabled() async {
    try {
      final config = await _api.getAppConfig();
      if (mounted) {
        setState(() {
          _uberEnabled = config['uber_module_enabled'] == 'true' || config['uber_module_enabled'] == true;
        });
      }
    } catch (_) {}
  }



  // --- Socket Handlers ---

  void _handleServiceCreated(dynamic data) async {
    if (!mounted) return;
    if (mounted) {
      _loadData();
    }
  }

  void _handleServiceOffered(dynamic data) {
    if (mounted) {
      debugPrint('🔔 Service Offered Event Received in Home: $data');
      if (data is Map<String, dynamic>) {
        _onServiceOffered(data);
      } else if (data is Map) {
        _onServiceOffered(Map<String, dynamic>.from(data));
      }
    }
  }

  void _listenToAvailableServices() {
    if (_myProfessions.isEmpty) return;

    for (var sub in _serviceSubscriptions) {
      sub.cancel();
    }
    _serviceSubscriptions.clear();
    
    debugPrint('🔥 [Supabase] Listening for services for professions: $_myProfessions');

    final sub = Supabase.instance.client
        .from('service_requests_new')
        .stream(primaryKey: ['id'])
        .eq('status', 'open_for_schedule')
        .listen((snapshot) {
      if (!mounted) return;
      
      final services = snapshot.where((d) {
         final prof = d['profession']?.toString();
         return prof != null && _myProfessions.contains(prof);
      }).map((d) {
        final data = d;
        
        // Ensure numeric types are safe for Dart
        if (data['price_estimated'] is int) data['price_estimated'] = (data['price_estimated'] as int).toDouble();
        if (data['price_upfront'] is int) data['price_upfront'] = (data['price_upfront'] as int).toDouble();
        if (data['latitude'] is int) data['latitude'] = (data['latitude'] as int).toDouble();
        if (data['longitude'] is int) data['longitude'] = (data['longitude'] as int).toDouble();
        
        return data;
      }).toList();

      debugPrint('🔥 [Supabase] Received ${services.length} available services in real-time');
      _updateAvailableServicesWithTravel(services);
    }, onError: (e) {
       debugPrint('❌ [Supabase] Error listening to services: $e');
    });
    
    _serviceSubscriptions.add(sub);
  }
  
  void _updateAvailableServicesWithTravel(List<dynamic> firestoreServices) async {
       Position? currentPos;
       try {
         // Best effort location
         currentPos = await Geolocator.getLastKnownPosition();
         currentPos ??= await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 2)));
       } catch (e) {
         debugPrint('⚠️ [Location] Could not get location for distance calc: $e');
       }
       
       final updated = firestoreServices.map((s) {
           if (currentPos != null && s['latitude'] != null && s['longitude'] != null) {
               final double lat = s['latitude'] is String ? double.parse(s['latitude']) : s['latitude'];
               final double lon = s['longitude'] is String ? double.parse(s['longitude']) : s['longitude'];
               
               final dist = Geolocator.distanceBetween(
                   currentPos.latitude, currentPos.longitude, 
                   lat, lon
               ) / 1000.0; // km
               s['distance_km'] = dist;
           }
           return s;
       }).toList();
       
       if (mounted) {
           setState(() {
               _availableServices = updated;
               _notifText = (updated.isNotEmpty)
                ? '${updated.first['category_name'] ?? updated.first['description'] ?? 'Serviço'} - ${updated.first['address'] ?? ''}'
                : null;
           });
           
           // If we have available services, try to prefetch better travel info if needed
           if (_availableServices.isNotEmpty) {
             _prefetchTravelForFirstAvailable();
           }
       }
  }

  Future<void> _checkOverlayPermission() async {
    final ns = NotificationService();
    final hasPermission = await ns.hasOverlayPermission();
    if (!hasPermission && mounted) {
      // Small delay to ensure UI is ready
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
           _showOverlayPermissionDialog();
        }
      });
    }
  }

  void _showOverlayPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          '🔔 Notificações Urgentes',
          style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Para que o aplicativo possa abrir automaticamente quando houver um novo serviço (mesmo se você estiver usando outro app), é necessário ativar a permissão "Sobreposição de Tela" ou "Mostrar sobre outros aplicativos".',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('DEPOIS', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await NotificationService().requestOverlayPermission();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: const Text('ATIVAR AGORA'),
          ),
        ],
      ),
    );
  }

  void _handlePaymentUpdate(dynamic data) {
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Pagamento confirmado pelo cliente!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    }
  }

  void _handleServiceUpdated(dynamic data) {
    if (mounted) {
      if (data != null && data['status'] == 'open_for_schedule') {
        debugPrint('🔄 [ProviderHome] Service became open_for_schedule. Forcing refresh.');
        _loadData(showLoading: false);
      } else {
        _loadData(showLoading: false); // Avoid full screen loading for updates
      }
    }
  }

  void _handleServiceCancelled(dynamic data) {
    if (mounted && data != null && data['service_id'] != null) {
      final idStr = data['service_id'].toString();
      setState(() {
         // Remove from available services
         _availableServices.removeWhere((s) => s['id'].toString() == idStr);
         
         // If it was the notification text, clear it
         if (_availableServices.isEmpty) {
            _notifText = null;
         } else if (_notifText != null && _notifText!.contains(idStr)) {
            // Simplistic check, ideally verify if notif matches service
             final first = _availableServices.first;
             _notifText = '${first['category_name'] ?? first['description'] ?? 'Serviço'} - ${first['address'] ?? ''}';
         }
      });
      // Optionally show a toast (or not, if we want it silent)
      // ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Um serviço foi cancelado.')));
    }
  }

  // --- Actions ---

  Future<void> _checkLocationPermission() async {
    try {
      final messenger = ScaffoldMessenger.of(context);
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Por favor, habilite a localização.')),
          );
        }
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (serviceEnabled &&
          (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse)) {
        await Geolocator.getCurrentPosition();
      }
    } catch (_) {}
  }

  Future<void> _loadAvatar() async {
    try {
      final bytes = await _media.loadMyAvatarBytes();
      if (mounted && bytes != null) {
        setState(() => _avatarBytes = bytes);
      }
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _api.getMyProfile();

      if (mounted) {
        setState(() {
          _userName = user['name'] ?? user['full_name'];
          _walletBalance = (user['balance'] ?? 0).toDouble();
        });

        if (user['id'] != null) {
          final userId = user['id'] is int
              ? user['id']
              : int.tryParse(user['id'].toString());

          if (userId != null) {
            _currentUserId = userId;
            RealtimeService().authenticate(userId);
            // Mobile Provider: Ensure tracking is ON
            RealtimeService().startLocationUpdates(userId);
          }
        }
        
        if (user['professions'] != null) {
           _myProfessions = List<String>.from(user['professions']);
           _listenToAvailableServices(); // Start listening after we know professions
        }
      }
    } catch (_) {}
  }

  Future<void> _onServiceOffered(Map<String, dynamic> data) async {
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('sounds/chamado.mp3'));
    } catch (_) {}

    if (!mounted) return;
    _loadData();

    final serviceId = data['id'] ?? data['service_id'];
    if (serviceId != null) {
      final sId = serviceId.toString();
      if (_openOfferIds.contains(sId)) return;
      _openOfferIds.add(sId);

      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => ServiceOfferModal(
          serviceId: sId,
          initialData: data,
          onAccepted: () => _loadData(showLoading: false),
          onRejected: () => _loadData(showLoading: false),
        ),
      );
      if (!mounted) return;
      _openOfferIds.remove(sId);
    }
  }


  Future<void> _loadData({bool showLoading = true}) async {
    if (_loadingData || !mounted) return;
    _loadingData = true;
    if (showLoading) {
      _isLoadingVN.value = true;
    }

    _loadAvatar();
    _loadProfile();

    try {
      final availableNow = await _api.getAvailableServices();
      final availableSched = await _api.getAvailableForSchedule();
      final my = await _api.getMyServices();
      debugPrint('📋 [DEBUG] availableNow: ${availableNow.length} items');
      debugPrint('📋 [DEBUG] availableSched: ${availableSched.length} items');
      debugPrint('📋 [DEBUG] myServices: ${my.length} items');
      if (availableNow.isNotEmpty) debugPrint('📋 [DEBUG] availableNow[0]: ${availableNow.first}');
      if (availableSched.isNotEmpty) debugPrint('📋 [DEBUG] availableSched[0]: ${availableSched.first}');
      
      // Real-time notifications handled by DataGateway

      // Combine services and deduplicate by ID
      final Map<String, dynamic> uniqueServices = {};
      
      for (var service in availableNow) {
        if (service['id'] != null) {
          uniqueServices[service['id'].toString()] = service;
        }
      }
      
      for (var service in availableSched) {
        if (service['id'] != null) {
          uniqueServices[service['id'].toString()] = service;
        }
      }

      final List<dynamic> combinedAvailable = uniqueServices.values.toList();
      
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          
          final activeWork = my.where((s) {
            final st = s['status']?.toString().toLowerCase();
            return st != 'completed' && st != 'cancelled' && st != 'canceled';
          }).toList();

          setState(() {
            _availableServices = combinedAvailable;
            _myServices = my;
            _notifText = (combinedAvailable.isNotEmpty)
                ? '${combinedAvailable.first['category_name'] ?? combinedAvailable.first['description'] ?? 'Serviço'} - ${combinedAvailable.first['address'] ?? ''}'
                : null;
            
            // Auto-switch based on presence of active work
            if (activeWork.isNotEmpty) {
               if (_tabController.index != 0) _tabController.animateTo(0);
            } else {
               // Default to "Disponíveis" (Index 1) if "Meus" is empty
               if (_tabController.index != 1) _tabController.animateTo(1);
            }
          });
          _isLoadingVN.value = false;
          _loadingData = false;
          if (_availableServices.isNotEmpty) {
            _prefetchTravelForFirstAvailable();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _isLoadingVN.value = false;
        _loadingData = false;
      }
    }
  }

  // --- Travel Logic ---

  Future<void> _prefetchTravelForFirstAvailable() async {
    final first = _availableServices.first;
    _ensureLoadTravelForItem(first);
  }

  void _ensureLoadTravelForItem(Map<String, dynamic> item) {
    final String? id = item['id']?.toString();
    if (id == null) return;
    if (_travelById.containsKey(id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTravelForService(item);
    });
  }

  Future<void> _loadTravelForService(Map<String, dynamic> s) async {
    final id = s['id']?.toString();
    debugPrint('🚦 [Travel] Loading for service $id');
    try {
      final toLat = s['latitude'] is num ? (s['latitude'] as num).toDouble() : double.tryParse('${s['latitude']}');
      final toLon = s['longitude'] is num ? (s['longitude'] as num).toDouble() : double.tryParse('${s['longitude']}');
      
      if (toLat == null || toLon == null) {
         debugPrint('❌ [Travel] Invalid destination coords for $id');
         return;
      }

      // ... (Fuel logic skipped for brevity, keeping existing if needed but focusing on distance) ...
      double? gasolina = 6.0; // Default fallback to ensure calc runs

      double? fromLat;
      double? fromLon;
      try {
        // Try getting last known first (faster)
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
           fromLat = lastPos.latitude;
           fromLon = lastPos.longitude;
        } else {
           final pos = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 5));
           fromLat = pos.latitude;
           fromLon = pos.longitude;
        }
        debugPrint('📍 [Travel] Got start pos: $fromLat, $fromLon');
      } catch (e) {
         debugPrint('⚠️ [Travel] Location error: $e');
      }
      
      // Fallback if no location
      if (fromLat == null) {
          debugPrint('⚠️ [Travel] No location found. Using default default.');
          fromLat = -23.5505; 
          fromLon = -46.6333;
      }

      debugPrint('📍 [Travel] Service coords: $toLat, $toLon');
      debugPrint('📍 [Travel] Provider coords: $fromLat, $fromLon');

      // Calculate locally using Geolocator (Haversine)
      final distMeters = Geolocator.distanceBetween(fromLat, fromLon!, toLat, toLon);
      final d = distMeters / 1000.0;
      final t = d / (30.0 / 60.0); // 30km/h

      debugPrint('🏁 [Travel] Calc for $id: $d km, $t min');

      final costCar = TravelHelper.calculateCarCost(d, gasolina);
      final costMoto = TravelHelper.calculateMotoCost(d, gasolina);

      if (!mounted) return;
      setState(() {
        if (id != null) {
          _travelById[id] = {
            'distance': TravelHelper.formatDistance(d),
            'duration': TravelHelper.formatDuration(t),
            'costCar': TravelHelper.formatCost(costCar),
            'costMoto': TravelHelper.formatCost(costMoto),
          };
        }
      });
    } catch (e, stack) {
      debugPrint('❌ [Travel] Critical error: $e\n$stack');
    }
  }

  Future<void> _openNavigation(Map<String, dynamic> s) async {
    final toLat = s['latitude'] is num ? (s['latitude'] as num).toDouble() : double.tryParse('${s['latitude']}');
    final toLon = s['longitude'] is num ? (s['longitude'] as num).toDouble() : double.tryParse('${s['longitude']}');
    if (toLat == null || toLon == null) return;
    
    await NavigationHelper.openNavigation(
      latitude: toLat,
      longitude: toLon,
    );
  }

  void _showWithdrawalDialog() async {
    final success = await showDialog<bool>(
      context: context,
      builder: (context) => WithdrawalDialog(api: _api, currentBalance: _walletBalance),
    );
    if (success == true) {
      _loadProfile();
    }
  }

  // --- UI Components ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: _buildHeader(context),
            ),
            // Removed _buildNewOpportunityCard

            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.darkBlueText,
                  unselectedLabelColor: Colors.grey[600],
                  labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  unselectedLabelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                  indicatorColor: AppTheme.darkBlueText,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: [
                    Tab(child: _buildTabLabel('Meus', _myServices.where((s) {
                       final st = s['status']?.toString().toLowerCase();
                       return st != 'completed' && st != 'cancelled' && st != 'canceled';
                    }).length)),
                    Tab(child: _buildTabLabel('Disponíveis', _availableServices.length)),
                    Tab(child: _buildTabLabel('Finalizados', _myServices.where((s) {
                       final st = s['status']?.toString().toLowerCase();
                       return st == 'completed' || st == 'cancelled' || st == 'canceled';
                    }).length)),
                  ],
                ),
              ),
            ),
          ],
          body: ValueListenableBuilder<bool>(
            valueListenable: _isLoadingVN,
            builder: (context, isLoading, _) {
              if (isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              return TabBarView(
                controller: _tabController,
                children: [
                   _buildServiceList(
                     _myServices.where((s) {
                       final st = s['status']?.toString().toLowerCase();
                       return st != 'completed' && st != 'cancelled' && st != 'canceled';
                     }).toList()..sort((a, b) {
                        // Prioritize 'accepted' or 'in_progress' over 'pending'
                        final statusA = a['status']?.toString().toLowerCase() ?? '';
                        final statusB = b['status']?.toString().toLowerCase() ?? '';
                        if (statusA == 'in_progress' && statusB != 'in_progress') return -1;
                        if (statusB == 'in_progress' && statusA != 'in_progress') return 1;
                        if (statusA == 'accepted' && (statusB != 'accepted' && statusB != 'in_progress')) return -1;
                        if (statusB == 'accepted' && (statusA != 'accepted' && statusA != 'in_progress')) return 1;
                        return 0;
                     }),
                   ),
                   _buildServiceList(_availableServices, isAvailable: true),
                   _buildServiceList(
                     _myServices.where((s) {
                       final st = s['status']?.toString().toLowerCase();
                       return st == 'completed' || st == 'cancelled' || st == 'canceled';
                     }).toList(),
                   ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 32),
      decoration: BoxDecoration(
        color: AppTheme.primaryYellow,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        image: _avatarBytes != null
                            ? DecorationImage(
                                image: MemoryImage(_avatarBytes!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _avatarBytes == null
                          ? const Center(
                              child: Text('P',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold)))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Olá,',
                              style: TextStyle(color: Colors.black54)),
                          Text(
                            _userName ?? 'Prestador',
                            style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _showWithdrawalDialog,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: Supabase.instance.client.auth.currentUser?.id != null
                              ? DataGateway().watchNotifications(
                                  Supabase.instance.client.auth.currentUser!.id)
                              : const Stream.empty(),
                          builder: (context, snapshot) {
                            final notifications = snapshot.data ?? [];
                            final unreadCount = notifications
                                .where((n) =>
                                    n['read'] != true && n['is_read'] != true)
                                .length;

                            return Stack(
                              alignment: Alignment.topRight,
                              children: [
                                IconButton(
                                  icon: const Icon(LucideIcons.bell,
                                      color: Colors.black87),
                                  onPressed: () async {
                                    await context.push('/notifications');
                                    _loadData(showLoading: false);
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                if (unreadCount > 0)
                                  Positioned(
                                    right: 0,
                                    top: 0,
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
                                        unreadCount > 9
                                            ? '9+'
                                            : unreadCount.toString(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        const Text('Saldo disponível',
                            style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.wallet,
                            color: Colors.black87, size: 20),
                        const SizedBox(width: 8),
                        Text(
                            'R\$ ${_walletBalance.toStringAsFixed(2).replaceAll('.', ',')}',
                            style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_uberEnabled) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/uber-driver'),
                icon: const Icon(LucideIcons.car, size: 18),
                label: const Text('MODO MOTORISTA'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }



  Widget _buildServiceList(List<dynamic> items, {bool isAvailable = false}) {
    if (items.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Icon(
                isAvailable ? LucideIcons.search : LucideIcons.briefcase,
                size: 64,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                isAvailable ? 'Nenhuma oportunidade no momento' : 'Você não tem serviços ativos',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black54),
              ),

              const SizedBox(height: 48),
              const Padding(
                 padding: EdgeInsets.symmetric(horizontal: 0.0),
                 child: AdCarousel(height: 300),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      itemCount: items.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == items.length) {
          return const Padding(
            padding: EdgeInsets.only(top: 24, bottom: 48),
            child: AdCarousel(height: 300),
          );
        }
        final item = items[index];
        _ensureLoadTravelForItem(item);
        final id = item['id']?.toString();
        final travel = id != null ? _travelById[id] : null;

        return ProviderServiceCard(
          service: item,
          travelInfo: travel,
          onNavigate: () => _openNavigation(item),
          onArrive: id != null ? () async {
             final messenger = ScaffoldMessenger.of(context);
             setState(() => _isLoadingVN.value = true);
             try {
               await _api.arriveService(id);
               if (mounted) {
                 messenger.showSnackBar(const SnackBar(content: Text('Cliente notificado!')));
                 _loadData();
               }
             } catch (e) {
               if (mounted) {
                 messenger.showSnackBar(SnackBar(content: Text('Erro ao notificar: $e')));
               }
             } finally {
               if (mounted) setState(() => _isLoadingVN.value = false);
             }
          } : null,
          onStart: id != null ? () => _startService(id) : null,
          onFinish: id != null ? () => context.push('/service-details', extra: id).then((_) => _loadData()) : null,
          onViewDetails: id != null ? () => context.push('/service-details', extra: id).then((_) => _loadData()) : null,
          onSchedule: id != null ? (scheduledAt, message) async {
            setState(() => _isLoadingVN.value = true);
            final messenger = ScaffoldMessenger.of(context);
            try {
              await _api.proposeSchedule(id, scheduledAt);
              if (mounted) {
                messenger.showSnackBar(const SnackBar(content: Text('Proposta enviada!')));
                _loadData();
              }
            } catch (e) {
              if (mounted) messenger.showSnackBar(SnackBar(content: Text('Erro: $e')));
            } finally {
              if (mounted) setState(() => _isLoadingVN.value = false);
            }
          } : null,
          onConfirmSchedule: (id != null && item['scheduled_at'] != null) ? () async {
            setState(() => _isLoadingVN.value = true);
            final messenger = ScaffoldMessenger.of(context);
            try {
              final scheduledAt = DateTime.parse(item['scheduled_at'].toString());
              await _api.confirmSchedule(id, scheduledAt);
              if (mounted) {
                messenger.showSnackBar(const SnackBar(
                  content: Text('Agendamento confirmado!'),
                  backgroundColor: Colors.green,
                ));
                _loadData();
              }
            } catch (e) {
              if (mounted) messenger.showSnackBar(SnackBar(content: Text('Erro: $e')));
            } finally {
              if (mounted) setState(() => _isLoadingVN.value = false);
            }
          } : null,
        );
      },
    );
  }

  Future<void> _startService(String id) async {
    // Moved helper here since used in mobile items
    setState(() => _isLoadingVN.value = true);
    try {
      await _api.startService(id);
      if (mounted) _loadData();
    } finally {
      if (mounted) setState(() => _isLoadingVN.value = false);
    }
  }


  Widget _buildTabLabel(String label, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }


}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  _SliverAppBarDelegate(this._tabBar);
  @override double get minExtent => _tabBar.preferredSize.height;
  @override double get maxExtent => _tabBar.preferredSize.height;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: Colors.grey[50], child: _tabBar);
  @override bool shouldRebuild(covariant _SliverAppBarDelegate oldDelegate) => false;
}
