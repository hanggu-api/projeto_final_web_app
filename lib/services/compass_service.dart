import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class CompassService {
  StreamSubscription? _compassSubscription;
  StreamSubscription? _userAccelSubscription;

  double _smoothedHeading = 0.0;
  bool _isMoving = false;

  final StreamController<double> _headingController =
      StreamController<double>.broadcast();
  Stream<double> get headingStream => _headingController.stream;

  double get currentHeading => _smoothedHeading;

  void start() {
    if (kIsWeb) return;

    // 1. Ler a Bússola (Direção Magnética)
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        _updateHeading(event.heading!);
      }
    });

    // 2. Detectar se o usuário está em movimento (acelerômetro) para filtrar ruído
    // Nota: sensores_plus 6.x usa userAccelerometerEventStream()
    _userAccelSubscription = userAccelerometerEventStream().listen((event) {
      final force = event.x * event.x + event.y * event.y + event.z * event.z;
      _isMoving = force > 1.5; // Limiar simples de movimento
    });
  }

  void _updateHeading(double newHeading) {
    // Suavização (Low-pass filter) para evitar tremedeira
    // Se estiver parado, suaviza mais (0.1). Se movendo, responde mais rápido (0.4).
    final alpha = _isMoving ? 0.4 : 0.1;

    // Lógica para evitar giro de 360 graus no reset (normalize)
    double diff = newHeading - _smoothedHeading;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    _smoothedHeading = _smoothedHeading + diff * alpha;

    // Manter entre 0 e 360
    if (_smoothedHeading < 0) _smoothedHeading += 360;
    if (_smoothedHeading >= 360) _smoothedHeading -= 360;

    _headingController.add(_smoothedHeading);
  }

  void stop() {
    _compassSubscription?.cancel();
    _userAccelSubscription?.cancel();
    _headingController.close();
  }

  // Função utilitária para calcular o caminho mais curto de rotação
  static double normalizeHeading(double current, double target) {
    double diff = target - current;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return current + diff;
  }
}
