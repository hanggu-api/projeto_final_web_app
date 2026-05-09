import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/core/contracts/service_flow_contract.dart';

void main() {
  group('ServiceFlowContract transitions', () {
    test('permite caminho feliz completo', () {
      expect(
        ServiceFlowContract.canTransition(
          CanonicalServiceState.searchingProvider,
          CanonicalServiceState.offeredToProvider,
        ),
        isTrue,
      );
      expect(
        ServiceFlowContract.canTransition(
          CanonicalServiceState.offeredToProvider,
          CanonicalServiceState.providerAccepted,
        ),
        isTrue,
      );
      expect(
        ServiceFlowContract.canTransition(
          CanonicalServiceState.providerAccepted,
          CanonicalServiceState.providerArrived,
        ),
        isTrue,
      );
      expect(
        ServiceFlowContract.canTransition(
          CanonicalServiceState.providerArrived,
          CanonicalServiceState.waitingPixDownPayment,
        ),
        isTrue,
      );
      expect(
        ServiceFlowContract.canTransition(
          CanonicalServiceState.waitingPixDownPayment,
          CanonicalServiceState.pixDownPaymentPaid,
        ),
        isTrue,
      );
      expect(
        ServiceFlowContract.canTransition(
          CanonicalServiceState.pixDownPaymentPaid,
          CanonicalServiceState.inProgress,
        ),
        isTrue,
      );
      expect(
        ServiceFlowContract.canTransition(
          CanonicalServiceState.inProgress,
          CanonicalServiceState.awaitingCompletionCode,
        ),
        isTrue,
      );
      expect(
        ServiceFlowContract.canTransition(
          CanonicalServiceState.awaitingCompletionCode,
          CanonicalServiceState.completed,
        ),
        isTrue,
      );
    });

    test('bloqueia pular PIX para in_progress', () {
      expect(
        ServiceFlowContract.canTransition(
          CanonicalServiceState.providerArrived,
          CanonicalServiceState.inProgress,
        ),
        isFalse,
      );
    });

    test('estado terminal nao transiciona', () {
      expect(
        ServiceFlowContract.canTransition(
          CanonicalServiceState.completed,
          CanonicalServiceState.inProgress,
        ),
        isFalse,
      );
    });
  });

  group('ServiceFlowContract permissions', () {
    test('cliente nao pode aceitar oferta', () {
      expect(
        ServiceFlowContract.canRoleExecute(
          ServiceActorRole.client,
          ServiceAction.acceptOffer,
        ),
        isFalse,
      );
    });

    test('prestador pode aceitar oferta e marcar chegada', () {
      expect(
        ServiceFlowContract.canRoleExecute(
          ServiceActorRole.provider,
          ServiceAction.acceptOffer,
        ),
        isTrue,
      );
      expect(
        ServiceFlowContract.canRoleExecute(
          ServiceActorRole.provider,
          ServiceAction.markArrived,
        ),
        isTrue,
      );
    });

    test('acao idempotente inclui complete/cancel', () {
      expect(
        ServiceFlowContract.idempotentActions.contains(
          ServiceAction.completeService,
        ),
        isTrue,
      );
      expect(
        ServiceFlowContract.idempotentActions.contains(
          ServiceAction.cancelService,
        ),
        isTrue,
      );
    });
  });
}
