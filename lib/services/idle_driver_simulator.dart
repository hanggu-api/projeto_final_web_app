import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'map_service.dart';

/// Represents a ghost car moving on the map to give the app a "live" feel.
class SimulatedCar {
  final String id;
  LatLng position;
  double heading;

  // Route following data
  List<LatLng> currentRoute = [];
  int currentRouteIndex = 0;
  bool isFetchingRoute = false;

  // Reduced speed for more realistic city movement
  final double speed = 0.00003; // Approx 3m per tick

  SimulatedCar({
    required this.id,
    required this.position,
    required this.heading,
  });
}

class IdleDriverSimulator {
  Timer? _timer;
  final Random _random = Random();
  final List<SimulatedCar> _cars = [];
  LatLng? _center;

  // Callbacks
  Function(List<SimulatedCar> cars)? onCarsUpdated;

  void start(LatLng center, {int carCount = 4}) {
    _center = center;
    _cars.clear();

    // Spawn cars around the center
    for (int i = 0; i < carCount; i++) {
      final startPos = _generatePositionAround(center, maxRadiusDegrees: 0.015);

      final car = SimulatedCar(
        id: 'sim_$i',
        position: startPos,
        heading: _random.nextDouble() * 360,
      );
      _cars.add(car);

      // Fetch initial route
      _assignNewRoute(car);
    }

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), _updateCars);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _cars.clear();
  }

  Future<void> _assignNewRoute(SimulatedCar car) async {
    if (_center == null) return;

    car.isFetchingRoute = true;
    final targetPos = _generatePositionAround(_center!, maxRadiusDegrees: 0.02);

    try {
      final routePoints = await MapService().getRoutePoints(
        car.position,
        targetPos,
      );
      if (routePoints.isNotEmpty) {
        car.currentRoute = routePoints;
        car.currentRouteIndex = 0;
      }
    } catch (e) {
      debugPrint('Failed to get idle car route: $e');
    } finally {
      car.isFetchingRoute = false;
    }
  }

  void _updateCars(Timer timer) {
    if (_center == null) return;

    for (var car in _cars) {
      if (car.isFetchingRoute) continue;

      if (car.currentRoute.isEmpty ||
          car.currentRouteIndex >= car.currentRoute.length) {
        // Reached end of route, get a new one
        _assignNewRoute(car);
        continue;
      }

      final targetNode = car.currentRoute[car.currentRouteIndex];
      final dx = targetNode.longitude - car.position.longitude;
      final dy = targetNode.latitude - car.position.latitude;
      final distStr = sqrt(dx * dx + dy * dy);

      // If reached target node (or very close), shift to next node
      if (distStr < 0.0001) {
        car.currentRouteIndex++;
        continue;
      }

      // Move towards target node
      final moveX = (dx / distStr) * car.speed;
      final moveY = (dy / distStr) * car.speed;

      car.position = LatLng(
        car.position.latitude + moveY,
        car.position.longitude + moveX,
      );

      // Smoothly adjust heading
      final targetHeading = _calculateHeading(car.position, targetNode);
      car.heading = _lerpHeading(car.heading, targetHeading, 0.2);
    }

    onCarsUpdated?.call(_cars);
  }

  LatLng _generatePositionAround(
    LatLng center, {
    double maxRadiusDegrees = 0.02,
  }) {
    // Generate roughly within a 1.5km to 2km radius
    final latOffset = (_random.nextDouble() * 2 - 1) * maxRadiusDegrees;
    final lngOffset = (_random.nextDouble() * 2 - 1) * maxRadiusDegrees;
    return LatLng(center.latitude + latOffset, center.longitude + lngOffset);
  }

  double _calculateHeading(LatLng start, LatLng end) {
    final dx = end.longitude - start.longitude;
    final dy = end.latitude - start.latitude;
    // atan2 is y, x but for map (where North is Up)
    // standard math angle 0 is Right (East), 90 is Up (North)
    final angleRad = atan2(dx, dy);
    return angleRad * 180 / pi;
  }

  double _lerpHeading(double current, double target, double t) {
    // Shortest path interpolation for angles
    double diff = target - current;
    while (diff < -180) {
      diff += 360;
    }
    while (diff > 180) {
      diff -= 360;
    }
    return current + diff * t;
  }
}
