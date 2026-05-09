import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class UpcomingAppointmentDetailsArgs {
  final Map<String, dynamic> appointment;
  final String providerName;
  final String serviceName;
  final String address;
  final DateTime start;
  final String dateTimeLabel;
  final String timeLabel;
  final bool isOverdue;
  final bool isVeryClose;
  final String remainingLabel;
  final String leaveInLabel;
  final double distanceKm;
  final int travelTimeMin;
  final bool canOpenTracking;

  const UpcomingAppointmentDetailsArgs({
    required this.appointment,
    required this.providerName,
    required this.serviceName,
    required this.address,
    required this.start,
    required this.dateTimeLabel,
    required this.timeLabel,
    required this.isOverdue,
    required this.isVeryClose,
    required this.remainingLabel,
    required this.leaveInLabel,
    required this.distanceKm,
    required this.travelTimeMin,
    required this.canOpenTracking,
  });
}

class UpcomingAppointmentDetailsScreen extends StatelessWidget {
  final UpcomingAppointmentDetailsArgs args;

  const UpcomingAppointmentDetailsScreen({super.key, required this.args});

  String _buildStatusLabel() {
    if (args.isOverdue) return 'Agendamento em andamento';
    if (args.isVeryClose) return 'Saia em breve';
    return 'Proximo compromisso';
  }

  Color _accentColor() {
    if (args.isOverdue) return Colors.grey.shade700;
    if (args.isVeryClose) return const Color(0xFFDC2626);
    return AppTheme.primaryBlue;
  }

  Color _surfaceColor() {
    if (args.isOverdue) return const Color(0xFFF2F3F5);
    if (args.isVeryClose) return const Color(0xFFFFF1F2);
    return const Color(0xFFF4F8FF);
  }

  String _serviceId() {
    return (args.appointment['service_id'] ??
            args.appointment['agendamento_servico_id'] ??
            args.appointment['service_request_id'] ??
            '')
        .toString();
  }

  String _trackingSummaryText() {
    if (args.canOpenTracking) {
      return 'O acompanhamento já está liberado. Abra a tela completa para ver status, chegada e atualizações do atendimento.';
    }
    return 'O acompanhamento ao vivo abre 30 minutos antes do horário marcado. Até lá, esta tela mostra o resumo do seu agendamento.';
  }

  String _trackingButtonLabel() {
    return args.canOpenTracking
        ? 'Abrir acompanhamento'
        : 'Acompanhamento libera 30 min antes';
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColor();
    final serviceId = _serviceId();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Proximo agendamento'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _surfaceColor(),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: accentColor.withValues(alpha: 0.16)),
              ),
              child: Column(
                children: [
                  Icon(
                    args.isOverdue
                        ? Icons.history
                        : (args.isVeryClose
                              ? Icons.alarm
                              : Icons.event_available),
                    color: accentColor,
                    size: 34,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _buildStatusLabel(),
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    args.serviceName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.darkBlueText,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    args.providerName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.darkBlueText.withValues(alpha: 0.74),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    args.timeLabel,
                    style: TextStyle(
                      color: AppTheme.darkBlueText,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    args.dateTimeLabel,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Endereco do atendimento',
                    style: TextStyle(
                      color: AppTheme.darkBlueText,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    args.address.trim().isEmpty
                        ? 'Endereco nao informado'
                        : args.address,
                    style: TextStyle(
                      color: AppTheme.darkBlueText.withValues(alpha: 0.74),
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildInfoChip(
                  icon: Icons.schedule_rounded,
                  label: args.isOverdue
                      ? 'Servico em andamento ou atrasado'
                      : 'Falta ${args.remainingLabel}',
                ),
                _buildInfoChip(
                  icon: Icons.route_outlined,
                  label: '${args.distanceKm.toStringAsFixed(1)} km',
                ),
                _buildInfoChip(
                  icon: Icons.directions_car_filled_outlined,
                  label: '~${args.travelTimeMin} min',
                ),
                if (!args.isOverdue)
                  _buildInfoChip(
                    icon: Icons.alarm_rounded,
                    label: 'Saia em ${args.leaveInLabel}',
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acompanhamento do agendamento',
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _trackingSummaryText(),
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: serviceId.isEmpty
                    ? null
                    : () {
                        if (!args.canOpenTracking) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'O acompanhamento ao vivo libera 30 minutos antes do horário agendado.',
                              ),
                            ),
                          );
                          return;
                        }
                        context.push('/scheduled-service/$serviceId');
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _trackingButtonLabel(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
