import 'package:flutter/material.dart';

enum SnapMarkerType { pickup, destination }

class SnapPinMarker extends StatelessWidget {
  final Color color;
  final double size;
  final SnapMarkerType type;

  const SnapPinMarker({
    super.key,
    required this.color,
    this.size = 48.0,
    this.type = SnapMarkerType.pickup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Colors.transparent),
      child: CustomPaint(
        size: Size(size, size),
        painter: _UberMarkerPainter(color: color, type: type),
      ),
    );
  }
}

class _UberMarkerPainter extends CustomPainter {
  final Color color;
  final SnapMarkerType type;

  _UberMarkerPainter({required this.color, required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width / 2;
    // A cabeça flutua no topo, a haste vai até o fundo (base do widget)
    final double headSize = size.width * 0.45;
    final double headCenterY = headSize / 2 + 2; // Pequeno respiro no topo
    final double stemBottomY = size.height;

    final paint = Paint()
      ..color = Colors
          .black // Uber usa marcadores pretos na Web/App moderno
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final stemPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    // 1. Desenhar a Haste (Stem)
    // A haste conecta a base da forma ao ponto exato no mapa (base do widget)
    canvas.drawLine(
      Offset(
        centerX,
        headCenterY +
            (type == SnapMarkerType.pickup ? headSize / 2 : headSize / 2),
      ),
      Offset(centerX, stemBottomY),
      stemPaint,
    );

    // 2. Desenhar a Cabeça (Head)
    if (type == SnapMarkerType.pickup) {
      // Círculo para Origem
      canvas.drawCircle(Offset(centerX, headCenterY), headSize / 2, paint);
      // Borda branca fina
      canvas.drawCircle(
        Offset(centerX, headCenterY),
        headSize / 2,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      // Ponto central branco
      canvas.drawCircle(Offset(centerX, headCenterY), 2.5, whitePaint);
    } else {
      // Quadrado para Destino
      final rect = Rect.fromCenter(
        center: Offset(centerX, headCenterY),
        width: headSize,
        height: headSize,
      );
      canvas.drawRect(rect, paint);
      // Borda branca fina
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      // Ponto central branco
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(centerX, headCenterY),
          width: 5,
          height: 5,
        ),
        whitePaint,
      );
    }

    // 3. Pequena sombra na base da haste para profundidade
    canvas.drawCircle(
      Offset(centerX, stemBottomY),
      2,
      Paint()..color = Colors.black.withOpacity(0.3),
    );
  }

  @override
  bool shouldRepaint(_UberMarkerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.type != type;
}
