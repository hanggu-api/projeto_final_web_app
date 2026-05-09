// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/home/backend_client_home_state.dart';
import '../../core/home/backend_home_api.dart';
import '../../core/tracking/backend_tracking_api.dart';
import '../../core/utils/fixed_schedule_gate.dart';
import '../../core/utils/mobile_client_navigation_gate.dart';
import '../../services/theme_service.dart';
import '../../services/api_service.dart';
import '../../services/central_service.dart';
import '../../services/notification_service.dart';
import '../../services/global_startup_manager.dart';
import '../../services/device_capability_service.dart';
import '../../services/data_gateway.dart';
import '../../services/realtime_service.dart';
import '../payment/models/pending_fixed_booking_policy.dart';
import '../shared/chat_screen.dart';
import '../../widgets/ios_date_time_picker.dart';
import 'mixins/home_realtime_mixin.dart';
import 'mixins/home_service_mixin.dart';
import 'models/home_stage.dart';
import 'upcoming_appointment_details_screen.dart';
import 'home_state.dart';
import 'mixins/home_location_mixin.dart';
import 'mixins/home_search_mixin.dart';

import 'widgets/home_map_widget.dart';
import 'widgets/home_map_floating_controls.dart';
import 'widgets/home_explore_entry_card.dart';
import 'widgets/home_pending_fixed_payment_banner.dart';
import 'widgets/home_quick_category_group.dart';
import 'widgets/home_saved_places.dart';
import 'widgets/home_search_bar.dart';
import 'widgets/safe_stitch_header.dart';
import 'widgets/home_stage_panel_body.dart';
import 'widgets/home_upcoming_appointment_banner.dart';
import 'widgets/home_waiting_service_banner.dart';
import '../../widgets/ad_carousel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with
        TickerProviderStateMixin,
        WidgetsBindingObserver,
        HomeStateMixin<HomeScreen>,
        HomeLocationMixin<HomeScreen>,
        HomeSearchMixin<HomeScreen>,
        HomeRealtimeMixin<HomeScreen>,
        HomeServiceMixin<HomeScreen> {
  final ApiService _api = ApiService();
  final BackendHomeApi _backendHomeApi = const BackendHomeApi();
  final BackendTrackingApi _backendTrackingApi = const BackendTrackingApi();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  StreamSubscription? _servicesSubscription;
  bool _checkingPayments = false;
  Map<String, dynamic>? _activeServiceForBanner;
  Map<String, dynamic>? _pendingFixedPaymentBanner;
  Map<String, dynamic>? _upcomingAppointment;
  Timer? _appointmentRefreshTimer;
  Timer? _pendingFixedPaymentWatcherTimer;
  Timer? _pendingFixedPaymentExpiryTimer;
  Timer? _servicesListenerRetryTimer;
  Timer? _activeServiceBannerRefreshTimer;
  Timer? _activeServiceRecoveryTimer;
  StreamSubscription<List<dynamic>>? _upcomingAppointmentChatSubscription;
  Timer? _chatPreviewHideTimer;
  String? _lastShownHomeScheduleProposalKey;
  bool _isSubmittingHomeScheduleNegotiation = false;
  List<Map<String, dynamic>> _professionQuickAccessItems = [];
  final Map<String, Set<String>> _synonymLexicon = {};
  static const String _synonymLexiconCacheKey = 'home_synonym_lexicon_v1';
  bool _deferredStartupScheduled = false;
  bool _openingHomeSearch = false;
  int _servicesListenerRetryAttempt = 0;
  DateTime? _lastServicesRealtimeErrorLogAt;
  String? _lastServicesRealtimeErrorSignature;
  String? _lastTimeToLeaveNotificationId;
  int? _lastShownUpcomingChatMessageId;
  String? _chatPreviewServiceId;
  String? _chatPreviewTitle;
  String? _chatPreviewMessage;
  int? _chatPreviewLocalEventId;
  BackendClientHomeState? _lastBackendHomeSnapshot;
  DateTime? _lastBackendHomeSnapshotAt;
  void Function(dynamic)? _globalChatMessageHandler;
  bool _isForeground = true;
  bool _wasVisibleOnLastDependencyCheck = false;
  bool get _enableCentralRuntime => false;
  bool get _isExecutingActiveService => activeTrip != null;
  bool get uberTripMode => false;
  bool get _shouldSuppressAutoNavigation => false;
  bool get _shouldRenderLiveMap {
    if (_isExecutingActiveService) return true;
    if (isPickingOnMap) return true;
    if (routePolyline.isNotEmpty || arrivalPolyline.isNotEmpty) return true;
    if (DeviceCapabilityService.instance.prefersLightweightMaps) return true;
    return GlobalStartupManager.instance.canLoadHeavyWidgets.value;
  }

  bool get _shouldEnableMapLiveSensors =>
      !DeviceCapabilityService.instance.prefersLightweightMaps &&
      (_isExecutingActiveService || isPickingOnMap);

  String _formatCurrency(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return 'R\$ ${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _formatPendingScheduleLabel(dynamic rawValue) {
    final date = DateTime.tryParse((rawValue ?? '').toString())?.toLocal();
    if (date == null) return 'Horário pendente';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final target = DateTime(date.year, date.month, date.day);
    final timeLabel = DateFormat('HH:mm', 'pt_BR').format(date);
    if (target == today) return 'Hoje às $timeLabel';
    if (target == tomorrow) return 'Amanhã às $timeLabel';
    return DateFormat("dd/MM 'às' HH:mm", 'pt_BR').format(date);
  }

  String _buildPendingCompactSummary(Map<String, dynamic> pending) {
    final serviceLabel =
        (pending['task_name'] ??
                pending['description'] ??
                pending['profession_name'] ??
                'Agendamento')
            .toString()
            .trim();
    final whenLabel = _formatPendingScheduleLabel(pending['scheduled_at']);
    final pixLabel = _formatCurrency(
      pending['price_upfront'] ?? pending['pix_fee'],
    );
    return '$serviceLabel • $whenLabel • Pix $pixLabel';
  }

  bool get _shouldPinPendingFixedBanner => _pendingFixedPaymentBanner != null;

  double _homeSheetInitialSize(HomeStageSnapshot homeStage) {
    if (homeStage.isSearchMode) return 1.0;
    if (_shouldPinPendingFixedBanner) return 0.72;
    return 0.58;
  }

  double _homeSheetMinSize(HomeStageSnapshot homeStage) {
    if (homeStage.isSearchMode) return 1.0;
    if (_shouldPinPendingFixedBanner) return 0.56;
    return 0.30;
  }

  List<double> _homeSheetSnapSizes(HomeStageSnapshot homeStage) {
    if (homeStage.isSearchMode) return const [1.0];
    if (_shouldPinPendingFixedBanner) return const [0.56, 0.72, 0.95];
    return const [0.30, 0.58, 0.95];
  }

  void _ensurePendingFixedBannerVisible() {
    if (!_shouldPinPendingFixedBanner || !_sheetController.isAttached) return;
    final minSize = _homeSheetMinSize(
      HomeStageResolver.resolve(
        isSearchMode: false,
        hasPendingFixedPaymentBanner: true,
        hasUpcomingAppointment: _upcomingAppointment != null,
        showWaitingServiceBanner: _shouldShowHomeReturningServiceBanner(
          _activeServiceForBanner,
        ),
      ),
    );
    final target = _homeSheetInitialSize(
      HomeStageResolver.resolve(
        isSearchMode: false,
        hasPendingFixedPaymentBanner: true,
        hasUpcomingAppointment: _upcomingAppointment != null,
        showWaitingServiceBanner: _shouldShowHomeReturningServiceBanner(
          _activeServiceForBanner,
        ),
      ),
    );
    if (_sheetController.size < minSize) {
      _sheetController.jumpTo(target);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bellController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _scheduleDeferredStartup();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final location = GoRouterState.of(context).uri.toString();
    final isHomeVisible = location.startsWith('/home');
    if (isHomeVisible && !_wasVisibleOnLastDependencyCheck) {
      unawaited(_loadPendingFixedPaymentBanner());
      unawaited(_loadUpcomingAppointment());
      unawaited(_recoverActiveService());
    }
    _wasVisibleOnLastDependencyCheck = isHomeVisible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    _isForeground = isForeground;
    if (isForeground) {
      unawaited(_bootstrapChatUiState());
      _initAppointmentRefreshTimer();
      _startActiveServiceBannerRefreshLoop();
      _startActiveServiceRecoveryLoop();
      if (_pendingFixedPaymentBanner != null) {
        final intentId =
            (_pendingFixedPaymentBanner?['pending_fixed_booking_intent_id'] ??
                    _pendingFixedPaymentBanner?['id'])
                .toString()
                .trim();
        if (intentId.isNotEmpty) {
          _startPendingFixedPaymentWatcher(intentId);
        }
      }
      unawaited(_loadUpcomingAppointment());
      unawaited(_recoverActiveService());
      return;
    }
    _appointmentRefreshTimer?.cancel();
    _pendingFixedPaymentWatcherTimer?.cancel();
    _pendingFixedPaymentExpiryTimer?.cancel();
    _activeServiceBannerRefreshTimer?.cancel();
    _activeServiceRecoveryTimer?.cancel();
  }

  void _scheduleDeferredStartup() {
    if (_deferredStartupScheduled) return;
    _deferredStartupScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runPrimaryHomeStartup());
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          _runSecondaryHomeStartup,
        ),
      );
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 900),
          _runBackgroundHomeStartup,
        ),
      );
    });
  }

  Future<void> _runPrimaryHomeStartup() async {
    await _loadServices();
    if (!mounted) return;
    await _bootstrapChatUiState();
    if (!mounted) return;
    unawaited(checkLocationPermission());
    unawaited(_restoreSynonymLexiconFromCache());
  }

  Future<void> _runSecondaryHomeStartup() async {
    if (!mounted) return;
    await _loadPendingFixedPaymentBanner();
    if (!mounted) return;
    unawaited(_loadUpcomingAppointment());
    _initAppointmentRefreshTimer();
    unawaited(_loadProfile());
    unawaited(_loadSavedPlaces());
    unawaited(_loadServiceAutocompleteCatalog());
  }

  Future<void> _runBackgroundHomeStartup() async {
    if (!mounted) return;
    await _recoverAndInitHomeBackground();
    if (!mounted) return;
    _bindGlobalChatPreviewListener();
    unawaited(_listenToServices());
    _startActiveServiceBannerRefreshLoop();
    _startActiveServiceRecoveryLoop();
    unawaited(_checkPaymentProfileForClientOnHome());
  }

  Future<void> _recoverAndInitHomeBackground() async {
    try {
      await _recoverActiveService();
    } catch (_) {
      // ignora falhas de recuperação; home carrega normalmente
    }
  }

  Future<void> _bootstrapChatUiState() async {
    final unread = await DataGateway().loadUnreadChatCount();
    if (!mounted) return;
    setState(() {
      unreadCountCount = unread;
    });
  }

  bool get _canUseBackendClientHomeSnapshot {
    final role = (_api.role ?? '').trim().toLowerCase();
    return role.isEmpty || role == 'client';
  }

  Future<BackendClientHomeState?> _fetchBackendHomeSnapshot({
    bool force = false,
  }) async {
    if (!_canUseBackendClientHomeSnapshot) return null;

    if (!force &&
        _lastBackendHomeSnapshot != null &&
        _lastBackendHomeSnapshotAt != null) {
      final age = DateTime.now().difference(_lastBackendHomeSnapshotAt!);
      if (age < const Duration(seconds: 20)) {
        return _lastBackendHomeSnapshot;
      }
    }

    try {
      final snapshot = await _backendHomeApi.fetchClientHome();
      if (snapshot == null) return null;
      _lastBackendHomeSnapshot = snapshot;
      _lastBackendHomeSnapshotAt = DateTime.now();
      return snapshot;
    } catch (e) {
      debugPrint('⚠️ [Home] Snapshot backend da home indisponível: $e');
      return null;
    }
  }

  void _bindGlobalChatPreviewListener() {
    if (_globalChatMessageHandler != null) return;

    final rt = RealtimeService();
    final myUserId = (_api.userId ?? '').trim();

    void handleChatPreview(dynamic data) async {
      if (!mounted || !_isForeground) return;
      if (data is! Map) return;

      final payload = Map<String, dynamic>.from(data);
      final serviceId = (payload['service_id'] ?? payload['id'] ?? '')
          .toString()
          .trim();
      if (serviceId.isEmpty) return;
      if (ChatScreen.activeChatServiceId == serviceId) return;

      final senderId = (payload['sender_id'] ?? '').toString().trim();
      if (myUserId.isNotEmpty && senderId.isNotEmpty && senderId == myUserId) {
        return;
      }

      final latestUnread = await DataGateway().loadUnreadChatCount();

      final title =
          (payload['title'] ??
                  payload['sender_name'] ??
                  payload['provider_name'] ??
                  payload['client_name'] ??
                  'Nova mensagem')
              .toString()
              .trim();
      final message =
          (payload['body'] ?? payload['message'] ?? payload['content'])
              .toString()
              .trim();
      final localEventId = payload['message_id'] is int
          ? payload['message_id'] as int
          : int.tryParse('${payload['message_id'] ?? payload['id'] ?? ''}') ??
                DateTime.now().millisecondsSinceEpoch;

      if (_chatPreviewLocalEventId == localEventId) {
        if (mounted) {
          setState(() {
            unreadCountCount = latestUnread;
          });
        }
        return;
      }

      _chatPreviewHideTimer?.cancel();
      setState(() {
        unreadCountCount = latestUnread;
        _chatPreviewServiceId = serviceId;
        _chatPreviewTitle = title.isEmpty ? 'Nova mensagem' : title;
        _chatPreviewMessage = message.isEmpty
            ? 'Toque para abrir a conversa.'
            : message;
        _chatPreviewLocalEventId = localEventId;
      });

      _chatPreviewHideTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() {
          _chatPreviewServiceId = null;
          _chatPreviewTitle = null;
          _chatPreviewMessage = null;
        });
      });
    }

    _globalChatMessageHandler = handleChatPreview;
    rt.on('chat.message', handleChatPreview);
    rt.on('chat_message', handleChatPreview);
  }

  void _openTopChatPreview() {
    final serviceId = _chatPreviewServiceId?.trim() ?? '';
    if (serviceId.isEmpty) return;
    _chatPreviewHideTimer?.cancel();
    setState(() {
      _chatPreviewServiceId = null;
      _chatPreviewTitle = null;
      _chatPreviewMessage = null;
    });
    final appointment = _upcomingAppointment;
    final participants = appointment == null
        ? const <Map<String, dynamic>>[]
        : DataGateway().extractChatParticipants(appointment);
    context.push(
      '/chat/$serviceId',
      extra: {'serviceId': serviceId, 'participants': participants},
    );
  }

  Future<void> _loadPendingFixedPaymentBanner() async {
    if (_api.role != null && _api.role != 'client') {
      _pendingFixedPaymentWatcherTimer?.cancel();
      _pendingFixedPaymentExpiryTimer?.cancel();
      if (mounted && _pendingFixedPaymentBanner != null) {
        setState(() => _pendingFixedPaymentBanner = null);
      }
      return;
    }

    try {
      final snapshot = await _fetchBackendHomeSnapshot();
      final snapshotPending = snapshot?.pendingFixedPayment;
      if (snapshotPending != null) {
        final pending = Map<String, dynamic>.from(snapshotPending);
        final banner = <String, dynamic>{
          ...pending,
          'status': 'waiting_payment',
          'payment_status': pending['payment_status'] ?? 'pending',
          'provider_name':
              pending['provider_name'] ??
              pending['provider']?['commercial_name'] ??
              pending['provider']?['full_name'] ??
              'Salão parceiro',
          'provider_avatar':
              pending['provider_avatar'] ?? pending['provider']?['avatar_url'],
          'description':
              pending['task_name'] ??
              pending['profession_name'] ??
              pending['description'] ??
              'Agendamento pendente',
          'profession_name':
              pending['profession_name'] ?? pending['task_name'] ?? 'Serviço',
          'price_estimated':
              pending['price_estimated'] ?? pending['task_price'],
          'price_upfront': pending['price_upfront'] ?? pending['pix_fee'],
          'address': pending['address'] ?? pending['provider']?['address'],
          'latitude': pending['latitude'] ?? pending['provider']?['latitude'],
          'longitude':
              pending['longitude'] ?? pending['provider']?['longitude'],
          'provider_id': pending['prestador_user_id'] ?? pending['provider_id'],
          'location_type': pending['location_type'] ?? 'provider',
          'service_type': pending['service_type'] ?? 'at_provider',
          'is_fixed': pending['is_fixed'] ?? true,
          'at_provider': pending['at_provider'] ?? true,
          'pending_fixed_booking_intent_id': pending['id'],
          'pix_fee': pending['price_upfront'] ?? pending['pix_fee'],
        };

        if (mounted) {
          setState(() => _pendingFixedPaymentBanner = banner);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _ensurePendingFixedBannerVisible();
          });
        }
        _armPendingFixedPaymentExpiry(pending);
        _startPendingFixedPaymentWatcher(
          (pending['id'] ?? '').toString().trim(),
        );
        return;
      }

      if (_pendingFixedPaymentBanner != null) {
        debugPrint(
          '⚠️ [Home] Pendência fixa ausente no snapshot; preservando banner atual para evitar oscilação.',
        );
        return;
      }
      _pendingFixedPaymentWatcherTimer?.cancel();
      _pendingFixedPaymentExpiryTimer?.cancel();
      return;
    } catch (e) {
      debugPrint('❌ [Home] Erro ao carregar pendência fixa: $e');
    }
  }

  Future<void> _clearPendingFixedPixCache() async {
    await PendingFixedBookingPolicy.clearLocalCache();
  }

  void _armPendingFixedPaymentExpiry(Map<String, dynamic> pending) {
    _pendingFixedPaymentExpiryTimer?.cancel();
    final expiryAt = PendingFixedBookingPolicy.resolveExpiryAt(pending);
    if (expiryAt == null) return;

    final remaining = expiryAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      unawaited(_expirePendingFixedPaymentBanner());
      return;
    }

    _pendingFixedPaymentExpiryTimer = Timer(
      remaining,
      () => unawaited(_expirePendingFixedPaymentBanner()),
    );
  }

  Future<void> _expirePendingFixedPaymentBanner() async {
    _pendingFixedPaymentExpiryTimer?.cancel();
    _pendingFixedPaymentWatcherTimer?.cancel();
    await _clearPendingFixedPixCache();
    if (!mounted || _pendingFixedPaymentBanner == null) return;
    setState(() => _pendingFixedPaymentBanner = null);
  }

  void _startPendingFixedPaymentWatcher(String intentId) {
    if (intentId.isEmpty) {
      _pendingFixedPaymentWatcherTimer?.cancel();
      return;
    }

    _pendingFixedPaymentWatcherTimer?.cancel();
    _pendingFixedPaymentWatcherTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) async {
        if (!_isForeground) return;
        try {
          final detail = await _api.getPendingFixedBookingIntent(intentId);
          if (detail == null) {
            debugPrint(
              '⚠️ [Home] Watcher do PIX pendente recebeu detalhe nulo; mantendo banner atual até confirmação terminal explícita.',
            );
            return;
          }

          final decision = PendingFixedBookingPolicy.evaluate(detail);
          if (decision.shouldNavigateToScheduledService) {
            _pendingFixedPaymentWatcherTimer?.cancel();
            _pendingFixedPaymentExpiryTimer?.cancel();
            await _clearPendingFixedPixCache();
            if (!mounted) return;
            setState(() => _pendingFixedPaymentBanner = null);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Pagamento confirmado. Abrindo agendamento.'),
                backgroundColor: Colors.green,
              ),
            );
            context.go(decision.scheduledServiceRoute);
            return;
          }

          if (decision.shouldClearCache) {
            _pendingFixedPaymentWatcherTimer?.cancel();
            _pendingFixedPaymentExpiryTimer?.cancel();
            await _clearPendingFixedPixCache();
            if (!mounted) return;
            setState(() => _pendingFixedPaymentBanner = null);
            return;
          }

          _armPendingFixedPaymentExpiry(detail);
        } catch (e) {
          debugPrint('❌ [Home] Erro ao vigiar PIX pendente fixo: $e');
        }
      },
    );
  }

  Future<void> _openPendingFixedBookingFlow() async {
    final pending = _pendingFixedPaymentBanner;
    if (pending == null) {
      await context.push('/beauty-booking');
      if (!mounted) return;
      await _loadPendingFixedPaymentBanner();
      return;
    }
    final routeData = <String, dynamic>{
      'pending_fixed_booking_intent_id':
          (pending['pending_fixed_booking_intent_id'] ?? pending['id'])
              .toString()
              .trim(),
      'pending_fixed_payment_focus': true,
      'q':
          (pending['task_name'] ??
                  pending['description'] ??
                  pending['profession_name'] ??
                  'Agendamento')
              .toString()
              .trim(),
      'description':
          (pending['task_name'] ??
                  pending['description'] ??
                  pending['profession_name'] ??
                  'Agendamento')
              .toString()
              .trim(),
      'task_name': (pending['task_name'] ?? '').toString().trim(),
      'profession': (pending['profession_name'] ?? '').toString().trim(),
      'pre_selected_provider': {
        'id': pending['provider_id'],
        'commercial_name': pending['provider_name'],
        'full_name': pending['provider_name'],
        'address': pending['address'],
        'latitude': pending['latitude'],
        'longitude': pending['longitude'],
        'service_type': 'at_provider',
      },
    };
    await context.push('/beauty-booking', extra: routeData);
    if (!mounted) return;
    await _loadPendingFixedPaymentBanner();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _servicesSubscription?.cancel();
    _appointmentRefreshTimer?.cancel();
    _pendingFixedPaymentWatcherTimer?.cancel();
    _pendingFixedPaymentExpiryTimer?.cancel();
    _servicesListenerRetryTimer?.cancel();
    _activeServiceBannerRefreshTimer?.cancel();
    _activeServiceRecoveryTimer?.cancel();
    _upcomingAppointmentChatSubscription?.cancel();
    _chatPreviewHideTimer?.cancel();
    final handler = _globalChatMessageHandler;
    if (handler != null) {
      final rt = RealtimeService();
      rt.off('chat.message', handler);
      rt.off('chat_message', handler);
    }
    _sheetController.dispose();
    disposeHomeState();
    super.dispose();
  }

  Future<void> _restoreSynonymLexiconFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_synonymLexiconCacheKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _synonymLexicon.clear();
      decoded.forEach((key, value) {
        final token = key.toString().trim();
        if (token.isEmpty) return;
        if (value is List) {
          _synonymLexicon[token] = value
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toSet();
        }
      });
    } catch (_) {
      // best-effort cache restore
    }
  }

  Future<void> _persistSynonymLexiconToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, List<String>>{};
      _synonymLexicon.forEach((key, value) {
        if (key.isEmpty || value.isEmpty) return;
        payload[key] = value.toList()..sort();
      });
      await prefs.setString(_synonymLexiconCacheKey, jsonEncode(payload));
    } catch (_) {
      // best-effort cache persist
    }
  }

  Future<void> _loadServiceAutocompleteCatalog() async {
    try {
      final snapshot = await _fetchBackendHomeSnapshot(force: true);
      final catalog = List<Map<String, dynamic>>.from(snapshot?.services ?? []);
      if (!mounted) return;
      String norm(String value) => value
          .toLowerCase()
          .replaceAll('á', 'a')
          .replaceAll('à', 'a')
          .replaceAll('â', 'a')
          .replaceAll('ã', 'a')
          .replaceAll('ä', 'a')
          .replaceAll('é', 'e')
          .replaceAll('ê', 'e')
          .replaceAll('è', 'e')
          .replaceAll('ë', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ì', 'i')
          .replaceAll('î', 'i')
          .replaceAll('ï', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ò', 'o')
          .replaceAll('ô', 'o')
          .replaceAll('õ', 'o')
          .replaceAll('ö', 'o')
          .replaceAll('ú', 'u')
          .replaceAll('ù', 'u')
          .replaceAll('û', 'u')
          .replaceAll('ü', 'u')
          .replaceAll('ç', 'c');
      final tokenReg = RegExp(r'[a-z0-9]{3,}');

      final baseGroups = <List<String>>[
        ['corte', 'cortar', 'aparar', 'degrade', 'degradee'],
        ['barba', 'barbear', 'barbeiro'],
        ['sobrancelha', 'designer', 'design'],
        ['maquiagem', 'maquiar', 'make'],
        ['hidratar', 'hidratacao', 'hidra'],
        ['escova', 'escovar'],
        ['limpeza', 'faxina', 'higienizacao', 'higienizar'],
        ['encanador', 'encanamento', 'hidraulico', 'bombeiro'],
        ['eletricista', 'eletrica', 'eletrico'],
        ['montagem', 'montar', 'instalacao', 'instalar'],
        ['chaveiro', 'fechadura', 'chave'],
        ['grama', 'jardinagem', 'jardineiro', 'paisagismo'],
        ['pintura', 'pintor', 'pintar'],
      ];

      _synonymLexicon.clear();
      for (final group in baseGroups) {
        final g = group.map(norm).toSet();
        for (final token in g) {
          _synonymLexicon.putIfAbsent(token, () => <String>{}).addAll(g);
        }
      }

      final rows = catalog
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      for (final row in rows) {
        final profession = norm((row['profession_name'] ?? '').toString());
        final task = norm((row['task_name'] ?? row['name'] ?? '').toString());
        final keywords = norm((row['keywords'] ?? '').toString());
        final pool = '$profession $task $keywords';
        final tokens = tokenReg
            .allMatches(pool)
            .map((m) => m.group(0)!)
            .toSet()
            .where((t) => t.length >= 3)
            .toList();
        for (final t in tokens) {
          _synonymLexicon.putIfAbsent(t, () => <String>{}).add(t);
        }
        for (var i = 0; i < tokens.length; i++) {
          for (var j = i + 1; j < tokens.length; j++) {
            final a = tokens[i];
            final b = tokens[j];
            if (a.length < 4 || b.length < 4) continue;
            _synonymLexicon[a]!.add(b);
            _synonymLexicon[b]!.add(a);
          }
        }
      }

      setState(() {
        _professionQuickAccessItems = _buildProfessionQuickAccessItems(rows);
      });
      _persistSynonymLexiconToCache();
    } catch (_) {
      // Mantém estado atual se snapshot estiver indisponível.
    }
  }

  void _openServicesQuickAccess() {
    context.push('/home-search');
  }

  void _openServicesQuickAccessWithQuery(String rawQuery) {
    final query = rawQuery.trim();
    if (query.length < 2) return;
    if (_openingHomeSearch) return;
    _openingHomeSearch = true;
    context.push('/home-search', extra: {'query': query});
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      _openingHomeSearch = false;
    });
  }

  void _openBeautyQuickAccess() {
    context.push('/home-search', extra: {'query': 'beleza'});
  }

  List<Map<String, dynamic>> _buildProfessionQuickAccessItems(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final professionName = _stringValue(row['profession_name']);
      if (professionName.isEmpty) continue;
      final professionId = int.tryParse('${row['profession_id'] ?? ''}');
      final key =
          '${professionId ?? professionName}|${professionName.toLowerCase()}';
      final taskName = _stringValue(
        row['task_name'],
        fallback: _stringValue(row['name']),
      );
      final score = _extractProfessionRankingScore(row);

      final current = grouped[key];
      if (current == null) {
        grouped[key] = {
          'profession_id': professionId,
          'profession_name': professionName,
          'task_count': 1,
          'ranking_score': score,
          'sample_task': taskName,
          'service_type': _stringValue(row['service_type']),
        };
        continue;
      }

      current['task_count'] = (current['task_count'] as int) + 1;
      current['ranking_score'] = (current['ranking_score'] as int) + score;
      if ((_stringValue(current['sample_task'])).isEmpty &&
          taskName.isNotEmpty) {
        current['sample_task'] = taskName;
      }
    }

    final items = grouped.values
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final hasRankingData = items.any(
      (item) => ((item['ranking_score'] ?? 0) as int) > 0,
    );

    if (hasRankingData) {
      items.sort((a, b) {
        final byScore = ((b['ranking_score'] ?? 0) as int).compareTo(
          (a['ranking_score'] ?? 0) as int,
        );
        if (byScore != 0) return byScore;
        final byCount = ((b['task_count'] ?? 0) as int).compareTo(
          (a['task_count'] ?? 0) as int,
        );
        if (byCount != 0) return byCount;
        return _stringValue(
          a['profession_name'],
        ).compareTo(_stringValue(b['profession_name']));
      });
    } else {
      final random = math.Random();
      items.shuffle(random);
    }

    return items.take(12).toList();
  }

  int _extractProfessionRankingScore(Map<String, dynamic> row) {
    const candidates = [
      'completed_services_count',
      'services_completed_count',
      'service_count',
      'completed_count',
      'total_completed',
      'bookings_count',
      'requests_count',
    ];

    for (final key in candidates) {
      final raw = row[key];
      final parsed = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (parsed != null && parsed > 0) return parsed;
    }

    return 0;
  }

  int _professionQuickAccessTaskCount(Map<String, dynamic> item) {
    return item['task_count'] is num
        ? (item['task_count'] as num).toInt()
        : int.tryParse('${item['task_count'] ?? ''}') ?? 0;
  }

  bool _hasProfessionUsageRanking(Map<String, dynamic> item) {
    return _extractProfessionRankingScore(item) > 0;
  }

  String _professionQuickAccessMetricLabel(Map<String, dynamic> item) {
    final rankingScore = _extractProfessionRankingScore(item);
    if (rankingScore > 0) {
      return rankingScore == 1
          ? '1 atendimento concluido'
          : '$rankingScore atendimentos concluidos';
    }
    final taskCount = _professionQuickAccessTaskCount(item);
    if (taskCount > 1) {
      return '$taskCount servicos disponiveis';
    }
    if (taskCount == 1) {
      return '1 servico disponivel';
    }
    return 'Toque para ver servicos';
  }

  String _professionQuickAccessSummary(Map<String, dynamic> item) {
    final taskCount = item['task_count'] is num
        ? (item['task_count'] as num).toInt()
        : int.tryParse('${item['task_count'] ?? ''}') ?? 0;
    final sampleTask = _stringValue(item['sample_task']);
    if (_hasProfessionUsageRanking(item)) {
      return 'Mais usada na plataforma';
    }
    if (taskCount > 1) {
      return '$taskCount servicos nessa profissao';
    }
    if (sampleTask.isNotEmpty) {
      return sampleTask;
    }
    return 'Toque para ver os servicos';
  }

  IconData _resolveProfessionIcon(String professionName) {
    final normalized = professionName.toLowerCase();
    if (normalized.contains('barb') ||
        normalized.contains('cabelo') ||
        normalized.contains('beleza') ||
        normalized.contains('estet') ||
        normalized.contains('manicure')) {
      return Icons.content_cut_rounded;
    }
    if (normalized.contains('eletric')) {
      return Icons.electrical_services_rounded;
    }
    if (normalized.contains('encan') || normalized.contains('hidraul')) {
      return Icons.plumbing_rounded;
    }
    if (normalized.contains('pint')) {
      return Icons.format_paint_rounded;
    }
    if (normalized.contains('jardin')) {
      return Icons.yard_rounded;
    }
    if (normalized.contains('limpeza') || normalized.contains('faxina')) {
      return Icons.cleaning_services_rounded;
    }
    if (normalized.contains('mont') || normalized.contains('instal')) {
      return Icons.handyman_rounded;
    }
    return Icons.build_circle_outlined;
  }

  Color _resolveProfessionAccent(String professionName) {
    final normalized = professionName.toLowerCase();
    if (normalized.contains('barb') ||
        normalized.contains('cabelo') ||
        normalized.contains('beleza') ||
        normalized.contains('estet')) {
      return const Color(0xFFB45309);
    }
    if (normalized.contains('eletric')) {
      return const Color(0xFF2563EB);
    }
    if (normalized.contains('encan') || normalized.contains('hidraul')) {
      return const Color(0xFF0891B2);
    }
    if (normalized.contains('pint')) {
      return const Color(0xFF7C3AED);
    }
    if (normalized.contains('jardin')) {
      return const Color(0xFF15803D);
    }
    return const Color(0xFF1D4ED8);
  }

  bool _isBeautyProfession(Map<String, dynamic> profession) {
    final normalized = _stringValue(
      profession['profession_name'],
    ).toLowerCase().trim();
    final keywords = _stringValue(
      profession['profession_keywords'],
    ).toLowerCase().trim();
    const beautyTokens = [
      'barb',
      'cabel',
      'beleza',
      'estet',
      'manicure',
      'pedicure',
      'maqui',
      'depil',
      'sobrancel',
      'podolog',
      'massag',
      'sal',
      'spa',
      'escova',
      'unha',
    ];
    final matchesBeautyToken =
        beautyTokens.any(normalized.contains) ||
        beautyTokens.any(keywords.contains);
    if (matchesBeautyToken) {
      return true;
    }
    return isCanonicalFixedServiceRecord(profession) &&
        (normalized.contains('designer') || normalized.contains('studio'));
  }

  void _openProfessionQuickAccess(Map<String, dynamic> profession) {
    final professionName = _stringValue(profession['profession_name']);
    if (professionName.isEmpty) return;
    context.push(
      '/home-search',
      extra: {'query': professionName, 'profession_name': professionName},
    );
  }

  Widget _buildQuickCategoryFallbackWrap() {
    return HomeQuickCategoryWrap(
      items: [
        HomeQuickCategoryTileData(
          icon: Icons.build_rounded,
          label: 'Servicos',
          metric: 'Atendimento movel',
          summary: 'Manutencao, instalacao e ajuda perto de voce.',
          accentColor: const Color(0xFF1D4ED8),
          onTap: _openServicesQuickAccess,
        ),
        HomeQuickCategoryTileData(
          icon: Icons.content_cut_rounded,
          label: 'Beleza',
          metric: 'Salao e barbearia',
          summary: 'Agenda, estetica e atendimento em local parceiro.',
          accentColor: const Color(0xFFB45309),
          onTap: _openBeautyQuickAccess,
          highlighted: true,
        ),
      ],
    );
  }

  HomeQuickCategoryTileData _buildProfessionQuickAccessTile(
    Map<String, dynamic> profession, {
    required bool highlighted,
  }) {
    final professionName = _stringValue(profession['profession_name']);
    return HomeQuickCategoryTileData(
      icon: _resolveProfessionIcon(professionName),
      label: professionName,
      metric: _professionQuickAccessMetricLabel(profession),
      summary: _professionQuickAccessSummary(profession),
      accentColor: highlighted
          ? AppTheme.primaryBlue
          : _resolveProfessionAccent(professionName),
      onTap: () => _openProfessionQuickAccess(profession),
      highlighted: highlighted,
    );
  }

  Widget _buildProfessionQuickAccessGroup({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
    required Color accentColor,
    bool highlighted = false,
  }) {
    return HomeProfessionQuickAccessGroup(
      title: title,
      subtitle: subtitle,
      items: items.map((profession) {
        final isHighlighted =
            highlighted || _hasProfessionUsageRanking(profession);
        return _buildProfessionQuickAccessTile(
          profession,
          highlighted: isHighlighted,
        );
      }).toList(),
      accentColor: accentColor,
      highlighted: highlighted,
    );
  }

  Future<void> _loadProfile() async {
    // Lógica simplificada de carregamento de perfil
    try {
      await _api.getProfile();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _checkPaymentProfileForClientOnHome() async {
    if (_checkingPayments) return;
    _checkingPayments = true;
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      // Não sincronizar/garantir "customer" automaticamente no Home.
      // Customer só é necessário em fluxos de cartão e deve ser criado sob demanda.
    } catch (e) {
      debugPrint('⚠️ [Home] Falha ao validar perfil de pagamento: $e');
    } finally {
      _checkingPayments = false;
    }
  }

  Future<void> _loadServices() async {
    // Carregamento silencioso: só mostra esqueleto se a lista estiver vazia
    if (servicesList.isEmpty) {
      setState(() => isLoadingServices = true);
    }

    try {
      final snapshot = await _fetchBackendHomeSnapshot();
      if (snapshot != null) {
        final backendServices = List<Map<String, dynamic>>.from(
          snapshot.services,
        );
        if (mounted) {
          setState(() {
            servicesList = backendServices;
            _activeServiceForBanner =
                snapshot.activeService ??
                _pickLatestActiveService(backendServices);
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          servicesList = <Map<String, dynamic>>[];
          _activeServiceForBanner = null;
        });
      }
    } catch (e) {
      debugPrint('❌ [Home] Erro ao carregar serviços: $e');
    } finally {
      if (mounted) setState(() => isLoadingServices = false);
    }
  }

  Future<void> _loadSavedPlaces() async {
    // Lógica de lugares salvos
  }

  Future<void> _recoverActiveService() async {
    // Só cliente deve ser redirecionado para a página própria do serviço.
    if (_api.role != null && _api.role != 'client') return;
    if (_api.userId == null) await _api.loadToken();

    final userId = _api.userId;
    if (userId == null) return;

    try {
      Map<String, dynamic>? service;

      final snapshot = await _fetchBackendHomeSnapshot(force: true);
      service = snapshot?.activeService == null
          ? null
          : Map<String, dynamic>.from(snapshot!.activeService!);

      if (!mounted || service == null || service['id'] == null) return;

      final status = (service['status'] ?? '').toString();
      final bool fixedReadyForSchedule = _isFixedReadyForScheduledScreen(
        service,
      );

      if (_shouldSuppressAutoNavigation) {
        setState(
          () => _activeServiceForBanner = Map<String, dynamic>.from(service!),
        );
        _startActiveServiceBannerRefreshLoop();
        return;
      }

      if (fixedReadyForSchedule) {
        debugPrint(
          '✅ [Reconexão] Agendamento fixo encontrado: ${service['id']} ($status). Redirecionando...',
        );
        context.go('/scheduled-service/${service['id']}');
      } else if (shouldClientOpenTrackingForMobileService(service)) {
        debugPrint(
          '✅ [Reconexão] Serviço móvel em rotina ativa: ${service['id']} ($status). Abrindo rota ativa...',
        );
        context.go(
          resolveClientActiveServiceRoute(service, service['id'].toString()),
        );
      } else {
        // Mantém na Home e exibe banner para não "travar" o app.
        setState(
          () => _activeServiceForBanner = Map<String, dynamic>.from(service!),
        );
        _startActiveServiceBannerRefreshLoop();
      }
    } catch (e) {
      debugPrint('❌ Erro ao recuperar serviço ativo na home: $e');
    }
  }

  bool _isTerminalServiceStatus(String statusRaw) {
    final status = statusRaw.toLowerCase().trim();
    return {
      'completed',
      'done',
      'finished',
      'canceled',
      'cancelled',
      'refunded',
      'expired',
      'closed',
      'deleted',
    }.contains(status);
  }

  bool _isFixedReadyForScheduledScreen(Map<String, dynamic> service) {
    logFixedScheduleGateDecision('home_active_service', service);
    return evaluateFixedScheduleGate(service).shouldStayOnScheduledScreen;
  }

  bool _shouldShowHomeReturningServiceBanner(Map<String, dynamic>? service) {
    return shouldKeepClientOnHomeForMobileService(service);
  }

  DateTime? _parseHomeScheduleDateTime(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  String _formatHomeScheduleDateTime(DateTime? value) {
    if (value == null) return 'Horário a definir';
    return DateFormat("dd/MM 'às' HH:mm", 'pt_BR').format(value);
  }

  bool _isClientScheduleProposalForHome(Map<String, dynamic> service) {
    final proposedBy =
        '${service['schedule_proposed_by_user_id'] ?? service['schedule_proposed_by'] ?? ''}'
            .trim();
    final currentUserId = (_api.userId ?? '').trim();
    if (proposedBy.isNotEmpty && currentUserId.isNotEmpty) {
      return proposedBy == currentUserId;
    }
    final clientId = '${service['client_id'] ?? ''}'.trim();
    return proposedBy.isNotEmpty &&
        clientId.isNotEmpty &&
        proposedBy == clientId;
  }

  int _homeScheduleRoundOf(Map<String, dynamic> service) {
    final raw = service['schedule_round'];
    if (raw is int) return raw;
    return int.tryParse('${raw ?? 0}') ?? 0;
  }

  DateTime _normalizedHomeScheduleDateTimeForSubmit(DateTime candidate) {
    final local = candidate.toLocal();
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
  }

  Future<void> _acceptScheduleProposalFromHome(
    Map<String, dynamic> service,
  ) async {
    if (_isSubmittingHomeScheduleNegotiation) return;
    final serviceId = (service['id'] ?? '').toString().trim();
    final scheduledAt = _parseHomeScheduleDateTime(service['scheduled_at']);
    if (serviceId.isEmpty || scheduledAt == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horário proposto não encontrado.')),
      );
      return;
    }

    setState(() => _isSubmittingHomeScheduleNegotiation = true);
    try {
      final ok = await _backendTrackingApi.confirmSchedule(
        serviceId,
        scheduledAt: scheduledAt,
      );
      if (!ok) {
        throw Exception('Confirmação de agenda não aceita pelo backend.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Agendamento confirmado!')));
      await _recoverActiveService();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao confirmar: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSubmittingHomeScheduleNegotiation = false);
      }
    }
  }

  Future<void> _counterProposeScheduleFromHome(
    Map<String, dynamic> service,
  ) async {
    if (_isSubmittingHomeScheduleNegotiation) return;

    final serviceId = (service['id'] ?? '').toString().trim();
    if (serviceId.isEmpty) return;

    final now = DateTime.now();
    final nowMinimum = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final currentProposal = _parseHomeScheduleDateTime(service['scheduled_at']);
    final initialDateTime =
        currentProposal != null && currentProposal.isAfter(nowMinimum)
        ? currentProposal
        : nowMinimum;

    final selectedDate = await AppCupertinoPicker.showDatePicker(
      context: context,
      initialDate: initialDateTime,
      firstDate: DateTime(nowMinimum.year, nowMinimum.month, nowMinimum.day),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      title: 'Sugerir nova data',
    );
    if (selectedDate == null || !mounted) return;

    final sameMinimumDay =
        selectedDate.year == nowMinimum.year &&
        selectedDate.month == nowMinimum.month &&
        selectedDate.day == nowMinimum.day;

    final selectedTime = await AppCupertinoPicker.showTimePicker(
      context: context,
      initialTime: sameMinimumDay
          ? TimeOfDay.fromDateTime(nowMinimum)
          : TimeOfDay.fromDateTime(initialDateTime),
      title: 'Sugerir horário',
    );
    if (selectedTime == null || !mounted) return;

    final selectedDateTime = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    final normalizedSelectedDateTime = _normalizedHomeScheduleDateTimeForSubmit(
      selectedDateTime,
    );

    setState(() => _isSubmittingHomeScheduleNegotiation = true);
    try {
      final ok = await _backendTrackingApi.proposeSchedule(
        serviceId,
        scheduledAt: normalizedSelectedDateTime,
      );
      if (!ok) {
        throw Exception('Contraproposta de agenda não aceita pelo backend.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nova proposta enviada ao prestador!')),
      );
      await _recoverActiveService();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao sugerir horário: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSubmittingHomeScheduleNegotiation = false);
      }
    }
  }

  Future<void> _resendOpenForScheduleFromHome(
    Map<String, dynamic> service,
  ) async {
    if (_isSubmittingHomeScheduleNegotiation) return;

    final serviceId = (service['id'] ?? '').toString().trim();
    if (serviceId.isEmpty) return;

    setState(() => _isSubmittingHomeScheduleNegotiation = true);
    try {
      await _api.updateServiceStatus(
        serviceId,
        'searching_provider',
        scope: ServiceDataScope.mobileOnly,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Serviço reenviado para uma nova rodada de agendamento.',
          ),
        ),
      );
      await _recoverActiveService();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao reenviar para agendamento: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingHomeScheduleNegotiation = false);
      }
    }
  }

  Future<void> _cancelServiceFromHome(String serviceId) async {
    if (serviceId.trim().isEmpty) return;

    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancelar serviço'),
          content: const Text('Tem certeza que deseja cancelar este serviço?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Voltar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Cancelar serviço'),
            ),
          ],
        );
      },
    );
    if (shouldCancel != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _api.cancelService(serviceId, scope: ServiceDataScope.mobileOnly);
      if (!mounted) return;
      setState(() => _activeServiceForBanner = null);
      messenger.showSnackBar(
        const SnackBar(content: Text('Solicitação cancelada.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Erro ao cancelar: $e')));
    }
  }

  void _maybeShowHomeScheduleProposalSheet([Map<String, dynamic>? service]) {
    final current = service ?? _activeServiceForBanner;
    if (!mounted || current == null) return;

    final status = '${current['status'] ?? ''}'.trim().toLowerCase();
    if (status != 'schedule_proposed') return;
    if (_isClientScheduleProposalForHome(current)) return;

    final serviceId = '${current['id'] ?? ''}'.trim();
    if (serviceId.isEmpty) return;
    final key =
        '$serviceId:${_homeScheduleRoundOf(current)}:${current['scheduled_at'] ?? ''}';
    if (_lastShownHomeScheduleProposalKey == key) return;
    _lastShownHomeScheduleProposalKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(resolveClientActiveServiceRoute(current, serviceId));
    });
  }

  Map<String, dynamic>? _pickLatestActiveService(List<dynamic> services) {
    for (final row in services) {
      if (row is! Map) continue;
      final st = (row['status'] ?? '').toString();
      if (st.isEmpty) continue;
      if (_isTerminalServiceStatus(st)) continue;
      return Map<String, dynamic>.from(row);
    }
    return null;
  }

  Future<void> _showWaitingServiceDetailsSheet(
    Map<String, dynamic> service,
  ) async {
    final serviceId = (service['id'] ?? '').toString().trim();
    final status = (service['status'] ?? '').toString().toLowerCase().trim();
    if (status == 'schedule_proposed') {
      if (serviceId.isNotEmpty) {
        context.go(resolveClientActiveServiceRoute(service, serviceId));
      }
      return;
    }
    final profession =
        (service['profession'] ?? service['profession_name'] ?? 'Serviço')
            .toString()
            .trim();
    final description =
        (service['description'] ?? service['task_name'] ?? profession)
            .toString()
            .trim();
    final price = _formatCurrency(
      service['price_estimated'] ?? service['price'] ?? 0,
    );
    final address = (service['address'] ?? '').toString().trim();
    final scheduledAt = _parseHomeScheduleDateTime(service['scheduled_at']);
    final expiresAt = _parseHomeScheduleDateTime(
      service['schedule_expires_at'],
    );
    final isClientProposal = _isClientScheduleProposalForHome(service);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        status == 'schedule_proposed'
                            ? 'Proposta de agendamento'
                            : 'Serviço aguardando retorno',
                        style: TextStyle(
                          color: AppTheme.darkBlueText,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        profession,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        price,
                        style: TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          address,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (status == 'schedule_proposed') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FAFF),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isClientProposal
                              ? 'Sua contraproposta foi enviada'
                              : 'Horário sugerido pelo prestador',
                          style: TextStyle(
                            color: AppTheme.primaryBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatHomeScheduleDateTime(scheduledAt),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                        if (expiresAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Responder até ${_formatHomeScheduleDateTime(expiresAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9E4),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppTheme.primaryYellow.withValues(alpha: 0.34),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'O que está acontecendo agora',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        status == 'schedule_proposed'
                            ? (isClientProposal
                                  ? 'Sua sugestão já foi enviada. Você pode abrir os detalhes para acompanhar ou alterar o horário.'
                                  : 'O prestador enviou uma proposta de agendamento. Você pode aceitar agora ou responder com outro horário.')
                            : status == 'open_for_schedule'
                            ? 'Nenhum prestador aceitou na rotina inicial de notificação. O serviço segue ativo e aguardando retorno de prestadores da profissão.'
                            : 'Seu serviço continua ativo na plataforma.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (status == 'open_for_schedule') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmittingHomeScheduleNegotiation
                          ? null
                          : () async {
                              Navigator.of(sheetContext).pop();
                              await _resendOpenForScheduleFromHome(service);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _isSubmittingHomeScheduleNegotiation
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Enviar novamente para agendamento',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (status == 'schedule_proposed' && !isClientProposal) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmittingHomeScheduleNegotiation
                          ? null
                          : () async {
                              Navigator.of(sheetContext).pop();
                              await _acceptScheduleProposalFromHome(service);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _isSubmittingHomeScheduleNegotiation
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Aceitar agendamento',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed:
                        serviceId.isEmpty ||
                            _isSubmittingHomeScheduleNegotiation
                        ? null
                        : () async {
                            Navigator.of(sheetContext).pop();
                            await _counterProposeScheduleFromHome(service);
                          },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.textDark,
                      side: BorderSide(
                        color: AppTheme.textDark.withValues(alpha: 0.90),
                        width: 1.8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    child: Text(
                      status == 'schedule_proposed'
                          ? 'Sugerir outro horário'
                          : 'Ver detalhes do serviço',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: serviceId.isEmpty
                        ? null
                        : () async {
                            Navigator.of(sheetContext).pop();
                            await _cancelServiceFromHome(serviceId);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryYellow,
                      foregroundColor: AppTheme.textDark,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Cancelar serviço',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWaitingServiceBanner(Map<String, dynamic> service) {
    final serviceId = (service['id'] ?? '').toString();
    final status = (service['status'] ?? '').toString().toLowerCase().trim();
    final profession =
        (service['profession'] ?? service['profession_name'] ?? 'Serviço')
            .toString();
    final price = (service['price_estimated'] ?? service['price'] ?? '')
        .toString()
        .trim();

    String label = 'Serviço em andamento';
    if (status == 'searching') {
      label = 'Aguardando contato de prestadores';
    } else if (status == 'open_for_schedule') {
      label = 'Aguardando prestador agendar';
    } else if (status == 'schedule_proposed') {
      label = _isClientScheduleProposalForHome(service)
          ? 'Sua proposta foi enviada'
          : 'Proposta de agendamento';
    } else if (status == 'pending' || status == 'waiting_payment') {
      label = 'Aguardando pagamento';
    } else if (status == 'contested') {
      label = 'Serviço sob contestação';
    }

    final subtitle = status == 'schedule_proposed'
        ? (_isClientScheduleProposalForHome(service)
              ? 'Aguardando a resposta do prestador • Toque para detalhes'
              : 'Prestador sugeriu ${_formatHomeScheduleDateTime(_parseHomeScheduleDateTime(service['scheduled_at']))} • Toque para responder')
        : status == 'open_for_schedule'
        ? 'Serviço buscando retorno de prestadores • Toque para detalhes'
        : status == 'contested'
        ? 'Análise em andamento. Consulte os detalhes do serviço.'
        : '$profession${price.isNotEmpty ? ' • R\$ $price' : ''}';
    final leadingIcon = status == 'schedule_proposed'
        ? Icons.event_available_rounded
        : status == 'open_for_schedule'
        ? Icons.schedule_send_rounded
        : Icons.hourglass_bottom;

    return HomeWaitingServiceBanner(
      label: label,
      subtitle: subtitle,
      leadingIcon: leadingIcon,
      onTap: serviceId.isEmpty
          ? null
          : () {
              if (status == 'schedule_proposed') {
                context.go(resolveClientActiveServiceRoute(service, serviceId));
                return;
              }
              _showWaitingServiceDetailsSheet(service);
            },
    );
  }

  Widget _buildPendingFixedPaymentBanner() {
    final pending = _pendingFixedPaymentBanner;
    if (pending == null) return const SizedBox.shrink();
    final compactSummary = _buildPendingCompactSummary(pending);
    final providerName = (pending['provider_name'] ?? 'Salao parceiro')
        .toString()
        .trim();
    final serviceLabel =
        (pending['task_name'] ??
                pending['description'] ??
                pending['profession_name'] ??
                'Agendamento pendente')
            .toString()
            .trim();
    return HomePendingFixedPaymentBanner(
      scheduleLabel: _formatPendingScheduleLabel(pending['scheduled_at']),
      compactSummary: compactSummary,
      providerName: providerName,
      serviceLabel: serviceLabel,
      upfrontValueLabel: _formatCurrency(
        pending['price_upfront'] ?? pending['pix_fee'],
      ),
      address: (pending['address'] ?? '').toString().trim(),
      onOpenPayment: _openPendingFixedBookingFlow,
      onRefreshNeeded: _loadPendingFixedPaymentBanner,
      details: pending,
    );
  }

  void _initAppointmentRefreshTimer() {
    if (!_isForeground) return;
    _appointmentRefreshTimer?.cancel();
    if (_upcomingAppointment == null) return;
    _appointmentRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadUpcomingAppointment(),
    );
  }

  Future<void> _loadUpcomingAppointment() async {
    final role = _api.role;
    if (role == 'driver' || role == 'provider') return;

    try {
      final snapshot = await _fetchBackendHomeSnapshot();
      final snapshotAppointment = snapshot?.upcomingAppointment;
      if (snapshotAppointment != null) {
        if (mounted) {
          setState(() {
            _upcomingAppointment = Map<String, dynamic>.from(
              snapshotAppointment,
            );
          });
        }
        unawaited(_bindUpcomingAppointmentChat(snapshotAppointment));
        _initAppointmentRefreshTimer();
        _maybeNotifyTimeToLeave();
        return;
      }
      _appointmentRefreshTimer?.cancel();
      _cancelUpcomingAppointmentChatWatcher();
      if (mounted) setState(() => _upcomingAppointment = null);
    } catch (e) {
      debugPrint('❌ [Home] Erro ao carregar próximo agendamento: $e');
    }
  }

  void _cancelUpcomingAppointmentChatWatcher() {
    _upcomingAppointmentChatSubscription?.cancel();
    _upcomingAppointmentChatSubscription = null;
  }

  Future<void> _bindUpcomingAppointmentChat(
    Map<String, dynamic> appointment,
  ) async {
    final serviceId = (appointment['service_id'] ?? appointment['id'] ?? '')
        .toString()
        .trim();
    if (serviceId.isEmpty) {
      _cancelUpcomingAppointmentChatWatcher();
      return;
    }

    final myUserId = (await _api.getMyUserId())?.toString();
    _cancelUpcomingAppointmentChatWatcher();

    _upcomingAppointmentChatSubscription = DataGateway()
        .watchChat(serviceId)
        .listen((msgs) {
          if (!mounted) return;

          final currentServiceId =
              (_upcomingAppointment?['service_id'] ??
                      _upcomingAppointment?['id'])
                  .toString()
                  .trim();
          if (currentServiceId != serviceId) return;

          final sorted = List<dynamic>.from(msgs)
            ..sort((a, b) {
              final aDate =
                  DateTime.tryParse(
                    '${a['sent_at'] ?? a['created_at'] ?? ''}',
                  ) ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final bDate =
                  DateTime.tryParse(
                    '${b['sent_at'] ?? b['created_at'] ?? ''}',
                  ) ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });

          String? previewMessage;
          int unreadCount = 0;
          int? latestIncomingId;

          for (final raw in sorted) {
            final msg = raw is Map<String, dynamic>
                ? raw
                : Map<String, dynamic>.from(raw as Map);
            final senderId = '${msg['sender_id'] ?? ''}';
            final isMine = myUserId != null && senderId == myUserId;
            final content = (msg['content'] ?? '').toString().trim();

            previewMessage ??= content.isEmpty ? null : content;

            if (!isMine) {
              if ((msg['read_at'] ?? msg['readAt']) == null) unreadCount++;
              latestIncomingId ??= msg['id'] is int
                  ? msg['id'] as int
                  : int.tryParse('${msg['id']}');
            }
          }

          setState(() {
            _upcomingAppointment = {
              ...?_upcomingAppointment,
              'chat_preview_message': previewMessage,
              'chat_unread_count': unreadCount,
              'chat_latest_incoming_message_id': latestIncomingId,
            };
          });

          if (_isForeground &&
              latestIncomingId != null &&
              unreadCount > 0 &&
              _lastShownUpcomingChatMessageId != latestIncomingId &&
              ChatScreen.activeChatServiceId != serviceId) {
            _lastShownUpcomingChatMessageId = latestIncomingId;
            final snackBar = SnackBar(
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              backgroundColor: Colors.white,
              duration: const Duration(seconds: 5),
              content: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppTheme.primaryBlue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      previewMessage ?? 'Você recebeu uma nova mensagem.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'Abrir',
                textColor: AppTheme.primaryBlue,
                onPressed: () => context.push('/chat/$serviceId'),
              ),
            );
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(snackBar);
          }
        });
  }

  void _maybeNotifyTimeToLeave() {
    final appointment = _upcomingAppointment;
    if (appointment == null) return;
    final id = (appointment['id'] ?? '').toString();
    if (id.isEmpty) return;

    final start = DateTime.tryParse(
      (appointment['start_time'] ?? '').toString(),
    )?.toLocal();
    if (start == null) return;

    final travelTimeMin = _estimateTravelTimeMinutesForAppointment(appointment);
    final leaveAt = start.subtract(Duration(minutes: travelTimeMin + 15));
    final now = DateTime.now();
    if (now.isBefore(leaveAt)) return;
    if (_lastTimeToLeaveNotificationId == id) return;

    _lastTimeToLeaveNotificationId = id;
    final providerName = (appointment['provider_name'] ?? 'seu agendamento')
        .toString();
    final serviceName = (appointment['service_name'] ?? 'seu serviço')
        .toString();
    final timeStr = TimeOfDay.fromDateTime(start).format(context);
    NotificationService().showNotification(
      'Hora de sair para o serviço',
      'Hora de sair para o serviço $serviceName em $providerName. Chegada prevista para $timeStr.',
    );
  }

  double _estimateDistanceKmForAppointment(Map<String, dynamic> appointment) {
    final providerLat = double.tryParse('${appointment['provider_lat'] ?? ''}');
    final providerLon = double.tryParse('${appointment['provider_lon'] ?? ''}');
    if (providerLat == null || providerLon == null) return 0;
    final distanceKm = const Distance().as(
      LengthUnit.Kilometer,
      currentPosition,
      LatLng(providerLat, providerLon),
    );
    return double.parse(distanceKm.toStringAsFixed(1));
  }

  int _estimateTravelTimeMinutesForAppointment(
    Map<String, dynamic> appointment,
  ) {
    final distanceKm = _estimateDistanceKmForAppointment(appointment);
    if (distanceKm <= 0) return 20;
    final estimated = ((distanceKm / 25) * 60).round();
    return estimated < 5 ? 5 : estimated;
  }

  bool _isUpcomingAppointmentExpired(DateTime start, {DateTime? now}) {
    final resolvedNow = now ?? DateTime.now();
    return resolvedNow.isAfter(start.add(const Duration(minutes: 30)));
  }

  String _formatUpcomingAppointmentDateTime(DateTime start) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final target = DateTime(start.year, start.month, start.day);
    final timeLabel = DateFormat('HH:mm', 'pt_BR').format(start);

    if (target == today) return 'Hoje • $timeLabel';
    if (target == tomorrow) return 'Amanhã • $timeLabel';
    return DateFormat("dd/MM • HH:mm", 'pt_BR').format(start);
  }

  Widget _buildUpcomingAppointmentBanner() {
    final appointment = _upcomingAppointment;
    if (appointment == null) return const SizedBox.shrink();

    final start = DateTime.tryParse(
      (appointment['start_time'] ?? '').toString(),
    )?.toLocal();
    if (start == null) return const SizedBox.shrink();
    if (_isUpcomingAppointmentExpired(start)) return const SizedBox.shrink();

    final now = DateTime.now();
    final remaining = start.difference(now);
    final travelTimeMin = _estimateTravelTimeMinutesForAppointment(appointment);
    final distanceKm = _estimateDistanceKmForAppointment(appointment);
    final leaveAt = start.subtract(Duration(minutes: travelTimeMin + 15));
    final leaveIn = leaveAt.difference(now);

    String format(Duration d) {
      if (d.isNegative) return 'agora';
      if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}min';
      return '${d.inMinutes}min';
    }

    final providerName = (appointment['provider_name'] ?? 'Salão').toString();
    final serviceName = (appointment['service_name'] ?? 'Serviço de beleza')
        .toString();
    final addr = (appointment['provider_address'] ?? '').toString();
    final dateTimeLabel = _formatUpcomingAppointmentDateTime(start);
    final timeLabel = DateFormat('HH:mm').format(start);
    final isOverdue = remaining.isNegative;
    final isVeryClose = !isOverdue && remaining.inMinutes <= 30;

    Future<void> openUpcomingAppointmentDetails() async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UpcomingAppointmentDetailsScreen(
            args: UpcomingAppointmentDetailsArgs(
              appointment: Map<String, dynamic>.from(appointment),
              providerName: providerName,
              serviceName: serviceName,
              address: addr,
              start: start,
              dateTimeLabel: dateTimeLabel,
              timeLabel: timeLabel,
              isOverdue: isOverdue,
              isVeryClose: isVeryClose,
              remainingLabel: format(remaining),
              leaveInLabel: format(leaveIn),
              distanceKm: distanceKm,
              travelTimeMin: travelTimeMin,
              canOpenTracking: _isFixedReadyForScheduledScreen(appointment),
            ),
          ),
        ),
      );
    }

    return HomeUpcomingAppointmentBanner(
      providerName: providerName,
      serviceName: serviceName,
      address: addr,
      dateTimeLabel: dateTimeLabel,
      timeLabel: timeLabel,
      isOverdue: isOverdue,
      isVeryClose: isVeryClose,
      remainingLabel: format(remaining),
      leaveInLabel: format(leaveIn),
      distanceKm: distanceKm,
      travelTimeMin: travelTimeMin,
      chatPreviewMessage:
          (appointment['chat_preview_message'] ?? '').toString().trim().isEmpty
          ? null
          : (appointment['chat_preview_message'] ?? '').toString(),
      unreadChatCount: appointment['chat_unread_count'] is num
          ? (appointment['chat_unread_count'] as num).toInt()
          : int.tryParse('${appointment['chat_unread_count'] ?? 0}') ?? 0,
      onOpenChat: () => context.push(
        '/chat/${(appointment['service_id'] ?? appointment['id']).toString()}',
      ),
      onOpenDetails: openUpcomingAppointmentDetails,
    );
  }

  void _scheduleServicesListenerRetry() {
    _servicesListenerRetryTimer?.cancel();
    _servicesListenerRetryAttempt = (_servicesListenerRetryAttempt + 1).clamp(
      1,
      6,
    );
    final seconds = (1 << _servicesListenerRetryAttempt).clamp(2, 25);
    debugPrint(
      '🔁 [Realtime] Retry stream de serviços em ${seconds}s '
      'tentativa=$_servicesListenerRetryAttempt',
    );
    _servicesListenerRetryTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      unawaited(_listenToServices());
    });
  }

  bool _isTransientServicesRealtimeError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('realtimesubscribestatus.channelerror') ||
        text.contains('realtimesubscribestatus.timedout') ||
        text.contains('realtimecloseevent(code: 1006') ||
        text.contains('realtimecloseevent(code: 1002') ||
        text.contains('socketexception') ||
        text.contains('websocket') ||
        text.contains('timedout');
  }

  void _logServicesRealtimeIssue(Object error) {
    final signature = error.toString();
    final now = DateTime.now();
    final shouldThrottle =
        _lastServicesRealtimeErrorSignature == signature &&
        _lastServicesRealtimeErrorLogAt != null &&
        now.difference(_lastServicesRealtimeErrorLogAt!) <
            const Duration(seconds: 20);
    if (shouldThrottle) return;

    _lastServicesRealtimeErrorSignature = signature;
    _lastServicesRealtimeErrorLogAt = now;

    if (_isTransientServicesRealtimeError(error)) {
      debugPrint('ℹ️ [Realtime] Stream de serviços transitório: $error');
      return;
    }

    debugPrint('❌ [Realtime] Erro no stream de serviços: $error');
  }

  void _startActiveServiceBannerRefreshLoop() {
    if (!_isForeground) return;
    final initialActiveId = (_activeServiceForBanner?['id'] ?? '')
        .toString()
        .trim();
    if (initialActiveId.isEmpty) {
      _activeServiceBannerRefreshTimer?.cancel();
      return;
    }
    _activeServiceBannerRefreshTimer?.cancel();
    _activeServiceBannerRefreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) async {
        if (!mounted) return;
        final activeId = (_activeServiceForBanner?['id'] ?? '')
            .toString()
            .trim();
        if (activeId.isEmpty) return;

        try {
          final refreshed = await _backendTrackingApi.fetchServiceDetails(
            activeId,
            scope: ServiceDataScope.mobileOnly.name,
          );
          if (refreshed == null) return;
          if (!mounted) return;

          setState(() {
            _activeServiceForBanner = Map<String, dynamic>.from(refreshed);
            servicesList = servicesList
                .map((row) {
                  final rowId = (row['id'] ?? '').toString().trim();
                  if (rowId != activeId) return row;
                  return Map<String, dynamic>.from(refreshed);
                })
                .toList()
                .cast<Map<String, dynamic>>();
          });
          _maybeShowHomeScheduleProposalSheet(_activeServiceForBanner);
        } catch (e) {
          debugPrint('⚠️ [Home] Falha no refresh leve do banner ativo: $e');
        }
      },
    );
  }

  void _startActiveServiceRecoveryLoop() {
    if (!_isForeground) return;
    _activeServiceRecoveryTimer?.cancel();
    _activeServiceRecoveryTimer = Timer.periodic(const Duration(seconds: 20), (
      _,
    ) async {
      if (!mounted) return;
      if (_shouldSuppressAutoNavigation) return;
      if (_activeServiceForBanner != null &&
          shouldKeepClientOnHomeForMobileService(_activeServiceForBanner)) {
        return;
      }
      if (_api.role != null && _api.role != 'client') return;

      try {
        await _recoverActiveService();
      } catch (e) {
        debugPrint('⚠️ [Home] Falha na recuperação periódica do serviço: $e');
      }
    });
  }

  Future<void> _listenToServices() async {
    _servicesSubscription?.cancel();
    _servicesListenerRetryTimer?.cancel();

    await _api.loadToken();
    final userId = _api.userId;
    if (userId == null || userId.trim().isEmpty) {
      debugPrint(
        '⚠️ [Home] userId ainda indisponível para watchUserServices. Tentando novamente...',
      );
      _scheduleServicesListenerRetry();
      return;
    }

    if (kIsWeb) {
      await RealtimeService().requestSocketReconnect();
    }

    _servicesSubscription = CentralService()
        .watchUserServices(userId)
        .listen(
          (services) {
            if (!mounted) return;
            _servicesListenerRetryAttempt = 0;
            debugPrint(
              '⚡ [Realtime] Atualização de serviços recebida: ${services.length} itens.',
            );
            final latestActive = _pickLatestActiveService(services);
            if (latestActive != null && !_shouldSuppressAutoNavigation) {
              final activeId = (latestActive['id'] ?? '').toString().trim();
              if (activeId.isNotEmpty &&
                  shouldClientOpenTrackingForMobileService(latestActive)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  context.go(
                    resolveClientActiveServiceRoute(latestActive, activeId),
                  );
                });
              }
            }
            setState(() {
              servicesList = services;
              _activeServiceForBanner = _pickLatestActiveService(servicesList);
              // Se recebemos dados via realtime, podemos desligar o loading inicial
              isLoadingServices = false;
            });
            _startActiveServiceBannerRefreshLoop();
            _maybeShowHomeScheduleProposalSheet(_activeServiceForBanner);
          },
          onError: (e) {
            _logServicesRealtimeIssue(e);
            _scheduleServicesListenerRetry();
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final centralTripMode = _enableCentralRuntime && _isExecutingActiveService;
    final bottomNavHeight = MediaQuery.of(context).padding.bottom + 80;

    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          // 🗺️ MAPA (Base)
          Positioned.fill(
            child: ValueListenableBuilder<bool>(
              valueListenable:
                  GlobalStartupManager.instance.canLoadHeavyWidgets,
              builder: (context, _, __) {
                if (!_shouldRenderLiveMap) {
                  return _buildMapPlaceholder();
                }
                return HomeMapWidget(
                  mapController: mapController,
                  currentPosition: currentPosition,
                  routePolyline: routePolyline,
                  arrivalPolyline: arrivalPolyline,
                  pickupLocation: pickupLocation,
                  dropoffLocation: dropoffLocation,
                  driverLatLng: _enableCentralRuntime ? driverLatLng : null,
                  tripStatus: _enableCentralRuntime ? activeTripStatus : null,
                  isInTripMode: centralTripMode,
                  isPickingOnMap: isPickingOnMap,
                  enableLiveSensors: _shouldEnableMapLiveSensors,
                  simulatedCars: const [],
                  onPickingLocationChanged: (pos) =>
                      setState(() => pickedLocation = pos),
                  onMapReady: () => setState(() => isMapReady = true),
                  onAnimationStart: () {
                    setState(() => isMapAnimating = true);
                    ThemeService().setNavBarVisible(false);
                  },
                  onAnimationEnd: () {
                    setState(() => isMapAnimating = false);
                    if (!uberTripMode) ThemeService().setNavBarVisible(true);
                  },
                );
              },
            ),
          ),

          // 📍 UI Dinâmica (Overlays)
          _buildHeader(),
          if (_api.role != 'driver') ...[
            _buildFloatingControls(),
            _buildBottomPanel(bottomNavHeight),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (isPickingOnMap) return const SizedBox.shrink();
    // Headers migrados para widgets seria o ideal, mas mantendo build logic principal aqui por enquanto
    return SafeStitchHeader(
      unreadCount: unreadCountCount,
      bellController: bellController,
      showChatPreview:
          (_chatPreviewServiceId?.trim().isNotEmpty ?? false) &&
          (_chatPreviewMessage?.trim().isNotEmpty ?? false),
      chatPreviewTitle: _chatPreviewTitle,
      chatPreviewMessage: _chatPreviewMessage,
      onChatPreviewTap: _openTopChatPreview,
    );
  }

  Widget _buildMapPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEFF6FF), Color(0xFFD6E4FF), Color(0xFFF8FAFC)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 120,
            left: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: const Color(0xFFBFDBFE).withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -30,
            bottom: 180,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: const Color(0xFF93C5FD).withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on_rounded,
                  size: 48,
                  color: Color(0xFF2563EB),
                ),
                SizedBox(height: 8),
                Text(
                  'Preparando mapa',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingControls() {
    final centralTripMode = _enableCentralRuntime && _isExecutingActiveService;
    void safeMoveTo(LatLng target, double zoom) {
      if (!isMapReady) return;
      try {
        mapController.move(target, zoom);
      } catch (e) {
        debugPrint('🗺️ [HomeMap] move controle ignorado: $e');
      }
    }

    return HomeMapFloatingControls(
      bottomOffset: centralTripMode ? 360 : 540,
      isMapAnimating: isMapAnimating,
      onZoomIn: () => safeMoveTo(
        mapController.camera.center,
        mapController.camera.zoom + 1,
      ),
      onZoomOut: () => safeMoveTo(
        mapController.camera.center,
        mapController.camera.zoom - 1,
      ),
      onCenterLocation: () {
        if (!isMapReady) return;
        try {
          mapController.move(currentPosition, 16);
        } catch (e) {
          debugPrint('🗺️ [HomeMap] localização ignorada: $e');
        }
      },
    );
  }

  Widget _buildBottomPanel(double offset) {
    final centralTripMode = _enableCentralRuntime && _isExecutingActiveService;
    if (centralTripMode) {
      return const Align(
        alignment: Alignment.bottomCenter,
        child: Text('Painel de Execução Central Ativo'),
      );
    }

    final shouldShowWaitingServiceBanner =
        _shouldShowHomeReturningServiceBanner(_activeServiceForBanner);
    final homeStage = HomeStageResolver.resolve(
      isSearchMode: false,
      hasPendingFixedPaymentBanner: _pendingFixedPaymentBanner != null,
      hasUpcomingAppointment: _upcomingAppointment != null,
      showWaitingServiceBanner: shouldShowWaitingServiceBanner,
    );
    final stage = homeStage.stage;
    final hasBlockingService = homeStage.hasBlockingService;

    // Painel Padrão (Home)
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _homeSheetInitialSize(homeStage),
      minChildSize: _homeSheetMinSize(homeStage),
      maxChildSize: homeStage.isSearchMode ? 1.0 : 0.95,
      snap: !homeStage.isSearchMode,
      snapSizes: _homeSheetSnapSizes(homeStage),
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 32,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              FocusScope.of(context).unfocus();
            },
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFF9FAFB), Colors.white],
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  HomeStagePanelBody(
                    stage: stage,
                    isSearchMode: false,
                    hasBlockingService: hasBlockingService,
                    searchModeHeader: null,
                    pendingFixedPaymentBanner:
                        homeStage.showPendingFixedPaymentBanner
                        ? _buildPendingFixedPaymentBanner()
                        : null,
                    upcomingAppointmentBanner:
                        homeStage.showUpcomingAppointmentBanner
                        ? _buildUpcomingAppointmentBanner()
                        : null,
                    searchBar: HomeSearchBar(
                      key: const ValueKey('home-inline-search-bar'),
                      currentAddress: pickupController.text.isNotEmpty
                          ? pickupController.text
                          : null,
                      isLoadingLocation: isLocating || pickupLocation == null,
                      isEnabled: true,
                      autoFocus: false,
                      onTap: _openServicesQuickAccess,
                      onServiceTypeSelected: null,
                      onSuggestionSelected: null,
                      onQueryChanged: _openServicesQuickAccessWithQuery,
                      onQuerySubmitted: _openServicesQuickAccessWithQuery,
                      onCloseTap: null,
                      autocompleteItems: const [],
                      seedQuery: '',
                      seedVersion: 0,
                      launcherMode: true,
                      useInternalSearch: false,
                    ),
                    waitingServiceBanner: homeStage.showWaitingServiceBanner
                        ? _buildWaitingServiceBanner(_activeServiceForBanner!)
                        : null,
                    searchModeEmptyState: null,
                    adCarousel: !homeStage.isSearchMode
                        ? const AdCarousel()
                        : null,
                    professionGroups:
                        !homeStage.isSearchMode && !hasBlockingService
                        ? Builder(
                            builder: (context) {
                              final beautyProfessions =
                                  _professionQuickAccessItems
                                      .where(_isBeautyProfession)
                                      .toList();
                              final generalProfessions =
                                  _professionQuickAccessItems
                                      .where(
                                        (item) => !_isBeautyProfession(item),
                                      )
                                      .toList();

                              return Column(
                                children: [
                                  if (_professionQuickAccessItems.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: _buildQuickCategoryFallbackWrap(),
                                    )
                                  else ...[
                                    if (beautyProfessions.isNotEmpty)
                                      _buildProfessionQuickAccessGroup(
                                        title: 'Beleza e estetica',
                                        subtitle:
                                            'Profissoes com agenda, salao, barbearia e cuidados pessoais em destaque.',
                                        items: beautyProfessions,
                                        accentColor: const Color(0xFFB45309),
                                        highlighted: true,
                                      ),
                                    if (beautyProfessions.isNotEmpty &&
                                        generalProfessions.isNotEmpty)
                                      const SizedBox(height: 12),
                                    if (generalProfessions.isNotEmpty)
                                      _buildProfessionQuickAccessGroup(
                                        title: 'Outras profissoes',
                                        subtitle:
                                            'Servicos moveis, reparos e atendimentos proximos de voce sem depender de carrossel.',
                                        items: generalProfessions,
                                        accentColor: const Color(0xFF1D4ED8),
                                      ),
                                  ],
                                ],
                              );
                            },
                          )
                        : null,
                    exploreEntryCard:
                        !homeStage.isSearchMode && !hasBlockingService
                        ? _buildExploreEntryCard()
                        : null,
                    savedPlaces: !homeStage.isSearchMode && !hasBlockingService
                        ? HomeSavedPlaces(
                            savedPlaces: savedPlacesList,
                            onPlaceTap: (place) {},
                          )
                        : null,
                    bottomSpacing:
                        80 + MediaQuery.of(context).padding.bottom + 24,
                  ),
                  if (stage == HomeStage.mixed) const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchPremiumContent() {
    return HomeExploreEntryCard(
      onOpenExplore: () => context.push('/home-explore'),
    );
  }

  Widget _buildExploreEntryCard() => _buildSearchPremiumContent();

  String _stringValue(dynamic raw, {String fallback = ''}) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }
}
