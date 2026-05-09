import 'package:flutter/material.dart';

class TrackingStageBody extends StatelessWidget {
  final Widget? searchingWidget;
  final Widget? providerJourneyWidget;
  final Widget? dispatchTimelineWidget;
  final Widget? completionCodeWidget;
  final Widget? pixWidget;
  final Widget? scheduleProposalWidget;
  final Widget? remainingPaidWidget;
  final Widget finalActionsWidget;

  const TrackingStageBody({
    super.key,
    this.searchingWidget,
    this.providerJourneyWidget,
    this.dispatchTimelineWidget,
    this.completionCodeWidget,
    this.pixWidget,
    this.scheduleProposalWidget,
    this.remainingPaidWidget,
    required this.finalActionsWidget,
  });

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];

    if (searchingWidget != null) {
      widgets.add(const SizedBox(height: 10));
      widgets.add(searchingWidget!);
    }

    widgets.add(const SizedBox(height: 14));

    if (providerJourneyWidget != null) {
      widgets.add(providerJourneyWidget!);
    }

    widgets.add(const SizedBox(height: 12));

    if (dispatchTimelineWidget != null) {
      widgets.add(dispatchTimelineWidget!);
      widgets.add(const SizedBox(height: 14));
    } else {
      widgets.add(const SizedBox(height: 4));
    }

    if (completionCodeWidget != null) {
      widgets.add(completionCodeWidget!);
      widgets.add(const SizedBox(height: 12));
    }

    if (pixWidget != null) {
      widgets.add(pixWidget!);
      widgets.add(const SizedBox(height: 6));
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgets,
      );
    }

    if (scheduleProposalWidget != null) {
      widgets.add(scheduleProposalWidget!);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgets,
      );
    }

    if (remainingPaidWidget != null) {
      widgets.add(remainingPaidWidget!);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgets,
      );
    }

    widgets.add(finalActionsWidget);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }
}
