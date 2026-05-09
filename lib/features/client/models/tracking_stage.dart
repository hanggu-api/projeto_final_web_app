import '../../../core/constants/trip_statuses.dart';

enum TrackingStage {
  paymentPending,
  searchingProvider,
  providerJourney,
  schedule,
  inProgress,
  awaitingConfirmation,
  completed,
  dispute,
  generic,
}

class TrackingStageSnapshot {
  final TrackingStage stage;
  final int stepIndex;
  final String headline;

  const TrackingStageSnapshot({
    required this.stage,
    required this.stepIndex,
    required this.headline,
  });
}

class TrackingStageResolver {
  static TrackingStageSnapshot resolve({
    required String status,
    required bool entryPaid,
    required bool remainingPaid,
    required bool providerArrived,
    required bool hasProvider,
    required bool isUnderDisputeAnalysis,
  }) {
    final normalized = normalizeServiceStatus(status);

    if (isUnderDisputeAnalysis) {
      return const TrackingStageSnapshot(
        stage: TrackingStage.dispute,
        stepIndex: 4,
        headline: 'Análise de disputa em andamento',
      );
    }

    if (normalized.isEmpty) {
      return TrackingStageSnapshot(
        stage: entryPaid ? TrackingStage.generic : TrackingStage.paymentPending,
        stepIndex: entryPaid ? 1 : 0,
        headline: entryPaid
            ? 'Status do serviço'
            : 'Aguardando pagamento 30% de entrada',
      );
    }

    if ((normalized == TripStatuses.waitingPayment ||
            normalized == 'awaiting_signal') &&
        !entryPaid) {
      return const TrackingStageSnapshot(
        stage: TrackingStage.paymentPending,
        stepIndex: 0,
        headline: 'Aguardando pagamento 30% de entrada',
      );
    }

    if (({
          ...ServiceStatusSets.clientSearch,
          TripStatuses.pending,
        }.contains(normalized)) &&
        !entryPaid) {
      return const TrackingStageSnapshot(
        stage: TrackingStage.paymentPending,
        stepIndex: 0,
        headline: 'Aguardando pagamento 30% de entrada',
      );
    }

    if ({
      ...ServiceStatusSets.clientSearch,
      TripStatuses.pending,
    }.contains(normalized)) {
      return const TrackingStageSnapshot(
        stage: TrackingStage.searchingProvider,
        stepIndex: 1,
        headline: 'Buscando prestador disponível',
      );
    }

    if (providerArrived && !remainingPaid) {
      return const TrackingStageSnapshot(
        stage: TrackingStage.providerJourney,
        stepIndex: 2,
        headline: 'Aguardando pagamento seguro (70%)',
      );
    }

    if (normalized == TripStatuses.accepted) {
      return const TrackingStageSnapshot(
        stage: TrackingStage.providerJourney,
        stepIndex: 2,
        headline: 'Prestador a caminho',
      );
    }

    if (normalized == 'provider_near') {
      return const TrackingStageSnapshot(
        stage: TrackingStage.providerJourney,
        stepIndex: 2,
        headline: 'Prestador próximo',
      );
    }

    if (normalized == TripStatuses.arrived) {
      return const TrackingStageSnapshot(
        stage: TrackingStage.providerJourney,
        stepIndex: 2,
        headline: 'O prestador chegou',
      );
    }

    if (ServiceStatusSets.paymentRemaining.contains(normalized)) {
      return TrackingStageSnapshot(
        stage: TrackingStage.providerJourney,
        stepIndex: remainingPaid ? 3 : 2,
        headline: remainingPaid
            ? 'Pagamento seguro realizado'
            : 'Aguardando pagamento seguro (70%)',
      );
    }

    if (normalized == ServiceStatusAliases.scheduleProposed) {
      return const TrackingStageSnapshot(
        stage: TrackingStage.schedule,
        stepIndex: 2,
        headline: 'Negociando horário do serviço',
      );
    }

    if (normalized == TripStatuses.scheduled) {
      return const TrackingStageSnapshot(
        stage: TrackingStage.schedule,
        stepIndex: 2,
        headline: 'Serviço agendado',
      );
    }

    if (normalized == TripStatuses.inProgress) {
      return const TrackingStageSnapshot(
        stage: TrackingStage.inProgress,
        stepIndex: 3,
        headline: 'Serviço sendo realizado',
      );
    }

    if (ServiceStatusSets.providerConcluding.contains(normalized)) {
      return const TrackingStageSnapshot(
        stage: TrackingStage.awaitingConfirmation,
        stepIndex: 4,
        headline: 'Confirme o serviço',
      );
    }

    if (normalized == TripStatuses.completed || normalized == 'finished') {
      return const TrackingStageSnapshot(
        stage: TrackingStage.completed,
        stepIndex: 4,
        headline: 'Serviço concluído!',
      );
    }

    return TrackingStageSnapshot(
      stage: hasProvider
          ? TrackingStage.providerJourney
          : TrackingStage.generic,
      stepIndex: entryPaid ? 1 : 0,
      headline: 'Status do serviço',
    );
  }
}
