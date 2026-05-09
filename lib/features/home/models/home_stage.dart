enum HomeStage {
  defaultPanel,
  search,
  activeService,
  pendingFixedPayment,
  upcomingAppointment,
  mixed,
}

class HomeStageSnapshot {
  final HomeStage stage;
  final bool isSearchMode;
  final bool showPendingFixedPaymentBanner;
  final bool showUpcomingAppointmentBanner;
  final bool showWaitingServiceBanner;
  final bool hasBlockingService;

  const HomeStageSnapshot({
    required this.stage,
    required this.isSearchMode,
    required this.showPendingFixedPaymentBanner,
    required this.showUpcomingAppointmentBanner,
    required this.showWaitingServiceBanner,
    required this.hasBlockingService,
  });
}

class HomeStageResolver {
  static HomeStageSnapshot resolve({
    required bool isSearchMode,
    required bool hasPendingFixedPaymentBanner,
    required bool hasUpcomingAppointment,
    required bool showWaitingServiceBanner,
  }) {
    if (isSearchMode) {
      return const HomeStageSnapshot(
        stage: HomeStage.search,
        isSearchMode: true,
        showPendingFixedPaymentBanner: false,
        showUpcomingAppointmentBanner: false,
        showWaitingServiceBanner: false,
        hasBlockingService: false,
      );
    }

    final visibleCount = [
      hasPendingFixedPaymentBanner,
      hasUpcomingAppointment,
      showWaitingServiceBanner,
    ].where((value) => value).length;

    final HomeStage stage;
    if (showWaitingServiceBanner) {
      stage = visibleCount > 1 ? HomeStage.mixed : HomeStage.activeService;
    } else if (hasPendingFixedPaymentBanner) {
      stage = visibleCount > 1
          ? HomeStage.mixed
          : HomeStage.pendingFixedPayment;
    } else if (hasUpcomingAppointment) {
      stage = visibleCount > 1
          ? HomeStage.mixed
          : HomeStage.upcomingAppointment;
    } else {
      stage = HomeStage.defaultPanel;
    }

    return HomeStageSnapshot(
      stage: stage,
      isSearchMode: false,
      showPendingFixedPaymentBanner: hasPendingFixedPaymentBanner,
      showUpcomingAppointmentBanner: hasUpcomingAppointment,
      showWaitingServiceBanner: showWaitingServiceBanner,
      hasBlockingService: false,
    );
  }
}
