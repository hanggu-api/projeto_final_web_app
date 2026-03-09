import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

class NavigationMath {
  static final ll.Distance _distance = ll.Distance();

  static double normalizeDegrees(double angle) {
    final normalized = angle % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
  }

  static double shortestAngleDelta(double from, double to) {
    final delta =
        (normalizeDegrees(to) - normalizeDegrees(from) + 540.0) % 360.0 - 180.0;
    return delta;
  }

  static double lerpAngleDegrees(double from, double to, double alpha) {
    final clampedAlpha = alpha.clamp(0.0, 1.0);
    final delta = shortestAngleDelta(from, to);
    return normalizeDegrees(from + delta * clampedAlpha);
  }

  static double? courseBetween({
    required ll.LatLng from,
    required ll.LatLng to,
    double minDistanceMeters = 2.0,
  }) {
    final meters = _distance.as(ll.LengthUnit.Meter, from, to);
    if (!meters.isFinite || meters < minDistanceMeters) return null;

    final fromLat = from.latitude * math.pi / 180.0;
    final fromLng = from.longitude * math.pi / 180.0;
    final toLat = to.latitude * math.pi / 180.0;
    final toLng = to.longitude * math.pi / 180.0;
    final dLng = toLng - fromLng;

    final y = math.sin(dLng) * math.cos(toLat);
    final x =
        math.cos(fromLat) * math.sin(toLat) -
        math.sin(fromLat) * math.cos(toLat) * math.cos(dLng);

    return normalizeDegrees(math.atan2(y, x) * 180.0 / math.pi);
  }
}
