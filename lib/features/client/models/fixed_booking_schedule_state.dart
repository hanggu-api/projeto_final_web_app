class FixedBookingScheduleState {
  DateTime? selectedDate;
  String? selectedTimeSlot;
  List<Map<String, dynamic>> realSlots;
  bool loadingSlots;

  FixedBookingScheduleState({
    this.selectedDate,
    this.selectedTimeSlot,
    List<Map<String, dynamic>>? realSlots,
    this.loadingSlots = false,
  }) : realSlots = realSlots ?? [];

  bool get hasSelectedSlot =>
      selectedDate != null && (selectedTimeSlot ?? '').trim().isNotEmpty;

  void clearSelection({bool clearDate = false}) {
    if (clearDate) {
      selectedDate = null;
    }
    selectedTimeSlot = null;
    realSlots = [];
  }
}
