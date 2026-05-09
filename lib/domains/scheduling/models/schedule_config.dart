class ScheduleConfig {
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String? breakStart;
  final String? breakEnd;
  final int slotDuration;
  final bool isEnabled;

  const ScheduleConfig({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.breakStart,
    this.breakEnd,
    this.slotDuration = 30,
    this.isEnabled = true,
  });

  Map<String, dynamic> toMap() => {
    'day_of_week': dayOfWeek,
    'start_time': startTime,
    'end_time': endTime,
    'break_start': breakStart,
    'break_end': breakEnd,
    'lunch_start': breakStart,
    'lunch_end': breakEnd,
    'slot_duration': slotDuration,
    'is_enabled': isEnabled,
  };

  factory ScheduleConfig.fromMap(Map<String, dynamic> map) => ScheduleConfig(
    dayOfWeek: map['day_of_week'] as int,
    startTime: map['start_time']?.toString() ?? '08:00:00',
    endTime: map['end_time']?.toString() ?? '18:00:00',
    breakStart: (map['break_start'] ?? map['lunch_start'])?.toString(),
    breakEnd: (map['break_end'] ?? map['lunch_end'])?.toString(),
    slotDuration: (map['slot_duration'] as num?)?.toInt() ?? 30,
    isEnabled: map['is_enabled'] as bool? ?? true,
  );
}
