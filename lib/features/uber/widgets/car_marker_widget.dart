import 'package:flutter/material.dart';
import 'dart:math';

/// Widget que desenha um carro visto de cima usando CustomPainter.
/// Permite definir a cor do carro e a rotação (heading).
class CarMarkerWidget extends StatelessWidget {
  final Color carColor;
  final double heading; // em graus (0 = norte, 90 = leste)
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
    return Transform.rotate(
      angle: heading * pi / 180,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: isMoto
              ? _MotoPainter(color: carColor)
              : _CarTopViewPainter(color: carColor),
        ),
      ),
    );
  }
}

class _CarTopViewPainter extends CustomPainter {
  final Color color;
  _CarTopViewPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sombra
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.18, h * 0.12, w * 0.64, h * 0.78),
        Radius.circular(w * 0.18),
      ),
      shadowPaint,
    );

    // Corpo do carro
    final bodyPaint = Paint()..color = color;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.2, h * 0.1, w * 0.6, h * 0.8),
      Radius.circular(w * 0.16),
    );
    canvas.drawRRect(bodyRect, bodyPaint);

    // Contorno
    final outlinePaint = Paint()
      ..color = _darken(color, 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(bodyRect, outlinePaint);

    // Teto / Vidro dianteiro
    final glassPaint = Paint()
      ..color = Colors.lightBlueAccent.withValues(alpha: 0.5);
    final glassRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.28, h * 0.18, w * 0.44, h * 0.22),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(glassRect, glassPaint);

    // Vidro traseiro
    final rearGlassRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.28, h * 0.62, w * 0.44, h * 0.18),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(rearGlassRect, glassPaint);

    // Rodas
    final wheelPaint = Paint()..color = Colors.black87;
    // Frente esquerda
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.12, h * 0.2, w * 0.1, h * 0.14),
        Radius.circular(2),
      ),
      wheelPaint,
    );
    // Frente direita
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.78, h * 0.2, w * 0.1, h * 0.14),
        Radius.circular(2),
      ),
      wheelPaint,
    );
    // Traseira esquerda
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.12, h * 0.66, w * 0.1, h * 0.14),
        Radius.circular(2),
      ),
      wheelPaint,
    );
    // Traseira direita
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.78, h * 0.66, w * 0.1, h * 0.14),
        Radius.circular(2),
      ),
      wheelPaint,
    );

    // Faróis dianteiros
    final lightPaint = Paint()..color = Colors.yellow.shade200;
    canvas.drawCircle(Offset(w * 0.32, h * 0.13), w * 0.04, lightPaint);
    canvas.drawCircle(Offset(w * 0.68, h * 0.13), w * 0.04, lightPaint);

    // Lanternas traseiras
    final tailPaint = Paint()..color = Colors.red.shade400;
    canvas.drawCircle(Offset(w * 0.32, h * 0.87), w * 0.04, tailPaint);
    canvas.drawCircle(Offset(w * 0.68, h * 0.87), w * 0.04, tailPaint);
  }

  Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  @override
  bool shouldRepaint(covariant _CarTopViewPainter old) => old.color != color;
}

class _MotoPainter extends CustomPainter {
  final Color color;
  _MotoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sombra
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.32, h * 0.08, w * 0.36, h * 0.84),
        Radius.circular(w * 0.12),
      ),
      shadowPaint,
    );

    // Corpo da moto
    final bodyPaint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.35, h * 0.1, w * 0.3, h * 0.8),
        Radius.circular(w * 0.1),
      ),
      bodyPaint,
    );

    // Contorno
    final outlinePaint = Paint()
      ..color = _darken(color, 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.35, h * 0.1, w * 0.3, h * 0.8),
        Radius.circular(w * 0.1),
      ),
      outlinePaint,
    );

    // Roda dianteira
    final wheelPaint = Paint()..color = Colors.black87;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.12), width: w * 0.22, height: h * 0.1),
      wheelPaint,
    );
    // Roda traseira
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.88), width: w * 0.22, height: h * 0.1),
      wheelPaint,
    );

    // Guidão
    final handlePaint = Paint()
      ..color = Colors.grey.shade600
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.25, h * 0.2), Offset(w * 0.75, h * 0.2), handlePaint);

    // Farol
    final lightPaint = Paint()..color = Colors.yellow.shade200;
    canvas.drawCircle(Offset(w * 0.5, h * 0.08), w * 0.04, lightPaint);

    // Lanterna traseira
    final tailPaint = Paint()..color = Colors.red.shade400;
    canvas.drawRect(Rect.fromLTWH(w * 0.42, h * 0.92, w * 0.16, h * 0.03), tailPaint);
  }

  Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  @override
  bool shouldRepaint(covariant _MotoPainter old) => old.color != color;
}
