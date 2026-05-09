import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:service_101/core/theme/app_theme.dart';

class ProximityAlerts extends StatelessWidget {
  final bool showAlert500m;
  final bool showAlert100m;
  final bool showAlertArrived;
  final bool showPixDirectPaymentPrompt;
  final String? pixDirectAmountLabel;

  const ProximityAlerts({
    super.key,
    required this.showAlert500m,
    required this.showAlert100m,
    required this.showAlertArrived,
    this.showPixDirectPaymentPrompt = false,
    this.pixDirectAmountLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (showPixDirectPaymentPrompt)
          _buildAlert(
            icon: LucideIcons.qrCode,
            title: 'PAGUE DIRETO AO PRESTADOR (PIX)',
            subtitle: (pixDirectAmountLabel != null &&
                    pixDirectAmountLabel!.trim().isNotEmpty)
                ? 'Estamos chegando. Pague na maquininha do prestador • ${pixDirectAmountLabel!.trim()}'
                : 'Estamos chegando. Pague na maquininha do prestador',
            color: const Color(0xFF00BFA5),
            persistent: true,
          ),
        if (showAlert500m)
          _buildAlert(
            icon: LucideIcons.navigation,
            title: 'PRESTADOR PRÓXIMO',
            subtitle: 'O prestador está a menos de 500m',
            color: Colors.blueAccent,
          ),
        if (showAlert100m)
          _buildAlert(
            icon: LucideIcons.zap,
            title: 'QUASE LÁ',
            subtitle: 'O prestador está chegando agora',
            color: Colors.orangeAccent,
          ),
        if (showAlertArrived)
          _buildAlert(
            icon: LucideIcons.checkCircle,
            title: 'PRESTADOR NO LOCAL',
            subtitle: 'Vá até o local combinado com segurança',
            color: Colors.green,
            persistent: true,
          ),
      ],
    );
  }

  Widget _buildAlert({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    bool persistent = false,
  }) {
    return Positioned(
      top: 120,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.2), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().slideY(begin: -0.5, end: 0, duration: 400.ms).fadeIn(),
    );
  }
}
