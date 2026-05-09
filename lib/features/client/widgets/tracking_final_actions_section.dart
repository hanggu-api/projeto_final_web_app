import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class TrackingFinalActionsSection extends StatelessWidget {
  final Widget? disputeAnalysisCard;
  final bool showConfirm;
  final bool isConfirmingService;
  final VoidCallback onConfirmService;
  final VoidCallback onOpenComplaint;
  final bool showCompletedMessage;
  final bool canCancel;
  final VoidCallback onCancelService;

  const TrackingFinalActionsSection({
    super.key,
    this.disputeAnalysisCard,
    required this.showConfirm,
    required this.isConfirmingService,
    required this.onConfirmService,
    required this.onOpenComplaint,
    required this.showCompletedMessage,
    required this.canCancel,
    required this.onCancelService,
  });

  @override
  Widget build(BuildContext context) {
    if (disputeAnalysisCard != null) {
      return disputeAnalysisCard!;
    }

    if (showConfirm) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isConfirmingService ? null : onConfirmService,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(vertical: 26),
              ),
              child: const Text(
                'CONFIRMAR SERVIÇO',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onOpenComplaint,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.errorRed,
                side: BorderSide(color: AppTheme.errorRed.withOpacity(0.35)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'ABRIR RECLAMAÇÃO',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      );
    }

    if (showCompletedMessage) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: const Text(
          'Serviço finalizado com sucesso.',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.green),
        ),
      );
    }

    if (canCancel) {
      return ElevatedButton(
        onPressed: onCancelService,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryYellow,
          foregroundColor: Colors.black,
          elevation: 10,
          shadowColor: AppTheme.primaryYellow.withOpacity(0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        child: const Text(
          'CANCELAR SOLICITAÇÃO',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: const Text(
        'Cancelamento indisponível: prestador a menos de 100m.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
