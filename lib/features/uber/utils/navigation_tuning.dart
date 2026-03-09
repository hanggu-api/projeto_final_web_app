enum NavigationProfile { urban, highway }

class NavigationTuning {
  final double courseMinDistanceMeters;
  final double courseSpeedThresholdMps;
  final double headingSmoothingLowSpeed;
  final double headingSmoothingCruise;
  final double headingSmoothingFast;
  final double highwayEnterSpeedMps;
  final double highwayExitSpeedMps;

  const NavigationTuning({
    required this.courseMinDistanceMeters,
    required this.courseSpeedThresholdMps,
    required this.headingSmoothingLowSpeed,
    required this.headingSmoothingCruise,
    required this.headingSmoothingFast,
    required this.highwayEnterSpeedMps,
    required this.highwayExitSpeedMps,
  });

  static const NavigationTuning urban = NavigationTuning(
    courseMinDistanceMeters: 3.0,
    courseSpeedThresholdMps: 1.8,
    headingSmoothingLowSpeed: 0.20,
    headingSmoothingCruise: 0.32,
    headingSmoothingFast: 0.40,
    highwayEnterSpeedMps: 12.5, // ~45 km/h
    highwayExitSpeedMps: 10.0, // ~36 km/h
  );

  static const NavigationTuning highway = NavigationTuning(
    courseMinDistanceMeters: 4.5,
    courseSpeedThresholdMps: 2.4,
    headingSmoothingLowSpeed: 0.16,
    headingSmoothingCruise: 0.26,
    headingSmoothingFast: 0.34,
    highwayEnterSpeedMps: 12.5,
    highwayExitSpeedMps: 10.0,
  );
}
