/// Contrato canônico backend-first do fluxo de serviço mobile.
///
/// Mantém uma máquina de estados única para cliente/prestador/backend,
/// incluindo transições permitidas e permissões por papel.
enum CanonicalServiceState {
  searchingProvider,
  openForSchedule,
  offeredToProvider,
  providerAccepted,
  providerRejected,
  providerArrived,
  waitingPixDownPayment,
  pixDownPaymentPaid,
  inProgress,
  awaitingCompletionCode,
  completed,
  cancelled,
  expired,
  disputed,
}

enum DispatchEvent {
  queued,
  offerDispatched,
  providerAccepted,
  providerRejected,
  timeout,
  queueExhausted,
}

enum PixPaymentState { created, pending, paid, failed, expired }

enum ServiceActorRole { client, provider, backend }

enum ServiceAction {
  createRequest,
  dispatchOffer,
  acceptOffer,
  rejectOffer,
  markArrived,
  generatePixDownPayment,
  confirmPixPaid,
  startService,
  issueCompletionCode,
  confirmCompletionCode,
  completeService,
  cancelService,
  openDispute,
}

class ServiceFlowContract {
  static const Map<CanonicalServiceState, Set<CanonicalServiceState>>
  allowedTransitions = {
    CanonicalServiceState.searchingProvider: {
      CanonicalServiceState.openForSchedule,
      CanonicalServiceState.offeredToProvider,
      CanonicalServiceState.cancelled,
      CanonicalServiceState.expired,
    },
    CanonicalServiceState.openForSchedule: {
      CanonicalServiceState.offeredToProvider,
      CanonicalServiceState.cancelled,
      CanonicalServiceState.expired,
    },
    CanonicalServiceState.offeredToProvider: {
      CanonicalServiceState.providerAccepted,
      CanonicalServiceState.providerRejected,
      CanonicalServiceState.expired,
      CanonicalServiceState.cancelled,
    },
    CanonicalServiceState.providerRejected: {
      CanonicalServiceState.offeredToProvider,
      CanonicalServiceState.expired,
      CanonicalServiceState.cancelled,
    },
    CanonicalServiceState.providerAccepted: {
      CanonicalServiceState.providerArrived,
      CanonicalServiceState.cancelled,
    },
    CanonicalServiceState.providerArrived: {
      CanonicalServiceState.waitingPixDownPayment,
      CanonicalServiceState.cancelled,
    },
    CanonicalServiceState.waitingPixDownPayment: {
      CanonicalServiceState.pixDownPaymentPaid,
      CanonicalServiceState.cancelled,
      CanonicalServiceState.expired,
    },
    CanonicalServiceState.pixDownPaymentPaid: {
      CanonicalServiceState.inProgress,
      CanonicalServiceState.cancelled,
    },
    CanonicalServiceState.inProgress: {
      CanonicalServiceState.awaitingCompletionCode,
      CanonicalServiceState.disputed,
      CanonicalServiceState.cancelled,
    },
    CanonicalServiceState.awaitingCompletionCode: {
      CanonicalServiceState.completed,
      CanonicalServiceState.disputed,
    },
    CanonicalServiceState.disputed: {
      CanonicalServiceState.completed,
      CanonicalServiceState.cancelled,
    },
    CanonicalServiceState.completed: {},
    CanonicalServiceState.cancelled: {},
    CanonicalServiceState.expired: {},
  };

  static const Map<ServiceActorRole, Set<ServiceAction>> permissions = {
    ServiceActorRole.client: {
      ServiceAction.createRequest,
      ServiceAction.confirmPixPaid,
      ServiceAction.confirmCompletionCode,
      ServiceAction.cancelService,
      ServiceAction.openDispute,
    },
    ServiceActorRole.provider: {
      ServiceAction.acceptOffer,
      ServiceAction.rejectOffer,
      ServiceAction.markArrived,
      ServiceAction.startService,
      ServiceAction.issueCompletionCode,
      ServiceAction.completeService,
      ServiceAction.openDispute,
    },
    ServiceActorRole.backend: {
      ServiceAction.dispatchOffer,
      ServiceAction.generatePixDownPayment,
      ServiceAction.completeService,
      ServiceAction.cancelService,
    },
  };

  static const Set<ServiceAction> idempotentActions = {
    ServiceAction.acceptOffer,
    ServiceAction.rejectOffer,
    ServiceAction.markArrived,
    ServiceAction.confirmPixPaid,
    ServiceAction.completeService,
    ServiceAction.cancelService,
  };

  static bool canTransition(
    CanonicalServiceState from,
    CanonicalServiceState to,
  ) {
    final allowed = allowedTransitions[from];
    if (allowed == null) return false;
    return allowed.contains(to);
  }

  static bool canRoleExecute(ServiceActorRole role, ServiceAction action) {
    final allowed = permissions[role];
    if (allowed == null) return false;
    return allowed.contains(action);
  }

  static bool isTerminal(CanonicalServiceState state) {
    return state == CanonicalServiceState.completed ||
        state == CanonicalServiceState.cancelled ||
        state == CanonicalServiceState.expired;
  }
}

class ServiceContractPayloadKeys {
  static const serviceState = 'service_state';
  static const dispatchEvent = 'dispatch_event';
  static const pixState = 'pix_state';
  static const completionCode = 'completion_code';
  static const completionCodeExpiresAt = 'completion_code_expires_at';
  static const completionCodeConsumedAt = 'completion_code_consumed_at';
  static const reviewTrigger = 'review_trigger';
}
