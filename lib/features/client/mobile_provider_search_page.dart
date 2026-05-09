import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/config/supabase_config.dart';
import '../../core/constants/trip_statuses.dart';
import '../../core/maps/app_tile_layer.dart';
import '../../core/remote_ui/remote_screen_body.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/data_gateway.dart';
import 'widgets/dispatch_tracking_timeline.dart';

typedef MobileProviderSearchCancel = Future<void> Function(String serviceId);

class MobileProviderSearchPage extends StatefulWidget {
  final String serviceId;
  final Stream<Map<String, dynamic>>? serviceStream;
  final Future<Map<String, dynamic>> Function(String serviceId)? loadService;
  final MobileProviderSearchCancel? cancelService;
  final bool showMap;
  final Widget? dispatchTimelineOverride;

  const MobileProviderSearchPage({
    super.key,
    required this.serviceId,
    this.serviceStream,
    this.loadService,
    this.cancelService,
    this.showMap = true,
    this.dispatchTimelineOverride,
  });

  @override
  State<MobileProviderSearchPage> createState() =>
      _MobileProviderSearchPageState();
}

class _MobileProviderSearchPageState extends State<MobileProviderSearchPage>
    with WidgetsBindingObserver {
  static const Duration _fallbackPollingInterval = Duration(seconds: 6);
  static const Duration _noProviderFoundReturnDelay = Duration(seconds: 2);
  final MapController _mapController = MapController();
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _refreshTimer;
  Timer? _returnHomeTimer;
  Map<String, dynamic>? _service;
  bool _loading = true;
  bool _cancelling = false;
  bool _openingTracking = false;
  bool _isForeground = true;
  bool _showNoProviderFoundState = false;
  LatLng? _candidateProviderLatLng;
  String? _lastSoundStatusKey;
  String _headline = 'Buscando o prestador mais próximo';
  String _subtitle =
      'Pagamento confirmado. Estamos consultando um prestador por vez por ordem de distância.';

  bool _isOpenForSchedule(String? status) {
    return normalizeServiceStatus(status) == TripStatuses.openForSchedule;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadOnce();
    _listenService();
    _startFallbackPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _refreshTimer?.cancel();
    _returnHomeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    _isForeground = isForeground;
    if (isForeground) {
      _startFallbackPolling();
      unawaited(_refreshNow());
      return;
    }
    _refreshTimer?.cancel();
  }

  void _startFallbackPolling() {
    if (!_isForeground) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_fallbackPollingInterval, (_) {
      _refreshNow();
    });
  }

  Future<void> _refreshNow() async {
    if (!mounted || _openingTracking || !_isForeground) return;
    try {
      final loader =
          widget.loadService ??
          (String id) => DataGateway().getServiceDetails(
            id,
            scope: ServiceDataScope.mobileOnly,
          );
      final details = await loader(widget.serviceId);
      if (!mounted) return;
      _applyService(details);
    } catch (_) {
      // Realtime continua sendo a fonte principal; polling é fallback.
    }
  }

  Future<void> _loadOnce() async {
    try {
      final loader =
          widget.loadService ??
          (String id) => DataGateway().getServiceDetails(
            id,
            scope: ServiceDataScope.mobileOnly,
          );
      final details = await loader(widget.serviceId);
      if (!mounted) return;
      _applyService(details);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _listenService() {
    final stream =
        widget.serviceStream ??
        DataGateway().watchService(
          widget.serviceId,
          scope: ServiceDataScope.mobileOnly,
        );
    _sub = stream.listen((data) {
      if (!mounted || data.isEmpty) return;
      _applyService(data);
    });
  }

  void _applyService(Map<String, dynamic> data) {
    if (_openingTracking) return;
    final service = Map<String, dynamic>.from(data);
    if (_shouldReturnHomeNoProviderFound(service)) {
      _handleNoProviderFound(service);
      return;
    }
    if (_shouldOpenTracking(service)) {
      _openTracking();
      return;
    }
    setState(() {
      _service = service;
      _loading = false;
      _showNoProviderFoundState = false;
    });
  }

  bool _shouldReturnHomeNoProviderFound(Map<String, dynamic> service) {
    return _isOpenForSchedule(service['status']?.toString());
  }

  void _handleNoProviderFound(Map<String, dynamic> service) {
    if (_showNoProviderFoundState || _openingTracking) return;
    _refreshTimer?.cancel();
    _returnHomeTimer?.cancel();
    setState(() {
      _service = service;
      _loading = false;
      _showNoProviderFoundState = true;
      _headline = 'Nenhum prestador encontrado';
      _subtitle =
          'Nenhum prestador aceitou após as 3 rodadas de tentativa. Voltando para a Home.';
    });
    _returnHomeTimer = Timer(_noProviderFoundReturnDelay, () {
      if (!mounted) return;
      context.go('/home');
    });
  }

  void _openTracking() {
    if (_openingTracking) return;
    _openingTracking = true;
    _refreshTimer?.cancel();
    Future.microtask(() {
      if (!mounted) return;
      context.go('/service-tracking/${widget.serviceId}');
    });
  }

  bool _shouldOpenTracking(Map<String, dynamic> service) {
    final status = (service['status'] ?? '').toString().toLowerCase().trim();
    final hasProvider =
        service['provider_id'] != null ||
        (service['provider_uid'] ?? '').toString().trim().isNotEmpty;
    return hasProvider ||
        {
          'accepted',
          'provider_accepted',
          'provider_assigned',
          'provider_near',
          'arrived',
          'in_progress',
          'waiting_remaining_payment',
          'waiting_payment_remaining',
          'awaiting_confirmation',
          'waiting_client_confirmation',
        }.contains(status);
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final cancel =
          widget.cancelService ??
          (String id) => ApiService().cancelService(
            id,
            scope: ServiceDataScope.mobileOnly,
          );
      await cancel(widget.serviceId);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Solicitação cancelada.')),
      );
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Erro ao cancelar: $e')));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  LatLng get _serviceCenter {
    final lat = (_service?['latitude'] as num?)?.toDouble();
    final lon = (_service?['longitude'] as num?)?.toDouble();
    return LatLng(lat ?? -5.52, lon ?? -47.48);
  }

  String get _serviceLabel {
    return (_service?['description'] ??
            _service?['task_name'] ??
            _service?['profession'] ??
            'Serviço móvel')
        .toString();
  }

  String get _paidChipText {
    final status = (_service?['payment_status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return status == 'paid' ||
            status == 'partially_paid' ||
            status == 'paid_manual'
        ? '30% PAGO'
        : 'PAGAMENTO';
  }

  void _maybePlayStatusSound(String title) {
    final normalized = title.toLowerCase().trim();
    final shouldAlert =
        normalized.contains('sem resposta em 30s') ||
        normalized.contains('ampliando a busca');
    if (!shouldAlert || _lastSoundStatusKey == normalized) return;
    _lastSoundStatusKey = normalized;
    SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _handleProviderCandidate(
    DispatchProviderCandidate? candidate,
  ) async {
    if (!mounted) return;
    if (candidate == null) {
      if (_candidateProviderLatLng != null) {
        setState(() => _candidateProviderLatLng = null);
      }
      return;
    }

    final directLocation = candidate.location;
    if (directLocation != null) {
      setState(() => _candidateProviderLatLng = directLocation);
      _fitMapToSearchPoints();
      return;
    }

    final location = await _loadCandidateProviderLocation(candidate);
    if (!mounted || location == null) return;
    setState(() => _candidateProviderLatLng = location);
    _fitMapToSearchPoints();
  }

  Future<LatLng?> _loadCandidateProviderLocation(
    DispatchProviderCandidate candidate,
  ) async {
    try {
      final uid = candidate.providerUid?.trim();
      if (uid != null && uid.isNotEmpty) {
        final row = await DataGateway().fetchProviderLocation(providerUid: uid);
        return _latLngFromRow(row);
      }

      final providerId = candidate.providerId;
      if (providerId != null) {
        final row = await DataGateway().fetchProviderLocation(
          providerId: providerId,
        );
        return _latLngFromRow(row);
      }
    } catch (e) {
      debugPrint('[MobileProviderSearch] Falha ao carregar localização: $e');
    }
    return null;
  }

  LatLng? _latLngFromRow(Map<String, dynamic>? row) {
    final lat = (row?['latitude'] as num?)?.toDouble();
    final lon = (row?['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  void _fitMapToSearchPoints() {
    final providerPoint = _candidateProviderLatLng;
    if (providerPoint == null) return;
    try {
      final bounds = LatLngBounds.fromPoints([_serviceCenter, providerPoint]);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(72)),
      );
    } catch (_) {
      // O mapa pode ainda não estar pronto no primeiro frame.
    }
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/home'),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Busca de prestador',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          const Text(
            '101SERVICE',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    Widget dot({
      required bool active,
      required IconData icon,
      required String label,
    }) {
      return Expanded(
        child: Column(
          children: [
            Container(
              width: active ? 34 : 30,
              height: active ? 34 : 30,
              decoration: BoxDecoration(
                color: active ? AppTheme.primaryYellow : Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 16,
                color: active ? Colors.black : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: active ? AppTheme.darkBlueText : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    Widget line(bool active) => Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 22),
        color: active ? AppTheme.primaryYellow : Colors.grey.shade300,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          dot(active: false, icon: LucideIcons.banknote, label: 'Reserva'),
          line(true),
          dot(active: true, icon: LucideIcons.radar, label: 'Busca'),
          line(false),
          dot(active: false, icon: LucideIcons.navigation, label: 'Chegada'),
          line(false),
          dot(active: false, icon: LucideIcons.badgeCheck, label: 'Conclusão'),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (!widget.showMap) {
      return Container(
        color: const Color(0xFFF3F4F6),
        child: const Center(child: Icon(LucideIcons.map, size: 42)),
      );
    }

    final center = _serviceCenter;
    final providerPoint = _candidateProviderLatLng;
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14.5,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            AppTileLayer.standard(mapboxToken: SupabaseConfig.mapboxToken),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 48,
                  height: 48,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primaryYellow,
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(LucideIcons.mapPin, size: 18),
                  ),
                ),
                if (providerPoint != null)
                  Marker(
                    point: providerPoint,
                    width: 52,
                    height: 52,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.20),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Column(
            children: [
              _mapButton(
                icon: Icons.add,
                onTap: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  );
                },
              ),
              const SizedBox(height: 10),
              _mapButton(
                icon: Icons.remove,
                onTap: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mapButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 6,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(width: 46, height: 46, child: Icon(icon)),
      ),
    );
  }

  Widget _buildBottomCard() {
    final timeline =
        widget.dispatchTimelineOverride ??
        DispatchTrackingTimeline(
          serviceId: widget.serviceId,
          onProviderFound: _openTracking,
          onSearchStateChanged: (title, subtitle) {
            if (!mounted) return;
            _maybePlayStatusSound(title);
            if (_headline == title && _subtitle == subtitle) return;
            setState(() {
              _headline = title;
              _subtitle = subtitle;
            });
          },
          onProviderCandidateChanged: _handleProviderCandidate,
        );
    final screenStatus =
        (_service?['status'] ?? '').toString().toLowerCase().trim();
    final paymentStatus =
        (_service?['payment_status'] ?? '').toString().toLowerCase().trim();

    return Container(
      decoration: BoxDecoration(
        color: _showNoProviderFoundState
            ? const Color(0xFFFFFBEB)
            : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 30,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STATUS ATUAL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: _showNoProviderFoundState
                              ? const Color(0xFF9A6700)
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryYellow,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _paidChipText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _serviceLabel,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (!_showNoProviderFoundState)
              SizedBox(
                height: 320,
                child: RemoteScreenBody(
                  screenKey: 'provider_search',
                  padding: EdgeInsets.zero,
                  context: {
                    'service_id': widget.serviceId,
                    'status': screenStatus,
                    'payment_status': paymentStatus,
                    'headline': _headline,
                    'subtitle': _subtitle,
                    'service_label': _serviceLabel,
                    'show_map': widget.showMap,
                  },
                  fallbackBuilder: (_) => timeline,
                ),
              ),
            if (_showNoProviderFoundState) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3C4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF1C232)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      LucideIcons.searchX,
                      color: Color(0xFF9A6700),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'A busca foi encerrada sem aceite. Você poderá tentar novamente pela Home.',
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF9A6700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (!_showNoProviderFoundState)
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _cancelling ? null : _cancel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryYellow,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _cancelling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'CANCELAR SOLICITAÇÃO',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStepper(),
            Expanded(child: _buildMap()),
            _buildBottomCard(),
          ],
        ),
      ),
    );
  }
}
