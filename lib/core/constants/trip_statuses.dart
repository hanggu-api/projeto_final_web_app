/// Trip request status constants.
abstract final class TripStatuses {
  static const searching = 'searching';
  static const pending = 'pending';
  static const openForSchedule = 'open_for_schedule';
  static const accepted = 'accepted';
  static const inProgress = 'in_progress';
  static const arrived = 'arrived';
  static const completed = 'completed';
  static const finished = 'finished';
  static const cancelled = 'cancelled';
  static const canceled =
      'canceled'; // Alternative spelling also used in backend
  static const waitingPayment = 'waiting_payment';
  static const scheduled = 'scheduled';
  static const clientDeparting = 'client_departing';
  static const clientArrived = 'client_arrived';
  static const deleted = 'deleted'; // Synthetic status for removed items
  static const notFound = 'not_found'; // Synthetic status for missing rows
}

/// Appointment/slot status constants.
abstract final class AppointmentStatuses {
  static const booked = 'booked';
  static const free = 'free';
  static const confirmed = 'confirmed';
  static const waitingPayment = 'waiting_payment';
}

/// Presence status constants.
abstract final class PresenceStatuses {
  static const online = 'online';
}

abstract final class ServiceStatusAliases {
  static const waitingPaymentRemaining = 'waiting_payment_remaining';
  static const waitingRemainingPayment = 'waiting_remaining_payment';
  static const awaitingConfirmation = 'awaiting_confirmation';
  static const waitingClientConfirmation = 'waiting_client_confirmation';
  static const completionRequested = 'completion_requested';
  static const searchingProvider = 'searching_provider';
  static const searchProvider = 'search_provider';
  static const waitingProvider = 'waiting_provider';
  static const scheduleProposed = 'schedule_proposed';
  static const contested = 'contested';
  static const refunded = 'refunded';
  static const expired = 'expired';
  static const closed = 'closed';
  static const concluidedLegacy = 'concluido';
  static const cancelledLegacy = 'cancelado';
}

abstract final class ServiceStatusSets {
  static const paymentRemaining = <String>{
    ServiceStatusAliases.waitingPaymentRemaining,
    ServiceStatusAliases.waitingRemainingPayment,
  };

  static const providerConcluding = <String>{
    ServiceStatusAliases.awaitingConfirmation,
    ServiceStatusAliases.waitingClientConfirmation,
    ServiceStatusAliases.completionRequested,
  };

  static const mobileActive = <String>{
    TripStatuses.waitingPayment,
    TripStatuses.pending,
    TripStatuses.searching,
    ServiceStatusAliases.searchingProvider,
    ServiceStatusAliases.searchProvider,
    ServiceStatusAliases.waitingProvider,
    TripStatuses.accepted,
    'provider_near',
    TripStatuses.arrived,
    TripStatuses.inProgress,
    ServiceStatusAliases.scheduleProposed,
    TripStatuses.scheduled,
    ServiceStatusAliases.waitingPaymentRemaining,
    ServiceStatusAliases.waitingRemainingPayment,
    ServiceStatusAliases.awaitingConfirmation,
    ServiceStatusAliases.waitingClientConfirmation,
    ServiceStatusAliases.completionRequested,
    ServiceStatusAliases.contested,
    TripStatuses.clientDeparting,
    TripStatuses.clientArrived,
  };

  static const clientHomeFallback = <String>{TripStatuses.openForSchedule};

  static const clientSearch = <String>{
    TripStatuses.searching,
    ServiceStatusAliases.searchingProvider,
    ServiceStatusAliases.searchProvider,
    ServiceStatusAliases.waitingProvider,
  };

  static const clientTracking = <String>{'awaiting_signal', ...mobileActive};

  static const inactiveTerminal = <String>{
    TripStatuses.completed,
    TripStatuses.finished,
    TripStatuses.cancelled,
    TripStatuses.canceled,
    ServiceStatusAliases.concluidedLegacy,
    ServiceStatusAliases.cancelledLegacy,
    ServiceStatusAliases.refunded,
    ServiceStatusAliases.expired,
    ServiceStatusAliases.closed,
    TripStatuses.deleted,
    TripStatuses.notFound,
  };
}

String normalizeServiceStatus(String? rawStatus) {
  return (rawStatus ?? '').toString().trim().toLowerCase();
}
