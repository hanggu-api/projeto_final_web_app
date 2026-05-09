import 'schedule_config.dart';

class ScheduleConfigResult {
  final int providerId;
  final String? providerUid;
  final List<ScheduleConfig> configs;
  final bool usedLegacyFallback;
  final bool foundProviderSchedules;

  const ScheduleConfigResult({
    required this.providerId,
    required this.providerUid,
    required this.configs,
    required this.usedLegacyFallback,
    required this.foundProviderSchedules,
  });

  bool get hasAnyConfig => configs.isNotEmpty;
  int get configCount => configs.length;

  static const empty = ScheduleConfigResult(
    providerId: 0,
    providerUid: null,
    configs: [],
    usedLegacyFallback: false,
    foundProviderSchedules: false,
  );
}
