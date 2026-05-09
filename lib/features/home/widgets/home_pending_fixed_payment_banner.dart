import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';

class HomePendingFixedPaymentBanner extends StatefulWidget {
  final String scheduleLabel;
  final String compactSummary;
  final String providerName;
  final String serviceLabel;
  final String upfrontValueLabel;
  final String? address;
  final VoidCallback onOpenPayment;
  final VoidCallback onRefreshNeeded;
  final Map<String, dynamic> details;

  const HomePendingFixedPaymentBanner({
    super.key,
    required this.scheduleLabel,
    required this.compactSummary,
    required this.providerName,
    required this.serviceLabel,
    required this.upfrontValueLabel,
    required this.address,
    required this.onOpenPayment,
    required this.onRefreshNeeded,
    required this.details,
  });

  @override
  State<HomePendingFixedPaymentBanner> createState() =>
      _HomePendingFixedPaymentBannerState();
}

class _HomePendingFixedPaymentBannerState
    extends State<HomePendingFixedPaymentBanner> {
  Widget _buildPendingInfoChip({
    required IconData icon,
    required String label,
    Color? backgroundColor,
    Color? textColor,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor ?? Colors.grey.shade700),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: textColor ?? Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedProviderName = widget.providerName.isEmpty
        ? 'Estabelecimento parceiro'
        : widget.providerName;
    final resolvedAddress = (widget.address ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: widget.onOpenPayment,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFF7D6), Colors.white],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: AppTheme.primaryYellow.withValues(alpha: 0.58),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFC98E12).withValues(alpha: 0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pix, color: Colors.white, size: 12),
                              SizedBox(width: 6),
                              Text(
                                'Pagamento pendente',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildPendingInfoChip(
                          icon: Icons.event_outlined,
                          label: widget.scheduleLabel,
                          backgroundColor: Colors.white,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Horario pre-reservado aguardando Pix',
                      style: TextStyle(
                        color: AppTheme.darkBlueText,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.compactSummary,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.darkBlueText.withValues(alpha: 0.74),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFF111827),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.storefront_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  resolvedProviderName,
                                  style: TextStyle(
                                    color: AppTheme.darkBlueText,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.serviceLabel,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppTheme.darkBlueText.withValues(
                                      alpha: 0.68,
                                    ),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildPendingInfoChip(
                          icon: Icons.payments_outlined,
                          label: widget.upfrontValueLabel,
                          backgroundColor: Colors.white,
                        ),
                        if (resolvedAddress.isNotEmpty)
                          _buildPendingInfoChip(
                            icon: Icons.location_on_outlined,
                            label: resolvedAddress,
                            backgroundColor: Colors.white,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.onOpenPayment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF111827),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(LucideIcons.qrCode, size: 18),
                            label: const Text('Abrir pagamento'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
