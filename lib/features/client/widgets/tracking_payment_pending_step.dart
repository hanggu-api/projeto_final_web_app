import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/ad_carousel.dart';

class TrackingPaymentPendingStep extends StatelessWidget {
  final bool realtimeDegraded;
  final bool hasPixLoaded;
  final bool inSecurePaymentPhase;
  final double securePaymentAmount;
  final bool isLoadingPix;
  final String? lastPixErrorMessage;
  final String? lastPixErrorTraceId;
  final VoidCallback onRetryPix;
  final double pixDisplayAmount;
  final String pixDisplayLabel;
  final Widget qrWidget;
  final String? pixPayload;
  final String pixPayloadForQr;
  final VoidCallback onCopyPix;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final bool cancelBlockedByProximity;
  final VoidCallback onCancelService;

  const TrackingPaymentPendingStep({
    super.key,
    required this.realtimeDegraded,
    required this.hasPixLoaded,
    required this.inSecurePaymentPhase,
    required this.securePaymentAmount,
    required this.isLoadingPix,
    required this.lastPixErrorMessage,
    required this.lastPixErrorTraceId,
    required this.onRetryPix,
    required this.pixDisplayAmount,
    required this.pixDisplayLabel,
    required this.qrWidget,
    required this.pixPayload,
    required this.pixPayloadForQr,
    required this.onCopyPix,
    this.primaryActionLabel,
    this.onPrimaryAction,
    required this.cancelBlockedByProximity,
    required this.onCancelService,
  });

  Widget _flowStep({
    required String index,
    required String title,
    required String subtitle,
  }) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            index,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPayload = (pixPayload?.trim().isNotEmpty ?? false);
    final showInlinePixContent = onPrimaryAction == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showInlinePixContent && realtimeDegraded && hasPixLoaded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Text(
              'Conexão instável. Mantendo QR carregado enquanto reconecta...',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.orange.shade900,
              ),
            ),
          ),
        if (inSecurePaymentPhase && securePaymentAmount > 0) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.shield, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Pague 70% quando prestador chegar: R\$ ${securePaymentAmount.toStringAsFixed(2).replaceAll('.', ',')}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (showInlinePixContent && isLoadingPix)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(),
          ),
        if (showInlinePixContent &&
            !isLoadingPix &&
            !hasPixLoaded &&
            (lastPixErrorMessage?.trim().isNotEmpty ?? false))
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Erro ao carregar PIX',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  lastPixErrorMessage!,
                  style: const TextStyle(fontSize: 12),
                ),
                if ((lastPixErrorTraceId ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Trace: $lastPixErrorTraceId',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onRetryPix,
                    icon: const Icon(LucideIcons.refreshCcw, size: 16),
                    label: const Text('Tentar novamente'),
                  ),
                ),
              ],
            ),
          ),
        if (pixDisplayAmount > 0) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                Text(
                  pixDisplayLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      LucideIcons.wallet,
                      size: 18,
                      color: Colors.black87,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'R\$ ${pixDisplayAmount.toStringAsFixed(2).replaceAll('.', ',')}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (showInlinePixContent)
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: qrWidget,
            ),
          ),
        if (showInlinePixContent && hasPixLoaded) const SizedBox(height: 8),
        if (showInlinePixContent && hasPayload) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              pixPayload!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: onCopyPix,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: Colors.black.withOpacity(0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(LucideIcons.copy, size: 20),
              label: const Text(
                'PIX Copiar e Colar',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
        if (!showInlinePixContent &&
            onPrimaryAction != null &&
            (primaryActionLabel ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: onPrimaryAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: Colors.black.withOpacity(0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(LucideIcons.qrCode, size: 20),
              label: Text(
                primaryActionLabel!,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                child: _flowStep(
                  index: '1',
                  title: 'Entrada',
                  subtitle: 'Pague 30% para reservar',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _flowStep(
                  index: '2',
                  title: 'Serviço',
                  subtitle: 'Prestador vai até você',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _flowStep(
                  index: '3',
                  title: 'Final',
                  subtitle: 'Pague 70% quando prestador chegar',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blueGrey.shade100),
          ),
          child: const Text(
            'O prestador só recebe da plataforma após você confirmar serviço feito.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const AdCarousel(
          placement: 'tracking-banner',
          appContext: 'service-tracking',
          height: 180,
        ),
        const SizedBox(height: 12),
        if (!cancelBlockedByProximity)
          ElevatedButton(
            onPressed: onCancelService,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.errorRed,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(color: AppTheme.errorRed.withOpacity(0.25)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'CANCELAR (SEM CUSTO)',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          )
        else
          Container(
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
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}
