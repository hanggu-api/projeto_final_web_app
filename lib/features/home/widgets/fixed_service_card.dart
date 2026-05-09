import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/utils/fixed_schedule_gate.dart';
import '../../../core/utils/navigation_helper.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/api_service.dart';
import '../../../services/data_gateway.dart';
import '../../../services/notification_service.dart';

/// CARD PARA PRESTADOR FIXO (BARBEARIA, SALÃO, ESTABELECIMENTO)
/// O cliente vai até o local.
class FixedServiceCard extends StatefulWidget {
  final String status;
  final String providerName;
  final String category;
  final Map<String, dynamic>? details;
  final ValueChanged<bool>? onExpandChange;
  final bool? expanded;
  final bool showExpandIcon;
  final VoidCallback? onCancel;
  final VoidCallback? onArrived;
  final VoidCallback? onPay;
  final VoidCallback? onRate;
  final VoidCallback? onRefreshNeeded;
  final bool isProviderView;
  final String? serviceId;

  const FixedServiceCard({
    super.key,
    required this.status,
    required this.providerName,
    required this.category,
    this.details,
    this.onExpandChange,
    this.expanded,
    this.onCancel,
    this.onArrived,
    this.onPay,
    this.onRate,
    this.onRefreshNeeded,
    this.showExpandIcon = true,
    this.isProviderView = false,
    this.serviceId,
  });

  @override
  State<FixedServiceCard> createState() => _FixedServiceCardState();
}

class _FixedServiceCardState extends State<FixedServiceCard>
    with TickerProviderStateMixin {
  bool _expanded = false;
  String? _providerAvatarUrl;
  Uint8List? _providerAvatarBytes;

  // Real-time Sync
  StreamSubscription? _serviceSubscription;
  String? _streamStatus;
  Map<String, dynamic>? _streamDetails;

  String get _currentStatus => _streamStatus ?? widget.status;
  Map<String, dynamic> get _currentDetails => {
    ...?widget.details,
    ...?_streamDetails,
  };

  Timer? _refreshTimer;
  String? _travelHeadline;
  DateTime? _lastScheduledAtForNotify;
  bool _alertTriggered = false; // Flag para evitar disparos múltiplos do modal

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
    resolveProviderAvatar();
    _startTravelPolling();
  }

  @override
  void didUpdateWidget(FixedServiceCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Setup listener if ID changes
    if (widget.details?['id'] != oldWidget.details?['id']) {
      _setupRealtimeListener();
    }

    // Refresh calculations and avatar if critical data changes
    if (widget.details?['id'] != oldWidget.details?['id'] ||
        widget.details?['client_arrived'] !=
            oldWidget.details?['client_arrived'] ||
        widget.details?['arrived_at'] != oldWidget.details?['arrived_at'] ||
        widget.status != oldWidget.status) {
      _calculateTravelTime();
      resolveProviderAvatar();
    }

    // Handle expanded state changes from parent
    if (widget.expanded != null && widget.expanded != oldWidget.expanded) {
      _expanded = widget.expanded!;
    }

    // General details update
    if (widget.details != oldWidget.details) {
      resolveProviderAvatar();
    }
  }

  @override
  void dispose() {
    _serviceSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startTravelPolling() {
    _refreshTimer?.cancel();
    _calculateTravelTime();
    // Atualiza a cada 30 segundos para evitar sobrecarga de GPS e poluição do console
    // A precisão de 30s é suficiente para um alerta de trânsito.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _calculateTravelTime(),
    );
  }

  Future<void> _calculateTravelTime() async {
    final detail = _currentDetails;

    // 0. Check for client arrival first to stop polling and show correct info
    final bool clientHasArrived =
        detail['arrived_at'] != null ||
        detail['client_arrived'] == true ||
        detail['client_arrived'] == 'true';

    if (clientHasArrived) {
      if (mounted) {
        setState(() {
          _travelHeadline = 'CLIENTE NO LOCAL 📍';
        });
      }
      return;
    }

    final scheduledAt = _toDate(detail['scheduled_at']);
    if (scheduledAt == null ||
        !['accepted', 'scheduled', 'confirmed'].contains(_currentStatus)) {
      if (mounted) {
        setState(() {
          _travelHeadline = null;
        });
      }
      return;
    }

    // O destino é sempre o local do serviço (que em serviços fixos é a sede do prestador)
    final destLat = _toDouble(detail['latitude']);
    final destLon = _toDouble(detail['longitude']);

    if (destLat == null || destLon == null) return;

    try {
      // Tenta obter a localização atual do usuário via GPS
      Position? position;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        position =
            await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 3),
              ),
            ).timeout(
              const Duration(seconds: 4),
              onTimeout: () => throw TimeoutException('GPS Timeout'),
            );
      }

      if (position != null) {
        final distanceKm = const Distance().as(
          LengthUnit.Kilometer,
          LatLng(position.latitude, position.longitude),
          LatLng(destLat, destLon),
        );

        // 1. Cálculo base de viagem (25km/h)
        final travelTimeMin = ((distanceKm / 25) * 60).round().clamp(5, 120);

        // 2. Margem de antecedência solicitada: 3 minutos
        const leadTimeMin = 3;

        // 3. Momento de sair = Início do serviço - tempo de viagem - antecedência
        final leaveAt = scheduledAt.subtract(
          Duration(minutes: travelTimeMin + leadTimeMin),
        );

        final now = DateTime.now();
        final diffService = scheduledAt.difference(now);

        final bool isLate = now.isAfter(leaveAt);

        // Formatação amigável do tempo restante
        String formatRemaining(Duration d) {
          if (d.inSeconds <= 0) return '0 min';
          if (d.inHours > 0) {
            return '${d.inHours}h ${d.inMinutes.remainder(60)}min';
          }
          return '${d.inMinutes} min';
        }

        if (mounted) {
          setState(() {
            // Título focado no início do serviço
            final serviceIn = formatRemaining(diffService);
            _travelHeadline = 'Serviço em $serviceIn';

            // Subtítulo focado na saída com a inteligência de trânsito + antecedência
            if (isLate) {
              _travelHeadline = 'SAIA AGORA!';

              // 4. DISPARO ATIVO (Polling): Se ainda não disparou o alerta, dispara agora
              if (!_alertTriggered) {
                _alertTriggered = true;
                final serviceId =
                    (widget.serviceId ?? widget.details?['id'] ?? detail['id'])
                        ?.toString();
                if (serviceId != null) {
                  NotificationService().showTimeToLeaveModal({
                    'type': 'time_to_leave',
                    'service_id': serviceId,
                    'travel_time': travelTimeMin.toString(),
                    'lat': destLat,
                    'lng': destLon,
                  });
                }
              }
            } else {
              _alertTriggered =
                  false; // Reseta o trigger se o usuário se aproximar do local e o trânsito mudar
            }
          });

          // 5. Agendamento legado (Fallback para background)
          final serviceId =
              (widget.serviceId ?? widget.details?['id'] ?? detail['id'])
                  ?.toString();
          if (serviceId != null && _lastScheduledAtForNotify != leaveAt) {
            _lastScheduledAtForNotify = leaveAt;
            NotificationService().scheduleTimeToLeave(
              serviceId: serviceId,
              leaveAtAt: leaveAt,
              travelTimeMin: travelTimeMin,
              lat: destLat,
              lng: destLon,
            );
          }
        }
      }
    } catch (e) {
      // Silencioso para evitar poluição no console
      //debugPrint('🚦 [VIAGEM] Erro ao obter localização GPS: $e');
    }
  }

  void _setupRealtimeListener() {
    _serviceSubscription?.cancel();
    final serviceId = widget.details?['id']?.toString();
    if (serviceId != null) {
      _serviceSubscription = DataGateway()
          .watchService(serviceId, scope: ServiceDataScope.fixedOnly)
          .listen((data) {
            if (!mounted) return;
            if (data.isNotEmpty) {
              final oldStatus = _streamStatus;
              final newStatus = data['status'];

              if (newStatus == 'deleted' ||
                  (oldStatus != newStatus && widget.onRefreshNeeded != null)) {
                if (widget.onRefreshNeeded != null) widget.onRefreshNeeded!();
              }

              setState(() {
                _streamStatus = newStatus;
                _streamDetails = data;
              });
            }
          });
    }
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      var s = v.trim();
      if (RegExp(r'^\d{1,3}(\.\d{3})+(,\d+)$').hasMatch(s)) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else if (s.contains(',') && !s.contains('.')) {
        s = s.replaceAll(',', '.');
      }
      return double.tryParse(s);
    }
    return null;
  }

  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) {
      String s = v.trim();
      if (s.contains(' ') && !s.contains('T') && !s.contains('Z')) {
        s = '${s.replaceFirst(' ', 'T')}Z';
      }
      return DateTime.tryParse(s)?.toLocal();
    }
    if (v is num) {
      final n = v.toInt();
      return DateTime.fromMillisecondsSinceEpoch(
        n > 1000000000000 ? n : n * 1000,
        isUtc: true,
      ).toLocal();
    }
    return null;
  }

  String _formatFriendlyDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final target = DateTime(dt.year, dt.month, dt.day);
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (target == today) return 'Hoje às $timeStr';
    if (target == tomorrow) return 'Amanhã às $timeStr';
    final days = [
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo',
    ];
    return '${days[dt.weekday - 1]} ${dt.day}/${dt.month} às $timeStr';
  }

  String getStatusText() {
    final detail = _currentDetails;
    final arrivedAt = detail['arrived_at'];
    final paymentStatus = detail['payment_remaining_status'];

    if (arrivedAt != null &&
        paymentStatus != 'paid' &&
        ['accepted', 'in_progress'].contains(_currentStatus)) {
      return 'Pagamento no local';
    }

    switch (_currentStatus) {
      case 'accepted':
        return 'Agendado';
      case 'in_progress':
        return 'Em Andamento';
      case 'awaiting_confirmation':
        return 'Aguardando Validação';
      case 'completed':
        return 'Serviço concluído';
      case 'waiting_client_confirmation':
        return 'Serviço Finalizado. Confirme!';
      case 'pending':
        return 'Agendado';
      case 'waiting_payment':
        return 'Aguardando pagamento';
      case 'cancelled':
        return 'Cancelado';
      case 'open_for_schedule':
        return 'Disponível para Agendamento';
      case 'schedule_proposed':
        return 'Proposta de Agendamento';
      case 'scheduled':
        return 'Serviço Agendado';
      case 'confirmed':
        return 'Confirmado';
      default:
        return _currentStatus;
    }
  }

  bool _isAwaitingFixedDeposit() {
    final paymentStatus = (_currentDetails['payment_status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (paymentStatus == 'paid' || paymentStatus == 'partially_paid') {
      return false;
    }
    return _currentStatus == 'waiting_payment' || _currentStatus == 'pending';
  }

  @override
  Widget build(BuildContext context) {
    final detail = _currentDetails;
    final scheduledAt = _toDate(detail['scheduled_at']);
    final isExpanded = widget.expanded ?? _expanded;

    final bool clientHasArrived =
        detail['arrived_at'] != null ||
        detail['client_arrived'] == true ||
        detail['client_arrived'] == 'true';

    Color borderColor = clientHasArrived
        ? Colors.grey.shade300
        : (['accepted', 'scheduled', 'confirmed'].contains(_currentStatus)
              ? AppTheme.primaryYellow
              : Colors.grey.shade300);

    return InkWell(
      onTap: () {
        if (_isAwaitingFixedDeposit()) {
          context.push('/beauty-booking');
          return;
        }
        final serviceId = (widget.serviceId ?? _currentDetails['id'])
            ?.toString();
        if (serviceId != null) {
          logFixedScheduleGateDecision(
            'fixed_service_card_tap',
            _currentDetails,
          );
          if (!widget.isProviderView &&
              !evaluateFixedScheduleGate(
                _currentDetails,
              ).shouldStayOnScheduledScreen) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'O acompanhamento libera 30 minutos antes do agendamento.',
                ),
              ),
            );
            return;
          }
          context.push('/scheduled-service/$serviceId');
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.all(isExpanded ? 16 : 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              offset: const Offset(0, 4),
              blurRadius: 16,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // TOPO: Agendamento Confirmado + Data/Hora
            if (['accepted', 'scheduled', 'confirmed'].contains(_currentStatus))
              _buildStatusHeader(scheduledAt),

            const SizedBox(height: 16),

            // Alerta de Saída (Fica no topo se ativo)
            if (_travelHeadline != null && !clientHasArrived)
              _buildTravelAlert(clientHasArrived),

            const SizedBox(height: 12),

            // Informações do Profissional (Avatar, Nome, Perfil, Chat)
            _buildProviderSection(detail),

            const SizedBox(height: 16),

            // Descrição do Serviço
            Text(
              detail['description'] ?? widget.category,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),

            const SizedBox(height: 16),

            // Ações (Maps, Estou a Caminho, Cheguei, Pagar)
            _buildUnifiedActions(detail),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(DateTime? scheduledAt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Center(
          child: Text(
            'Agendamento Confirmado',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (scheduledAt != null)
          Center(
            child: Text(
              _formatFriendlyDate(scheduledAt),
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTravelAlert(bool clientHasArrived) {
    final isLate = _travelHeadline?.contains('AGORA') ?? false;
    final isDeparting = _currentStatus == 'client_departing';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: isLate || isDeparting ? Colors.red[50] : Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isLate || isDeparting
                ? LucideIcons.alertTriangle
                : LucideIcons.clock,
            color: isLate || isDeparting ? Colors.red[700] : Colors.blue[700],
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              isDeparting ? 'ESTOU A CAMINHO! 🚗' : _travelHeadline!,
              style: TextStyle(
                color: isLate || isDeparting
                    ? Colors.red[700]
                    : Colors.blue[700],
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSection(Map<String, dynamic> detail) {
    final name = detail['provider_name'] ?? widget.providerName;
    final rating = detail['provider_rating'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: _providerAvatarBytes != null
                ? MemoryImage(_providerAvatarBytes!)
                : (_providerAvatarUrl != null
                          ? CachedNetworkImageProvider(_providerAvatarUrl!)
                          : null)
                      as ImageProvider?,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profissional',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.star, size: 14, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      rating > 0 ? rating.toString() : 'Novo',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: () {
                    final providerId = detail['provider_id'];
                    if (providerId != null) {
                      context.push(
                        '/provider-profile',
                        extra: int.tryParse(providerId.toString()),
                      );
                    }
                  },
                  child: Text(
                    'Ver perfil completo',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryPurple,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Botão de Chat
          IconButton(
            onPressed: () {
              final id = detail['id']?.toString();
              if (id != null) {
                final participants = DataGateway().extractChatParticipants(
                  detail,
                );
                final beneficiary = participants
                    .cast<Map<String, dynamic>?>()
                    .firstWhere(
                      (item) => item?['role'] == 'beneficiary',
                      orElse: () => null,
                    );
                final requester = participants
                    .cast<Map<String, dynamic>?>()
                    .firstWhere(
                      (item) => item?['role'] == 'requester',
                      orElse: () => null,
                    );
                final beneficiaryName =
                    '${beneficiary?['display_name'] ?? ''}'.trim();
                final beneficiaryId = '${beneficiary?['user_id'] ?? ''}'.trim();
                final requesterId = '${requester?['user_id'] ?? ''}'.trim();
                final participantContextLabel =
                    beneficiaryName.isNotEmpty &&
                        (beneficiaryId.isEmpty || beneficiaryId != requesterId)
                    ? 'Pessoa atendida: $beneficiaryName'
                    : null;
                context.push(
                  '/chat/$id',
                  extra: {
                    'serviceId': id,
                    'participants': participants,
                    'participantContextLabel': participantContextLabel,
                  },
                );
              }
            },
            icon: Icon(LucideIcons.messageCircle, color: AppTheme.primaryBlue),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedActions(Map<String, dynamic> detail) {
    if (widget.isProviderView) return _buildProviderActions(detail);
    return _buildClientActions(detail);
  }

  Widget _buildClientActions(Map<String, dynamic> detail) {
    final status = _currentStatus;
    final bool clientHasArrived =
        detail['arrived_at'] != null ||
        detail['client_arrived'] == true ||
        detail['client_arrived'] == 'true';

    return Column(
      children: [
        // 1. Abrir no Maps (Sempre visível para agendados ativos)
        if ([
          'accepted',
          'scheduled',
          'confirmed',
          'in_progress',
        ].contains(status))
          _buildActionButton(
            label: 'Abrir no Maps',
            icon: LucideIcons.map,
            color: Colors.white,
            textColor: Colors.black87,
            onPressed: _openMap,
            border: BorderSide(color: Colors.grey[300]!),
          ),

        const SizedBox(height: 12),

        // 2. Estou a Caminho
        if (status == 'accepted' ||
            status == 'scheduled' ||
            status == 'confirmed')
          _buildActionButton(
            label: 'Estou a Caminho',
            icon: LucideIcons.car,
            color: Colors.blue[600]!,
            onPressed: () => _updateClientStatus('depart'),
          ),

        // 3. Cheguei no Local
        if (status == 'client_departing' ||
            (['accepted', 'scheduled', 'confirmed'].contains(status) &&
                !clientHasArrived))
          _buildActionButton(
            label: 'CHEGUEI AO LOCAL',
            icon: LucideIcons.mapPin,
            color: Colors.blue,
            onPressed: () => _updateClientStatus('arrived_client'),
          ),

        // 4. Orientação do pagamento presencial
        if (clientHasArrived &&
            status != 'completed' &&
            detail['payment_remaining_status'] != 'paid')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Text(
              'Os 90% restantes são pagos diretamente ao prestador no local, fora do app.',
              style: TextStyle(
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),

        // 5. Cancelar
        if (!clientHasArrived && status != 'completed' && status != 'cancelled')
          TextButton(
            onPressed: widget.onCancel,
            child: Text(
              'Cancelar Agendamento',
              style: TextStyle(color: Colors.red[300], fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildProviderActions(Map<String, dynamic> detail) {
    final status = _currentStatus;
    final shouldShowManualPaymentWarning =
        status == 'client_arrived' ||
        detail['payment_remaining_status'] == 'pending';
    return Column(
      children: [
        if (status == 'pending')
          _buildActionButton(
            label: 'ACEITAR',
            icon: Icons.check,
            color: Colors.green,
            onPressed: () => _handleStatusChange('accepted'),
          ),

        if ([
          'accepted',
          'scheduled',
          'confirmed',
          'client_departing',
          'client_arrived',
        ].contains(status))
          _buildActionButton(
            label: 'INICIAR SERVIÇO',
            icon: Icons.play_arrow,
            color: Colors.blue,
            onPressed: () => _handleStatusChange('in_progress'),
          ),

        if (status == 'in_progress')
          _buildActionButton(
            label: 'CONCLUIR SERVIÇO',
            icon: Icons.stop,
            color: Colors.black,
            onPressed: () => _handleStatusChange('completed'),
          ),

        if (shouldShowManualPaymentWarning)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Text(
              'O valor restante deste agendamento é pago presencialmente, fora do app. Não há confirmação manual interna.',
              style: TextStyle(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    Color textColor = Colors.white,
    BorderSide? border,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: textColor,
            elevation: 0,
            side: border,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  void _updateClientStatus(String endpoint) async {
    final id = _currentDetails['id']?.toString();
    if (id == null) return;
    try {
      if (endpoint == 'depart') {
        await ApiService().markClientDeparting(id);
        await _sendCurrentClientLocation(id);
        if (mounted) {
          setState(() => _streamStatus = 'client_departing');
        }
      } else if (endpoint == 'arrived_client') {
        await ApiService().markClientArrived(id);
        if (mounted) {
          setState(() => _streamStatus = 'client_arrived');
        }
      } else {
        await ApiService().post('/services/$id/$endpoint', {});
      }
      if (widget.onRefreshNeeded != null) widget.onRefreshNeeded!();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _sendCurrentClientLocation(String serviceId) async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
      await ApiService().updateServiceClientLocation(
        serviceId,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (_) {
      // best effort: status update must continue even without location
    }
  }

  Future<void> _handleStatusChange(String s) async {
    final id = _currentDetails['id']?.toString();
    if (id == null) return;
    try {
      await ApiService().updateServiceStatus(id, s);
      if (widget.onRefreshNeeded != null) widget.onRefreshNeeded!();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _openMap() async {
    final detail = _currentDetails;
    final providerLat = detail['latitude'] ?? detail['provider_lat'];
    final providerLon = detail['longitude'] ?? detail['provider_lon'];

    if (providerLat == null || providerLon == null) return;

    await NavigationHelper.openNavigation(
      latitude: double.tryParse(providerLat.toString()) ?? 0,
      longitude: double.tryParse(providerLon.toString()) ?? 0,
    );
  }

  Future<void> resolveProviderAvatar() async {
    try {
      final d = _currentDetails;
      final raw =
          d['provider_avatar'] ??
          d['providerPhoto'] ??
          d['providers']?['users']?['avatar_url'];
      if (raw is String && raw.startsWith('http')) {
        _providerAvatarUrl = raw;
      } else if (raw is String && raw.isNotEmpty) {
        _providerAvatarBytes = await ApiService().getMediaBytes(raw);
      }
      setState(() {});
    } catch (_) {}
  }
}
