import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Timeline de dispatch que lê os eventos de `service_logs` via Supabase SDK.
/// Usa Realtime para atualizar em tempo real sem polling.
class DispatchTrackingTimeline extends StatefulWidget {
  final String serviceId;
  final VoidCallback onProviderFound;

  const DispatchTrackingTimeline({
    super.key,
    required this.serviceId,
    required this.onProviderFound,
  });

  @override
  State<DispatchTrackingTimeline> createState() =>
      _DispatchTrackingTimelineState();
}

class _DispatchTrackingTimelineState extends State<DispatchTrackingTimeline> {
  RealtimeChannel? _channel;
  String _headline = "Iniciando busca...";
  List<Map<String, dynamic>> _timeline = [];
  bool _isLoading = true;
  bool _providerFoundCalled = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  /// Carrega os logs do Supabase SDK (tabela service_logs)
  Future<void> _loadLogs() async {
    try {
      final rows = await Supabase.instance.client
          .from('service_logs')
          .select('action, message, created_at')
          .eq('service_id', widget.serviceId)
          .order('created_at', ascending: false)
          .limit(10);

      if (!mounted) return;
      _applyLogs(List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      debugPrint('[DispatchTimeline] Erro ao carregar logs: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Converte os rows de service_logs em headline + timeline
  void _applyLogs(List<Map<String, dynamic>> rows) {
    if (!mounted) return;

    final timeline = rows.map((r) {
      final raw = r['created_at'] as String?;
      final dt = raw != null ? DateTime.tryParse(raw)?.toLocal() : null;
      final timeStr = dt != null
          ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
          : '';
      return {
        'message': r['message'] ?? r['action'] ?? '',
        'time': timeStr,
        'action': r['action'] ?? '',
      };
    }).toList();

    // Gerar headline baseado no evento mais recente
    final latestEvent = rows.isNotEmpty
        ? (rows.first['action'] as String? ?? '')
        : '';
    final headline = _headlineFor(
      latestEvent,
      rows.isNotEmpty ? (rows.first['message'] as String?) : null,
    );

    // Verificar se prestador foi encontrado
    final accepted = rows.any(
      (r) =>
          (r['action'] as String?)?.contains('ACCEPTED') == true ||
          (r['action'] as String?)?.contains('PROVIDER_ASSIGNED') == true,
    );

    setState(() {
      _headline = headline;
      _timeline = timeline;
      _isLoading = false;
    });

    if (accepted && !_providerFoundCalled) {
      _providerFoundCalled = true;
      widget.onProviderFound();
    }
  }

  /// Retorna uma headline amigável baseada no tipo de evento
  String _headlineFor(String eventType, String? message) {
    switch (eventType.toUpperCase()) {
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
      case 'OPEN_FOR_SCHEDULE':
        return 'Disponível para agendamento';
      case 'CANCELLED':
        return 'Serviço cancelado';
      default:
        return message ?? 'Processando...';
    }
  }

  /// Escuta inserções em tempo real na tabela service_logs para este serviço
  void _subscribeRealtime() {
    _channel = Supabase.instance.client
        .channel('service_logs:${widget.serviceId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'service_logs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'service_id',
            value: widget.serviceId,
          ),
          callback: (payload) {
            debugPrint(
              '[DispatchTimeline] Novo log recebido via RT: ${payload.newRecord}',
            );
            // Re-carregar todos os logs para manter a ordem
            _loadLogs();
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline
          Row(
            children: [
              if (_isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(LucideIcons.radar, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _headline,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Timeline
          if (_timeline.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: Text(
                "Conectando ao servidor...",
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _timeline.length > 3 ? 3 : _timeline.length,
              itemBuilder: (context, index) {
                final event = _timeline[index];
                final isLast =
                    index == (_timeline.length > 3 ? 2 : _timeline.length - 1);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: index == 0
                                  ? Colors.green
                                  : Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                          ),
                          if (!isLast)
                            Container(
                              width: 2,
                              height: 20,
                              color: Colors.grey.shade200,
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event['message'] ?? '',
                              style: TextStyle(
                                fontSize: 14,
                                color: index == 0
                                    ? Colors.black87
                                    : Colors.grey,
                                fontWeight: index == 0
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                            ),
                            Text(
                              event['time'] ?? '',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
