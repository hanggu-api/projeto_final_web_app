class FixedBookingPendingPixState {
  String? intentId;
  String? payload;
  String? image;
  double fee;
  bool visible;
  bool pendingProviderAutoScrollArmed;

  FixedBookingPendingPixState({
    this.intentId,
    this.payload,
    this.image,
    this.fee = 0,
    this.visible = false,
    this.pendingProviderAutoScrollArmed = false,
  });

  bool get hasIntent => (intentId ?? '').trim().isNotEmpty;
  bool get hasPayload => (payload ?? '').trim().isNotEmpty;

  void clear() {
    intentId = null;
    payload = null;
    image = null;
    fee = 0;
    visible = false;
    pendingProviderAutoScrollArmed = false;
  }
}
