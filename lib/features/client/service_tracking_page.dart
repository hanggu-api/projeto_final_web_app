import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/constants/trip_statuses.dart';
import '../../core/tracking/backend_tracking_api.dart';
import '../../core/tracking/backend_tracking_snapshot_state.dart';
import '../../core/maps/app_tile_layer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/payment_audit_logger.dart';
import '../../core/utils/service_flow_classifier.dart';
import 'models/tracking_stage.dart';
import '../../services/api_service.dart';
import '../../services/data_gateway.dart';
import '../../services/central_service.dart';
import '../../services/client_tracking_service.dart';
import '../../services/realtime_service.dart';
import '../../services/service_tracking_bus.dart';
import '../shared/simple_video_player.dart';
import 'refund_request_screen.dart';
import 'widgets/dispatch_tracking_timeline.dart';
import 'widgets/tracking_final_actions_section.dart';
import 'widgets/tracking_payment_pending_step.dart';
import 'widgets/tracking_provider_journey_card.dart';
import 'widgets/tracking_searching_provider_step.dart';
import 'widgets/tracking_stage_body.dart';

class ServiceTrackingPage extends StatefulWidget {
  final String serviceId;
  final ServiceDataScope scope;
  const ServiceTrackingPage({
    super.key,
    required this.serviceId,
    required this.scope,
  });

  @override
  State<ServiceTrackingPage> createState() => _ServiceTrackingPageState();
}

class _ServiceTrackingPageState extends State<ServiceTrackingPage>
    with WidgetsBindingObserver {
  static const Duration _foregroundRefreshInterval = Duration(seconds: 6);
  static const Duration _disputeRefreshInterval = Duration(seconds: 20);
  StreamSubscription? _sub;
  StreamSubscription? _providerLocSub;
  Map<String, dynamic>? _service;
  Map<String, dynamic>? _openDispute;
  Map<String, dynamic>? _latestPrimaryDispute;
  String? _status;
  bool _loading = true;
  final MapController _mapController = MapController();
  LatLng? _providerLatLng;
  final List<LatLng> _providerTrail = [];
  int? _watchingProviderId;
  String? _watchingProviderUid;
  bool _nearNotified = false;
  Timer? _refreshTimer;
  Timer? _mapKickTimer;
  bool _isRefreshing = false;
  bool _redirectScheduledAfterCompletion = false;
  String? _dispatchHeadlineOverride;
  String? _dispatchSubtitleOverride;
  final BackendTrackingApi _backendTrackingApi = const BackendTrackingApi();
  BackendTrackingSnapshotState? _latestBackendTrackingSnapshot;

  // PIX deposit inline
  bool _isLoadingPix = false;
  String? _pixPayload;
  String? _pixQrBase64;
  Uint8List? _pixQrBytes;
  String? _pixQrDataUrl;
  Timer? _pixPollTimer;
  Timer? _pixAutoRetryTimer;
  bool _pixPaid = false;
  bool _depositPixAutoLoadAttempted = false;
  bool _remainingPixAutoLoadAttempted = false;
  int _pixAutoRetryAttempt = 0;
  DateTime? _lastPixErrorSnackAt;
  String? _lastPixErrorTraceId;
  String? _lastPixErrorMessage;
  bool _realtimeDegraded = false;
  bool _isForeground = true;
  DateTime? _lastDisputeRefreshAt;
  int _initialNotFoundRetries = 0;
  bool _isConfirmingService = false;
  bool _scheduleProposalModalOpen = false;
  bool _isSubmittingScheduleNegotiation = false;
  bool _isSchedulingCounterProposal = false;
  late DateTime _selectedScheduleDate;
  late TimeOfDay _selectedScheduleTime;
  Timer? _realtimeRetryTimer;
  int _realtimeRetryAttempt = 0;
  int _consecutiveNotFoundSignals = 0;

  String _servicePaymentMethodRaw(Map<String, dynamic>? service) {
    if (service == null) return '';
    return (service['payment_method_id'] ??
            service['payment_method'] ??
            service['manual_payment_method_id'] ??
            service['preferred_payment_method'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
  }

  bool _isDirectProviderPaymentMethod(Map<String, dynamic>? service) {
    final method = _servicePaymentMethodRaw(service);
    if (method.isEmpty) return false;
    return method == 'pix_direct' ||
        method == 'pix direto' ||
        method == 'cash' ||
        method == 'dinheiro' ||
        method == 'dinheiro/direto' ||
        method.startsWith('card_machine');
  }

  String _scopeParam() {
    switch (widget.scope) {
      case ServiceDataScope.fixedOnly:
        return 'fixed';
      case ServiceDataScope.mobileOnly:
        return 'mobile';
      case ServiceDataScope.tripOnly:
        return 'trip';
      case ServiceDataScope.auto:
        return 'auto';
    }
  }

  ServiceDataScope _scopeValue() {
    return widget.scope;
  }

  bool _supportsInlinePlatformPix(Map<String, dynamic>? service) {
    final method = _servicePaymentMethodRaw(service);
    if (method.isEmpty) return true;
    return !_isDirectProviderPaymentMethod(service);
  }

  Widget _buildDirectPaymentInfoCard({
    required bool isRemainingPayment,
    required double amount,
  }) {
    final amountLabel = amount > 0
        ? 'R\$ ${amount.toStringAsFixed(2).replaceAll('.', ',')}'
        : 'valor combinado';
    final title = isRemainingPayment
        ? 'Pagamento restante direto ao prestador'
        : 'Pagamento direto ao prestador';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.28), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.wallet, color: Colors.black, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pagamento fora do QR do app',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$title em $amountLabel.',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Quando o método escolhido for chave simples, Pix direto ou pagamento presencial, o app não tenta gerar código PIX da plataforma.',
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
          ),
        ],
      ),
    );
  }

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

  bool get _isUnderDisputeAnalysis {
    final status = (_status ?? '').toLowerCase().trim();
    return status == 'contested' ||
        _openDispute != null ||
        _hasResolvedDisputeFeedback;
  }

  bool get _hasResolvedDisputeFeedback {
    final acknowledgedAt =
        (_latestPrimaryDispute?['client_acknowledged_at'] ?? '')
            .toString()
            .trim();
    if (acknowledgedAt.isNotEmpty) return false;
    final decision = (_latestPrimaryDispute?['platform_decision'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final disputeStatus = (_latestPrimaryDispute?['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return decision == 'rejected' ||
        decision == 'accepted' ||
        disputeStatus == 'dismissed' ||
        disputeStatus == 'resolved';
  }

  bool get _isDisputeRejected {
    final decision = (_latestPrimaryDispute?['platform_decision'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final disputeStatus = (_latestPrimaryDispute?['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return decision == 'rejected' || disputeStatus == 'dismissed';
  }

  bool get _isDisputeAccepted {
    final decision = (_latestPrimaryDispute?['platform_decision'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final disputeStatus = (_latestPrimaryDispute?['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return decision == 'accepted' || disputeStatus == 'resolved';
  }

  String get _pixPayloadForQr =>
      (_pixPayload ?? '').replaceAll(RegExp(r'\s+'), '');

  String _extractPixPayload(Map pix) {
    return (pix['copy_and_paste'] ??
            pix['payload'] ??
            pix['pix_payload'] ??
            pix['pix_code'] ??
            pix['code'] ??
            '')
        .toString()
        .trim();
  }

  String _extractPixQr(Map pix) {
    return (pix['encodedImage'] ??
            pix['image_url'] ??
            pix['qr_code_base64'] ??
            pix['qr_code'] ??
            pix['qrcode_base64'] ??
            pix['qr'] ??
            '')
        .toString()
        .trim();
  }

  DateTime? _parseScheduleDateTime(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  DateTime _normalizedScheduleDateTimeForSubmit(DateTime candidate) {
    final now = DateTime.now();
    final minimum = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    if (candidate.isBefore(minimum)) {
      return minimum;
    }
    return candidate;
  }

  String _formatScheduleDateTime(DateTime? value) {
    if (value == null) return 'Horário a definir';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month às $hour:$minute';
  }

  bool _isClientScheduleProposal(Map<String, dynamic> service) {
    final proposedBy =
        '${service['schedule_proposed_by_user_id'] ?? service['schedule_proposed_by'] ?? ''}'
            .trim();
    final currentUserId = (ApiService().userId ?? '').trim();
    if (proposedBy.isNotEmpty && currentUserId.isNotEmpty) {
      return proposedBy == currentUserId;
    }
    final clientId = '${service['client_id'] ?? ''}'.trim();
    return proposedBy.isNotEmpty &&
        clientId.isNotEmpty &&
        proposedBy == clientId;
  }

  DateTime _minimumScheduleDateTime() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour, now.minute);
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _composeSelectedScheduleDateTime({DateTime? date, TimeOfDay? time}) {
    final selectedDate = date ?? _selectedScheduleDate;
    final selectedTime = time ?? _selectedScheduleTime;
    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
  }

  void _syncScheduleSelectionWithMinimum() {
    final minimum = _minimumScheduleDateTime();
    final minimumDay = DateTime(minimum.year, minimum.month, minimum.day);

    if (_selectedScheduleDate.isBefore(minimumDay)) {
      _selectedScheduleDate = minimumDay;
      _selectedScheduleTime = TimeOfDay.fromDateTime(minimum);
      return;
    }

    final selectedDateTime = _composeSelectedScheduleDateTime();
    if (_isSameCalendarDay(_selectedScheduleDate, minimumDay) &&
        selectedDateTime.isBefore(minimum)) {
      _selectedScheduleTime = TimeOfDay.fromDateTime(minimum);
    }
  }

  void _startCounterProposalScheduling([Map<String, dynamic>? service]) {
    final currentProposal = _parseScheduleDateTime(
      service?['scheduled_at'] ?? _service?['scheduled_at'],
    );
    final minimum = _minimumScheduleDateTime();
    final initialDateTime =
        currentProposal != null && currentProposal.isAfter(minimum)
        ? currentProposal
        : minimum;

    setState(() {
      _isSchedulingCounterProposal = true;
      _selectedScheduleDate = DateTime(
        initialDateTime.year,
        initialDateTime.month,
        initialDateTime.day,
      );
      _selectedScheduleTime = TimeOfDay.fromDateTime(initialDateTime);
      _syncScheduleSelectionWithMinimum();
    });
  }

  void _applyCurrentScheduleNow() {
    final minimum = _minimumScheduleDateTime();
    setState(() {
      _selectedScheduleDate = DateTime(
        minimum.year,
        minimum.month,
        minimum.day,
      );
      _selectedScheduleTime = TimeOfDay.fromDateTime(minimum);
    });
  }

  void _showCounterProposalTimePickerModal() {
    showDialog(
      context: context,
      builder: (context) {
        final minimum = _minimumScheduleDateTime();
        final selectedDateTime = _composeSelectedScheduleDateTime();
        final selectedIsToday = _isSameCalendarDay(
          _selectedScheduleDate,
          minimum,
        );
        final initialDateTime =
            selectedIsToday && selectedDateTime.isBefore(minimum)
            ? minimum
            : selectedDateTime;
        TimeOfDay tempTime = TimeOfDay.fromDateTime(initialDateTime);
        return Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Selecione o Horário',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      initialDateTime: DateTime(
                        2024,
                        1,
                        1,
                        initialDateTime.hour,
                        initialDateTime.minute,
                      ),
                      minimumDate: selectedIsToday
                          ? DateTime(2024, 1, 1, minimum.hour, minimum.minute)
                          : null,
                      use24hFormat: true,
                      onDateTimeChanged: (DateTime newDate) {
                        tempTime = TimeOfDay(
                          hour: newDate.hour,
                          minute: newDate.minute,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _selectedScheduleTime = tempTime;
                          _syncScheduleSelectionWithMinimum();
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCounterProposalTimeDisplay(String value) {
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _getScheduleDayName(DateTime date) {
    const days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];
    return days[date.weekday - 1];
  }

  Future<void> _acceptScheduleProposal(Map<String, dynamic> service) async {
    if (_isSubmittingScheduleNegotiation) return;
    final scheduledAt = _parseScheduleDateTime(service['scheduled_at']);
    if (scheduledAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horário proposto não encontrado.')),
      );
      return;
    }

    setState(() => _isSubmittingScheduleNegotiation = true);
    try {
      final ok = await _backendTrackingApi.confirmSchedule(
        widget.serviceId,
        scheduledAt: scheduledAt,
      );
      if (!ok) {
        throw Exception('Confirmação de agenda não aceita pelo backend.');
      }
      if (!mounted) return;
      if (_scheduleProposalModalOpen) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Agendamento confirmado!')));
      await _refreshNow();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao confirmar: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSubmittingScheduleNegotiation = false);
      }
    }
  }

  Future<void> _counterProposeSchedule(Map<String, dynamic> service) async {
    if (_isSubmittingScheduleNegotiation) return;
    final selectedDateTime = _composeSelectedScheduleDateTime();
    final normalizedSelectedDateTime = _normalizedScheduleDateTimeForSubmit(
      selectedDateTime,
    );

    setState(() => _isSubmittingScheduleNegotiation = true);
    try {
      final ok = await _backendTrackingApi.proposeSchedule(
        widget.serviceId,
        scheduledAt: normalizedSelectedDateTime,
      );
      if (!ok) {
        throw Exception('Contraproposta de agenda não aceita pelo backend.');
      }
      if (!mounted) return;
      if (_scheduleProposalModalOpen) {
        Navigator.of(context).pop();
      }
      setState(() => _isSchedulingCounterProposal = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nova proposta enviada ao prestador!')),
      );
      await _refreshNow();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao sugerir horário: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSubmittingScheduleNegotiation = false);
      }
    }
  }

  Widget _buildScheduleProposalCard(Map<String, dynamic> service) {
    final scheduledAt = _parseScheduleDateTime(service['scheduled_at']);
    final expiresAt = _parseScheduleDateTime(service['schedule_expires_at']);
    final isClientProposal = _isClientScheduleProposal(service);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isClientProposal
                    ? 'Sua contraproposta foi enviada'
                    : 'Proposta de agendamento recebida',
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatScheduleDateTime(scheduledAt),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              if (expiresAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Validade até ${_formatScheduleDateTime(expiresAt)}',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                isClientProposal
                    ? 'Estamos aguardando a resposta do prestador para o horário sugerido.'
                    : 'Você pode aceitar este horário ou responder com outra data.',
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!isClientProposal) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmittingScheduleNegotiation
                  ? null
                  : () => _acceptScheduleProposal(service),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _isSubmittingScheduleNegotiation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'ACEITAR AGENDAMENTO',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (!isClientProposal)
          SizedBox(
            width: double.infinity,
            child: !_isSchedulingCounterProposal
                ? OutlinedButton(
                    onPressed: _isSubmittingScheduleNegotiation
                        ? null
                        : () => _startCounterProposalScheduling(service),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'SUGERIR OUTRO HORÁRIO',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  )
                : _buildCounterProposalScheduleForm(),
          ),
      ],
    );
  }

  Widget _buildCounterProposalScheduleForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Selecione o dia:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 7,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final now = DateTime.now();
              final date = DateTime(now.year, now.month, now.day + index);
              final isSelected =
                  _selectedScheduleDate.day == date.day &&
                  _selectedScheduleDate.month == date.month;
              final dayName = index == 0
                  ? 'Hoje'
                  : index == 1
                  ? 'Amanha'
                  : _getScheduleDayName(date);
              final dayNum =
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedScheduleDate = date;
                    _syncScheduleSelectionWithMinimum();
                  });
                },
                child: Container(
                  width: 70,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue[600] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? Colors.blue[700]! : Colors.grey[300]!,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        dayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected ? Colors.white : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dayNum,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Horario:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            InkWell(
              onTap: _showCounterProposalTimePickerModal,
              child: _buildCounterProposalTimeDisplay(
                _selectedScheduleTime.hour.toString().padLeft(2, '0'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                ':',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            InkWell(
              onTap: _showCounterProposalTimePickerModal,
              child: _buildCounterProposalTimeDisplay(
                _selectedScheduleTime.minute.toString().padLeft(2, '0'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _applyCurrentScheduleNow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue[700],
                  side: BorderSide(color: Colors.blue[200]!),
                  backgroundColor: Colors.blue[50],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Agora',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () =>
                    setState(() => _isSchedulingCounterProposal = false),
                child: const Text(
                  'CANCELAR',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isSubmittingScheduleNegotiation
                    ? null
                    : () => _counterProposeSchedule(_service ?? const {}),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSubmittingScheduleNegotiation
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'ENVIAR AO PRESTADOR',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _maybeShowScheduleProposalModal([Map<String, dynamic>? service]) {
    // O card de proposta agora fica inline no tracking.
    // Evitamos abrir um modal duplicado por cima dele.
    _scheduleProposalModalOpen = false;
  }

  String _extractProofVideoKey(Map<String, dynamic>? service) {
    if (service == null) return '';
    return (service['proof_video'] ??
            service['service_video'] ??
            service['completion_video'] ??
            service['video_proof'] ??
            service['finish_video'] ??
            '')
        .toString()
        .trim();
  }

  Future<void> _showConfirmServiceDialog() async {
    int rating = 0;
    final commentController = TextEditingController();
    final proofVideoKey = _extractProofVideoKey(_service);
    final Future<String>? proofVideoUrlFuture = proofVideoKey.isEmpty
        ? null
        : proofVideoKey.startsWith('http')
        ? Future.value(proofVideoKey)
        : ApiService().getMediaViewUrl(proofVideoKey);
    bool proofVideoReady = proofVideoKey.startsWith('http');
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          return AlertDialog(
            title: const Text('Confirmar Serviço'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Confira o vídeo enviado pelo prestador antes de liberar o pagamento.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (proofVideoKey.isNotEmpty)
                      FutureBuilder<String>(
                        future: proofVideoUrlFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return Container(
                              height: 210,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          if (!snapshot.hasData ||
                              snapshot.data!.trim().isEmpty) {
                            return _proofVideoUnavailableBox();
                          }
                          if (!proofVideoReady) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setLocalState(() => proofVideoReady = true);
                              }
                            });
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: SizedBox(
                              height: 230,
                              child: SimpleVideoPlayer(
                                videoUrl: snapshot.data!.trim(),
                              ),
                            ),
                          );
                        },
                      )
                    else
                      _proofVideoUnavailableBox(),
                    const SizedBox(height: 16),
                    const Text(
                      'Avaliação do serviço',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: commentController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText:
                            'Conte como foi o atendimento, o resultado e qualquer observação importante.',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: AppTheme.primaryBlue,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$rating de 5 estrelas',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starValue = index + 1;
                        return IconButton(
                          tooltip:
                              '$starValue estrela${starValue == 1 ? '' : 's'}',
                          onPressed: () => setLocalState(() {
                            rating = rating == starValue ? 0 : starValue;
                          }),
                          icon: Icon(
                            index < rating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 34,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isConfirmingService
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: _isConfirmingService || !proofVideoReady
                    ? null
                    : () async {
                        Navigator.of(dialogContext).pop();
                        await _confirmServiceDirectly(
                          rating,
                          comment: commentController.text.trim(),
                        );
                      },
                child: const Text('Enviar e Finalizar'),
              ),
            ],
          );
        },
      ),
    );
    commentController.dispose();
  }

  Widget _proofVideoUnavailableBox() {
    return Container(
      height: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF4C542)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off_outlined, color: Colors.black87, size: 34),
          SizedBox(height: 10),
          Text(
            'Vídeo do serviço ainda não encontrado.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          SizedBox(height: 6),
          Text(
            'A confirmação fica bloqueada até o vídeo enviado pelo prestador estar disponível.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmServiceDirectly(int rating, {String? comment}) async {
    if (_isConfirmingService) return;
    setState(() => _isConfirmingService = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await _backendTrackingApi.confirmFinalService(
        widget.serviceId,
        rating: rating,
        comment: comment,
      );
      if (!ok) throw Exception('Confirmação final rejeitada pelo backend.');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Serviço confirmado com sucesso!')),
      );
      await _refreshNow();
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao confirmar serviço: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isConfirmingService = false);
      }
    }
  }

  Future<void> _openComplaintFlow({
    String title = 'Abrir Reclamação',
    String claimType = 'complaint',
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.7,
        maxChildSize: 0.98,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(
                child: RefundRequestForm(
                  serviceId: widget.serviceId,
                  title: title,
                  claimType: claimType,
                  showAppBarHeader: true,
                  onSubmitted: () => Navigator.of(sheetContext).pop(true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == true && mounted) {
      await _refreshNow();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            claimType == 'refund_request'
                ? 'Solicitação de devolução registrada e enviada para análise.'
                : 'Reclamação registrada e enviada para análise.',
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    final minimumSchedule = _minimumScheduleDateTime();
    _selectedScheduleDate = DateTime(
      minimumSchedule.year,
      minimumSchedule.month,
      minimumSchedule.day,
    );
    _selectedScheduleTime = TimeOfDay.fromDateTime(minimumSchedule);
    WidgetsBinding.instance.addObserver(this);
    _loadOnce();
    _listenRealtime();
    ServiceTrackingBus().setActive(widget.serviceId, _refreshNow);
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _providerLocSub?.cancel();
    _pixPollTimer?.cancel();
    _pixAutoRetryTimer?.cancel();
    _refreshTimer?.cancel();
    _mapKickTimer?.cancel();
    _realtimeRetryTimer?.cancel();
    ServiceTrackingBus().clearActive(widget.serviceId);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    _isForeground = isForeground;
    if (isForeground) {
      _startPolling();
      _scheduleRealtimeResubscribe(immediate: true);
      unawaited(_refreshNow(forceDisputeRefresh: true));
      return;
    }
    _refreshTimer?.cancel();
    _realtimeRetryTimer?.cancel();
  }

  bool _isTransientRealtimeTrackingError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('realtimecloseevent(code: 1006') ||
        text.contains('realtimesubscribestatus.channelerror') ||
        text.contains('realtimesubscribestatus.timedout') ||
        text.contains('websocket') ||
        text.contains('socket');
  }

  void _scheduleRealtimeResubscribe({bool immediate = false, Object? error}) {
    if (!mounted || !_isForeground) return;
    _realtimeRetryTimer?.cancel();
    final seconds = immediate
        ? 0
        : (_realtimeRetryAttempt <= 0
              ? 1
              : (1 << _realtimeRetryAttempt).clamp(1, 12));
    if (!immediate) {
      _realtimeRetryAttempt = (_realtimeRetryAttempt + 1).clamp(0, 6);
    }
    _realtimeRetryTimer = Timer(Duration(seconds: seconds), () async {
      if (!mounted || !_isForeground) return;
      try {
        if (kIsWeb) {
          await RealtimeService().requestSocketReconnect();
        }
        _listenRealtime();
        await _refreshNow(forceDisputeRefresh: true);
      } catch (e) {
        debugPrint('⚠️ [ServiceTracking] falha ao religar realtime: $e');
        _scheduleRealtimeResubscribe(error: e);
      }
    });
    debugPrint(
      'ℹ️ [ServiceTracking] reagendando realtime em ${seconds}s${error == null ? '' : ' por $error'}',
    );
  }

  void _startPolling() {
    if (!_isForeground) return;
    _refreshTimer?.cancel();
    // Realtime continua sendo a fonte principal; polling fica como fallback.
    _refreshTimer = Timer.periodic(_foregroundRefreshInterval, (_) {
      _refreshNow();
    });
  }

  bool _isTerminalStatus(String status) {
    final s = normalizeServiceStatus(status);
    return s == 'finished' ||
        s == 'not_found' ||
        ServiceStatusSets.inactiveTerminal.contains(s);
  }

  bool _shouldPinTrackingRoute() {
    final status = ((_service?['status'] ?? _status ?? '') as String)
        .toLowerCase()
        .trim();
    // Mantém tela/URL de tracking fixas enquanto há serviço ativo,
    // incluindo pagamento pendente.
    return !{
      'completed',
      'finished',
      'cancelled',
      'canceled',
      'deleted',
    }.contains(status);
  }

  bool _shouldOpenProviderSearchPage({
    required String status,
    required bool entryPaid,
    required bool hasProvider,
  }) {
    if (!entryPaid || hasProvider) return false;
    return ServiceStatusSets.clientSearch.contains(
      normalizeServiceStatus(status),
    );
  }

  Future<void> _handleServiceNotFound() async {
    if (!mounted) return;
    if (_shouldPinTrackingRoute()) {
      await _refreshNow(forceDisputeRefresh: true);
      return;
    }
    _consecutiveNotFoundSignals++;
    if (_consecutiveNotFoundSignals < 3) {
      // Proteção contra falso "not_found" transitório (realtime/polling).
      await _refreshNow(forceDisputeRefresh: true);
      return;
    }

    _refreshTimer?.cancel();
    _pixPollTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Solicitação não encontrada. Retornando para a Home.'),
      ),
    );
    Future.microtask(() {
      if (!mounted) return;
      context.go('/home');
    });
  }

  void _handleOpenForScheduleFallback() {
    if (!mounted) return;
    if (_shouldPinTrackingRoute()) {
      return;
    }
    _refreshTimer?.cancel();
    _pixPollTimer?.cancel();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Nenhum prestador aceitou no ciclo inicial. O serviço voltou para a Home aguardando retorno de prestadores.',
        ),
      ),
    );
    Future.microtask(() {
      if (!mounted) return;
      context.go('/home');
    });
  }

  bool _shouldRefreshDisputeState({required bool force}) {
    if (force) return true;
    final lastRefresh = _lastDisputeRefreshAt;
    if (lastRefresh == null) return true;
    return DateTime.now().difference(lastRefresh) >= _disputeRefreshInterval;
  }

  Future<BackendTrackingSnapshotState?> _fetchTrackingSnapshot({
    bool force = false,
  }) async {
    try {
      return await _backendTrackingApi.fetchTrackingSnapshot(
        widget.serviceId,
        scope: widget.scope.name,
      );
    } catch (e) {
      if (force) {
        debugPrint('⚠️ [ServiceTracking] snapshot backend indisponível: $e');
      }
      return null;
    }
  }

  Future<void> _refreshNow({bool forceDisputeRefresh = false}) async {
    if (_isRefreshing) return;
    if (!mounted || !_isForeground) return;
    if (_isTerminalStatus((_status ?? '').toString())) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }

    _isRefreshing = true;
    try {
      final backendSnapshot = await _fetchTrackingSnapshot();
      final row =
          backendSnapshot?.service ??
          await ApiService().getServiceDetails(
            widget.serviceId,
            scope: widget.scope,
          );
      if (row['not_found'] == true ||
          normalizeServiceStatus((row['status'] ?? '').toString()) ==
              'not_found') {
        _handleServiceNotFound();
        return;
      }
      final normalized = _normalizeServiceRow(row);
      final normalizedStatus = normalizeServiceStatus(
        (normalized['status'] ?? '').toString(),
      );
      if (normalizedStatus == TripStatuses.openForSchedule) {
        _handleOpenForScheduleFallback();
        return;
      }
      Map<String, dynamic>? openDispute = _openDispute;
      Map<String, dynamic>? latestPrimaryDispute = _latestPrimaryDispute;
      if (_shouldRefreshDisputeState(force: forceDisputeRefresh)) {
        openDispute =
            backendSnapshot?.openDispute ??
            await ApiService().getOpenDisputeForService(widget.serviceId);
        latestPrimaryDispute =
            backendSnapshot?.latestPrimaryDispute ??
            await ApiService().getLatestPrimaryDisputeForService(
              widget.serviceId,
            );
        _lastDisputeRefreshAt = DateTime.now();
      }
      if (!mounted) return;
      setState(() {
        _latestBackendTrackingSnapshot =
            backendSnapshot ?? _latestBackendTrackingSnapshot;
        _service = {...?_service, ...normalized};
        _openDispute = openDispute;
        _latestPrimaryDispute = latestPrimaryDispute;
        _status = (normalized['status'] ?? _status ?? '').toString();
      });
      _applyBackendProviderLocationSnapshot(backendSnapshot?.providerLocation);
      _maybeShowScheduleProposalModal(normalized);

      final refreshedStatus = normalizeServiceStatus(_status ?? '');
      if (ServiceStatusSets.providerConcluding.contains(refreshedStatus)) {
        final autoConfirmed = await ApiService()
            .autoConfirmServiceAfterGraceIfEligible(
              widget.serviceId,
              graceMinutes: 720,
            );
        if (autoConfirmed) {
          final latest = await ApiService().getServiceDetails(
            widget.serviceId,
            scope: widget.scope,
          );
          if (!mounted) return;
          setState(() {
            _service = {...?_service, ...latest};
            _status = (latest['status'] ?? _status ?? '').toString();
          });
        }
      }

      final dynamic pidRaw =
          (normalized['provider_id'] ?? _service?['provider_id']);
      final int? providerId = pidRaw is int
          ? pidRaw
          : int.tryParse(pidRaw?.toString() ?? '');
      if (providerId != null && providerId > 0) {
        _startWatchingProviderLocation(providerId);
        if (_providerLatLng == null) {
          await _pollProviderLocationById(providerId);
        }
      }
      final providerUid =
          (normalized['provider_uid'] ?? _service?['provider_uid'] ?? '')
              .toString();
      if (providerUid.trim().isNotEmpty) {
        _startWatchingProviderLocationByUid(providerUid);
        if (_providerLatLng == null) {
          await _pollProviderLocationByUid(providerUid);
        }
      }

      if (_isTerminalStatus((_status ?? '').toString())) {
        _refreshTimer?.cancel();
        _refreshTimer = null;
      }
    } catch (_) {
      // ignore refresh failures
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _loadOnce() async {
    try {
      final backendSnapshot = await _fetchTrackingSnapshot(force: true);
      final details =
          backendSnapshot?.service ??
          await ApiService().getServiceDetails(
            widget.serviceId,
            scope: widget.scope,
            forceRefresh: true,
          );
      if (details['not_found'] == true ||
          (details['status'] ?? '').toString().toLowerCase().trim() ==
              'not_found') {
        // Evita falso "não encontrado" logo após criar o serviço (consistência eventual).
        if (_initialNotFoundRetries < 4) {
          _initialNotFoundRetries++;
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) _loadOnce();
          });
          return;
        }
        _handleServiceNotFound();
        return;
      }

      final normalized = _normalizeServiceRow(details);
      final normalizedStatus = (normalized['status'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      if (normalizedStatus == 'open_for_schedule') {
        _handleOpenForScheduleFallback();
        return;
      }
      final openDispute =
          backendSnapshot?.openDispute ??
          await ApiService().getOpenDisputeForService(widget.serviceId);
      final latestPrimaryDispute =
          backendSnapshot?.latestPrimaryDispute ??
          await ApiService().getLatestPrimaryDisputeForService(
            widget.serviceId,
          );
      _lastDisputeRefreshAt = DateTime.now();
      if (!mounted) return;
      setState(() {
        _latestBackendTrackingSnapshot = backendSnapshot;
        _service = normalized;
        _openDispute = openDispute;
        _latestPrimaryDispute = latestPrimaryDispute;
        _status = (normalized['status'] ?? '').toString();
        _loading = false;
      });
      _consecutiveNotFoundSignals = 0;
      unawaited(ClientTrackingService.syncTrackingForService(normalized));
      _applyBackendProviderLocationSnapshot(backendSnapshot?.providerLocation);
      _maybeShowScheduleProposalModal(normalized);

      // Start provider location tracking immediately (do not wait for polling/realtime).
      final dynamic pidRaw = (normalized['provider_id']);
      final int? providerId = pidRaw is int
          ? pidRaw
          : int.tryParse(pidRaw?.toString() ?? '');
      if (providerId != null && providerId > 0) {
        debugPrint(
          '📍 [ServiceTracking] start watchProviderLocation providerId=$providerId',
        );
        _startWatchingProviderLocation(providerId);
        await _pollProviderLocationById(providerId);
      }

      final providerUid = (normalized['provider_uid'] ?? '').toString().trim();
      if (providerUid.isNotEmpty) {
        debugPrint(
          '📍 [ServiceTracking] start watchProviderLocationByUid providerUid=$providerUid',
        );
        _startWatchingProviderLocationByUid(providerUid);
        await _pollProviderLocationByUid(providerUid);
      }

      // Pix de entrada é renderizado no card do tracking quando necessário.
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _listenRealtime() {
    _sub?.cancel();
    _sub = DataGateway()
        .watchService(widget.serviceId, scope: widget.scope)
        .listen(
          (data) {
            if (!mounted) return;
            if (data.isEmpty) return;
            if (data['not_found'] == true) {
              // Se realmente foi removido/cancelado no banco, retorna para Home.
              // Para evitar falso-positivo transitório, só executa quando já havia um serviço carregado.
              if (_service != null) _handleServiceNotFound();
              return;
            }
            final normalized = _normalizeServiceRow(data);
            final normalizedStatus = (normalized['status'] ?? '')
                .toString()
                .toLowerCase()
                .trim();
            if (normalizedStatus == 'open_for_schedule') {
              _handleOpenForScheduleFallback();
              return;
            }
            setState(() {
              _service = {...?_service, ...normalized};
              _status = (normalized['status'] ?? _status ?? '').toString();
              _realtimeDegraded = false;
            });
            _consecutiveNotFoundSignals = 0;
            unawaited(ClientTrackingService.syncTrackingForService(_service));
            _realtimeRetryAttempt = 0;
            _realtimeRetryTimer?.cancel();
            _maybeShowScheduleProposalModal(normalized);
            ApiService().getOpenDisputeForService(widget.serviceId).then((
              dispute,
            ) {
              if (!mounted) return;
              setState(() => _openDispute = dispute);
            });
            ApiService()
                .getLatestPrimaryDisputeForService(widget.serviceId)
                .then((dispute) {
                  if (!mounted) return;
                  setState(() => _latestPrimaryDispute = dispute);
                });

            final dynamic pidRaw = (_service?['provider_id']);
            final int? providerId = pidRaw is int
                ? pidRaw
                : int.tryParse(pidRaw?.toString() ?? '');
            if (providerId != null && providerId > 0) {
              _startWatchingProviderLocation(providerId);
            }
            final providerUid = (_service?['provider_uid'] ?? '').toString();
            if (providerUid.trim().isNotEmpty) {
              _startWatchingProviderLocationByUid(providerUid);
            }

            // Pix de entrada é renderizado no card do tracking quando necessário.
          },
          onError: (e) {
            if (!mounted) return;
            setState(() {
              _realtimeDegraded = true;
            });
            final transient = _isTransientRealtimeTrackingError(e);
            debugPrint(
              '${transient ? 'ℹ️' : '⚠️'} [ServiceTracking] watchService degraded: $e',
            );
            _scheduleRealtimeResubscribe(error: e);
          },
        );
  }

  Map<String, dynamic> _normalizeServiceRow(Map<String, dynamic> row) {
    final normalized = Map<String, dynamic>.from(row);
    final status = (normalized['status'] ?? '').toString().toLowerCase().trim();
    if (status.isEmpty &&
        widget.scope == ServiceDataScope.mobileOnly &&
        classifyServiceFlow(normalized) == ServiceFlowKind.mobile) {
      normalized['status'] = 'waiting_payment';
    }
    return normalized;
  }

  String _disputePrimaryMessage() {
    final disputeType =
        (_latestPrimaryDispute?['type'] ?? _openDispute?['type'] ?? '')
            .toString()
            .trim();
    if (_isDisputeRejected) {
      return 'Sua reclamação foi rejeitada pela plataforma.';
    }
    if (_isDisputeAccepted) {
      return 'Sua reclamação foi aceita pela plataforma e o caso já recebeu decisão.';
    }
    if (disputeType == 'refund_request') {
      return 'Sua solicitação de reembolso está em análise pela plataforma.';
    }
    return 'Você tem um serviço sob contestação e a análise ainda não foi concluída.';
  }

  String _disputeReasonLabel() {
    final reasonRaw =
        (_latestPrimaryDispute?['reason'] ?? _openDispute?['reason'] ?? '')
            .toString()
            .trim();
    if (reasonRaw.isEmpty) return '';
    return reasonRaw.replaceFirst(RegExp(r'^\[claim_type:[^\]]+\]\s*'), '');
  }

  Future<void> _showDisputeDetailsSheet() async {
    final createdAtRaw = (_latestPrimaryDispute?['created_at'] ?? '')
        .toString()
        .trim();
    final type =
        (_latestPrimaryDispute?['type'] ?? _openDispute?['type'] ?? 'complaint')
            .toString();
    final reasonLabel = _disputeReasonLabel();
    final createdAt = DateTime.tryParse(createdAtRaw);
    final createdLabel = createdAt == null
        ? ''
        : '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(sheetContext).viewPadding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Detalhes da contestação',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF4C542)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status: ${_isDisputeRejected
                        ? 'rejeitada pela plataforma'
                        : _isDisputeAccepted
                        ? 'aceita pela plataforma'
                        : 'em análise'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.black.withOpacity(0.82),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tipo: ${type == 'refund_request' ? 'Pedido de reembolso' : 'Reclamação'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black.withOpacity(0.75),
                    ),
                  ),
                  if (createdLabel.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Aberta em: $createdLabel',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withOpacity(0.75),
                      ),
                    ),
                  ],
                  if (reasonLabel.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      reasonLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Enquanto a contestação estiver ativa no fluxo do serviço, o app usa esse estado para orientar cobrança, reembolso e liberação do pagamento ao prestador.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text(
                  'ENTENDI',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisputeAnalysisCard() {
    final reasonLabel = _disputeReasonLabel();
    final isRejected = _isDisputeRejected;
    final isAccepted = _isDisputeAccepted;
    final title = isRejected
        ? 'Reclamação rejeitada'
        : isAccepted
        ? 'Decisão da plataforma'
        : 'Serviço em análise';
    final infoText = isRejected
        ? 'Sua reclamação foi rejeitada pela plataforma. Revise os detalhes e aceite a proposta da plataforma para encerrar este caso.'
        : isAccepted
        ? 'A plataforma já decidiu a seu favor e o caso foi encerrado no fluxo financeiro.'
        : reasonLabel.isEmpty
        ? 'Enquanto a análise não for resolvida, você não poderá contratar outro serviço no app.'
        : 'Motivo informado: $reasonLabel\n\nEnquanto a análise não for resolvida, você não poderá contratar outro serviço no app.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF4C542)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE082),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.policy_outlined, color: Colors.black87),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _disputePrimaryMessage(),
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withOpacity(0.25)),
            ),
            child: Text(
              infoText,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Colors.black.withOpacity(0.78),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showDisputeDetailsSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryYellow,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'CONSULTAR DETALHES',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                if (isRejected || isAccepted) {
                  ApiService()
                      .acceptPlatformDisputeDecision(widget.serviceId)
                      .then((_) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isRejected
                                  ? 'Caso encerrado com a decisão da plataforma.'
                                  : 'Decisão da plataforma reconhecida. Caso encerrado.',
                            ),
                          ),
                        );
                        context.go('/home');
                      })
                      .catchError((error) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Não foi possível encerrar o caso: $error',
                            ),
                          ),
                        );
                      });
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Ainda não há proposta da plataforma disponível para esta contestação.',
                    ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.black.withOpacity(0.18)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                isRejected || isAccepted
                    ? 'ACEITAR DECISÃO DA PLATAFORMA'
                    : 'ACEITAR PROPOSTA DA PLATAFORMA',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startWatchingProviderLocation(int providerId) {
    if (_watchingProviderId == providerId) return;
    _watchingProviderUid = null;
    _watchingProviderId = providerId;
    _providerLocSub?.cancel();
    _providerLocSub = DataGateway().watchProviderLocation(providerId).listen((
      row,
    ) {
      if (!mounted) return;
      if (row.isEmpty) return;
      _applyProviderLocationRow(row, debugContext: 'id=$providerId');
    }, onError: (_) {});
  }

  void _startWatchingProviderLocationByUid(String providerUid) {
    final uid = providerUid.trim();
    if (uid.isEmpty) return;
    if (_watchingProviderUid == uid) return;
    _watchingProviderUid = uid;
    _watchingProviderId = null;
    _providerLocSub?.cancel();
    _providerLocSub = DataGateway().watchProviderLocationByUid(uid).listen((
      row,
    ) {
      if (!mounted) return;
      if (row.isEmpty) return;
      _applyProviderLocationRow(row, debugContext: 'uid=$uid');
    }, onError: (_) {});
  }

  Future<void> _pollProviderLocationById(int providerId) async {
    try {
      final row = await DataGateway().fetchProviderLocation(
        providerId: providerId,
      );
      if (row != null) {
        _applyProviderLocationRow(row, debugContext: 'poll:id=$providerId');
      }
    } catch (_) {
      // best effort
    }
  }

  Future<void> _pollProviderLocationByUid(String providerUid) async {
    final uid = providerUid.trim();
    if (uid.isEmpty) return;
    try {
      final row = await DataGateway().fetchProviderLocation(providerUid: uid);
      if (row != null) {
        _applyProviderLocationRow(row, debugContext: 'poll:uid=$uid');
      }
    } catch (_) {
      // best effort
    }
  }

  void _applyBackendProviderLocationSnapshot(Map<String, dynamic>? row) {
    if (row == null || row.isEmpty) return;
    _applyProviderLocationRow(row, debugContext: 'backend-snapshot');
  }

  void _applyProviderLocationRow(
    Map<String, dynamic> row, {
    required String debugContext,
  }) {
    if (!mounted) return;
    final lat = (row['latitude'] as num?)?.toDouble();
    final lon = (row['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return;
    final p = LatLng(lat, lon);
    setState(() {
      _providerLatLng = p;
      if (_providerTrail.isEmpty ||
          (_providerTrail.last.latitude != p.latitude ||
              _providerTrail.last.longitude != p.longitude)) {
        _providerTrail.add(p);
        if (_providerTrail.length > 60) {
          _providerTrail.removeAt(0);
        }
      }
    });

    final sLat = (_service?['latitude'] as num?)?.toDouble();
    final sLon = (_service?['longitude'] as num?)?.toDouble();
    final currentStatus = (_status ?? '').toLowerCase().trim();
    if (sLat != null && sLon != null) {
      final distM = Geolocator.distanceBetween(
        sLat,
        sLon,
        p.latitude,
        p.longitude,
      );

      if (!_nearNotified &&
          distM <= 500 &&
          ['accepted', 'provider_near'].contains(currentStatus)) {
        _nearNotified = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prestador próximo (menos de 500m).')),
        );
        if (currentStatus == 'accepted') {
          unawaited(
            _backendTrackingApi.updateServiceStatus(
              widget.serviceId,
              status: 'provider_near',
              scope: _scopeParam(),
            ),
          );
        }
      }

      try {
        final bounds = LatLngBounds.fromPoints([LatLng(sLat, sLon), p]);
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(64)),
        );
      } catch (_) {}
    }

    debugPrint(
      '📡 [ServiceTracking] provider_locations update ($debugContext) '
      'lat=${p.latitude}, lon=${p.longitude}, updated_at=${row['updated_at']}',
    );
  }

  Future<void> _loadPixInline(
    String serviceId, {
    bool isRemainingPayment = false,
    bool manualRetry = false,
  }) async {
    if (_isLoadingPix) return;
    _pixAutoRetryTimer?.cancel();
    if (!isRemainingPayment) {
      _depositPixAutoLoadAttempted = true;
    } else {
      _remainingPixAutoLoadAttempted = true;
    }
    if (manualRetry) {
      _lastPixErrorTraceId = null;
      _lastPixErrorMessage = null;
      _pixAutoRetryAttempt = 0;
    }
    setState(() {
      _isLoadingPix = true;
      _pixPaid = false;
    });
    try {
      debugPrint(
        '[ServiceTracking][PIX] getPixData start serviceId=$serviceId',
      );
      final pixData = await CentralService()
          .getPixData(
            serviceId,
            entityType: 'service',
            paymentStage: isRemainingPayment ? 'remaining' : 'deposit',
          )
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw TimeoutException(
              'Tempo esgotado ao abrir o Pix. Verifique a conexão e tente novamente.',
            ),
          );
      final keys = pixData.keys.toList();
      final reasonCode = (pixData['reason_code'] ?? '').toString().trim();
      final traceIdFromMap = (pixData['trace_id'] ?? '').toString().trim();
      if (reasonCode == 'RESOURCE_NOT_FOUND') {
        PaymentAuditLogger.logServicePaymentEvent(
          serviceId: serviceId,
          event: 'pix_resource_scope_mismatch',
          traceId: traceIdFromMap.isNotEmpty ? traceIdFromMap : null,
          extra: {
            'scope': widget.scope.name,
            'entity_type': widget.scope == ServiceDataScope.fixedOnly
                ? 'service_fixed'
                : 'service_mobile',
            'route': '/service-tracking/$serviceId',
            'payment_type': isRemainingPayment ? 'remaining' : 'deposit',
            'reason_code': reasonCode,
            'source': 'service_tracking_page',
            'id_origin': widget.serviceId,
          },
        );
      }
      debugPrint(
        '[ServiceTracking][PIX] getPixData result type=${pixData.runtimeType} keys=$keys',
      );
      if (pixData['success'] == false ||
          (pixData['error']?.toString().trim().isNotEmpty ?? false)) {
        final errorMap = Map<String, dynamic>.from(pixData);
        throw ApiException(
          message: (errorMap['error'] ?? 'Falha ao gerar PIX').toString(),
          statusCode: int.tryParse('${errorMap['status_code'] ?? ''}') ?? 400,
          details: errorMap,
        );
      }
      final dynamic pix = (pixData['pix'] is Map) ? pixData['pix'] : pixData;
      if (pix is! Map) {
        throw Exception(pixData['error'] ?? 'Falha ao gerar PIX');
      }

      final payload = _extractPixPayload(pix);
      final qrBase64 = _extractPixQr(pix);

      String payloadPreview = payload;
      if (payloadPreview.length > 18) {
        payloadPreview =
            '${payloadPreview.substring(0, 10)}...${payloadPreview.substring(payloadPreview.length - 8)}';
      }
      debugPrint(
        '[ServiceTracking][PIX] parsed payloadLen=${payload.length} payloadPreview=$payloadPreview qrFieldLen=${qrBase64.length} qrIsUrl=${qrBase64.startsWith('http')}',
      );

      if (payload.isEmpty && qrBase64.isEmpty) {
        final maybeMap = Map<String, dynamic>.from(pixData);
        throw ApiException(
          message: (maybeMap['error'] ?? 'Falha ao gerar código PIX')
              .toString(),
          statusCode: int.tryParse('${maybeMap['status_code'] ?? ''}') ?? 400,
          details: maybeMap,
        );
      }

      if (!mounted) return;
      Uint8List? bytes;
      String? qrDataUrl;
      String qrRaw = qrBase64;
      // Some providers return `data:image/png;base64,...`
      if (qrRaw.startsWith('data:image')) {
        final idx = qrRaw.indexOf(',');
        if (idx >= 0) qrRaw = qrRaw.substring(idx + 1).trim();
      }
      // If it's a URL, we won't decode here (handled in UI).
      if (qrRaw.isNotEmpty && !qrRaw.startsWith('http')) {
        try {
          bytes = base64Decode(qrRaw);
        } catch (_) {
          bytes = null;
        }
      }

      // (debug) headerHex removed after QR fix

      // Detect SVG payload (some providers return SVG base64; Image.memory may render blank).
      if (bytes != null) {
        try {
          final asText = utf8.decode(bytes, allowMalformed: true).trimLeft();
          if (asText.startsWith('<svg') || asText.startsWith('<?xml')) {
            qrDataUrl = Uri.dataFromString(
              asText,
              mimeType: 'image/svg+xml',
              encoding: utf8,
            ).toString();
            debugPrint(
              '[ServiceTracking][PIX] detected SVG QR, using data URL (len=${qrDataUrl.length})',
            );
            // Keep bytes too, but prefer the data URL in UI.
          }
        } catch (_) {
          // ignore
        }
      }
      setState(() {
        _pixPayload = payload.isNotEmpty ? payload : null;
        _pixQrBase64 = qrBase64.isNotEmpty ? qrBase64 : null;
        _pixQrBytes = bytes;
        _pixQrDataUrl = qrDataUrl;
        _lastPixErrorTraceId = null;
        _lastPixErrorMessage = null;
      });
      _pixAutoRetryAttempt = 0;
      debugPrint(
        '[ServiceTracking][PIX] ready payloadForQrLen=${_pixPayloadForQr.length} bytes=${_pixQrBytes?.length ?? 0} hasUrl=${(_pixQrBase64 ?? '').trim().startsWith('http')}',
      );

      _startPixPaidPolling(serviceId, isRemainingPayment: isRemainingPayment);
    } on ApiException catch (e) {
      if (!mounted) return;
      final details = e.details ?? const <String, dynamic>{};
      final traceId = (details['trace_id'] ?? '').toString().trim();
      final is403 =
          e.statusCode == 403 ||
          e.message.toLowerCase().contains('acesso negado');
      _lastPixErrorTraceId = traceId.isNotEmpty ? traceId : null;
      _lastPixErrorMessage = e.message;
      final now = DateTime.now();
      if (_lastPixErrorSnackAt == null ||
          now.difference(_lastPixErrorSnackAt!).inSeconds >= 8) {
        _lastPixErrorSnackAt = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              is403
                  ? 'Acesso negado ao PIX desta solicitação. Trace: ${traceId.isNotEmpty ? traceId : "N/A"}.'
                  : 'Erro ao gerar PIX: ${e.message}${traceId.isNotEmpty ? " (trace: $traceId)" : ""}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      _schedulePixAutoRetry(serviceId, isRemainingPayment: isRemainingPayment);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final statusMatch = RegExp(r'Status:\\s*(\\d+)').firstMatch(raw);
      final traceMatch = RegExp(r'trace:\\s*([a-zA-Z0-9-]+)').firstMatch(raw);
      final statusCode = int.tryParse(statusMatch?.group(1) ?? '') ?? 0;
      final traceId = (traceMatch?.group(1) ?? '').trim();
      final is403 =
          statusCode == 403 || raw.toLowerCase().contains('acesso negado');
      _lastPixErrorTraceId = traceId.isNotEmpty ? traceId : null;
      _lastPixErrorMessage = raw;
      final now = DateTime.now();
      if (_lastPixErrorSnackAt == null ||
          now.difference(_lastPixErrorSnackAt!).inSeconds >= 8) {
        _lastPixErrorSnackAt = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              is403
                  ? 'Acesso negado ao PIX desta solicitação. Trace: ${traceId.isNotEmpty ? traceId : "N/A"}.'
                  : 'Erro ao gerar PIX: $raw',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      _schedulePixAutoRetry(serviceId, isRemainingPayment: isRemainingPayment);
    } finally {
      if (mounted) setState(() => _isLoadingPix = false);
    }
  }

  void _schedulePixAutoRetry(
    String serviceId, {
    required bool isRemainingPayment,
  }) {
    if (!mounted || _pixPaid) return;
    if (_pixAutoRetryAttempt >= 3) return;
    _pixAutoRetryTimer?.cancel();
    _pixAutoRetryAttempt++;
    final retryDelay = Duration(seconds: 3 * _pixAutoRetryAttempt);
    _pixAutoRetryTimer = Timer(retryDelay, () {
      if (!mounted || _pixPaid || _isLoadingPix) return;
      final hasPixLoaded =
          (_pixPayload?.trim().isNotEmpty ?? false) ||
          (_pixQrBase64?.trim().isNotEmpty ?? false) ||
          _pixQrBytes != null ||
          (_pixQrDataUrl?.trim().isNotEmpty ?? false);
      if (hasPixLoaded) return;
      _loadPixInline(serviceId, isRemainingPayment: isRemainingPayment);
    });
  }

  void _startPixPaidPolling(
    String serviceId, {
    required bool isRemainingPayment,
  }) {
    _pixPollTimer?.cancel();
    _pixPollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted || _pixPaid) return;
      try {
        final row = await ApiService().getServiceDetails(
          serviceId,
          scope: widget.scope,
        );
        if (!mounted) return;
        // Atualiza a tela mesmo que o Realtime falhe.
        setState(() {
          _service = {...?_service, ...row};
          _status = (row['status'] ?? _status ?? '').toString();
        });

        final paymentStatus = (row['payment_status'] ?? '')
            .toString()
            .toLowerCase();
        final paymentRemainingStatus = (row['payment_remaining_status'] ?? '')
            .toString()
            .toLowerCase();
        final remainingPaid =
            paymentRemainingStatus == 'paid' ||
            paymentRemainingStatus == 'paid_manual' ||
            paymentRemainingStatus == 'approved';
        final depositPaid =
            paymentStatus == 'paid' ||
            paymentStatus == 'partially_paid' ||
            paymentStatus == 'paid_manual';
        final paymentConfirmed = isRemainingPayment
            ? remainingPaid
            : depositPaid;

        if (paymentConfirmed) {
          _pixPollTimer?.cancel();
          _pixPollTimer = null;
          _pixAutoRetryTimer?.cancel();
          if (!mounted) return;

          // Se o pagamento do sinal (deposit) foi confirmado agora, movemos
          // o fluxo móvel para searching_provider para iniciar dispatch.
          if (!isRemainingPayment) {
            final currentStatus = (row['status'] ?? '')
                .toString()
                .toLowerCase();
            if (currentStatus == 'awaiting_signal' ||
                currentStatus == 'waiting_payment') {
              debugPrint(
                '✅ [ServiceTracking] Sinal Pago. Movendo status para "searching_provider".',
              );
              ApiService()
                  .updateServiceStatus(
                    serviceId,
                    'searching_provider',
                    scope: widget.scope,
                  )
                  .catchError((e) {
                    debugPrint(
                      '⚠️ [ServiceTracking] Erro ao mover para searching_provider: $e',
                    );
                    ApiService()
                        .updateServiceStatus(
                          serviceId,
                          'searching',
                          scope: widget.scope,
                        )
                        .catchError((_) {});
                  });
            }
          }
          setState(() {
            _pixPaid = true;
            if (!isRemainingPayment) {
              _status = 'searching_provider';
              _service = {
                ...?_service,
                'status': 'searching_provider',
                'payment_status': 'paid',
              };
            }
            // Limpa o QR/payload para não confundir após confirmação.
            _pixPayload = null;
            _pixQrBase64 = null;
            _pixQrBytes = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pagamento confirmado, buscando prestador mais próximo...',
              ),
              backgroundColor: Colors.green,
            ),
          );
          if (!isRemainingPayment) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              context.go('/service-busca-prestador-movel/$serviceId');
            });
          }
        }
      } catch (_) {
        // ignore polling failures
      }
    });
  }

  Future<void> _cancelService() async {
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
      await ApiService().cancelService(widget.serviceId, scope: _scopeValue());
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Solicitação cancelada.')),
      );
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      final errorText = e.toString().toLowerCase();
      final backendOffline =
          errorText.contains('failed to fetch') ||
          errorText.contains('connection refused') ||
          errorText.contains('err_connection_refused');
      final message = backendOffline
          ? 'Backend API do Supabase indisponível. Verifique SUPABASE_URL/BACKEND_API_URL e tente novamente.'
          : 'Erro ao cancelar: $e';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _buildStepper(int step, {bool inSecurePaymentPhase = false}) {
    // step: 0..4
    Widget dot({
      required bool done,
      required bool active,
      required IconData icon,
      required String label,
      bool paymentHighlight = false,
    }) {
      final Color bg = paymentHighlight
          ? Colors.orange
          : done
          ? AppTheme.primaryYellow
          : active
          ? AppTheme.darkBlueText
          : Colors.grey.shade200;
      final Color fg = paymentHighlight
          ? Colors.white
          : (done || active ? Colors.black : Colors.grey.shade600);
      return Expanded(
        child: Column(
          children: [
            Container(
              width: active ? 34 : 30,
              height: active ? 34 : 30,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon, size: 16, color: fg),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: paymentHighlight
                    ? Colors.orange.shade700
                    : (active ? AppTheme.darkBlueText : Colors.black54),
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

    return Row(
      children: [
        dot(
          done: step >= 1,
          active: step == 0 || step == 1,
          icon: LucideIcons.banknote,
          label: 'Reserva',
        ),
        line(step >= 2),
        dot(
          done: step >= 2,
          active: step == 2,
          icon: inSecurePaymentPhase
              ? LucideIcons.shield
              : LucideIcons.navigation,
          label: inSecurePaymentPhase ? 'Pagamento' : 'Chegada',
          paymentHighlight: inSecurePaymentPhase,
        ),
        line(step >= 3),
        dot(
          done: step >= 3,
          active: step == 3,
          icon: LucideIcons.wrench,
          label: 'Execução',
        ),
        line(step >= 4),
        dot(
          done: step >= 4,
          active: step == 4,
          icon: LucideIcons.badgeCheck,
          label: 'Conclusão',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final service = _service;
    final backendPaymentSummary =
        _latestBackendTrackingSnapshot?.paymentSummary;
    final backendFinalActions = _latestBackendTrackingSnapshot?.finalActions;
    final serviceStatus = (service?['status'] ?? '').toString();
    final status = (serviceStatus.trim().isNotEmpty ? serviceStatus : _status)
        .toString();
    // If a provider is already set but the status didn't refresh yet,
    // treat it as accepted for the UI to avoid showing "buscando".
    final bool hasProviderId = service?['provider_id'] != null;
    final paymentRemainingStatus = (service?['payment_remaining_status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final bool remainingPaid =
        backendPaymentSummary?['remainingPaid'] == true ||
        paymentRemainingStatus == 'paid' ||
        paymentRemainingStatus == 'paid_manual' ||
        paymentRemainingStatus == 'approved';
    final String effectiveStatus = status;
    final bool providerArrived =
        service?['arrived_at'] != null ||
        service?['client_arrived'] == true ||
        service?['client_arrived'] == 'true';
    final providerNameRaw = (service?['provider_name'] ?? '').toString().trim();
    final bool hasProvider = providerNameRaw.isNotEmpty || hasProviderId;
    final providerName = hasProvider
        ? (providerNameRaw.isNotEmpty ? providerNameRaw : 'Prestador')
        : '';
    final categoryName =
        (service?['category_name'] ?? service?['profession'] ?? 'Serviço')
            .toString();
    final participantContextLabel = _serviceParticipantContextLabel(service);

    final bool showPayRemaining =
        backendPaymentSummary?['showPayRemaining'] == true ||
        ([
                  'arrived',
                  'waiting_remaining_payment',
                  'waiting_payment_remaining',
                ].contains(effectiveStatus.toLowerCase().trim()) ||
                providerArrived) &&
            !remainingPaid;
    final bool inSecurePaymentPhase =
        backendPaymentSummary?['inSecurePaymentPhase'] == true ||
        ([
                  'waiting_remaining_payment',
                  'waiting_payment_remaining',
                ].contains(effectiveStatus.toLowerCase().trim()) ||
                providerArrived) &&
            !remainingPaid;

    final paymentStatus = (service?['payment_status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final bool backendAlreadySearching = [
      'searching_provider',
      'searching',
      'search_provider',
      'waiting_provider',
    ].contains(effectiveStatus.toLowerCase().trim());
    final bool entryPaid =
        backendPaymentSummary?['entryPaid'] == true ||
        backendAlreadySearching ||
        paymentStatus == 'paid' ||
        paymentStatus == 'partially_paid' ||
        paymentStatus == 'paid_manual';
    if (_shouldOpenProviderSearchPage(
      status: effectiveStatus,
      entryPaid: entryPaid,
      hasProvider: hasProvider,
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go('/service-busca-prestador-movel/${widget.serviceId}');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final trackingStage = TrackingStageResolver.resolve(
      status: effectiveStatus,
      entryPaid: entryPaid,
      remainingPaid: remainingPaid,
      providerArrived: providerArrived,
      hasProvider: hasProvider,
      isUnderDisputeAnalysis: _isUnderDisputeAnalysis,
    );
    final step = trackingStage.stepIndex;
    final headline = trackingStage.headline;
    final stage = trackingStage.stage;

    final bool showPayDeposit =
        backendPaymentSummary?['showPayDeposit'] == true ||
        !entryPaid &&
            [
              'waiting_payment',
              'awaiting_signal',
              'pending',
              'searching_provider',
              'search_provider',
              'waiting_provider',
            ].contains(effectiveStatus.toLowerCase().trim());
    final bool supportsInlinePlatformPix = _supportsInlinePlatformPix(service);
    final bool usesDirectProviderPayment = _isDirectProviderPaymentMethod(
      service,
    );
    final bool showPixInline =
        supportsInlinePlatformPix && (showPayDeposit || showPayRemaining);
    final bool showDirectPaymentInfo =
        usesDirectProviderPayment && (showPayDeposit || showPayRemaining);
    final bool hasPixLoaded =
        (_pixPayload?.trim().isNotEmpty ?? false) ||
        (_pixQrBase64?.trim().isNotEmpty ?? false) ||
        _pixQrBytes != null ||
        (_pixQrDataUrl?.trim().isNotEmpty ?? false);

    final bool isSearchingStage = stage == TrackingStage.searchingProvider;
    final bool isScheduleStage = stage == TrackingStage.schedule;
    final bool isDisputeStage = stage == TrackingStage.dispute;
    final bool isAwaitingConfirmationStage =
        stage == TrackingStage.awaitingConfirmation;

    final bool showDispatchTimeline =
        isSearchingStage &&
        entryPaid &&
        !hasProvider &&
        [
          'pending',
          'searching',
          'searching_provider',
          'search_provider',
          'waiting_provider',
        ].contains(effectiveStatus.toLowerCase().trim());
    final bool showSearchingProviderInfo =
        isSearchingStage &&
        entryPaid &&
        !hasProvider &&
        [
          'searching',
          'searching_provider',
          'search_provider',
          'waiting_provider',
        ].contains(effectiveStatus.toLowerCase().trim());
    final displayHeadline =
        showSearchingProviderInfo &&
            (_dispatchHeadlineOverride?.trim().isNotEmpty ?? false)
        ? _dispatchHeadlineOverride!.trim()
        : headline;
    final bool providerReadyToStart =
        effectiveStatus.toLowerCase().trim() == 'in_progress' &&
        remainingPaid &&
        service?['started_at'] == null;
    final resolvedHeadline = providerReadyToStart
        ? 'Pagamento confirmado'
        : displayHeadline;
    final searchingProviderMessage =
        showSearchingProviderInfo &&
            (_dispatchSubtitleOverride?.trim().isNotEmpty ?? false)
        ? _dispatchSubtitleOverride!.trim()
        : 'Pagamento confirmado. Estamos buscando um prestador disponível para você.';

    final bool showConfirm =
        backendFinalActions?['showConfirm'] == true ||
        isAwaitingConfirmationStage;
    final String completionCode =
        (service?['completion_code'] ?? service?['verification_code'] ?? '')
            .toString()
            .trim();
    final bool showCompletionCode =
        completionCode.isNotEmpty &&
        [
          'awaiting_confirmation',
          'waiting_client_confirmation',
          'in_progress',
        ].contains(effectiveStatus.toLowerCase().trim());
    final double serviceTotal =
        double.tryParse(
          '${service?['price_estimated'] ?? service?['total_price'] ?? ''}',
        ) ??
        0.0;
    final double securePaymentAmount =
        (backendPaymentSummary?['securePaymentAmount'] is num)
        ? (backendPaymentSummary!['securePaymentAmount'] as num).toDouble()
        : (service?['amount_payable_on_site'] is num)
        ? (service?['amount_payable_on_site'] as num).toDouble()
        : (serviceTotal > 0 ? serviceTotal * 0.70 : 0.0);
    final double depositPaymentAmount =
        (backendPaymentSummary?['depositPaymentAmount'] is num)
        ? (backendPaymentSummary!['depositPaymentAmount'] as num).toDouble()
        : serviceTotal > 0
        ? serviceTotal * 0.30
        : 0.0;
    final bool isRemainingPixPayment = showPayRemaining;
    final double pixDisplayAmount =
        (backendPaymentSummary?['pixDisplayAmount'] is num)
        ? (backendPaymentSummary!['pixDisplayAmount'] as num).toDouble()
        : isRemainingPixPayment
        ? securePaymentAmount
        : depositPaymentAmount;
    final String pixDisplayLabel =
        backendPaymentSummary?['pixDisplayLabel']?.toString() ??
        (isRemainingPixPayment
            ? 'Valor do pagamento (70%)'
            : 'Valor da entrada (30%)');

    final lat = (service?['latitude'] as num?)?.toDouble();
    final lon = (service?['longitude'] as num?)?.toDouble();
    final hasCoords = lat != null && lon != null;
    final center = LatLng(lat ?? -5.52, lon ?? -47.48);
    final hasProviderTracking = _providerLatLng != null && hasCoords;
    final double? providerDistanceMeters = hasProviderTracking
        ? Geolocator.distanceBetween(
            _providerLatLng!.latitude,
            _providerLatLng!.longitude,
            center.latitude,
            center.longitude,
          )
        : null;
    final double? providerDistanceKm = providerDistanceMeters != null
        ? providerDistanceMeters / 1000
        : null;
    final bool cancelBlockedByProximity =
        backendPaymentSummary?['cancelBlockedByProximity'] == true ||
        (providerDistanceMeters != null && providerDistanceMeters <= 100);
    final statusLower = effectiveStatus.toLowerCase().trim();
    final bool isCompletedStatus =
        statusLower == 'completed' || statusLower == 'finished';
    final bool shouldShowLiveProviderMovement =
        !isAwaitingConfirmationStage &&
        !isDisputeStage &&
        !isCompletedStatus &&
        ['accepted', 'provider_near', 'scheduled'].contains(statusLower);
    // ETA simples para teste E2E (equivalente a deslocamento urbano médio).
    final int? providerEtaMinutes = providerDistanceKm != null
        ? ((providerDistanceKm / 30.0) * 60.0).ceil().clamp(1, 120)
        : null;
    final String? providerEtaLabel =
        shouldShowLiveProviderMovement &&
            providerDistanceKm != null &&
            providerEtaMinutes != null
        ? '${providerDistanceKm.toStringAsFixed(providerDistanceKm < 10 ? 2 : 1)} km • ~$providerEtaMinutes min'
        : null;

    final paidChipText =
        (paymentStatus == 'paid' ||
            paymentStatus == 'partially_paid' ||
            paymentStatus == 'paid_manual')
        ? (remainingPaid ? '100% PAGO' : '30% PAGO')
        : 'PAGAMENTO';

    if (isCompletedStatus &&
        !_redirectScheduledAfterCompletion &&
        !_shouldPinTrackingRoute()) {
      _redirectScheduledAfterCompletion = true;
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        context.go('/home');
      });
    }

    final shouldAutoLoadPix =
        showPixInline &&
        !hasPixLoaded &&
        !_isLoadingPix &&
        ((showPayDeposit && !_depositPixAutoLoadAttempted) ||
            (showPayRemaining && !_remainingPixAutoLoadAttempted));
    if (shouldAutoLoadPix) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadPixInline(widget.serviceId, isRemainingPayment: showPayRemaining);
      });
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Conteúdo principal: topo + mapa
            Positioned.fill(
              child: Column(
                children: [
                  // Header (branco)
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Status do Serviço',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Text(
                          '101SERVICE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _buildStepper(
                      step,
                      inSecurePaymentPhase: inSecurePaymentPhase,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: Colors.grey.shade100,
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: center,
                              initialZoom: 14.5,
                              onMapReady: () {
                                _mapKickTimer?.cancel();
                                _mapKickTimer = Timer.periodic(
                                  const Duration(milliseconds: 650),
                                  (timer) {
                                    if (!mounted || timer.tick > 3) {
                                      timer.cancel();
                                      return;
                                    }
                                    try {
                                      _mapController.move(center, 14.5);
                                    } catch (_) {}
                                  },
                                );
                              },
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.all,
                              ),
                            ),
                            children: [
                              AppTileLayer.standard(
                                mapboxToken: SupabaseConfig.mapboxToken,
                              ),
                              if (_providerTrail.length >= 2)
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: List<LatLng>.from(_providerTrail),
                                      strokeWidth: 5,
                                      color: AppTheme.primaryBlue.withOpacity(
                                        0.55,
                                      ),
                                    ),
                                  ],
                                ),
                              if (_providerLatLng != null && hasCoords)
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: [_providerLatLng!, center],
                                      strokeWidth: 3,
                                      color: AppTheme.primaryBlue.withOpacity(
                                        0.25,
                                      ),
                                    ),
                                  ],
                                ),
                              if (hasCoords)
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: center,
                                      width: 44,
                                      height: 44,
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
                                              color: Colors.black.withOpacity(
                                                0.18,
                                              ),
                                              blurRadius: 14,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          LucideIcons.mapPin,
                                          size: 18,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              if (_providerLatLng != null)
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _providerLatLng!,
                                      width: 48,
                                      height: 48,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryBlue,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.18,
                                              ),
                                              blurRadius: 14,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 4,
                                          ),
                                        ),
                                        child: const Icon(
                                          LucideIcons.navigation,
                                          size: 18,
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
                                    final z = _mapController.camera.zoom + 1;
                                    _mapController.move(
                                      _mapController.camera.center,
                                      z,
                                    );
                                  },
                                ),
                                const SizedBox(height: 10),
                                _mapButton(
                                  icon: Icons.remove,
                                  onTap: () {
                                    final z = _mapController.camera.zoom - 1;
                                    _mapController.move(
                                      _mapController.camera.center,
                                      z,
                                    );
                                  },
                                ),
                                const SizedBox(height: 10),
                                _mapButton(
                                  icon: Icons.my_location,
                                  onTap: () {
                                    _mapController.move(center, 14.5);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Drawer inferior
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
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
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.88,
                  ),
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
                                    resolvedHeadline,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      height: 1.05,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (!inSecurePaymentPhase &&
                                      providerEtaLabel != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Prestador em deslocamento: $providerEtaLabel',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ],
                                  if (participantContextLabel != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      participantContextLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
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
                                paidChipText,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TrackingStageBody(
                          searchingWidget: showSearchingProviderInfo
                              ? TrackingSearchingProviderStep(
                                  title: displayHeadline,
                                  subtitle: searchingProviderMessage,
                                )
                              : null,
                          providerJourneyWidget:
                              hasProvider &&
                                  ({
                                    TrackingStage.providerJourney,
                                    TrackingStage.inProgress,
                                    TrackingStage.awaitingConfirmation,
                                    TrackingStage.completed,
                                    TrackingStage.dispute,
                                    TrackingStage.schedule,
                                  }.contains(stage))
                              ? TrackingProviderJourneyCard(
                                  providerName: providerName,
                                  categoryName: categoryName,
                                  providerEtaLabel: providerEtaLabel,
                                  isCompletedStatus: isCompletedStatus,
                                  chatAction: _circleIconButton(
                                    icon: LucideIcons.messageSquare,
                                    onTap: () {
                                      context.push('/chat/${widget.serviceId}');
                                    },
                                  ),
                                )
                              : null,
                          dispatchTimelineWidget: showDispatchTimeline
                              ? DispatchTrackingTimeline(
                                  serviceId: widget.serviceId,
                                  onProviderFound: () {},
                                  onSearchStateChanged: (title, subtitle) {
                                    if (!mounted) return;
                                    final normalizedTitle = title.trim();
                                    final normalizedSubtitle = subtitle.trim();
                                    if (_dispatchHeadlineOverride ==
                                            normalizedTitle &&
                                        _dispatchSubtitleOverride ==
                                            normalizedSubtitle) {
                                      return;
                                    }
                                    setState(() {
                                      _dispatchHeadlineOverride =
                                          normalizedTitle;
                                      _dispatchSubtitleOverride =
                                          normalizedSubtitle;
                                    });
                                  },
                                )
                              : null,
                          completionCodeWidget: showCompletionCode
                              ? Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: AppTheme.primaryBlue.withOpacity(
                                        0.65,
                                      ),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'Código de validação (6 dígitos)',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        completionCode,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 6,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : null,
                          pixWidget: showPixInline
                              ? TrackingPaymentPendingStep(
                                  realtimeDegraded: _realtimeDegraded,
                                  hasPixLoaded: hasPixLoaded,
                                  inSecurePaymentPhase: inSecurePaymentPhase,
                                  securePaymentAmount: securePaymentAmount,
                                  isLoadingPix: _isLoadingPix,
                                  lastPixErrorMessage: _lastPixErrorMessage,
                                  lastPixErrorTraceId: _lastPixErrorTraceId,
                                  onRetryPix: () {
                                    _loadPixInline(
                                      widget.serviceId,
                                      isRemainingPayment: showPayRemaining,
                                      manualRetry: true,
                                    );
                                  },
                                  pixDisplayAmount: pixDisplayAmount,
                                  pixDisplayLabel: pixDisplayLabel,
                                  qrWidget: Builder(
                                    builder: (_) {
                                      final url = (_pixQrBase64 ?? '').trim();
                                      final svgUrl = (_pixQrDataUrl ?? '')
                                          .trim();
                                      final shouldUsePainter =
                                          _pixPayloadForQr.isNotEmpty;

                                      if (shouldUsePainter) {
                                        if (_pixPayloadForQr.isEmpty) {
                                          return const SizedBox(
                                            width: 180,
                                            height: 180,
                                          );
                                        }
                                        final painter = QrPainter(
                                          data: _pixPayloadForQr,
                                          version: QrVersions.auto,
                                          eyeStyle: const QrEyeStyle(
                                            eyeShape: QrEyeShape.square,
                                            color: AppTheme.textDark,
                                          ),
                                          dataModuleStyle:
                                              const QrDataModuleStyle(
                                                dataModuleShape:
                                                    QrDataModuleShape.square,
                                                color: AppTheme.textDark,
                                              ),
                                        );

                                        return CustomPaint(
                                          size: const Size.square(180),
                                          painter: painter,
                                        );
                                      }

                                      if (svgUrl.isNotEmpty) {
                                        return Image.network(
                                          svgUrl,
                                          width: 180,
                                          height: 180,
                                          fit: BoxFit.contain,
                                        );
                                      }

                                      if (_pixQrBytes != null) {
                                        return Image.memory(
                                          _pixQrBytes!,
                                          width: 180,
                                          height: 180,
                                          fit: BoxFit.contain,
                                          gaplessPlayback: true,
                                          filterQuality: FilterQuality.none,
                                          errorBuilder: (_, __, ___) {
                                            return const SizedBox(
                                              width: 180,
                                              height: 180,
                                            );
                                          },
                                        );
                                      }

                                      return Image.network(
                                        url,
                                        width: 180,
                                        height: 180,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) {
                                          return const SizedBox(
                                            width: 180,
                                            height: 180,
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  pixPayload: _pixPayload,
                                  pixPayloadForQr: _pixPayloadForQr,
                                  onCopyPix: () async {
                                    final text = _pixPayloadForQr.isNotEmpty
                                        ? _pixPayloadForQr
                                        : (_pixPayload ?? '');
                                    await Clipboard.setData(
                                      ClipboardData(text: text),
                                    );
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Código PIX copiado!'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  primaryActionLabel: null,
                                  onPrimaryAction: null,
                                  cancelBlockedByProximity: inSecurePaymentPhase
                                      ? false
                                      : cancelBlockedByProximity,
                                  onCancelService: _cancelService,
                                )
                              : showDirectPaymentInfo
                              ? _buildDirectPaymentInfoCard(
                                  isRemainingPayment: showPayRemaining,
                                  amount: pixDisplayAmount,
                                )
                              : null,
                          scheduleProposalWidget:
                              isScheduleStage &&
                                  effectiveStatus.toLowerCase().trim() ==
                                      'schedule_proposed'
                              ? _buildScheduleProposalCard(
                                  service ?? <String, dynamic>{},
                                )
                              : null,
                          remainingPaidWidget:
                              [
                                    'waiting_payment_remaining',
                                    'waiting_remaining_payment',
                                    'in_progress',
                                  ].contains(
                                    effectiveStatus.toLowerCase().trim(),
                                  ) &&
                                  remainingPaid
                              ? Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.green.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    providerReadyToStart
                                        ? 'Pagamento seguro realizado. O prestador já pode iniciar o serviço.'
                                        : 'Pagamento seguro realizado. O prestador iniciará o serviço.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.green,
                                    ),
                                  ),
                                )
                              : null,
                          finalActionsWidget: TrackingFinalActionsSection(
                            disputeAnalysisCard: isDisputeStage
                                ? _buildDisputeAnalysisCard()
                                : null,
                            showConfirm: showConfirm,
                            isConfirmingService: _isConfirmingService,
                            onConfirmService: _showConfirmServiceDialog,
                            onOpenComplaint: _openComplaintFlow,
                            showCompletedMessage:
                                backendFinalActions?['showCompletedMessage'] ==
                                    true ||
                                stage == TrackingStage.completed,
                            canCancel:
                                backendFinalActions?['canCancel'] == true ||
                                !cancelBlockedByProximity,
                            onCancelService: _cancelService,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Icon(icon)),
      ),
    );
  }

  Widget _circleIconButton({required IconData icon, VoidCallback? onTap}) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20)),
      ),
    );
  }
}
