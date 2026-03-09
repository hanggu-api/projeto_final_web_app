import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:math';
import '../../../core/theme/app_theme.dart';

/// Marcador Premium para Motoristas (Carro/Moto)
/// Segue o design: Círculo amarelo, borda branca, sombra e ícone superior rotacionável.
class PremiumDriverMarker extends StatelessWidget {
  final double heading; // em graus (0 = norte, 90 = leste)
  final bool isMoto;
  final double size;
  final bool showPulse;
  final AnimationController? pulseController;
  final Color? pulseColor;

  const PremiumDriverMarker({
    super.key,
    this.heading = 0,
    this.isMoto = false,
    this.size = 48,
    this.showPulse = false,
    this.pulseController,
    this.pulseColor,
  });

  @override
  Widget build(BuildContext context) {
    // O ícone padrão do Lucide aponta para a direita (leste).
    // Compensamos -90° para alinhar heading 0° com o topo (norte).
    final visualHeading = heading - 90.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: visualHeading * (pi / 180),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Efeito de Pulso (opcional)
              if (showPulse && pulseController != null)
                ScaleTransition(
                  scale: Tween(begin: 1.0, end: 2.2).animate(
                    CurvedAnimation(
                      parent: pulseController!,
                      curve: Curves.easeOut,
                    ),
                  ),
                  child: FadeTransition(
                    opacity: Tween(begin: 0.6, end: 0.0).animate(
                      CurvedAnimation(
                        parent: pulseController!,
                        curve: Curves.easeOut,
                      ),
                    ),
                    child: Container(
                      width: size * 0.9,
                      height: size * 0.9,
                      decoration: BoxDecoration(
                        color: (pulseColor ?? AppTheme.primaryYellow)
                            .withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (pulseColor ?? AppTheme.primaryYellow)
                              .withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),

              // APENAS ÍCONE DO CARRO/MOTO (DESIGN LEVE)
              SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: Icon(
                    isMoto ? LucideIcons.bike : LucideIcons.car,
                    color: AppTheme.textDark, // Mantém preto premium
                    size: size * 0.85,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Widget legado mantido para compatibilidade se necessário, mas redirecionado
class CarMarkerWidget extends StatelessWidget {
  final Color carColor;
  final double heading;
  final bool isMoto;
  final double size;

  const CarMarkerWidget({
    super.key,
    required this.carColor,
    this.heading = 0,
    this.isMoto = false,
    this.size = 50,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumDriverMarker(heading: heading, isMoto: isMoto, size: size);
  }
}
