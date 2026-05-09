enum SlotStatus { free, booked, lunch }

class ScheduleSlot {
  final DateTime startTime;
  final DateTime endTime;
  final SlotStatus status;
  final bool isSelectable;
  final bool isManualBlock;
  final bool isSlotHold;
  final int providerId;
  final Map<String, dynamic>? appointment;

  const ScheduleSlot({
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.isSelectable,
    required this.providerId,
    this.isManualBlock = false,
    this.isSlotHold = false,
    this.appointment,
  });

  Map<String, dynamic> toMap() => {
    'start_time': startTime.toIso8601String(),
    'end_time': endTime.toIso8601String(),
    'status': status.name,
    'is_selectable': isSelectable,
    'is_manual_block': isManualBlock,
    'is_slot_hold': isSlotHold,
    'provider_id': providerId,
    if (appointment != null) 'appointment': appointment,
  };
}
