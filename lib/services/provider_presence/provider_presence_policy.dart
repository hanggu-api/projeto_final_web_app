enum ProviderPresenceTickResult {
  sent,
  skippedOffline,
  skippedFixedProvider,
  missingCoords,
  networkUnavailable,
  failed,
}

class ProviderPresenceDecision {
  const ProviderPresenceDecision({
    required this.result,
    required this.shouldSendHeartbeat,
    required this.shouldTouchLastSeen,
    required this.keepsProviderOnline,
  });

  final ProviderPresenceTickResult result;
  final bool shouldSendHeartbeat;
  final bool shouldTouchLastSeen;
  final bool keepsProviderOnline;
}

class ProviderPresencePolicy {
  const ProviderPresencePolicy._();

  static ProviderPresenceDecision resolve({
    required bool onlineForDispatch,
    required bool isFixedLocation,
    required bool canAttemptBackend,
    required bool hasCoords,
    bool allowFixedProviders = false,
  }) {
    if (!onlineForDispatch) {
      return const ProviderPresenceDecision(
        result: ProviderPresenceTickResult.skippedOffline,
        shouldSendHeartbeat: false,
        shouldTouchLastSeen: false,
        keepsProviderOnline: false,
      );
    }

    if (!canAttemptBackend) {
      return const ProviderPresenceDecision(
        result: ProviderPresenceTickResult.networkUnavailable,
        shouldSendHeartbeat: false,
        shouldTouchLastSeen: false,
        keepsProviderOnline: true,
      );
    }

    if (isFixedLocation && !allowFixedProviders) {
      return const ProviderPresenceDecision(
        result: ProviderPresenceTickResult.skippedFixedProvider,
        shouldSendHeartbeat: false,
        shouldTouchLastSeen: true,
        keepsProviderOnline: true,
      );
    }

    if (!hasCoords) {
      return const ProviderPresenceDecision(
        result: ProviderPresenceTickResult.missingCoords,
        shouldSendHeartbeat: false,
        shouldTouchLastSeen: true,
        keepsProviderOnline: true,
      );
    }

    return const ProviderPresenceDecision(
      result: ProviderPresenceTickResult.sent,
      shouldSendHeartbeat: true,
      shouldTouchLastSeen: false,
      keepsProviderOnline: true,
    );
  }
}
