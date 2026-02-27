import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/api_service.dart';
import '../../../services/data_gateway.dart';

/// CARD PARA PRESTADOR MÓVEL (PROFISSIONAL VAI ATÉ O CLIENTE)
class MobileServiceCard extends StatefulWidget {
  final String status;
  final String providerName;
  final String distance;
  final String category;
  final Map<String, dynamic>? details;
  final ValueChanged<bool>? onExpandChange;
  final bool? expanded;
  final bool showExpandIcon;
  final VoidCallback? onCancel;
  final VoidCallback? onTrack;
  final VoidCallback? onArrived;
  final VoidCallback? onPay;
  final VoidCallback? onRate;
  final VoidCallback? onRefreshNeeded;
  final bool isProviderView;
  final String? serviceId;

  const MobileServiceCard({
    super.key,
    required this.status,
    required this.providerName,
    required this.distance,
    required this.category,
    this.details,
    this.onExpandChange,
    this.expanded,
    this.onCancel,
    this.onTrack,
    this.onArrived,
    this.onPay,
    this.onRate,
    this.onRefreshNeeded,
    this.showExpandIcon = true,
    this.isProviderView = false,
    this.serviceId,
  });

  @override
  State<MobileServiceCard> createState() => _MobileServiceCardState();
}

class _MobileServiceCardState extends State<MobileServiceCard>
    with TickerProviderStateMixin {
  bool _expanded = false;
  String? _providerAvatarUrl;
  Uint8List? _providerAvatarBytes;
  
  // Review State
  int _rating = 0;
  final _commentController = TextEditingController();
  bool _submittingReview = false;
  bool _reviewSubmittedSuccessfully = false;

  // Real-time Sync
  StreamSubscription? _serviceSubscription;
  String? _streamStatus;
  Map<String, dynamic>? _streamDetails;

  String get _currentStatus => _streamStatus ?? widget.status;
  Map<String, dynamic> get _currentDetails => {...?widget.details, ...?_streamDetails};

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
    resolveProviderAvatar();
  }

  @override
  void didUpdateWidget(MobileServiceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.details?['id'] != oldWidget.details?['id']) {
      _setupRealtimeListener();
    }
    if (widget.expanded != null && widget.expanded != oldWidget.expanded) {
      _expanded = widget.expanded!;
    }
    if (widget.details != oldWidget.details) {
      resolveProviderAvatar();
    }
  }

  bool _isSchedulingCounter = false;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  final TextEditingController _msgCounterController = TextEditingController();

  @override
  void dispose() {
    _msgCounterController.dispose();
    _commentController.dispose();
    _serviceSubscription?.cancel();
    _trackingTimer?.cancel();
    _searchTickTimer?.cancel();
    super.dispose();
  }

  void _setupRealtimeListener() {
    _serviceSubscription?.cancel();
    final serviceId = widget.details?['id']?.toString();
    if (serviceId != null) {
      if (['searching', 'pending', 'open', 'paid', 'offered'].contains(_currentStatus)) {
         _startTrackingPoll(serviceId);
      }

      _serviceSubscription = DataGateway().watchService(serviceId).listen((data) {
        if (!mounted) return;
        
        if (data.isNotEmpty) {
          final oldStatus = _streamStatus;
          final newStatus = data['status'];
          
          if (newStatus == 'deleted' || (oldStatus != newStatus && widget.onRefreshNeeded != null)) {
            if (widget.onRefreshNeeded != null) widget.onRefreshNeeded!();
          }
          
          setState(() {
            _streamStatus = newStatus;
            _streamDetails = data;
          });

          if (['searching', 'pending', 'open', 'paid', 'offered'].contains(newStatus)) {
             _startTrackingPoll(serviceId);
          } else {
             _trackingTimer?.cancel();
             _searchTickTimer?.cancel();
          }
        }
      });
    }
  }

  Timer? _trackingTimer;
  Timer? _searchTickTimer;
  int _searchCountdown = 20;
  String? _trackingHeadline = "Iniciando busca...";

  String _getDynamicSearchMessage() {
    if (_searchCountdown > 15) return "Notificando prestador...";
    if (_searchCountdown > 5) return "Aguardando resposta...";
    return "Buscando próximo prestador...";
  }

  void _startTrackingPoll(String serviceId) {
    if (_searchTickTimer != null && _searchTickTimer!.isActive) return;
    
    _trackingTimer?.cancel();
    _searchTickTimer?.cancel();
    
    _fetchTrackingHeadline(serviceId);
    _searchCountdown = 20;

    _searchTickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_searchCountdown > 0) {
          _searchCountdown--;
        } else {
          _searchCountdown = 20;
          _fetchTrackingHeadline(serviceId);
        }
      });
    });
  }

  /// Sprint 3: Lê service_logs via Supabase SDK em vez do endpoint legado /service/:id/tracking
  Future<void> _fetchTrackingHeadline(String serviceId) async {
    try {
      final rows = await Supabase.instance.client
          .from('service_logs')
          .select('action, message, created_at')
          .eq('service_id', serviceId)
          .order('created_at', ascending: false)
          .limit(5);

      if (!mounted) return;

      final List<dynamic> logs = rows;

      if (logs.isEmpty) {
        setState(() {
          _trackingHeadline = 'Buscando prestadores...';
        });
        return;
      }

      final latest = logs.first as Map<String, dynamic>;
      final eventType = (latest['action'] as String? ?? '').toUpperCase();
      final message = latest['message'] as String?;

      // Verificar se prestador foi encontrado
      final accepted = logs.any((r) =>
          ((r as Map)['action'] as String?)?.toUpperCase().contains('ACCEPTED') == true ||
          (r['action'] as String?)?.toUpperCase().contains('PROVIDER_ASSIGNED') == true);

      setState(() {
        _trackingHeadline = _headlineFn(eventType, message);
      });

      if (accepted) {
        _trackingTimer?.cancel();
        _searchTickTimer?.cancel();
      }
    } catch (e) {
      debugPrint('[MobileCard] _fetchTrackingHeadline erro: $e');
    }
  }

  String _headlineFn(String eventType, String? message) {
    switch (eventType) {
      case 'CREATED':
      case 'SERVICE_CREATED':
        return 'Serviço criado. Procurando prestadores...';
      case 'DISPATCH_STARTED':
        return 'Buscando prestadores próximos...';
      case 'PROVIDER_NOTIFIED':
        return 'Prestador notificado. Aguardando resposta...';
      case 'PROVIDER_ACCEPTED':
      case 'ACCEPTED':
      case 'PROVIDER_ASSIGNED':
        return 'Prestador encontrado! 🎉';
      case 'PROVIDER_REJECTED':
        return 'Buscando próximo prestador...';
      case 'DISPATCH_TIMEOUT':
        return 'Reiniciando busca...';
      default:
        return message ?? 'Processando...';
    }
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      if (v.trim().isEmpty) return null;
      var s = v.trim();
      if (RegExp(r'^\d{1,3}(\.\d{3})+(,\d+)$').hasMatch(s)) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else if (s.contains(',') && !s.contains('.')) {
        s = s.replaceAll(',', '.');
      }
      var parsed = double.tryParse(s);
      if (parsed != null) return parsed;
      s = s.replaceAll(RegExp(r'[^0-9\.-]'), '');
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
      DateTime dt;
      if (n > 1000000000000) {
        dt = DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
      } else {
        dt = DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
      }
      return dt.toLocal();
    }
    return null;
  }

  String _formatFriendlyDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final target = DateTime(dt.year, dt.month, dt.day);

    final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    
    if (target == today) {
      return 'Hoje às $timeStr';
    } else if (target == tomorrow) {
      return 'Amanhã às $timeStr';
    } else {
      final days = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];
      final dayName = days[dt.weekday - 1];
      final dateStr = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
      return '$dayName $dateStr às $timeStr';
    }
  }

  bool get isWaitingState {
    return ['pending', 'searching', 'waiting_payment', 'open'].contains(_currentStatus);
  }

  Future<void> _handleStatusChange(String newStatus) async {
    final id = _currentDetails['id']?.toString();
    if (id == null) return;
    
    try {
      if (newStatus == 'accepted') {
         await ApiService().acceptService(id);
      } else {
         await ApiService().updateServiceStatus(id, newStatus);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status atualizado com sucesso!'))
        );
        if (widget.onRefreshNeeded != null) widget.onRefreshNeeded!();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar status: $e'))
        );
      }
    }
  }

  Widget _buildStandardButton(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  String getStatusText() {
    final detail = _currentDetails;
    final arrivedAt = detail['arrived_at'];
    final paymentStatus = detail['payment_remaining_status'];
    final bool isArrived = arrivedAt != null || (_trackingHeadline ?? '').toLowerCase().contains('chegou');

    if (isArrived &&
        paymentStatus != 'paid' &&
        ['accepted', 'in_progress', 'inProgress'].contains(_currentStatus)) {
      return 'Pagar Restante';
    }

    switch (_currentStatus) {
      case 'accepted':
        return widget.distance.isNotEmpty && widget.distance != '---'
            ? 'Distância: ${widget.distance}'
            : 'A caminho';
      case 'in_progress':
        final api = ApiService();
        return api.role == 'provider' ? 'Em Andamento' : 'Aguardando finalização';
      case 'awaiting_confirmation':
        final api = ApiService();
        return api.role == 'provider' ? 'Aguardando Validação' : 'Confirmação Necessária';
      case 'waiting_remaining_payment':
        return 'Aguardando pagamento restante';
      case 'completed':
        return 'Serviço concluído';
      case 'waiting_client_confirmation':
        return 'Serviço Finalizado. Confirme a Conclusão!';
      case 'pending':
        final api = ApiService();
        final isProvider = api.role == 'provider';
        if (isProvider) return 'Agendado';
        return 'Aguardando prestador';
      case 'waiting_payment_remaining':
        final api = ApiService();
        return api.role == 'provider' ? 'Aguardando Pagamento Seguro' : 'Pagar Restante';
      case 'waiting_payment':
      case 'arrived':
        return 'Aguardando pagamento';
      case 'searching':
        return 'Buscando prestador';
      case 'open':
        return 'Aberto';
      case 'paid':
      case 'offered':
        return 'Buscando prestador';
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

  @override
  Widget build(BuildContext context) {
    final detail = _currentDetails;
    final desc = (detail['description'] ?? widget.category).toString();
    final priceEstimated = _toDouble(detail['price_estimated']);
    final priceUpfront = _toDouble(detail['price_upfront']);
    String dateText = '';
    final createdDt = _toDate(detail['created_at']);
    if (createdDt != null) {
      dateText = _formatFriendlyDate(createdDt.toLocal());
    }
    final isExpanded = widget.expanded ?? _expanded;

    final borderColor =
        ['accepted', 'scheduled', 'confirmed'].contains(_currentStatus)
        ? AppTheme.primaryYellow
        : Colors.grey.shade300;

    final String currentProviderName = _currentDetails['provider_name'] ?? widget.providerName;
    final bool hasProvider = currentProviderName != 'Aguardando...' && currentProviderName.isNotEmpty;
    
    return InkWell(
      onTap: (_currentStatus == 'schedule_proposed') ? null : () {
        final serviceId = (widget.details?['id'] ?? _currentDetails['id'])?.toString();
        if (serviceId != null) {
          final api = ApiService();
          if (api.role == 'provider') {
            context.push('/provider-service-details/$serviceId');
          } else {
            context.push('/tracking/$serviceId');
          }
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: EdgeInsets.all(isExpanded ? 12 : 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                offset: const Offset(0, 4),
                blurRadius: 12,
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_currentDetails['title'] != null)
                      Text(
                        _currentDetails['title'].toString(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryPurple,
                        ),
                      )
                    else
                      const SizedBox.shrink(),

                    if (widget.showExpandIcon)
                      GestureDetector(
                        onTap: () {
                          if (widget.onExpandChange != null) {
                            widget.onExpandChange!.call(!isExpanded);
                          } else {
                            setState(() => _expanded = !isExpanded);
                          }
                        },
                        child: Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 24,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
                if (!isWaitingState) const SizedBox(height: 12),
                
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final textPainter = TextPainter(
                          text: TextSpan(
                            text: widget.category,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          maxLines: 1,
                          textDirection: ui.TextDirection.ltr,
                        );
                        textPainter.layout(maxWidth: constraints.maxWidth);
                        final isMultiline = textPainter.didExceedMaxLines;
                        
                        return Text(
                          widget.category,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isMultiline ? 14 : 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    if (priceEstimated != null)
                      Text(
                        'R\$ ${priceEstimated.toStringAsFixed(2)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                  ],
                ),
                
                if (hasProvider)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Builder(
                      builder: (context) {
                        return InkWell(
                          onTap: () {
                            final pIdRaw = _currentDetails['provider_id'];
                            if (pIdRaw != null) {
                              final pId = int.tryParse(pIdRaw.toString());
                              if (pId != null) {
                                context.push('/provider-profile', extra: pId);
                              }
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: Colors.grey,
                                backgroundImage: _providerAvatarBytes != null
                                    ? MemoryImage(_providerAvatarBytes!)
                                    : (_providerAvatarUrl != null
                                        ? CachedNetworkImageProvider(_providerAvatarUrl!)
                                        : null) as ImageProvider?,
                                child: (_providerAvatarBytes == null && _providerAvatarUrl == null)
                                    ? const Icon(Icons.person, size: 16, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _currentDetails['provider_name'] ?? widget.providerName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_currentDetails['provider_rating'] != null) ...[
                                 const SizedBox(width: 4),
                                 Row(
                                  children: [
                                    const Icon(Icons.star, size: 12, color: Colors.amber),
                                    const SizedBox(width: 2),
                                    Text(
                                      (double.tryParse(_currentDetails['provider_rating'].toString()) ?? 0.0).toStringAsFixed(1),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                                    ),
                                    Text(
                                      ' (${_currentDetails['provider_reviews'] ?? 0})',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ],
                              if (_currentDetails['provider_id'] != null) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
                              ],
                            ],
                          ),
                        );
                      }
                    ),
                  ),

                if (!widget.showExpandIcon && !isExpanded) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        dateText.isNotEmpty ? dateText.split(' ')[0] : '--/--/--',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                      const Spacer(),
                      Text(
                        priceEstimated != null ? 'R\$ ${priceEstimated.toStringAsFixed(2)}' : 'R\$ --',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryPurple),
                      ),
                    ],
                  ),
                ],

                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 250),
                  crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: const SizedBox(height: 0),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text(
                        desc,
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                       Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.attach_money, size: 18, color: AppTheme.primaryPurple),
                              const SizedBox(width: 6),
                              Text(
                                priceEstimated != null ? 'Estimado: R\$ ${priceEstimated.toStringAsFixed(2)}' : 'Estimado: --',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ],
                          ),
                          Text(
                            priceUpfront != null ? 'Entrada: R\$ ${priceUpfront.toStringAsFixed(2)}' : 'Entrada: --',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule, size: 18, color: AppTheme.primaryPurple),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              dateText.isNotEmpty ? dateText : '--',
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (createdDt != null) ...[
                            const SizedBox(width: 8),
                            _ServiceTimer(startTime: createdDt),
                          ],
                        ],
                      ),
                      
                      if (widget.onCancel != null &&
                          ['pending', 'open', 'searching', 'waiting_payment', 'accepted', 'open_for_schedule'].contains(_currentStatus) &&
                          detail['arrived_at'] == null) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        Center(
                          child: TextButton.icon(
                            onPressed: widget.onCancel,
                            icon: Icon(LucideIcons.xCircle, size: 16, color: Colors.red[300]),
                            label: Text(
                              'Cancelar solicitação',
                              style: TextStyle(fontSize: 12, color: Colors.red[300]),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 4),
                _buildActionButtons(detail, getStatusText()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, Color bg, Color text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: bg != Colors.transparent && bg != Colors.white ? [
          BoxShadow(
            color: bg.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ] : null,
      ),
      child: Text(
        label.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: text,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> detail, String statusText) {
    final api = ApiService();

    if (api.role == 'provider') {
      if (['pending', 'accepted'].contains(_currentStatus) && detail['scheduled_at'] == null) {
          return Column(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                   setState(() {
                      _isSchedulingCounter = true;
                      _expanded = true;
                   });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(LucideIcons.calendar, size: 18),
                label: const Text('PROPOR AGENDAMENTO', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (_isSchedulingCounter)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: _buildSchedulingForm(detail),
                ),
              const SizedBox(height: 12),
              if (_currentStatus == 'pending')
                 _buildStandardButton('ACEITAR SOLICITAÇÃO', Colors.green, () => _handleStatusChange('accepted')),
            ],
          );
      }

      if (_currentStatus == 'in_progress') {
        return ElevatedButton(
          onPressed: () {
            final serviceId = (widget.details?['id'] ?? _currentDetails['id'])?.toString();
            if (serviceId != null) {
              context.push('/provider-service-details/$serviceId');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('CONCLUIR SERVIÇO', style: TextStyle(fontWeight: FontWeight.bold)),
        );
      }
      
      if (_currentStatus == 'accepted' || _currentStatus == 'scheduled') {
        return ElevatedButton(
          onPressed: () {
            final serviceId = (widget.details?['id'] ?? _currentDetails['id'])?.toString();
            if (serviceId != null) {
              context.push('/provider-service-details/$serviceId');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _currentStatus == 'scheduled' ? Colors.cyan.shade600 : AppTheme.primaryPurple,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            _currentStatus == 'scheduled' ? 'VER AGENDAMENTO' : 'VER DETALHES',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      }
    }

    if (_currentStatus == 'open_for_schedule') {
      return _buildStatusChip('Aguardando contato prestadores', Colors.blue.shade600, Colors.white);
    }

    if (_currentStatus == 'waiting_payment') {
      if (api.role == 'provider') {
        return _buildStatusChip('Aguardando Pagamento da Entrada',
            Colors.grey.shade300, Colors.black54);
      } else {
        final double priceUpfront = _toDouble(detail['price_upfront']) ?? 0;
        return ElevatedButton(
          onPressed: widget.onPay,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 48),
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            'AGUARDANDO PAGAMENTO DA ENTRADA: R\$ ${priceUpfront.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
        );
      }
    }
    
    if (_currentStatus == 'scheduled') {
      final scheduledAt = _toDate(detail['scheduled_at']);
      final scheduledText = scheduledAt != null 
          ? _formatFriendlyDate(scheduledAt)
          : 'Data a confirmar';
      
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[600],
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            const Text(
              'AGENDADO PARA:',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              scheduledText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }
    
    if (_currentStatus == 'waiting_payment_remaining' ||
        statusText == 'Pagar Restante') {
      if (api.role == 'provider') {
        return _buildStatusChip('Aguardando Pagamento Seguro',
            Colors.grey.shade300, Colors.black54);
      } else {
        final double price = _toDouble(detail['price_estimated']) ?? 0;
        final remaining = price * 0.7;

        return Column(
          children: [
            ElevatedButton(
              onPressed: widget.onPay,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Pagar Restante: R\$ ${remaining.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'O valor ficará retido e será liberado após a conclusão.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        );
      }
    }


    if (_currentStatus == 'waiting_client_confirmation') {
      if (api.role == 'provider') {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.blue[600],
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              const Icon(LucideIcons.clock, color: Colors.white, size: 28),
              const SizedBox(height: 12),
              const Text(
                'Aguardando Confirmação do Cliente',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'O serviço será concluído automaticamente em 24h caso o cliente não confirme.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.9)),
              ),
            ],
          ),
        );
      } else {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Serviço Finalizado.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              const SizedBox(height: 12),
              if (_currentDetails['completion_code'] != null || _currentDetails['validation_code'] != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.shieldCheck, size: 14, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        'CÓDIGO: ${_currentDetails['completion_code'] ?? _currentDetails['validation_code']}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              ElevatedButton(
                onPressed: () => _confirmServiceCompletion(_currentDetails['id'].toString()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('CONFIRME A CONCLUSÃO!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(height: 12),
              const Text(
                'Após confirmação, o valor será repassado ao prestador.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        );
      }
    }

    if (_currentStatus == 'waiting_client_confirmation' || 
        (_currentStatus == 'in_progress' && api.role != 'provider')) {
      if (api.role == 'provider') {
        return _buildStatusChip('Aguardando Validação do Cliente',
            Colors.orange.shade100, Colors.orange.shade900);
      } else {
        final validationCode = _currentDetails['validation_code'];
        final completionCode = _currentDetails['completion_code'];
        final code = completionCode ?? validationCode;

        if (code == null) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[600],
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.shieldCheck, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Text('Código de Validação', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                code.toString(),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Informe este código ao prestador ao final do serviço',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        );
      }
    }

    final bool isSearching = ['Buscando prestador', 'Aguardando prestador'].contains(statusText);
    
    if (isSearching) {
      final String dynamicMsg = _getDynamicSearchMessage();
      final Color statusColor = Colors.blue[600]!;
      
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: statusColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dynamicMsg,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Aguarde enquanto conectamos você.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: _searchCountdown / 20,
                    strokeWidth: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                Text(
                  '${_searchCountdown}s',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_currentStatus == 'completed') {
      if (api.role == 'provider') {
        return _buildStatusChip('Serviço Concluído', Colors.blue.shade50, Colors.blue.shade900);
      } else {
        return _buildReviewSection(detail);
      }
    }

    if (_currentStatus == 'schedule_proposed' || statusText == 'Proposta de Agendamento') {
      final scheduledAt = detail['scheduled_at'];
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryPurple.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                const Text('Proposta de Horário:', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  (scheduledAt != null) 
                    ? _formatFriendlyDate(_toDate(scheduledAt) ?? DateTime.now()) 
                    : 'A definir',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryPurple),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              final api = ApiService();
              final id = detail['id']?.toString();
              if (id != null) {
                try {
                  if (scheduledAt != null) {
                    await api.confirmSchedule(id, _toDate(scheduledAt) ?? DateTime.now());
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data de agendamento não encontrada.')));
                  }
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agendamento confirmado!')));
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('CONFIRMAR AGENDAMENTO', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          if (!_isSchedulingCounter)
            OutlinedButton(
              onPressed: () => setState(() => _isSchedulingCounter = true),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                side: BorderSide(color: Colors.grey.shade400),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('SUGERIR OUTRO HORÁRIO', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
            )
          else
            _buildSchedulingForm(detail),
        ],
      );
    }

    if (_currentStatus == 'open_for_schedule' || statusText == 'Disponível para Agendamento') {
       return _buildStatusChip('Aguardando Proposta de Prestador', Colors.blue[600]!, Colors.white);
    }

    if (_currentStatus == 'scheduled' || statusText == 'Serviço Agendado') {
       final scheduledAt = detail['scheduled_at'];
       return Container(
         width: double.infinity,
         padding: const EdgeInsets.all(12),
         decoration: BoxDecoration(
           color: Colors.blue.shade50,
           borderRadius: BorderRadius.circular(12),
           border: Border.all(color: Colors.blue.shade200),
         ),
         child: Column(
           children: [
             Row(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 Icon(LucideIcons.calendarCheck, size: 16, color: Colors.blue[600]),
                 const SizedBox(width: 8),
                 Text('AGENDADO PARA:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[600])),
               ],
             ),
             const SizedBox(height: 4),
             Text(
               (scheduledAt != null) 
                 ? _formatFriendlyDate(_toDate(scheduledAt) ?? DateTime.now()) 
                 : '--/--/--', 
               style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
             ),
           ],
         ),
        );
    }

    return Center(
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            widget.onTrack?.call();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[600],
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            statusText.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewSection(Map<String, dynamic> detail) {
    if (_reviewSubmittedSuccessfully) {
       return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Column(
          children: [
            Icon(Icons.check_circle, color: Colors.blue[600], size: 48),
            const SizedBox(height: 12),
            Text('Avaliação enviada!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue[600])),
            const SizedBox(height: 4),
            Text('Obrigado por ajudar a comunidade.', style: TextStyle(fontSize: 13, color: Colors.blue.shade800)),
          ],
        ),
      );
    }

    final reviews = detail['reviews'] as List?;
    final existingReview = (reviews != null && reviews.isNotEmpty) ? reviews.first : null;

    if (existingReview != null) {
      final rating = int.tryParse(existingReview['rating']?.toString() ?? '0') ?? 0;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Sua Avaliação:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 8),
                Row(
                  children: List.generate(5, (i) => Icon(
                    i < rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 16,
                  )),
                ),
              ],
            ),
            if (existingReview['comment'] != null && existingReview['comment'].toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(existingReview['comment'], style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AVALIE O PRESTADOR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.grey)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            return IconButton(
              icon: Icon(index < _rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 32),
              onPressed: () => setState(() => _rating = index + 1),
            );
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _commentController,
          decoration: AppTheme.inputDecoration('Comentário (opcional)', LucideIcons.messageSquare).copyWith(hintText: 'Como foi o serviço?'),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: (_rating == 0 || _submittingReview) ? null : _submitLocalReview,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryYellow,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _submittingReview 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('ENVIAR AVALIAÇÃO', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _submittingReview ? null : _archiveService,
            child: Text('Pular Avaliação', style: TextStyle(color: Colors.grey[600])),
          ),
        ),
      ],
    );
  }

  Future<void> _archiveService() async {
    final id = _currentDetails['id']?.toString();
    if (id == null) return;
    setState(() => _submittingReview = true);
    try {
      await ApiService().post('/services/$id/archive', {});
      if (mounted && widget.onRefreshNeeded != null) widget.onRefreshNeeded!();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _submittingReview = false);
    }
  }

  Future<void> _submitLocalReview() async {
    final id = _currentDetails['id']?.toString();
    if (id == null) return;
    setState(() => _submittingReview = true);
    try {
      await ApiService().submitReview(serviceId: id, rating: _rating, comment: _commentController.text);
      if (mounted) {
        setState(() {
          _reviewSubmittedSuccessfully = true;
          _submittingReview = false;
        });
        if (widget.onRefreshNeeded != null) widget.onRefreshNeeded!();
      }
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('409')) {
          setState(() { _reviewSubmittedSuccessfully = true; _submittingReview = false; });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Avaliação já enviada anteriormente!')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
        }
      }
    } finally {
      if (mounted) setState(() => _submittingReview = false);
    }
  }

  Future<void> _confirmServiceCompletion(String serviceId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Confirmar Conclusão?'),
        content: const Text('Ao confirmar, você concorda que o serviço foi realizado conforme o combinado e libera o pagamento ao prestador.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600], foregroundColor: Colors.white), child: const Text('CONFIRMAR')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final api = ApiService();
      await api.completeService(serviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Serviço confirmado com sucesso!'), backgroundColor: Colors.green));
        context.push('/review/$serviceId');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> resolveProviderAvatar() async {
    try {
      final d = _currentDetails;
      final raw = d['provider_avatar'] ?? d['provider_avatar_url'] ?? d['providerPhoto'] ?? d['provider_photo'] ?? d['providers']?['users']?['avatar_url'];
      final key = d['provider_avatar_key'] ?? d['providerAvatarKey'] ?? d['provider_avatarKey'];
      String? url;
      Uint8List? bytes;
      final api = ApiService();
      if (raw is String && raw.startsWith('http')) { url = raw; }
      else if (raw is String && raw.isNotEmpty) { bytes = await api.getMediaBytes(raw); }
      else if (key is String && key.isNotEmpty) { bytes = await api.getMediaBytes(key); }
      setState(() { _providerAvatarUrl = url; _providerAvatarBytes = bytes; });
    } catch (_) {}
  }

  Widget _buildSchedulingForm(Map<String, dynamic> detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(),
        const Text('Selecione o novo dia:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
        const SizedBox(height: 12),
        SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 7,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final date = DateTime.now().add(Duration(days: index));
              final isSelected = _selectedDate.day == date.day && _selectedDate.month == date.month;
              final dayName = index == 0 ? 'Hoje' : index == 1 ? 'Amanhã' : _getDayName(date);
              return InkWell(
                onTap: () => setState(() => _selectedDate = date),
                child: Container(
                  width: 60,
                  decoration: BoxDecoration(color: isSelected ? AppTheme.primaryPurple : Colors.grey[100], borderRadius: BorderRadius.circular(10), border: Border.all(color: isSelected ? AppTheme.primaryPurple : Colors.grey[300]!)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(dayName, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : Colors.grey[600])),
                    Text('${date.day}/${date.month}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
            InkWell(onTap: _showTimePickerModal, child: _buildTimeDisplay(_selectedTime.hour.toString().padLeft(2, '0'))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            InkWell(onTap: _showTimePickerModal, child: _buildTimeDisplay(_selectedTime.minute.toString().padLeft(2, '0'))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
            Expanded(child: TextButton(onPressed: () => setState(() => _isSchedulingCounter = false), child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)))),
            Expanded(flex: 2, child: ElevatedButton(
                onPressed: () async {
                  final newDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime.hour, _selectedTime.minute);
                  try {
                    final id = detail['id']?.toString();
                    if (id != null) {
                      await ApiService().proposeSchedule(id, newDate);
                      await DataGateway().sendChatMessage(id, 'Não posso no horário proposto. Podemos fazer em: ${DateFormat("dd/MM 'às' HH:mm").format(newDate)}?', 'text');
                      if (!mounted) return;
                      setState(() => _isSchedulingCounter = false);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sugestão enviada com sucesso!')));
                    }
                  } catch (e) { 
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'))); 
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('ENVIAR SUGESTÃO', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
        ]),
      ],
    );
  }

  Widget _buildTimeDisplay(String value) {
    return Container(width: 50, padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)), child: Text(value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)));
  }

  void _showTimePickerModal() {
    showDialog(context: context, builder: (context) {
        TimeOfDay tempTime = _selectedTime;
        return Center(child: Container(margin: const EdgeInsets.all(24), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black, width: 2)), child: Material(color: Colors.transparent, child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Selecione o Horário', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(height: 200, child: CupertinoDatePicker(mode: CupertinoDatePickerMode.time, initialDateTime: DateTime(2024,1,1,_selectedTime.hour, _selectedTime.minute), use24hFormat: true, onDateTimeChanged: (DateTime newDate) { tempTime = TimeOfDay(hour: newDate.hour, minute: newDate.minute); })),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { setState(() => _selectedTime = tempTime); Navigator.pop(context); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)))),
        ]))));
    });
  }

  String _getDayName(DateTime date) {
    const days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    return days[date.weekday - 1];
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (widget.onExpandChange != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onExpandChange!.call(widget.expanded ?? _expanded);
      });
    }
  }
}

class _ServiceTimer extends StatefulWidget {
  final DateTime startTime;
  const _ServiceTimer({required this.startTime});
  @override
  State<_ServiceTimer> createState() => _ServiceTimerState();
}

class _ServiceTimerState extends State<_ServiceTimer> {
  late Timer timer;
  Duration elapsed = Duration.zero;
  @override
  void initState() {
    super.initState();
    updateTime();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => updateTime());
  }
  void updateTime() {
    if (!mounted) return;
    setState(() { elapsed = DateTime.now().difference(widget.startTime); if (elapsed.isNegative) elapsed = Duration.zero; });
  }
  @override
  void dispose() { timer.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)), child: Text('${twoDigits(elapsed.inHours)}:${twoDigits(elapsed.inMinutes.remainder(60))}:${twoDigits(elapsed.inSeconds.remainder(60))}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown[900])));
  }
}
