import 'dart:async';
import 'dart:math';
import 'package:latlong2/latlong.dart';

/// Serviço legado de simulação de movimentação operacional.
/// Gera waypoints aleatórios pela cidade para apoio local de desenvolvimento.
class DriverSimulationService {
  Timer? _moveTimer;
  final Random _random = Random();

  // Estado da simulação
  bool _isRunning = false;
  LatLng _currentPosition;
  double _currentHeading = 0;
  int _currentWaypointIndex = 0;
  List<LatLng> _waypoints = [];

  // Estado legado do atendimento simulado
  SimulationTripState _tripState = SimulationTripState.idle;
  String? _passengerName;
  String? _pickupAddress;
  String? _dropoffAddress;

  // Callbacks
  Function(LatLng position, double heading)? onPositionUpdate;
  Function(SimulationTripState state, Map<String, dynamic> tripInfo)?
  onTripStateChange;

  // Nomes simulados
  static const _names = [
    'Maria Silva',
    'João Santos',
    'Ana Costa',
    'Pedro Oliveira',
    'Carla Souza',
    'Lucas Lima',
    'Fernanda Rocha',
    'Rafael Alves',
    'Juliana Mendes',
    'Bruno Pereira',
    'Camila Ferreira',
    'Diego Martins',
  ];

  // Ruas de Imperatriz-MA
  static const _streets = [
    'Av. Babaçulândia',
    'Rua Antônio Miranda',
    'Av. Dorgival Pinheiro',
    'Rua Ceará',
    'Av. Bernardo Sayão',
    'Rua Pernambuco',
    'Av. Getúlio Vargas',
    'Rua Goiás',
    'Av. Dom Pedro II',
    'Rua Paraíba',
    'Av. JK',
    'Rua Sergipe',
    'Rua Alagoas',
    'Av. Marechal Castelo Branco',
    'Rua Piauí',
    'Rua Santo Antônio',
    'Av. São Luís Rei de França',
    'Rua Maranhão',
  ];

  DriverSimulationService(this._currentPosition);

  bool get isRunning => _isRunning;
  SimulationTripState get tripState => _tripState;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _generateWaypoints();
    _startMoving();
  }

  void stop() {
    _isRunning = false;
    _moveTimer?.cancel();
    _moveTimer = null;
    _tripState = SimulationTripState.idle;
  }

  void _generateWaypoints() {
    // Gerar 8-12 pontos aleatórios ao redor da posição atual (raio ~2km)
    final count = 8 + _random.nextInt(5);
    _waypoints = List.generate(count, (_) {
      final latOffset = (_random.nextDouble() - 0.5) * 0.04; // ~2km
      final lngOffset = (_random.nextDouble() - 0.5) * 0.04;
      return LatLng(
        _currentPosition.latitude + latOffset,
        _currentPosition.longitude + lngOffset,
      );
    });
    _currentWaypointIndex = 0;
  }

  void _startMoving() {
    // Move a cada 100ms para animação suave
    _moveTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_isRunning || _waypoints.isEmpty) return;
      _moveTowardsWaypoint();
    });

    // Iniciar primeira simulação após 2s
    Future.delayed(const Duration(seconds: 2), () {
      if (_isRunning) _startNewTrip();
    });
  }

  void _moveTowardsWaypoint() {
    final target = _waypoints[_currentWaypointIndex];
    final dx = target.longitude - _currentPosition.longitude;
    final dy = target.latitude - _currentPosition.latitude;
    final dist = sqrt(dx * dx + dy * dy);

    // Se chegou perto do waypoint, ir para o próximo
    if (dist < 0.0003) {
      _currentWaypointIndex++;
      if (_currentWaypointIndex >= _waypoints.length) {
        _generateWaypoints(); // Gerar novos waypoints
      }

      // Verificar se deve mudar o estado da simulação
      _checkTripProgress();
      return;
    }

    // Calcular heading (ângulo em graus, 0 = norte)
    final angle = atan2(dx, dy) * 180 / pi;
    _currentHeading = angle;

    // Mover suavemente (~30km/h ≈ 0.0001° por tick em 100ms)
    final speed = 0.00012;
    final moveX = (dx / dist) * speed;
    final moveY = (dy / dist) * speed;

    _currentPosition = LatLng(
      _currentPosition.latitude + moveY,
      _currentPosition.longitude + moveX,
    );

    onPositionUpdate?.call(_currentPosition, _currentHeading);
  }

  int _waypointsVisited = 0;

  void _checkTripProgress() {
    _waypointsVisited++;

    switch (_tripState) {
      case SimulationTripState.idle:
        // Após 2 waypoints sem atividade, iniciar uma nova simulação
        if (_waypointsVisited >= 2) {
          _startNewTrip();
          _waypointsVisited = 0;
        }
        break;
      case SimulationTripState.goingToPickup:
        // Após 2 waypoints, marca chegada ao ponto inicial simulado
        if (_waypointsVisited >= 2) {
          _arriveAtPickup();
          _waypointsVisited = 0;
        }
        break;
      case SimulationTripState.waitingPassenger:
        // Espera brevemente
        break;
      case SimulationTripState.inTrip:
        // Após 3 waypoints, "chegou" no destino
        if (_waypointsVisited >= 3) {
          _completeTrip();
          _waypointsVisited = 0;
        }
        break;
      case SimulationTripState.completed:
        // Após 1 waypoint, voltar a idle
        if (_waypointsVisited >= 1) {
          _tripState = SimulationTripState.idle;
          _waypointsVisited = 0;
        }
        break;
    }
  }

  void _startNewTrip() {
    _passengerName = _names[_random.nextInt(_names.length)];
    _pickupAddress =
        '${_streets[_random.nextInt(_streets.length)]}, ${100 + _random.nextInt(2000)}';
    _dropoffAddress =
        '${_streets[_random.nextInt(_streets.length)]}, ${100 + _random.nextInt(2000)}';

    _tripState = SimulationTripState.goingToPickup;
    _waypointsVisited = 0;

    final price = 8.0 + _random.nextDouble() * 25.0;
    final distance = 1.5 + _random.nextDouble() * 8.0;

    onTripStateChange?.call(_tripState, {
      'passenger': _passengerName,
      'pickup': _pickupAddress,
      'dropoff': _dropoffAddress,
      'price': price.toStringAsFixed(2),
      'distance': '${distance.toStringAsFixed(1)} km',
      'eta': '${2 + _random.nextInt(8)} min',
    });
  }

  void _arriveAtPickup() {
    _tripState = SimulationTripState.waitingPassenger;
    onTripStateChange?.call(_tripState, {
      'passenger': _passengerName,
      'pickup': _pickupAddress,
      'dropoff': _dropoffAddress,
    });

    // Continuação da simulação após 2 segundos
    Future.delayed(const Duration(seconds: 2), () {
      if (!_isRunning) return;
      _tripState = SimulationTripState.inTrip;
      _waypointsVisited = 0;
      onTripStateChange?.call(_tripState, {
        'passenger': _passengerName,
        'pickup': _pickupAddress,
        'dropoff': _dropoffAddress,
      });
    });
  }

  void _completeTrip() {
    _tripState = SimulationTripState.completed;
    final price = 8.0 + _random.nextDouble() * 25.0;
    onTripStateChange?.call(_tripState, {
      'passenger': _passengerName,
      'price': 'R\$ ${price.toStringAsFixed(2)}',
    });
  }

  void dispose() {
    stop();
  }
}

enum SimulationTripState {
  idle,
  goingToPickup,
  waitingPassenger,
  inTrip,
  completed,
}
