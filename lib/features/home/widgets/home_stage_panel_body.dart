import 'package:flutter/material.dart';

import '../models/home_stage.dart';

class HomeStagePanelBody extends StatelessWidget {
  final HomeStage stage;
  final bool isSearchMode;
  final bool hasBlockingService;
  final Widget? searchModeHeader;
  final Widget? pendingFixedPaymentBanner;
  final Widget? upcomingAppointmentBanner;
  final Widget searchBar;
  final Widget? waitingServiceBanner;
  final Widget? searchModeEmptyState;
  final Widget? adCarousel;
  final Widget? professionGroups;
  final Widget? exploreEntryCard;
  final Widget? savedPlaces;
  final double bottomSpacing;

  const HomeStagePanelBody({
    super.key,
    required this.stage,
    required this.isSearchMode,
    required this.hasBlockingService,
    this.searchModeHeader,
    this.pendingFixedPaymentBanner,
    this.upcomingAppointmentBanner,
    required this.searchBar,
    this.waitingServiceBanner,
    this.searchModeEmptyState,
    this.adCarousel,
    this.professionGroups,
    this.exploreEntryCard,
    this.savedPlaces,
    required this.bottomSpacing,
  });

  @override
  Widget build(BuildContext context) {
    final isSearchStage = stage == HomeStage.search;
    final isDefaultLikeStage =
        stage == HomeStage.defaultPanel ||
        stage == HomeStage.pendingFixedPayment ||
        stage == HomeStage.upcomingAppointment ||
        stage == HomeStage.activeService ||
        stage == HomeStage.mixed;

    return Column(
      children: [
        if (isSearchStage && searchModeHeader != null) searchModeHeader!,
        if (!hasBlockingService) ...[
          if (isDefaultLikeStage && pendingFixedPaymentBanner != null)
            pendingFixedPaymentBanner!,
          if (isDefaultLikeStage && upcomingAppointmentBanner != null)
            upcomingAppointmentBanner!,
          searchBar,
          if (isDefaultLikeStage && waitingServiceBanner != null)
            waitingServiceBanner!,
        ],
        if (isSearchStage && searchModeEmptyState != null)
          searchModeEmptyState!,
        if (isSearchStage) const SizedBox(height: 8),
        if (isDefaultLikeStage) const SizedBox(height: 6),
        if (isDefaultLikeStage && adCarousel != null) adCarousel!,
        if (isDefaultLikeStage) const SizedBox(height: 12),
        if (isDefaultLikeStage &&
            !hasBlockingService &&
            professionGroups != null)
          professionGroups!,
        if (isDefaultLikeStage &&
            !hasBlockingService &&
            exploreEntryCard != null)
          exploreEntryCard!,
        if (isDefaultLikeStage && !hasBlockingService && savedPlaces != null)
          savedPlaces!,
        SizedBox(height: bottomSpacing),
      ],
    );
  }
}
