import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';

class ScheduleProposalBubble extends StatelessWidget {
  final DateTime scheduledDate;
  final bool isMe;
  final VoidCallback? onConfirm;
  final bool isConfirming;
  final bool showAction;

  const ScheduleProposalBubble({
    super.key,
    required this.scheduledDate,
    required this.isMe,
    this.onConfirm,
    this.isConfirming = false,
    this.showAction = true,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat("dd/MM 'às' HH:mm", 'pt_BR');
    final dateStr = fmt.format(scheduledDate);

    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Proposta de Agendamento',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.grey[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            dateStr,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          if (showAction) ...[
            SizedBox(
              width: double.infinity,
              height: 36,
              child: ElevatedButton(
                onPressed: isConfirming ? null : onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryPurple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: isConfirming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Confirmar',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ] else
            Text(
              'Aguardando confirmação do cliente...',
              style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }
}
