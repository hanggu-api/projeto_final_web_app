import 'package:latlong2/latlong.dart' as ll;

class NavigationHelpers {
  static double? safeDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static ll.LatLng snapLocationToRoute({
    required ll.LatLng rawLocation,
    required List<ll.LatLng> route,
    required double maxDistanceMeters,
  }) {
    if (route.length < 2) return rawLocation;

    ll.LatLng? bestPoint;
    double bestDistance = double.infinity;

    for (int i = 0; i < route.length - 1; i++) {
      final projected = projectPointToSegment(rawLocation, route[i], route[i + 1]);
      final dist = const ll.Distance().as(ll.LengthUnit.Meter, rawLocation, projected);
      if (dist < bestDistance) {
        bestDistance = dist;
        bestPoint = projected;
      }
    }

    if (bestPoint == null || bestDistance > maxDistanceMeters) {
      return rawLocation;
    }
    return bestPoint;
  }

  static ll.LatLng projectPointToSegment(ll.LatLng p, ll.LatLng a, ll.LatLng b) {
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;
    final px = p.longitude;
    final py = p.latitude;

    final abx = bx - ax;
    final aby = by - ay;
    final ab2 = abx * abx + aby * aby;
    if (ab2 == 0) return a;

    final apx = px - ax;
    final apy = py - ay;
    final t = ((apx * abx + apy * aby) / ab2).clamp(0.0, 1.0);

    return ll.LatLng(ay + aby * t, ax + abx * t);
  }
}
