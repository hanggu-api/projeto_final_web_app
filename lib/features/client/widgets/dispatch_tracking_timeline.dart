import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../services/data_gateway.dart';

/// Timeline de dispatch que usa `notificacao_de_servicos` como runtime oficial
/// e `service_logs` apenas para histórico visual.
class DispatchTrackingTimeline extends StatefulWidget {
  final String serviceId;
  final VoidCallback onProviderFound;
  final void Function(String title, String subtitle)? onSearchStateChanged;
  final ValueChanged<DispatchProviderCandidate?>? onProviderCandidateChanged;

  const DispatchTrackingTimeline({
    super.key,
    required this.serviceId,
    required this.onProviderFound,
    this.onSearchStateChanged,
    this.onProviderCandidateChanged,
  });

  @override
  State<DispatchTrackingTimeline> createState() =>
      _DispatchTrackingTimelineState();
}

class _DispatchTrackingTimelineState extends State<DispatchTrackingTimeline> {
  Timer? _logsPollingTimer;
  Timer? _pulseTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _dispatchSub;
  List<Map<String, dynamic>> _timeline = [];
  bool _providerFoundCalled = false;
  String _latestAction = '';
  DateTime? _searchStartedAt;
  DateTime? _activeDeadlineAt;
  _DispatchUiState _uiState = const _DispatchUiState.searching();

  @override
  void initState() {
    super.initState();
    _searchStartedAt = DateTime.now();
    _loadLogs();
    _startLogsPolling();
    _subscribeDispatchRuntime();
    _pulseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _dispatchSub?.cancel();
    _logsPollingTimer?.cancel();
    _pulseTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    try {
      final rows = await DataGateway().loadServiceLogs(
        widget.serviceId,
        limit: 12,
      );

      if (!mounted) return;
      _applyLogs(rows);
    } catch (e) {
      debugPrint('[DispatchTimeline] Erro ao carregar logs: $e');
    }
  }

  void _applyLogs(List<Map<String, dynamic>> rows) {
    if (!mounted) return;

    final timeline = rows.map((r) {
      final action = (r['action'] ?? '').toString();
      final raw = r['created_at'] as String?;
      final dt = raw != null ? DateTime.tryParse(raw)?.toLocal() : null;
      final timeStr = dt != null
          ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
          : '';
      final details = _decodeDetails(r['details']);
      return {
        'message': _messageForTimeline(action, details),
        'time': timeStr,
        'action': action,
      };
    }).toList();

    final latestAction = rows.isNotEmpty
        ? (rows.first['action'] as String? ?? '')
        : '';
    final oldestRaw = rows.isNotEmpty
        ? rows.last['created_at'] as String?
        : null;
    final oldestDate = oldestRaw != null
        ? DateTime.tryParse(oldestRaw)?.toLocal()
        : null;

    setState(() {
      _timeline = timeline;
      _latestAction = latestAction;
      _searchStartedAt = oldestDate ?? _searchStartedAt ?? DateTime.now();
    });
  }

  void _subscribeDispatchRuntime() {
    _dispatchSub?.cancel();
    _dispatchSub = DataGateway()
        .watchDispatchQueueState(widget.serviceId)
        .listen(_applyDispatchRows);
    unawaited(
      DataGateway()
          .getDispatchQueueState(widget.serviceId)
          .then(_applyDispatchRows),
    );
  }

  void _applyDispatchRows(List<Map<String, dynamic>> rows) {
    if (!mounted) return;

    final activeRow = rows.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row != null && _isActiveRow(row),
      orElse: () => null,
    );
    final accepted = rows.any(
      (row) =>
          (row['status'] ?? '').toString().toLowerCase().trim() == 'accepted',
    );
    final activeCandidate = activeRow == null
        ? null
        : _candidateFromRuntimeRow(activeRow);
    final nextCandidate =
        activeCandidate ??
        rows
            .cast<Map<String, dynamic>?>()
            .firstWhere(
              (row) => row != null && _isPendingRow(row),
              orElse: () => null,
            )
            .let(_candidateFromRuntimeRowNullable);

    final uiState = _buildUiState(
      rows: rows,
      activeCandidate: activeCandidate,
      nextCandidate: nextCandidate,
      accepted: accepted,
    );

    setState(() {
      _uiState = uiState;
      _activeDeadlineAt = activeRow == null
          ? null
          : _parseDate(activeRow['response_deadline_at'])?.toLocal();
    });

    widget.onProviderCandidateChanged?.call(
      uiState.hasActiveCandidate ? activeCandidate : null,
    );

    if (accepted && !_providerFoundCalled) {
      _providerFoundCalled = true;
      widget.onProviderFound();
    }
  }

  bool _isActiveRow(Map<String, dynamic> row) {
    final status = (row['status'] ?? '').toString().toLowerCase().trim();
    if (status != 'notified') return false;
    final deadline = _parseDate(row['response_deadline_at']);
    return deadline == null || deadline.isAfter(DateTime.now());
  }

  bool _isPendingRow(Map<String, dynamic> row) {
    final status = (row['status'] ?? '').toString().toLowerCase().trim();
    return status == 'queued' || status == 'retry_ready';
  }

  DispatchProviderCandidate? _candidateFromRuntimeRowNullable(
    Map<String, dynamic>? row,
  ) {
    if (row == null) return null;
    return _candidateFromRuntimeRow(row);
  }

  DispatchProviderCandidate? _candidateFromRuntimeRow(
    Map<String, dynamic> row,
  ) {
    final providerId = _intFrom(row['provider_user_id']);
    final distanceKm = _doubleFrom(row['distance']);
    final queueOrder = _intFrom(row['queue_order']);
    final attemptNo = _intFrom(row['attempt_no']);
    final maxAttempts = _intFrom(row['max_attempts']);
    final responseDeadlineAt = _parseDate(row['response_deadline_at']);
    if (providerId == null && queueOrder == null && attemptNo == null) {
      return null;
    }

    return DispatchProviderCandidate(
      providerId: providerId,
      providerUid: null,
      location: null,
      distanceKm: distanceKm,
      queueOrder: queueOrder,
      cycle: attemptNo,
      responseDeadlineAt: responseDeadlineAt,
      maxAttempts: maxAttempts,
    );
  }

  String _messageForTimeline(String actionRaw, Map<String, dynamic>? details) {
    final action = actionRaw.toUpperCase().trim();
    final distanceKm = _doubleFrom(details?['distance_km']);
    final queueOrder = _intFrom(details?['queue_order']);
    final attemptNo = _intFrom(details?['attempt_no']);
    final maxAttempts = _intFrom(details?['max_attempts']);
    final distanceLabel = distanceKm != null && distanceKm > 0
        ? '${distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km'
        : null;
    final orderLabel = queueOrder != null && queueOrder > 0
        ? '$queueOrderº prestador'
        : null;
    final attemptLabel = attemptNo != null
        ? 'Tentativa $attemptNo${maxAttempts != null ? '/$maxAttempts' : ''}.'
        : null;

    switch (action) {
      case 'PROVIDER_NOTIFIED':
      case 'PROVIDER_NOTIFIED_TRANSIENT_PUSH':
        return [
          'Prestador atual notificado.',
          if (distanceLabel != null) 'Distância: $distanceLabel.',
          if (orderLabel != null) orderLabel,
          if (attemptLabel != null) attemptLabel,
        ].join(' ');
      case 'QUEUE_TIMEOUT_ADVANCE':
      case 'PROVIDER_REJECTED':
        return 'Sem resposta útil no prazo. Avançando para o próximo prestador elegível.';
      case 'PROVIDER_SKIPPED_UNDELIVERABLE':
        return 'Prestador ignorado por falha permanente de entrega. Seguimos para o próximo.';
      case 'DISPATCH_STARTED':
        return 'Busca iniciada. O sistema notifica um prestador por vez por ordem de distância.';
      case 'OPEN_FOR_SCHEDULE':
        return 'Busca imediata encerrada. Nenhum prestador aceitou nas 3 rodadas.';
      case 'PROVIDER_ACCEPTED':
        return 'Prestador aceitou a solicitação. Preparando o acompanhamento.';
      default:
        final txt = details != null && details.isNotEmpty
            ? jsonEncode(details)
            : actionRaw;
        if (txt.length > 140) return '${txt.substring(0, 140)}...';
        return txt;
    }
  }

  Map<String, dynamic>? _decodeDetails(Object? rawDetails) {
    if (rawDetails is Map) {
      return Map<String, dynamic>.from(rawDetails);
    }
    final raw = rawDetails?.toString().trim() ?? '';
    if (!raw.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  int? _intFrom(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _doubleFrom(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  Duration _remainingProviderResponseTime() {
    final deadline = _activeDeadlineAt;
    if (deadline == null) return Duration.zero;
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return Duration.zero;
    return remaining;
  }

  Duration _elapsedSearchTime() {
    final startedAt = _searchStartedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed.isNegative) return Duration.zero;
    return elapsed;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  _DispatchUiState _buildUiState({
    required List<Map<String, dynamic>> rows,
    required DispatchProviderCandidate? activeCandidate,
    required DispatchProviderCandidate? nextCandidate,
    required bool accepted,
  }) {
    if (accepted) {
      return const _DispatchUiState(
        title: 'Prestador confirmado',
        subtitle: 'O aceite foi recebido e o atendimento está seguindo.',
        color: Color(0xFF16A34A),
        softColor: Color(0xFFE8F7ED),
        icon: LucideIcons.badgeCheck,
      );
    }

    if (activeCandidate != null) {
      final parts = <String>['Aguardando resposta do prestador atual.'];
      if (activeCandidate.distanceKm != null &&
          activeCandidate.distanceKm! > 0) {
        parts.add(
          'Distância: ${activeCandidate.distanceKm!.toStringAsFixed(1).replaceAll('.', ',')} km.',
        );
      }
      if (activeCandidate.queueOrder != null &&
          activeCandidate.queueOrder! > 0) {
        parts.add('${activeCandidate.queueOrder}º da fila.');
      }
      if (activeCandidate.cycle != null) {
        final max = activeCandidate.maxAttempts ?? 3;
        parts.add('Tentativa ${activeCandidate.cycle}/$max.');
      }
      parts.add(
        'Se não houver resposta em 30 segundos, a plataforma avança para o próximo elegível.',
      );
      return _DispatchUiState(
        title: 'Notificando o prestador atual',
        subtitle: parts.join(' '),
        color: const Color(0xFFEA580C),
        softColor: const Color(0xFFFFE8D9),
        icon: LucideIcons.timer,
        hasActiveCandidate: true,
      );
    }

    if (nextCandidate != null) {
      final parts = <String>['Preparando a próxima tentativa da fila.'];
      if (nextCandidate.queueOrder != null && nextCandidate.queueOrder! > 0) {
        parts.add('${nextCandidate.queueOrder}º prestador elegível.');
      }
      if (nextCandidate.cycle != null) {
        final max = nextCandidate.maxAttempts ?? 3;
        parts.add('Próxima tentativa ${nextCandidate.cycle}/$max.');
      }
      return _DispatchUiState(
        title: 'Avançando na fila por distância',
        subtitle: parts.join(' '),
        color: const Color(0xFF0F766E),
        softColor: const Color(0xFFE6F7F4),
        icon: LucideIcons.refreshCcw,
      );
    }

    if (_latestAction.toUpperCase().trim() == 'OPEN_FOR_SCHEDULE') {
      return const _DispatchUiState(
        title: 'Busca imediata encerrada',
        subtitle:
            'Ninguém aceitou nas 3 rodadas. O serviço segue aguardando novo retorno.',
        color: Color(0xFF475569),
        softColor: Color(0xFFF1F5F9),
        icon: LucideIcons.calendarClock,
      );
    }

    if (rows.isNotEmpty) {
      return const _DispatchUiState(
        title: 'Organizando a fila de prestadores',
        subtitle:
            'O runtime do dispatch está definindo a próxima tentativa elegível.',
        color: Color(0xFF0891B2),
        softColor: Color(0xFFE0F7FC),
        icon: LucideIcons.locateFixed,
      );
    }

    return const _DispatchUiState.searching();
  }

  void _startLogsPolling() {
    _logsPollingTimer?.cancel();
    _logsPollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _loadLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final visual = _uiState;
    final isWaitingProviderResponse = visual.hasActiveCandidate;
    final timerText = isWaitingProviderResponse
        ? _formatDuration(_remainingProviderResponseTime())
        : _formatDuration(_elapsedSearchTime());
    final timerLabel = isWaitingProviderResponse ? 'resposta' : 'tempo';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onSearchStateChanged?.call(visual.title, visual.subtitle);
    });

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: visual.softColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: visual.color.withOpacity(0.20)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: visual.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(visual.icon, color: visual.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        visual.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: visual.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        visual.subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: visual.color.withOpacity(0.88),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timerText,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: visual.color,
                        ),
                      ),
                      Text(
                        timerLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: visual.color.withOpacity(0.75),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_timeline.isNotEmpty) ...[
            const SizedBox(height: 14),
            ..._timeline
                .take(4)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: visual.color.withOpacity(0.8),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item['message']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item['time']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

extension<T> on T {
  R let<R>(R Function(T value) fn) => fn(this);
}

class DispatchProviderCandidate {
  final int? providerId;
  final String? providerUid;
  final LatLng? location;
  final double? distanceKm;
  final int? queueOrder;
  final int? cycle;
  final int? maxAttempts;
  final DateTime? responseDeadlineAt;

  const DispatchProviderCandidate({
    this.providerId,
    this.providerUid,
    this.location,
    this.distanceKm,
    this.queueOrder,
    this.cycle,
    this.maxAttempts,
    this.responseDeadlineAt,
  });
}

class _DispatchUiState {
  final String title;
  final String subtitle;
  final Color color;
  final Color softColor;
  final IconData icon;
  final bool hasActiveCandidate;

  const _DispatchUiState({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.softColor,
    required this.icon,
    this.hasActiveCandidate = false,
  });

  const _DispatchUiState.searching()
    : title = 'Buscando o prestador mais próximo',
      subtitle =
          'Pagamento confirmado. Estamos consultando um prestador por vez por ordem de distância.',
      color = const Color(0xFF2563EB),
      softColor = const Color(0xFFE8F0FF),
      icon = LucideIcons.search,
      hasActiveCandidate = false;
}
