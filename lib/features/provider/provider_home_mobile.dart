import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/data_gateway.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/trip_statuses.dart';
import '../../core/utils/navigation_helper.dart';
import '../../core/utils/service_flow_classifier.dart';
import 'widgets/provider_profile_widgets.dart';
import 'widgets/provider_service_card.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/notification_type_helper.dart';
import '../../services/api_service.dart';
import '../../services/media_service.dart';
import '../../services/network_status_service.dart';
import '../../services/realtime_service.dart';
import '../../services/notification_service.dart';
import '../shared/widgets/notification_dropdown_menu.dart';
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
  bool _isUploadingAvatar = false;

  // Travel/Location State
  final Map<String, Map<String, String>> _travelById = {};
  final Set<String> _travelHydrationAttemptedIds = <String>{};
  Uint8List? _avatarBytes;
  String? _userName;
  String? _currentUserId;
  double? _providerLat;
  double? _providerLon;
  // Desativado: prestadores não podem ser motoristas ao mesmo tempo.
  // Mantido aqui somente se no futuro reativarmos o módulo Uber nesta tela.

  // Notification / Offer State
  final Set<String> _openOfferIds = {};
  final Map<String, DateTime> _offerCooldownUntilById = {};
  String? _lastAutoRedirectedServiceId;

  // Firebase Listeners for auto-refresh
  final List<StreamSubscription> _serviceSubscriptions = [];
  StreamSubscription<List<Map<String, dynamic>>>? _offersSub;
  List<String> _myProfessions = []; // Store provider professions for filtering
  Timer? _offersPollingTimer;
  Timer? _offersRetryTimer;
  Timer? _availableServicesRefreshTimer;
  Timer? _paymentStatusRefreshTimer;
  int _offersRetryAttempt = 0;
  int _offersPollingNetworkErrorCount = 0;
  bool _offersRebindInProgress = false;
  bool _socketHandlersBound = false;
  bool _offersStreamDegraded = false;
  DateTime? _offersStreamDegradedSince;
  DateTime? _lastOffersTransientLogAt;
  String? _lastOffersTransientSignature;
  DateTime? _lastHeavyFallbackRefreshAt;
  DateTime? _offersPollingPausedUntil;
  DateTime? _lastLocationPermissionLogAt;
  StreamSubscription<NetworkStatusSnapshot>? _networkStatusSub;
  final NetworkStatusService _networkStatus = NetworkStatusService();
  NetworkStatusSnapshot _networkSnapshot = const NetworkStatusSnapshot(
    kind: NetworkStatusKind.online,
    hasLocalConnectivity: true,
  );
  bool _isForeground = true;

  String _normText(String? value) {
    final raw = (value ?? '').toLowerCase().trim();
    const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const to = 'aaaaaeeeeiiiiooooouuuuc';
    var out = raw;
    for (var index = 0; index < from.length; index++) {
      out = out.replaceAll(from[index], to[index]);
    }
    return out;
  }

  bool _matchesProviderProfession(Map<String, dynamic> service) {
    if (_myProfessions.isEmpty) return true;

    final serviceProfession = _normText(
      service['profession']?.toString() ?? service['category_name']?.toString(),
    );
    if (serviceProfession.isEmpty) return true;

    for (final profession in _myProfessions) {
      final my = _normText(profession);
      if (my.isEmpty) continue;
      if (serviceProfession == my) return true;
      if (serviceProfession.contains(my) || my.contains(serviceProfession)) {
        return true;
      }
    }
    return false;
  }

  bool _isTransientNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('software caused connection abort') ||
        text.contains('connection abort') ||
        text.contains('clientexception');
  }

  bool _isOfferInLocalCooldown(String serviceId) {
    final until = _offerCooldownUntilById[serviceId];
    if (until == null) return false;
    if (until.isAfter(DateTime.now())) return true;
    _offerCooldownUntilById.remove(serviceId);
    return false;
  }

  void _setOfferLocalCooldown(String serviceId, {int seconds = 35}) {
    final normalized = serviceId.trim();
    if (normalized.isEmpty) return;
    _offerCooldownUntilById[normalized] = DateTime.now().add(
      Duration(seconds: seconds),
    );
  }

  Future<Set<String>> _loadActivePrivateDispatchServiceIds(
    List<dynamic> services,
  ) async {
    return DataGateway().loadActivePrivateDispatchServiceIds(services);
  }

  Future<List<dynamic>> _filterOutPrivateDispatchServices(
    List<dynamic> services,
  ) async {
    if (services.isEmpty) return services;
    final blockedIds = await _loadActivePrivateDispatchServiceIds(services);
    if (blockedIds.isEmpty) return services;

    final filtered = services.where((item) {
      final id = item['id']?.toString().trim() ?? '';
      if (id.isEmpty) return false;
      return !blockedIds.contains(id);
    }).toList();

    debugPrint(
      '🔒 [ProviderHomeMobile] Serviços ocultados da vitrine pública por fila privada ativa: ${blockedIds.length}',
    );
    return filtered;
  }

  // UI Notifiers
  final ValueNotifier<bool> _isLoadingVN = ValueNotifier<bool>(true);

  void _avatarTrace(String message) {
    debugPrint(message);
    // ignore: avoid_print
    print(message);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeNetworkState());
    _checkLocationPermission();
    unawaited(NotificationService().requestProviderPermissions());
    _tabController = TabController(length: 3, vsync: this);

    if (widget.initialAvailableServices != null ||
        widget.initialMyServices != null) {
      _availableServices =
          widget.initialAvailableServices ?? _availableServices;
      _myServices = widget.initialMyServices ?? _myServices;
      _isLoadingVN.value = false;
      if (_availableServices.isNotEmpty) {
        final first = _availableServices.first;
        _notifText =
            '${first['category_name'] ?? first['description'] ?? 'Serviço'} - ${first['address'] ?? ''}';
      } else {
        _notifText = null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeRedirectToActiveService(_myServices);
      });
    }

    if (widget.loadOnInit) {
      _ensureOfferListenerFromAuth();
      _startOffersPollingFallback();
      _startAvailableServicesRefreshLoop();
      _startPaymentStatusRefreshLoop();
      _initSocket();
      _loadData();
      // _checkUberEnabled(); // desativado (prestador não alterna para motorista)
    }
  }

  Future<void> _initializeNetworkState() async {
    await _networkStatus.ensureInitialized();
    if (!mounted) return;
    _networkSnapshot = _networkStatus.current;
    _networkStatusSub?.cancel();
    _networkStatusSub = _networkStatus.stream.listen((snapshot) {
      if (!mounted) return;
      final wasOfflineLike =
          _networkSnapshot.isOffline || _networkSnapshot.isBackendUnreachable;
      final isOfflineLike = snapshot.isOffline || snapshot.isBackendUnreachable;
      setState(() {
        _networkSnapshot = snapshot;
      });
      if (wasOfflineLike && snapshot.isOnline) {
        _offersRetryAttempt = 0;
        _offersPollingNetworkErrorCount = 0;
        _offersPollingPausedUntil = null;
        _listenToServiceOffers(_currentUserId?.trim() ?? '');
        unawaited(_pollOffersFallback());
        unawaited(_loadData(showLoading: false));
      } else if (isOfflineLike) {
        _offersSub?.cancel();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      debugPrint(
        '🔄 [ProviderHomeMobile] app resumed. Refreshing available services and active data.',
      );
      _startOffersPollingFallback();
      _startAvailableServicesRefreshLoop();
      _startPaymentStatusRefreshLoop();
      unawaited(_networkStatus.refreshConnectivity());
      unawaited(_loadData(showLoading: false));
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _isForeground = false;
      _offersPollingTimer?.cancel();
      _availableServicesRefreshTimer?.cancel();
      _paymentStatusRefreshTimer?.cancel();
      debugPrint(
        '⏸️ [ProviderHomeMobile] app in background. Polling loops paused until resume.',
      );
    }
  }

  void _ensureOfferListenerFromAuth() {
    final localUserId = _currentUserId?.trim() ?? '';
    if (localUserId.isNotEmpty) {
      _listenToServiceOffers(localUserId);
      return;
    }

    unawaited(() async {
      final authUid =
          Supabase.instance.client.auth.currentUser?.id.trim() ?? '';
      if (authUid.isEmpty) return;
      try {
        final resolvedUserId = await DataGateway().resolveUserIdByAuthUid(
          authUid,
        );
        final userId = (resolvedUserId ?? '').toString().trim();
        if (userId.isNotEmpty && mounted) {
          _currentUserId = userId;
          _listenToServiceOffers(userId);
        }
      } catch (e) {
        debugPrint(
          '⚠️ [ProviderHomeMobile] falha ao resolver user_id para listener: $e',
        );
      }
    }());
  }

  void _initSocket() {
    if (!widget.connectRealtime) return;
    final rt = RealtimeService();
    if (!_socketHandlersBound) {
      rt.on('service.created', _handleServiceCreated);
      rt.on(kCanonicalServiceOfferType, _handleServiceOffered);
      rt.onEvent('service_cancelled', _handleServiceCancelled);
      rt.onEvent('service_canceled', _handleServiceCancelled); // Typo safety
      rt.onEvent('payment_approved', _handlePaymentUpdate);
      rt.on('payment_remaining', _handlePaymentUpdate);
      rt.on('payment_confirmed', _handlePaymentUpdate);
      rt.on('service.status', _handleServiceUpdated);
      rt.on('service.updated', _handleServiceUpdated);
      _socketHandlersBound = true;
    }
    if (_currentUserId != null && _currentUserId!.trim().isNotEmpty) {
      rt.init(_currentUserId!.trim());
    }
    rt.connect();
  }

  void _openProviderActiveFlow(String serviceId) {
    if (!mounted || serviceId.trim().isEmpty) return;
    context.push('/provider-active/$serviceId');
  }

  bool _isTerminalStatus(String? raw) {
    final status = normalizeServiceStatus(raw);
    return status == 'finished' ||
        ServiceStatusSets.inactiveTerminal.contains(status);
  }

  int _statusPriority(String? raw) {
    final status = normalizeServiceStatus(raw);
    switch (status) {
      case ServiceStatusAliases.awaitingConfirmation:
      case ServiceStatusAliases.waitingClientConfirmation:
      case ServiceStatusAliases.completionRequested:
        return 0;
      case TripStatuses.inProgress:
      case ServiceStatusAliases.waitingPaymentRemaining:
      case ServiceStatusAliases.waitingRemainingPayment:
        return 1;
      case 'on_way':
      case 'provider_near':
      case TripStatuses.arrived:
      case TripStatuses.accepted:
        return 2;
      case TripStatuses.pending:
        return 3;
      default:
        return 4;
    }
  }

  String? _routeForActiveService(Map<String, dynamic> service) {
    final id = service['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    final status = normalizeServiceStatus(service['status']?.toString());
    if (ServiceStatusSets.providerConcluding.contains(status)) {
      return '/provider-home';
    }
    final flow = classifyServiceFlow(service);
    return flow == ServiceFlowKind.fixed
        ? '/provider-home'
        : '/provider-active/$id';
  }

  void _applyLocalScheduleProposalState(
    String serviceId,
    DateTime scheduledAt,
    Map<String, dynamic> source,
  ) {
    final providerId = int.tryParse(_currentUserId?.trim() ?? '');
    final updated = Map<String, dynamic>.from(source);
    updated['id'] = serviceId;
    updated['status'] = 'schedule_proposed';
    updated['provider_id'] = providerId ?? updated['provider_id'];
    updated['scheduled_at'] = scheduledAt.toUtc().toIso8601String();
    updated['schedule_proposed_by_user_id'] =
        providerId ?? updated['schedule_proposed_by_user_id'];
    updated['schedule_provider_rounds'] =
        (int.tryParse('${updated['schedule_provider_rounds'] ?? ''}') ?? 0) + 1;
    updated['schedule_round'] =
        (int.tryParse('${updated['schedule_round'] ?? ''}') ?? 0) + 1;

    setState(() {
      _availableServices.removeWhere((s) => s['id']?.toString() == serviceId);
      _myServices.removeWhere((s) => s['id']?.toString() == serviceId);
      _myServices.insert(0, updated);
      if (_tabController.index != 0) {
        _tabController.animateTo(0);
      }
    });
  }

  void _applyLocalScheduleConfirmedState(
    String serviceId,
    DateTime scheduledAt,
    Map<String, dynamic> source,
  ) {
    final updated = Map<String, dynamic>.from(source);
    updated['id'] = serviceId;
    updated['status'] = 'scheduled';
    updated['scheduled_at'] = scheduledAt.toUtc().toIso8601String();

    setState(() {
      _availableServices.removeWhere((s) => s['id']?.toString() == serviceId);
      final index = _myServices.indexWhere(
        (s) => s['id']?.toString() == serviceId,
      );
      if (index >= 0) {
        _myServices[index] = updated;
      } else {
        _myServices.insert(0, updated);
      }
      if (_tabController.index != 0) {
        _tabController.animateTo(0);
      }
    });
  }

  void _maybeRedirectToActiveService(List<dynamic> services) {
    if (!mounted || services.isEmpty) {
      _lastAutoRedirectedServiceId = null;
      return;
    }

    final activeCandidates = services
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((service) => !_isTerminalStatus(service['status']?.toString()))
        .toList();

    if (activeCandidates.isEmpty) {
      _lastAutoRedirectedServiceId = null;
      return;
    }

    activeCandidates.sort((a, b) {
      final byStatus = _statusPriority(
        a['status']?.toString(),
      ).compareTo(_statusPriority(b['status']?.toString()));
      if (byStatus != 0) return byStatus;
      final aCreated = a['created_at']?.toString() ?? '';
      final bCreated = b['created_at']?.toString() ?? '';
      return bCreated.compareTo(aCreated);
    });

    final selected = activeCandidates.first;
    final selectedId = selected['id']?.toString().trim() ?? '';
    final target = _routeForActiveService(selected);
    if (selectedId.isEmpty || target == null) return;

    if (_lastAutoRedirectedServiceId == selectedId) return;
    _lastAutoRedirectedServiceId = selectedId;

    final currentLocation = GoRouterState.of(context).uri.toString();
    if (currentLocation == target) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final liveLocation = GoRouterState.of(context).uri.toString();
      if (liveLocation != target) {
        context.go(target);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isLoadingVN.dispose();
    _tabController.dispose();
    RealtimeService().stopLocationUpdates();
    _offersSub?.cancel();
    _networkStatusSub?.cancel();
    _offersPollingTimer?.cancel();
    _offersRetryTimer?.cancel();
    _availableServicesRefreshTimer?.cancel();
    _paymentStatusRefreshTimer?.cancel();
    for (final sub in _serviceSubscriptions) {
      sub.cancel();
    }
    _serviceSubscriptions.clear();
    if (widget.connectRealtime) {
      final rt = RealtimeService();
      rt.off('service.created', _handleServiceCreated);
      rt.off(kCanonicalServiceOfferType, _handleServiceOffered);
      rt.offEvent('service_cancelled', _handleServiceCancelled);
      rt.offEvent('service_canceled', _handleServiceCancelled);
      rt.offEvent('payment_approved', _handlePaymentUpdate);
      rt.off('payment_remaining', _handlePaymentUpdate);
      rt.off('payment_confirmed', _handlePaymentUpdate);
      rt.off('service.status', _handleServiceUpdated);
      rt.off('service.updated', _handleServiceUpdated);
      _socketHandlersBound = false;
    }
    super.dispose();
  }

  void _startOffersPollingFallback() {
    if (!_isForeground) return;
    _offersPollingTimer?.cancel();
    _offersPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (!_isForeground) return;
      if (!_networkStatus.canAttemptSupabase) {
        return;
      }
      final pausedUntil = _offersPollingPausedUntil;
      if (pausedUntil != null && pausedUntil.isAfter(DateTime.now())) {
        return;
      }
      unawaited(_pollOffersFallback());
      if (_offersStreamDegraded) {
        final degradedSince = _offersStreamDegradedSince;
        final shouldForceHeavy =
            degradedSince != null &&
            DateTime.now().difference(degradedSince) >=
                const Duration(seconds: 15);
        if (shouldForceHeavy) {
          _lastHeavyFallbackRefreshAt = DateTime.now();
          unawaited(_loadData(showLoading: false));
        }
      }
      // Revalidação pesada em intervalo maior para reduzir custo e race conditions.
      final now = DateTime.now();
      final shouldRefreshHeavy =
          _lastHeavyFallbackRefreshAt == null ||
          now.difference(_lastHeavyFallbackRefreshAt!) >=
              const Duration(seconds: 30);
      if (shouldRefreshHeavy) {
        _lastHeavyFallbackRefreshAt = now;
        unawaited(_loadData(showLoading: false));
      }
    });
  }

  void _markOffersStreamHealthy() {
    _offersRetryAttempt = 0;
    _offersStreamDegraded = false;
    _offersStreamDegradedSince = null;
  }

  void _markOffersStreamDegraded() {
    _offersStreamDegraded = true;
    _offersStreamDegradedSince ??= DateTime.now();
  }

  void _logTransientOffersIssue(String message, {required String signature}) {
    final now = DateTime.now();
    final shouldLog =
        _lastOffersTransientSignature != signature ||
        _lastOffersTransientLogAt == null ||
        now.difference(_lastOffersTransientLogAt!) >
            const Duration(seconds: 20);
    if (!shouldLog) return;
    _lastOffersTransientSignature = signature;
    _lastOffersTransientLogAt = now;
    debugPrint(message);
  }

  void _startAvailableServicesRefreshLoop() {
    if (!_isForeground) return;
    _availableServicesRefreshTimer?.cancel();
    _availableServicesRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (!mounted) return;
        if (!_isForeground) return;
        if (!_networkStatus.canAttemptSupabase) return;
        debugPrint(
          '🔄 [ProviderHomeMobile] minute refresh for available services.',
        );
        unawaited(_loadData(showLoading: false));
      },
    );
  }

  bool _shouldUsePaymentStatusPolling() {
    for (final raw in _myServices) {
      if (raw is! Map) continue;
      final service = Map<String, dynamic>.from(raw);
      final status = (service['status'] ?? '').toString().toLowerCase().trim();
      final isWaitingSecurePayment =
          status == 'waiting_payment_remaining' ||
          status == 'waiting_remaining_payment';
      final isSchedulingFlow =
          status == 'schedule_proposed' || status == 'scheduled';
      final hasArrived =
          service['arrived_at'] != null ||
          service['client_arrived'] == true ||
          service['client_arrived'] == 'true';

      if (isWaitingSecurePayment || isSchedulingFlow || hasArrived) {
        return true;
      }
    }
    return false;
  }

  void _startPaymentStatusRefreshLoop() {
    if (!_isForeground) return;
    _paymentStatusRefreshTimer?.cancel();
    _paymentStatusRefreshTimer = Timer.periodic(const Duration(seconds: 10), (
      _,
    ) {
      if (!mounted) return;
      if (!_isForeground) return;
      if (!_networkStatus.canAttemptSupabase) return;
      if (!_shouldUsePaymentStatusPolling()) return;
      debugPrint(
        '🔄 [ProviderHomeMobile] 10s refresh while awaiting payment/schedule confirmation.',
      );
      unawaited(_loadData(showLoading: false));
    });
  }

  Future<void> _pollOffersFallback() async {
    final providerUserId = _currentUserId?.trim() ?? '';
    if (providerUserId.isEmpty) return;
    if (!_networkStatus.canAttemptSupabase) return;

    try {
      final rows = await DataGateway().loadProviderNotifiedOffers(
        providerUserId,
        limit: 5,
      );

      final now = DateTime.now();
      for (final r in rows) {
        final serviceId = (r['service_id'] ?? '').toString();
        if (serviceId.isEmpty) continue;

        final deadlineRaw = r['response_deadline_at'];
        final deadlineAt = deadlineRaw == null
            ? null
            : DateTime.tryParse(deadlineRaw.toString());
        if (deadlineAt != null && !deadlineAt.isAfter(now)) continue;
        if (_openOfferIds.contains(serviceId)) continue;
        if (_isOfferInLocalCooldown(serviceId)) continue;

        unawaited(
          _onServiceOffered({
            'id': serviceId,
            'service_id': serviceId,
            'type': 'service_offer',
          }),
        );
        break;
      }
      _offersPollingNetworkErrorCount = 0;
      _offersPollingPausedUntil = null;
      _networkStatus.markBackendRecovered();
    } catch (e) {
      if (_isTransientNetworkError(e)) {
        unawaited(_networkStatus.markBackendFailure(e));
        _offersPollingNetworkErrorCount = (_offersPollingNetworkErrorCount + 1)
            .clamp(1, 12);
        final backoffSeconds = (2 << (_offersPollingNetworkErrorCount - 1))
            .clamp(5, 60);
        _offersPollingPausedUntil = DateTime.now().add(
          Duration(seconds: backoffSeconds),
        );
        debugPrint(
          '⚠️ [ProviderHomeMobile] polling fallback offers sem rede '
          'cooldown=${backoffSeconds}s erro: $e',
        );
        return;
      }
      debugPrint('⚠️ [ProviderHomeMobile] polling fallback offers erro: $e');
    }
  }

  // Desativado: prestadores não podem ser motoristas ao mesmo tempo.
  // Future<void> _checkUberEnabled() async {}

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
    // Backend-first: não usa stream direto no Supabase para vitrine.
    // A lista é atualizada por `_loadData()` via API JSON e loops de refresh.
    for (var sub in _serviceSubscriptions) {
      sub.cancel();
    }
    _serviceSubscriptions.clear();
  }

  void _updateAvailableServicesWithTravel(
    List<dynamic> firestoreServices,
  ) async {
    Position? currentPos;
    try {
      // Best effort location
      currentPos = await Geolocator.getLastKnownPosition();
      currentPos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ [Location] Could not get location for distance calc: $e');
    }

    final updated = firestoreServices.map((s) {
      if (currentPos != null &&
          s['latitude'] != null &&
          s['longitude'] != null) {
        final double lat = s['latitude'] is String
            ? double.parse(s['latitude'])
            : s['latitude'];
        final double lon = s['longitude'] is String
            ? double.parse(s['longitude'])
            : s['longitude'];

        final dist =
            Geolocator.distanceBetween(
              currentPos.latitude,
              currentPos.longitude,
              lat,
              lon,
            ) /
            1000.0; // km
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
    if (!mounted) return;

    final idStr = data?['service_id']?.toString() ?? data?['id']?.toString();
    final status = data?['status']?.toString().toLowerCase().trim() ?? '';
    final providerId = data?['provider_id']?.toString().trim();
    final shouldDisappearFromAvailable =
        idStr != null &&
        idStr.isNotEmpty &&
        (_isTerminalStatus(status) ||
            (providerId != null && providerId.isNotEmpty) ||
            !{
              'pending',
              'open_for_schedule',
              'searching',
              'searching_provider',
              'search_provider',
              'waiting_provider',
            }.contains(status));

    if (shouldDisappearFromAvailable) {
      setState(() {
        _availableServices.removeWhere((s) => s['id']?.toString() == idStr);
        if (_availableServices.isEmpty) {
          _notifText = null;
        } else {
          final first = _availableServices.first;
          _notifText =
              '${first['category_name'] ?? first['description'] ?? 'Serviço'} - ${first['address'] ?? ''}';
        }
      });
    }

    if (data != null && data['status'] == 'open_for_schedule') {
      debugPrint(
        '🔄 [ProviderHome] Service became open_for_schedule. Forcing refresh.',
      );
      _loadData(showLoading: false);
    } else {
      _loadData(showLoading: false); // Avoid full screen loading for updates
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
          _notifText =
              '${first['category_name'] ?? first['description'] ?? 'Serviço'} - ${first['address'] ?? ''}';
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
      _avatarTrace('🧭 [AvatarFlow] ProviderHomeMobile iniciou _loadAvatar()');
      final bytes = await _media.loadMyAvatarBytes();
      if (mounted && bytes != null) {
        _avatarTrace(
          '🧭 [AvatarFlow] ProviderHomeMobile carregou avatar em memória | bytes=${bytes.length}',
        );
        setState(() => _avatarBytes = bytes);
      } else {
        _avatarTrace(
          '⚠️ [AvatarFlow] ProviderHomeMobile não recebeu bytes de avatar após recarregar.',
        );
      }
    } catch (e) {
      _avatarTrace('⚠️ [AvatarFlow] ProviderHomeMobile _loadAvatar falhou: $e');
    }
  }

  Future<void> _editAvatar() async {
    if (_isUploadingAvatar) return;
    _avatarTrace('🧭 [AvatarFlow] ProviderHomeMobile iniciou _editAvatar()');

    if (kIsWeb) {
      final res = await _media.pickImageWeb();
      if (res == null || res.files.isEmpty || res.files.first.bytes == null) {
        _avatarTrace(
          '⚠️ [AvatarFlow] ProviderHomeMobile cancelou seleção web ou arquivo veio sem bytes.',
        );
        return;
      }
      final file = res.files.first;
      final ext = file.extension?.toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
      setState(() => _isUploadingAvatar = true);
      try {
        _avatarTrace(
          '🧭 [AvatarFlow] ProviderHomeMobile enviando avatar web | file=${file.name} | mime=$mime | bytes=${file.bytes!.length}',
        );
        await _media.uploadAvatarBytes(file.bytes!, file.name, mime);
        await _loadAvatar();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto de perfil atualizada com sucesso!'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao atualizar foto: $e')));
      } finally {
        if (mounted) setState(() => _isUploadingAvatar = false);
      }
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Usar câmera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final xfile = await _media.pickImageMobile(source);
    if (xfile == null) {
      _avatarTrace(
        '⚠️ [AvatarFlow] ProviderHomeMobile cancelou captura/galeria no mobile.',
      );
      return;
    }

    final bytes = await xfile.readAsBytes();
    final ext = xfile.name.split('.').last.toLowerCase();
    final mime = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    setState(() => _isUploadingAvatar = true);
    try {
      _avatarTrace(
        '🧭 [AvatarFlow] ProviderHomeMobile enviando avatar mobile | file=${xfile.name} | mime=$mime | bytes=${bytes.length}',
      );
      await _media.uploadAvatarBytes(bytes, xfile.name, mime);
      await _loadAvatar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil atualizada com sucesso!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao atualizar foto: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _api.getMyProfile();

      if (mounted) {
        setState(() {
          _userName = user['name'] ?? user['full_name'];
          final walletRaw =
              user['wallet_balance_effective'] ??
              user['wallet_balance'] ??
              user['balance'] ??
              0;
          _walletBalance = walletRaw is num
              ? walletRaw.toDouble()
              : double.tryParse('$walletRaw') ?? 0;

          final provRaw = user['providers'];
          final prov = provRaw is List && provRaw.isNotEmpty
              ? provRaw.first
              : provRaw;
          if (prov is Map) {
            final latRaw = prov['latitude'];
            final lonRaw = prov['longitude'];
            _providerLat = latRaw is num
                ? latRaw.toDouble()
                : double.tryParse('$latRaw');
            _providerLon = lonRaw is num
                ? lonRaw.toDouble()
                : double.tryParse('$lonRaw');
          }
        });

        if (user['id'] != null) {
          _currentUserId = user['id']?.toString();
          RealtimeService().authenticate(_currentUserId!);
          _initSocket(); // garante init(userId) quando o ID fica disponível
          // Mobile Provider: Ensure tracking is ON
          final authUid = Supabase.instance.client.auth.currentUser?.id;
          final uid = (authUid ?? user['supabase_uid'] ?? '').toString();
          if (!kIsWeb) {
            RealtimeService().startLocationUpdates(
              _currentUserId!,
              userUid: uid,
            );
          }
          _listenToServiceOffers(_currentUserId!);
        }

        if (user['professions'] != null) {
          _myProfessions = List<String>.from(user['professions']);
          _listenToAvailableServices(); // Start listening after we know professions
        }
      }
    } catch (e) {
      debugPrint('❌ [ProviderHomeMobile] _loadProfile erro: $e');
      _ensureOfferListenerFromAuth();
    }
  }

  void _listenToServiceOffers(String providerUserIdText) {
    final providerUserId = int.tryParse(providerUserIdText.trim());
    if (providerUserId == null || providerUserId <= 0) return;
    _offersSub?.cancel();
    _offersRetryTimer?.cancel();
    _markOffersStreamDegraded();
    // Backend-first: ofertas chegam via API JSON (polling canônico).
    unawaited(_pollOffersFallback());
  }

  void _scheduleOffersResubscribe(String providerUserIdText, String reason) {
    if (!mounted || providerUserIdText.trim().isEmpty) return;
    if (_offersRebindInProgress) return;

    _offersRetryTimer?.cancel();
    if (!_networkStatus.canAttemptSupabase) {
      debugPrint(
        '🔁 [ProviderHomeMobile] notificacao_de_servicos aguardando rede/back-end para religar providerUserId=$providerUserIdText',
      );
      _offersRetryTimer = Timer(const Duration(seconds: 15), () async {
        if (!mounted) return;
        await _networkStatus.refreshConnectivity();
        if (_networkStatus.canAttemptSupabase) {
          _listenToServiceOffers(providerUserIdText);
        }
      });
      return;
    }
    _offersRetryAttempt = (_offersRetryAttempt + 1).clamp(1, 10);
    final seconds = (2 << (_offersRetryAttempt - 1)).clamp(2, 60);
    debugPrint(
      '🔁 [ProviderHomeMobile] retry notificacao_de_servicos in ${seconds}s '
      'attempt=$_offersRetryAttempt providerUserId=$providerUserIdText reason=$reason',
    );

    _offersRetryTimer = Timer(Duration(seconds: seconds), () async {
      if (!mounted) return;
      _offersRebindInProgress = true;
      try {
        await RealtimeService().requestSocketReconnect();
        _listenToServiceOffers(providerUserIdText);
        if (_offersStreamDegraded) {
          unawaited(_pollOffersFallback());
          if (_offersStreamDegradedSince != null &&
              DateTime.now().difference(_offersStreamDegradedSince!) >=
                  const Duration(seconds: 15)) {
            unawaited(_loadData(showLoading: false));
          }
        }
      } finally {
        _offersRebindInProgress = false;
      }
    });
  }

  Future<void> _onServiceOffered(Map<String, dynamic> data) async {
    if (!mounted) return;
    _loadData();

    final serviceId = data['id'] ?? data['service_id'];
    if (serviceId != null) {
      final sId = serviceId.toString();
      if (_openOfferIds.contains(sId)) return;
      if (_isOfferInLocalCooldown(sId)) return;
      _openOfferIds.add(sId);

      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ServiceOfferModal(
          serviceId: sId,
          initialData: data,
          onAccepted: () {
            _loadData(showLoading: false);
          },
          onRejected: () => _loadData(showLoading: false),
        ),
      );
      if (accepted == true) {
        _loadData(showLoading: false);
        _openProviderActiveFlow(sId);
      } else {
        _setOfferLocalCooldown(sId);
      }
      if (!mounted) return;
      _openOfferIds.remove(sId);
    }
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (_loadingData || !mounted) return;
    if (!_networkStatus.canAttemptSupabase) {
      return;
    }
    _loadingData = true;
    if (showLoading) {
      _isLoadingVN.value = true;
    }

    await Future.wait([_loadAvatar(), _loadProfile()]);
    _ensureOfferListenerFromAuth();

    try {
      final availableNow = await _api.getAvailableServices();
      final availableSched = await _api.getAvailableForSchedule();
      final my = await DataGateway().loadMyServices();
      debugPrint('📋 [DEBUG] availableNow: ${availableNow.length} items');
      debugPrint('📋 [DEBUG] availableSched: ${availableSched.length} items');
      debugPrint('📋 [DEBUG] myServices: ${my.length} items');
      if (availableNow.isNotEmpty) {
        debugPrint('📋 [DEBUG] availableNow[0]: ${availableNow.first}');
      }
      if (availableSched.isNotEmpty) {
        debugPrint('📋 [DEBUG] availableSched[0]: ${availableSched.first}');
      }

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

      List<dynamic> combinedAvailable = uniqueServices.values.toList();
      combinedAvailable = await _filterOutPrivateDispatchServices(
        combinedAvailable,
      );
      final shouldLoadEmergencyAvailable =
          combinedAvailable.isEmpty ||
          combinedAvailable.whereType<Map>().any(
            (service) => _shouldEnrichAvailableService(
              Map<String, dynamic>.from(service),
            ),
          );
      List<dynamic> emergencyAvailable = const [];
      if (shouldLoadEmergencyAvailable) {
        emergencyAvailable = await _loadEmergencyOpenServices();
      }
      if (combinedAvailable.isEmpty) {
        if (emergencyAvailable.isNotEmpty) {
          combinedAvailable = emergencyAvailable;
        }
      } else if (emergencyAvailable.isNotEmpty) {
        combinedAvailable = _mergeAvailableServicesWithCanonicalRows(
          combinedAvailable,
          emergencyAvailable,
        );
      }
      combinedAvailable = _mergeAvailableServicesPreservingRichData(
        combinedAvailable,
        _availableServices,
      );

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
          _maybeRedirectToActiveService(my);
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

  Future<List<dynamic>> _loadEmergencyOpenServices() async {
    try {
      final rows = await DataGateway().loadEmergencyOpenServices(limit: 30);

      final mapped = rows
          .map((row) {
            final m = Map<String, dynamic>.from(row);
            final categoryRel = m['service_categories'];
            if (categoryRel is Map && categoryRel['name'] != null) {
              m['category_name'] = categoryRel['name'];
            }
            final price =
                double.tryParse(m['price_estimated']?.toString() ?? '0') ?? 0.0;
            m['provider_amount'] = double.parse(
              (price * 0.85).toStringAsFixed(2),
            );
            return m;
          })
          .where((service) => _matchesProviderProfession(service))
          .toList();

      final providerUserId = int.tryParse(_currentUserId?.trim() ?? '');
      final rejectedIds = providerUserId != null && providerUserId > 0
          ? await DataGateway().loadRejectedServiceIdsForProvider(
              providerUserId,
            )
          : <String>{};

      final withoutRejected = mapped.where((service) {
        final id = service['id']?.toString().trim() ?? '';
        return id.isNotEmpty && !rejectedIds.contains(id);
      }).toList();

      final filtered = await _filterOutPrivateDispatchServices(withoutRejected);

      debugPrint(
        '🛟 [ProviderHomeMobile] fallback direto service_requests: ${filtered.length} itens públicos',
      );
      return filtered;
    } catch (e) {
      debugPrint('⚠️ [ProviderHomeMobile] _loadEmergencyOpenServices erro: $e');
      return [];
    }
  }

  bool _shouldEnrichAvailableService(Map<String, dynamic> service) {
    final status = normalizeServiceStatus(service['status']?.toString());
    if (status != TripStatuses.openForSchedule) return false;
    final description = (service['description'] ?? '').toString().trim();
    final address = (service['address'] ?? '').toString().trim();
    final profession = (service['profession'] ?? '').toString().trim();
    final categoryName = (service['category_name'] ?? '').toString().trim();
    final lat = service['latitude'] is num
        ? (service['latitude'] as num).toDouble()
        : double.tryParse('${service['latitude'] ?? ''}');
    final lon = service['longitude'] is num
        ? (service['longitude'] as num).toDouble()
        : double.tryParse('${service['longitude'] ?? ''}');
    return description.isEmpty ||
        _isUnavailableAddress(address) ||
        lat == null ||
        lon == null ||
        (profession.isEmpty && categoryName.isEmpty);
  }

  bool _isUnavailableAddress(String? value) {
    final normalized = (value ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return normalized.isEmpty ||
        normalized == 'endereço não disponível' ||
        normalized == 'endereco nao disponivel' ||
        normalized == 'endereco não disponivel' ||
        normalized == 'endereço nao disponível';
  }

  List<dynamic> _mergeAvailableServicesPreservingRichData(
    List<dynamic> incoming,
    List<dynamic> existing,
  ) {
    if (incoming.isEmpty || existing.isEmpty) return incoming;
    final existingById = <String, Map<String, dynamic>>{};
    for (final item in existing) {
      if (item is! Map) continue;
      final mapped = Map<String, dynamic>.from(item);
      final id = (mapped['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      existingById[id] = mapped;
    }

    String? preferredString(
      Map<String, dynamic> fresh,
      Map<String, dynamic> current,
      String key, {
      bool Function(String value)? isInvalid,
    }) {
      final freshValue = (fresh[key] ?? '').toString().trim();
      final freshInvalid =
          freshValue.isEmpty || (isInvalid?.call(freshValue) ?? false);
      if (!freshInvalid) return freshValue;
      final currentValue = (current[key] ?? '').toString().trim();
      final currentInvalid =
          currentValue.isEmpty || (isInvalid?.call(currentValue) ?? false);
      return currentInvalid ? null : currentValue;
    }

    dynamic preferredNumeric(
      Map<String, dynamic> fresh,
      Map<String, dynamic> current,
      String key,
    ) {
      final freshValue = fresh[key];
      final freshNumber = freshValue is num
          ? freshValue.toDouble()
          : double.tryParse('${freshValue ?? ''}');
      if (freshNumber != null) return freshValue;

      final currentValue = current[key];
      final currentNumber = currentValue is num
          ? currentValue.toDouble()
          : double.tryParse('${currentValue ?? ''}');
      return currentNumber == null ? freshValue : currentValue;
    }

    return incoming.map((item) {
      if (item is! Map) return item;
      final fresh = Map<String, dynamic>.from(item);
      final id = (fresh['id'] ?? '').toString().trim();
      final current = existingById[id];
      if (id.isEmpty || current == null) return fresh;

      fresh['description'] =
          preferredString(fresh, current, 'description') ??
          fresh['description'];
      fresh['address'] =
          preferredString(
            fresh,
            current,
            'address',
            isInvalid: _isUnavailableAddress,
          ) ??
          fresh['address'];
      fresh['profession'] =
          preferredString(fresh, current, 'profession') ?? fresh['profession'];
      fresh['category_name'] =
          preferredString(fresh, current, 'category_name') ??
          fresh['category_name'];
      fresh['task_name'] =
          preferredString(fresh, current, 'task_name') ?? fresh['task_name'];
      fresh['latitude'] = preferredNumeric(fresh, current, 'latitude');
      fresh['longitude'] = preferredNumeric(fresh, current, 'longitude');
      fresh['price_estimated'] = preferredNumeric(
        fresh,
        current,
        'price_estimated',
      );
      fresh['price_upfront'] = preferredNumeric(
        fresh,
        current,
        'price_upfront',
      );
      fresh['provider_amount'] = preferredNumeric(
        fresh,
        current,
        'provider_amount',
      );
      return fresh;
    }).toList();
  }

  List<dynamic> _mergeAvailableServicesWithCanonicalRows(
    List<dynamic> available,
    List<dynamic> canonicalRows,
  ) {
    if (available.isEmpty || canonicalRows.isEmpty) return available;
    final canonicalById = <String, Map<String, dynamic>>{};
    for (final row in canonicalRows) {
      if (row is! Map) continue;
      final mapped = Map<String, dynamic>.from(row);
      final id = (mapped['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      canonicalById[id] = mapped;
    }

    return available.map((item) {
      if (item is! Map) return item;
      final current = Map<String, dynamic>.from(item);
      final id = (current['id'] ?? '').toString().trim();
      final canonical = canonicalById[id];
      if (id.isEmpty || canonical == null) return current;

      String? takeIfMissing(String key) {
        final currentValue = (current[key] ?? '').toString().trim();
        if (currentValue.isNotEmpty) return null;
        final canonicalValue = (canonical[key] ?? '').toString().trim();
        return canonicalValue.isEmpty ? null : canonicalValue;
      }

      dynamic takeNumericIfMissing(String key) {
        final currentValue = current[key];
        final currentNumber = currentValue is num
            ? currentValue.toDouble()
            : double.tryParse('${currentValue ?? ''}');
        if (currentNumber != null) return currentValue;

        final canonicalValue = canonical[key];
        final canonicalNumber = canonicalValue is num
            ? canonicalValue.toDouble()
            : double.tryParse('${canonicalValue ?? ''}');
        return canonicalNumber == null ? currentValue : canonicalValue;
      }

      current['description'] =
          takeIfMissing('description') ?? current['description'];
      current['address'] = takeIfMissing('address') ?? current['address'];
      current['profession'] =
          takeIfMissing('profession') ?? current['profession'];
      current['category_name'] =
          takeIfMissing('category_name') ?? current['category_name'];
      current['task_name'] = takeIfMissing('task_name') ?? current['task_name'];
      current['latitude'] = takeNumericIfMissing('latitude');
      current['longitude'] = takeNumericIfMissing('longitude');
      current['price_estimated'] = takeNumericIfMissing('price_estimated');
      current['price_upfront'] = takeNumericIfMissing('price_upfront');
      return current;
    }).toList();
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

  Future<Map<String, dynamic>?> _hydrateAvailableServiceDetails(
    Map<String, dynamic> service,
  ) async {
    final serviceId = (service['id'] ?? '').toString().trim();
    if (serviceId.isEmpty) return null;
    if (_travelHydrationAttemptedIds.contains(serviceId)) {
      return null;
    }
    _travelHydrationAttemptedIds.add(serviceId);
    try {
      final directRow = await DataGateway().loadServiceRequestById(serviceId);
      final details =
          directRow ??
          await _api.getServiceDetails(
            serviceId,
            scope: ServiceDataScope.mobileOnly,
            forceRefresh: true,
          );
      if (details['not_found'] == true) return null;
      final merged = {...service, ...details, 'id': serviceId};
      if (!mounted) return merged;
      setState(() {
        _availableServices = _availableServices.map((item) {
          if (item is! Map) return item;
          final currentId = (item['id'] ?? '').toString().trim();
          if (currentId != serviceId) return item;
          return merged;
        }).toList();
      });
      return Map<String, dynamic>.from(merged);
    } catch (e) {
      debugPrint(
        '⚠️ [ProviderHomeMobile] Falha ao hidratar detalhes do serviço $serviceId: $e',
      );
      return null;
    }
  }

  Future<void> _loadTravelForService(Map<String, dynamic> s) async {
    final id = s['id']?.toString();
    debugPrint('🚦 [Travel] Loading for service $id');
    try {
      Map<String, dynamic> resolved = Map<String, dynamic>.from(s);
      double? toLat = resolved['latitude'] is num
          ? (resolved['latitude'] as num).toDouble()
          : double.tryParse('${resolved['latitude']}');
      double? toLon = resolved['longitude'] is num
          ? (resolved['longitude'] as num).toDouble()
          : double.tryParse('${resolved['longitude']}');

      if (toLat == null || toLon == null) {
        final hydrated = await _hydrateAvailableServiceDetails(resolved);
        if (hydrated != null) {
          resolved = hydrated;
          toLat = resolved['latitude'] is num
              ? (resolved['latitude'] as num).toDouble()
              : double.tryParse('${resolved['latitude']}');
          toLon = resolved['longitude'] is num
              ? (resolved['longitude'] as num).toDouble()
              : double.tryParse('${resolved['longitude']}');
        }
      }

      if (toLat == null || toLon == null) {
        debugPrint('❌ [Travel] Invalid destination coords for $id');
        return;
      }

      // ... (Fuel logic skipped for brevity, keeping existing if needed but focusing on distance) ...
      double? gasolina = 6.0; // Default fallback to ensure calc runs

      double? fromLat;
      double? fromLon;
      try {
        // Web does not support getLastKnownPosition in geolocator_web.
        Position? lastPos;
        if (!kIsWeb) {
          lastPos = await Geolocator.getLastKnownPosition();
        }
        if (lastPos != null) {
          fromLat = lastPos.latitude;
          fromLon = lastPos.longitude;
        } else {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 5),
            ),
          );
          fromLat = pos.latitude;
          fromLon = pos.longitude;
        }
        debugPrint('📍 [Travel] Got start pos: $fromLat, $fromLon');
      } catch (e) {
        _logLocationWarning(e, context: 'Travel');
      }

      // Fallback if no location
      if (fromLat == null) {
        if (_providerLat != null && _providerLon != null) {
          debugPrint(
            '⚠️ [Travel] No device location. Using provider profile coords.',
          );
          fromLat = _providerLat;
          fromLon = _providerLon;
        } else {
          debugPrint('⚠️ [Travel] No location found. Using fallback coords.');
          fromLat = -5.5265; // Imperatriz/MA (default for this app)
          fromLon = -47.4761;
        }
      }

      debugPrint('📍 [Travel] Service coords: $toLat, $toLon');
      debugPrint('📍 [Travel] Provider coords: $fromLat, $fromLon');

      // Calculate locally using Geolocator (Haversine)
      final distMeters = Geolocator.distanceBetween(
        fromLat!,
        fromLon!,
        toLat,
        toLon,
      );
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

  void _logLocationWarning(Object error, {required String context}) {
    final text = error.toString().toLowerCase();
    final isPermissionDenied =
        text.contains('denied permissions') ||
        text.contains('permission denied') ||
        text.contains('locationpermission.denied') ||
        text.contains('locationpermission.deniedforever');
    if (!isPermissionDenied) {
      debugPrint('⚠️ [$context] Location error: $error');
      return;
    }

    final now = DateTime.now();
    if (_lastLocationPermissionLogAt != null &&
        now.difference(_lastLocationPermissionLogAt!) <
            const Duration(minutes: 1)) {
      return;
    }
    _lastLocationPermissionLogAt = now;
    debugPrint(
      '⚠️ [$context] Location permission denied. Mantendo fallback sem repetir logs.',
    );
  }

  Future<void> _openNavigation(Map<String, dynamic> s) async {
    final toLat = s['latitude'] is num
        ? (s['latitude'] as num).toDouble()
        : double.tryParse('${s['latitude']}');
    final toLon = s['longitude'] is num
        ? (s['longitude'] as num).toDouble()
        : double.tryParse('${s['longitude']}');
    if (toLat == null || toLon == null) return;

    await NavigationHelper.openNavigation(latitude: toLat, longitude: toLon);
  }

  void _showWithdrawalDialog() async {
    final success = await showDialog<bool>(
      context: context,
      builder: (context) =>
          WithdrawalDialog(api: _api, currentBalance: _walletBalance),
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
        child: Column(
          children: [
            _buildNetworkStatusBanner(),
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(child: _buildHeader(context)),

                  // Removed _buildNewOpportunityCard
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SliverAppBarDelegate(
                      TabBar(
                        controller: _tabController,
                        labelColor: AppTheme.darkBlueText,
                        unselectedLabelColor: Colors.grey[600],
                        labelStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                        indicatorColor: AppTheme.darkBlueText,
                        indicatorWeight: 3,
                        indicatorSize: TabBarIndicatorSize.label,
                        tabs: [
                          Tab(
                            child: _buildTabLabel(
                              'Meus',
                              _myServices.where((s) {
                                final st = s['status']
                                    ?.toString()
                                    .toLowerCase();
                                return st != 'completed' &&
                                    st != 'cancelled' &&
                                    st != 'canceled';
                              }).length,
                            ),
                          ),
                          Tab(
                            child: _buildTabLabel(
                              'Disponíveis',
                              _availableServices.length,
                            ),
                          ),
                          Tab(
                            child: _buildTabLabel(
                              'Finalizados',
                              _myServices.where((s) {
                                final st = s['status']
                                    ?.toString()
                                    .toLowerCase();
                                return st == 'completed' ||
                                    st == 'cancelled' ||
                                    st == 'canceled';
                              }).length,
                            ),
                          ),
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
                            return st != 'completed' &&
                                st != 'cancelled' &&
                                st != 'canceled';
                          }).toList()..sort((a, b) {
                            // Prioritize 'accepted' or 'in_progress' over 'pending'
                            final statusA =
                                a['status']?.toString().toLowerCase() ?? '';
                            final statusB =
                                b['status']?.toString().toLowerCase() ?? '';
                            if (statusA == 'in_progress' &&
                                statusB != 'in_progress') {
                              return -1;
                            }
                            if (statusB == 'in_progress' &&
                                statusA != 'in_progress') {
                              return 1;
                            }
                            if (statusA == 'accepted' &&
                                (statusB != 'accepted' &&
                                    statusB != 'in_progress')) {
                              return -1;
                            }
                            if (statusB == 'accepted' &&
                                (statusA != 'accepted' &&
                                    statusA != 'in_progress')) {
                              return 1;
                            }
                            return 0;
                          }),
                          emptyStateContext: 'provider-mobile-my-empty',
                        ),
                        _buildServiceList(
                          _availableServices,
                          isAvailable: true,
                          emptyStateContext: 'provider-mobile-available-empty',
                        ),
                        _buildServiceList(
                          _myServices.where((s) {
                            final st = s['status']?.toString().toLowerCase();
                            return st == 'completed' ||
                                st == 'cancelled' ||
                                st == 'canceled';
                          }).toList(),
                          emptyStateContext: 'provider-mobile-finished-empty',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkStatusBanner() {
    if (_networkSnapshot.isOnline) {
      return const SizedBox.shrink();
    }

    final isOffline = _networkSnapshot.isOffline;
    final bgColor = isOffline
        ? const Color(0xFFFFF4CC)
        : const Color(0xFFFFE4D6);
    final textColor = isOffline
        ? const Color(0xFF7A5A00)
        : const Color(0xFF8A3B12);
    final text = isOffline
        ? 'Sem rede no momento. A tela vai retomar sozinha quando a conexão voltar.'
        : 'Servidor temporariamente indisponível. Vamos tentar sincronizar novamente.';

    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
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
                    Stack(
                      alignment: Alignment.bottomRight,
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
                                  child: Text(
                                    'P',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        GestureDetector(
                          onTap: _isUploadingAvatar ? null : _editAvatar,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            child: _isUploadingAvatar
                                ? const SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    LucideIcons.camera,
                                    color: Colors.white,
                                    size: 10,
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Olá,',
                            style: TextStyle(color: Colors.black54),
                          ),
                          Text(
                            _userName ?? 'Prestador',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
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
                          stream:
                              Supabase.instance.client.auth.currentUser?.id !=
                                  null
                              ? DataGateway().watchNotifications(
                                  Supabase.instance.client.auth.currentUser!.id,
                                )
                              : const Stream.empty(),
                          builder: (context, snapshot) {
                            final notifications = snapshot.data ?? [];
                            final unreadCount = notifications
                                .where(
                                  (n) =>
                                      n['read'] != true && n['is_read'] != true,
                                )
                                .length;

                            return Stack(
                              alignment: Alignment.topRight,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    LucideIcons.bell,
                                    color: Colors.black87,
                                  ),
                                  onPressed: () async {
                                    await NotificationDropdownMenu.show(
                                      context,
                                    );
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
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Saldo disponível',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.wallet,
                          color: Colors.black87,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'R\$ ${_walletBalance.toStringAsFixed(2).replaceAll('.', ',')}',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Removido a pedido do usuário: prestadores não podem ser motoristas ao mesmo tempo.
        ],
      ),
    );
  }

  Widget _buildServiceList(
    List<dynamic> items, {
    bool isAvailable = false,
    String emptyStateContext = 'provider-mobile-empty',
  }) {
    if (items.isEmpty) {
      final emptyTitle = isAvailable
          ? 'Nenhuma oportunidade no momento'
          : emptyStateContext == 'provider-mobile-finished-empty'
          ? 'Você não tem serviços finalizados'
          : 'Você não tem serviços ativos';
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
                emptyTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AdCarousel(
                    height: 220,
                    placement: 'home-banner',
                    appContext: emptyStateContext,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        _ensureLoadTravelForItem(item);
        final id = item['id']?.toString();
        final travel = id != null ? _travelById[id] : null;

        return ProviderServiceCard(
          key: ValueKey('provider_service_${id ?? index}'),
          service: item,
          travelInfo: travel,
          onNavigate: () => _openNavigation(item),
          onAccept: null,
          onReject: isAvailable && id != null
              ? () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await _api.dispatch.rejectService(id);
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Serviço recusado.')),
                    );
                    _loadData(showLoading: false);
                  } catch (e) {
                    if (!mounted) return;
                    final message = e is ApiException && e.statusCode == 409
                        ? 'Oferta já não está mais disponível para recusa.'
                        : 'Erro ao recusar: $e';
                    messenger.showSnackBar(SnackBar(content: Text(message)));
                    if (e is ApiException && e.statusCode == 409) {
                      _loadData(showLoading: false);
                    }
                  }
                }
              : null,
          onArrive: id != null
              ? () async {
                  final messenger = ScaffoldMessenger.of(context);
                  setState(() => _isLoadingVN.value = true);
                  try {
                    await _api.arriveService(id);
                    if (mounted) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Cliente notificado!')),
                      );
                      _loadData();
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Erro ao notificar: $e')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isLoadingVN.value = false);
                  }
                }
              : null,
          onStart: id != null ? () => _startService(id) : null,
          onFinish: id != null
              ? () => context
                    .push('/provider-service-finish/$id')
                    .then((_) => _loadData())
              : null,
          onViewDetails: id != null
              ? () => context
                    .push('/provider-service-details/$id')
                    .then((_) => _loadData())
              : null,
          onSchedule: id != null
              ? (scheduledAt, message) async {
                  setState(() => _isLoadingVN.value = true);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await _api.proposeSchedule(
                      id,
                      scheduledAt,
                      scope: ServiceDataScope.mobileOnly,
                    );
                    if (mounted) {
                      _applyLocalScheduleProposalState(
                        id,
                        scheduledAt,
                        Map<String, dynamic>.from(item),
                      );
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Proposta enviada!')),
                      );
                      unawaited(_loadData(showLoading: false));
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Erro: $e')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isLoadingVN.value = false);
                  }
                }
              : null,
          onConfirmSchedule: (id != null && item['scheduled_at'] != null)
              ? () async {
                  setState(() => _isLoadingVN.value = true);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final scheduledAt = DateTime.parse(
                      item['scheduled_at'].toString(),
                    );
                    await _api.confirmSchedule(
                      id,
                      scheduledAt,
                      scope: ServiceDataScope.mobileOnly,
                    );
                    if (mounted) {
                      _applyLocalScheduleConfirmedState(
                        id,
                        scheduledAt,
                        Map<String, dynamic>.from(item),
                      );
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Agendamento confirmado!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      unawaited(_loadData(showLoading: false));
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Erro: $e')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isLoadingVN.value = false);
                  }
                }
              : null,
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
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.1),
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
  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(color: Colors.grey[50], child: _tabBar);
  @override
  bool shouldRebuild(covariant _SliverAppBarDelegate oldDelegate) => false;
}
