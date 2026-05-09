import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/utils/fixed_schedule_gate.dart';
import '../../core/utils/navigation_helper.dart';
import '../../core/config/supabase_config.dart';
import '../../core/maps/app_tile_layer.dart';

import '../../core/theme/app_theme.dart';
import '../shared/chat_screen.dart';
import '../../services/api_service.dart';
import '../../services/background_main.dart';
import '../../services/client_tracking_service.dart';
import '../../services/data_gateway.dart';
import '../../widgets/app_dialog_actions.dart';

class ScheduledServiceScreen extends StatefulWidget {
  final String serviceId;

  const ScheduledServiceScreen({super.key, required this.serviceId});

  @override
  State<ScheduledServiceScreen> createState() => _ScheduledServiceScreenState();
}

class _ScheduledServiceScreenState extends State<ScheduledServiceScreen>
    with WidgetsBindingObserver {
  static const double _arrivedDistanceThresholdMeters = 200;
  final ApiService _api = ApiService();
  bool _isLoading = true;
  bool _isReturningHome = false;
  Map<String, dynamic>? _service;

  Timer? _refreshTimer;

  String? _serviceParticipantContextLabel(Map<String, dynamic>? service) {
    if (service == null) return null;
    final participants = DataGateway().extractChatParticipants(service);
    final beneficiary = participants.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['role'] == 'beneficiary',
      orElse: () => null,
    );
    final requester = participants.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['role'] == 'requester',
      orElse: () => null,
    );
    if (beneficiary == null) return null;
    final beneficiaryName = '${beneficiary['display_name'] ?? ''}'.trim();
    if (beneficiaryName.isEmpty) return null;
    final beneficiaryId = '${beneficiary['user_id'] ?? ''}'.trim();
    final requesterId = '${requester?['user_id'] ?? ''}'.trim();
    if (beneficiaryId.isNotEmpty && beneficiaryId == requesterId) return null;
    return 'Pessoa atendida: $beneficiaryName';
  }

  Future<void> _openChatModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.96,
          child: ChatScreen(
            serviceId: widget.serviceId,
            otherName: _service?['provider_name']?.toString(),
            otherAvatar: _service?['provider_avatar']?.toString(),
            isInline: true,
            onClose: () => Navigator.of(context).pop(),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadService();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
      unawaited(initializeBackgroundService());
      if (_service != null) {
        _handleScheduledGateDecision(_service!, source: 'resume', silent: true);
        unawaited(ClientTrackingService.syncTrackingForService(_service));
      }
      unawaited(_loadService(silent: true));
      return;
    }
    _refreshTimer?.cancel();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      return;
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadService(silent: true),
    );
  }

  bool _isMissingOrDeletedService(Map<String, dynamic> service) {
    final status = (service['status'] ?? '').toString().trim().toLowerCase();
    return service['not_found'] == true || status == 'deleted';
  }

  bool _shouldBlockUnpaidFixedAccess(Map<String, dynamic> service) {
    final status = (service['status'] ?? '').toString().trim().toLowerCase();
    final paymentStatus = (service['payment_status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isFixed =
        service['is_fixed'] == true ||
        service['at_provider'] == true ||
        (service['service_type'] ?? '').toString().trim().toLowerCase() ==
            'at_provider' ||
        (service['location_type'] ?? '').toString().trim().toLowerCase() ==
            'provider';
    final depositPaid =
        paymentStatus == 'paid' || paymentStatus == 'partially_paid';
    return isFixed &&
        !depositPaid &&
        {'waiting_payment', 'pending'}.contains(status);
  }

  bool _shouldKeepScheduledScreenLocked(Map<String, dynamic> service) {
    return evaluateFixedScheduleGate(service).shouldStayOnScheduledScreen;
  }

  void _scheduleReturnHomeForUnlockedService({bool showMessage = true}) {
    if (_isReturningHome) return;
    _isReturningHome = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Esse agendamento ainda está longe. A home foi liberada por enquanto.',
            ),
          ),
        );
      }
      context.go('/home');
    });
  }

  bool _handleScheduledGateDecision(
    Map<String, dynamic> service, {
    required String source,
    bool silent = false,
  }) {
    logFixedScheduleGateDecision(source, service);
    final decision = evaluateFixedScheduleGate(service);
    if (decision.shouldStayOnScheduledScreen) return true;

    _refreshTimer?.cancel();
    _scheduleReturnHomeForUnlockedService(showMessage: !silent);
    return false;
  }

  Future<void> _loadService({bool silent = false}) async {
    try {
      final data = await _api.getServiceDetails(
        widget.serviceId,
        scope: ServiceDataScope.fixedOnly,
      );
      debugPrint(
        '🔍 [ScheduledService] Data loaded: ${data['id']} - Status: ${data['status']}',
      );
      if (_isMissingOrDeletedService(data)) {
        _refreshTimer?.cancel();
        if (!mounted) return;
        setState(() {
          _service = null;
          _isLoading = false;
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Esse agendamento não existe mais. Voltando para a Home.',
              ),
            ),
          );
        }
        context.go('/home');
        return;
      }
      if (_shouldBlockUnpaidFixedAccess(data)) {
        _refreshTimer?.cancel();
        await ClientTrackingService.clearContext(finalStatus: 'waiting_payment');
        if (!mounted) return;
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Esse agendamento ainda está aguardando o pagamento da taxa. Volte para concluir o PIX.',
              ),
            ),
          );
        }
        context.go('/beauty-booking');
        return;
      }
      if (!_handleScheduledGateDecision(
        data,
        source: 'refresh_success',
        silent: silent,
      )) {
        await ClientTrackingService.syncTrackingForService(data);
        return;
      }
      if (mounted) {
        setState(() {
          _service = data;
          if (!silent) _isLoading = false;
        });
        await initializeBackgroundService();
        await ClientTrackingService.syncTrackingForService(data);

        // Fetch full profile if provider name is generic
        final pName = _service?['provider_name'];
        final pId = _service?['provider_id'];
        if ((pName == null || pName == 'Prestador') && pId != null) {
          final pIdInt = int.tryParse(pId.toString());
          if (pIdInt != null) {
            _fetchFullProviderProfile(pIdInt);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading service: $e');
      if (_service != null &&
          !_handleScheduledGateDecision(
            _service!,
            source: 'refresh_error_with_cached_service',
            silent: true,
          )) {
        return;
      }
      if (mounted && !silent) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar agendamento: $e')),
        );
      }
    }
  }

  Future<void> _fetchFullProviderProfile(int providerId) async {
    try {
      final profile = await _api.getProviderProfile(providerId);
      if (mounted && _service != null) {
        setState(() {
          final name = profile['name'] ?? profile['full_name'];
          if (name != null && name.toString().isNotEmpty) {
            _service!['provider_name'] = name;
          }

          final avatar =
              profile['avatar_url'] ?? profile['photo'] ?? profile['avatar'];
          if (avatar != null && avatar.toString().isNotEmpty) {
            _service!['provider_avatar'] = avatar;
          }

          if (profile['rating'] != null) {
            _service!['provider_rating'] = profile['rating'];
          }
          if (profile['rating_count'] != null) {
            _service!['provider_rating_count'] = profile['rating_count'];
          }
        });
      }
    } catch (e) {
      debugPrint(
        '⚠️ [ScheduledService] Error fetching full provider profile: $e',
      );
    }
  }

  Future<void> _openMap() async {
    final providerLat =
        _service?['provider_lat'] ?? _service?['provider']?['latitude'];
    final providerLon =
        _service?['provider_lon'] ?? _service?['provider']?['longitude'];

    if (providerLat == null || providerLon == null) return;

    await NavigationHelper.openNavigation(
      latitude: double.tryParse(providerLat.toString()) ?? 0,
      longitude: double.tryParse(providerLon.toString()) ?? 0,
    );
  }

  double? _distanceToProviderMeters() {
    final clientLat = double.tryParse(
      _service?['client_latitude']?.toString() ??
          _service?['latitude']?.toString() ??
          '',
    );
    final clientLon = double.tryParse(
      _service?['client_longitude']?.toString() ??
          _service?['longitude']?.toString() ??
          '',
    );
    final providerLat = double.tryParse(
      _service?['provider_lat']?.toString() ??
          _service?['provider']?['latitude']?.toString() ??
          '',
    );
    final providerLon = double.tryParse(
      _service?['provider_lon']?.toString() ??
          _service?['provider']?['longitude']?.toString() ??
          '',
    );
    if (clientLat == null ||
        clientLon == null ||
        providerLat == null ||
        providerLon == null) {
      return null;
    }
    return Geolocator.distanceBetween(
      clientLat,
      clientLon,
      providerLat,
      providerLon,
    );
  }

  bool _canMarkArrived() {
    final distanceMeters = _distanceToProviderMeters();
    if (distanceMeters == null) return false;
    return distanceMeters <= _arrivedDistanceThresholdMeters;
  }

  String? _trackingStatusMessage() {
    final detail = _service;
    if (detail == null) return null;

    final trackingStatus = (detail['client_tracking_status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final updatedAt = DateTime.tryParse(
      (detail['client_tracking_updated_at'] ?? '').toString(),
    )?.toLocal();
    final isTrackingActive = detail['client_tracking_active'] == true;

    if (trackingStatus == 'permission_denied') {
      return 'Acompanhamento pausado: habilite a localizacao para continuar enviando seu trajeto.';
    }
    if (trackingStatus == 'location_unavailable') {
      return 'Nao conseguimos atualizar sua localizacao agora. O app vai tentar novamente automaticamente.';
    }
    if (updatedAt != null &&
        DateTime.now().difference(updatedAt) > const Duration(minutes: 2)) {
      return 'Ultima atualizacao do trajeto ha mais de 2 minutos. O acompanhamento sera retomado assim que houver sinal.';
    }
    if (isTrackingActive) {
      return 'Seu trajeto ate o local esta sendo acompanhado automaticamente a cada 30 segundos.';
    }
    return null;
  }

  Future<void> _cancelService() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Agendamento?'),
        content: const Text('Tem certeza que deseja cancelar este serviço?'),
        actions: [
          AppDialogCancelAction(
            label: 'Não',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AppDialogCancelAction(
            label: 'Sim, Cancelar',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.cancelService(
          widget.serviceId,
          scope: ServiceDataScope.fixedOnly,
        );
        await ClientTrackingService.clearContext(finalStatus: 'cancelled');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Agendamento cancelado.')),
          );
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            context.go('/home');
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erro ao cancelar: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalhes do Agendamento')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalhes do Agendamento')),
        body: const Center(child: Text('Agendamento não encontrado.')),
      );
    }

    if (!_handleScheduledGateDecision(
      _service!,
      source: 'build_cached_service',
      silent: true,
    )) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Agendamento'),
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadService(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            vertical: 16,
          ), // Removida margem horizontal geral para permitir cards largos
          child: Column(
            children: [
              _buildStatusCard(),
              _buildMapSection(),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildProviderInfo(),
                    const SizedBox(height: 24),
                    _buildActions(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final scheduledAtStr = _service?['scheduled_at'];
    DateTime? scheduledAt;
    if (scheduledAtStr != null) {
      scheduledAt = DateTime.tryParse(scheduledAtStr)?.toLocal();
    }
    final participantContextLabel = _serviceParticipantContextLabel(_service);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          0,
        ), // Removido border radius lateral para alargar o card
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryYellow.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.calendarCheck,
              size: 40,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Agendamento Confirmado',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (participantContextLabel != null) ...[
            Text(
              participantContextLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (scheduledAt != null)
            Text(
              '${scheduledAt.day.toString().padLeft(2, '0')}/${scheduledAt.month.toString().padLeft(2, '0')} às ${scheduledAt.hour.toString().padLeft(2, '0')}:${scheduledAt.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          const SizedBox(height: 24),
          // Time to leave calculation
          _buildTimeToLeave(scheduledAt),
        ],
      ),
    );
  }

  Widget _buildTimeToLeave(DateTime? scheduledAt) {
    if (scheduledAt == null) return const SizedBox.shrink();
    if (_service == null || !_shouldKeepScheduledScreenLocked(_service!)) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now().toLocal();

    final clientLat = double.tryParse(_service?['latitude']?.toString() ?? '');
    final clientLon = double.tryParse(_service?['longitude']?.toString() ?? '');
    final providerLat = double.tryParse(
      _service?['provider_lat']?.toString() ?? '',
    );
    final providerLon = double.tryParse(
      _service?['provider_lon']?.toString() ?? '',
    );

    int travelTime = 30; // Default fallback

    if (clientLat != null &&
        clientLon != null &&
        providerLat != null &&
        providerLon != null) {
      // Calcula distância em KM
      final distanceKm = const Distance().as(
        LengthUnit.Kilometer,
        LatLng(clientLat, clientLon),
        LatLng(providerLat, providerLon),
      );

      // Travel Time = (Distância / Velocidade Média) * 60 minutos
      // Velocidade Média = 25 km/h
      travelTime = ((distanceKm / 25) * 60).round();

      // Mínimo de 5 minutos se a distância for muito curta
      if (travelTime < 5) travelTime = 5;
    } else {
      // Fallback para o valor do backend se disponível
      travelTime =
          int.tryParse(_service?['travel_time_min']?.toString() ?? '30') ?? 30;
    }

    final leaveAt = scheduledAt.subtract(Duration(minutes: travelTime + 15));
    final isLate = now.isAfter(leaveAt);
    final timeStr =
        '${leaveAt.hour.toString().padLeft(2, '0')}:${leaveAt.minute.toString().padLeft(2, '0')}';

    final bgColor = isLate ? Colors.red[50] : Colors.blue[50];
    final textColor = isLate ? Colors.red : Colors.blue;
    final message = isLate
        ? 'Saia agora para chegar com antecedência! ($timeStr)'
        : 'Saia de casa às $timeStr para chegar 15 min antes';
    final icon = isLate ? LucideIcons.alertTriangle : LucideIcons.clock;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection() {
    final clientLat = double.tryParse(_service?['latitude']?.toString() ?? '');
    final clientLon = double.tryParse(_service?['longitude']?.toString() ?? '');
    final providerLat = double.tryParse(
      _service?['provider_lat']?.toString() ?? '',
    );
    final providerLon = double.tryParse(
      _service?['provider_lon']?.toString() ?? '',
    );

    // Se não tiver pelo menos o destino, não mostra o mapa
    if (providerLat == null || providerLon == null) {
      return const SizedBox.shrink();
    }

    final centerLat = clientLat != null
        ? (clientLat + providerLat) / 2
        : providerLat;
    final centerLon = clientLon != null
        ? (clientLon + providerLon) / 2
        : providerLon;

    // Distância calculada se tivermos os dois pontos
    final distanceKm = (clientLat != null && clientLon != null)
        ? const Distance()
              .as(
                LengthUnit.Kilometer,
                LatLng(clientLat, clientLon),
                LatLng(providerLat, providerLon),
              )
              .toStringAsFixed(1)
        : '---';

    return InkWell(
      onTap: _openMap,
      child: Column(
        children: [
          IgnorePointer(
            ignoring:
                true, // Importante: Ignora toques no mapa para que o InkWell os receba
            child: Container(
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(0),
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(0),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(centerLat, centerLon),
                    initialZoom: (clientLat != null) ? 14 : 16,
                  ),
                  children: [
                    AppTileLayer.standard(
                      mapboxToken: SupabaseConfig.mapboxToken,
                    ),
                    if (clientLat != null && clientLon != null)
                      PolylineLayer(
                        polylines: <Polyline>[
                          Polyline(
                            points: [
                              LatLng(clientLat, clientLon),
                              LatLng(providerLat, providerLon),
                            ],
                            strokeWidth: 3,
                            color: AppTheme.primaryPurple,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (clientLat != null && clientLon != null)
                          Marker(
                            point: LatLng(clientLat, clientLon),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.person_pin_circle,
                              color: Colors.blue,
                              size: 40,
                            ),
                          ),
                        Marker(
                          point: LatLng(providerLat, providerLon),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_service?['provider_address'] != null)
            Text(
              _service!['provider_address'],
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.mapPin, size: 16, color: AppTheme.primaryPurple),
              const SizedBox(width: 4),
              Text(
                '$distanceKm km • ~${_service?['travel_time_min'] ?? 30} min',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProviderInfo() {
    final name = _service?['provider_name']?.toString() ?? 'Prestador';
    final avatarUrl = _service?['provider_avatar']?.toString();
    final rating =
        double.tryParse(_service?['provider_rating']?.toString() ?? '0') ?? 0.0;
    final ratingCount =
        int.tryParse(_service?['provider_rating_count']?.toString() ?? '0') ??
        0;
    final providerId = _service?['provider_id'];

    return GestureDetector(
      onTap: () {
        if (providerId != null) {
          context.push(
            '/provider-profile',
            extra: int.tryParse(providerId.toString()),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppTheme.primaryPurple,
              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? NetworkImage(avatarUrl)
                  : null,
              child: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? null
                  : Text(
                      name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profissional',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        rating > 0 ? rating.toStringAsFixed(1) : 'Novo',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      if (ratingCount > 0)
                        Text(
                          ' ($ratingCount avaliações)',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ver perfil completo',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryPurple,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _openChatModal,
              icon: const Icon(LucideIcons.messageCircle, color: Colors.green),
              style: IconButton.styleFrom(
                backgroundColor: Colors.green[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    final status = _service?['status'];
    final distanceMeters = _distanceToProviderMeters();
    final canMarkArrived = _canMarkArrived();
    final bool clientHasArrived =
        status == 'client_arrived' ||
        _service?['arrived_at'] != null ||
        _service?['client_arrived'] == true ||
        _service?['client_arrived'] == 'true';

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openMap,
            icon: const Icon(LucideIcons.map),
            label: const Text('Ir com GPS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
              side: BorderSide(color: Colors.grey[300]!),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_trackingStatusMessage() != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Text(
              _trackingStatusMessage()!,
              style: TextStyle(
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 1. Hora de Sair (Departing)
        if (status == 'accepted' || status == 'scheduled')
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                debugPrint(
                  '🏁 [ScheduledService] Clicking ESTOU A CAMINHO for: ${widget.serviceId}',
                );
                try {
                  await ApiService().markClientDeparting(widget.serviceId);
                  await ClientTrackingService.sendTrackingTick(
                    source: 'client_depart_button',
                  );
                  debugPrint(
                    '✅ [ScheduledService] markClientDeparting success',
                  );
                  _loadService();
                } catch (e) {
                  debugPrint(
                    '❌ [ScheduledService] Error marking departure: $e',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao marcar saída: $e')),
                    );
                  }
                }
              },
              icon: const Icon(LucideIcons.car),
              label: const Text('Estou a Caminho'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

        // 2. Cheguei (Arrived)
        if ((status == 'client_departing' ||
                status == 'accepted' ||
                status == 'scheduled') &&
            !clientHasArrived &&
            canMarkArrived)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                debugPrint(
                  '🏁 [ScheduledService] Clicking CHEGUEI NO LOCAL for: ${widget.serviceId}',
                );
                try {
                  await ApiService().markClientArrived(widget.serviceId);
                  debugPrint('✅ [ScheduledService] markClientArrived success');
                  _loadService();
                } catch (e) {
                  debugPrint('❌ [ScheduledService] Error marking arrived: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao marcar chegada: $e')),
                    );
                  }
                }
              },
              icon: const Icon(LucideIcons.mapPin),
              label: const Text('Cheguei no Local'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

        if ((status == 'client_departing' ||
                status == 'accepted' ||
                status == 'scheduled') &&
            !clientHasArrived &&
            !canMarkArrived)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Text(
              distanceMeters == null
                  ? 'O botão "Cheguei no local" aparece quando o app confirmar que você está próximo do salão.'
                  : 'Aproxime-se mais do salão para liberar "Cheguei no local". Distância atual: ${(distanceMeters / 1000).toStringAsFixed(distanceMeters >= 1000 ? 1 : 2)} km.',
              style: TextStyle(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blueGrey[50],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.blueGrey.shade100),
          ),
          child: const Text(
            'Pagamento final: os 90% restantes são pagos diretamente no salão, fora do app.',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        if (!clientHasArrived &&
            status != 'client_departing' &&
            status != 'client_arrived') ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: _cancelService,
            style: TextButton.styleFrom(foregroundColor: Colors.red[300]),
            child: const Text('Cancelar Agendamento'),
          ),
        ],
      ],
    );
  }
}
