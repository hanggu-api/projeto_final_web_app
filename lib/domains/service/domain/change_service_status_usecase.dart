import '../data/service_repository.dart';
import '../models/service_state.dart';

class ChangeServiceStatusUseCase {
  ChangeServiceStatusUseCase(this._repository);

  final ServiceRepository _repository;

  static const Map<ServiceState, Set<ServiceState>> _allowedTransitions = {
    ServiceState.requested: {
      ServiceState.accepted,
      ServiceState.cancelled,
    },
    ServiceState.accepted: {
      ServiceState.inProgress,
      ServiceState.cancelled,
    },
    ServiceState.inProgress: {
      ServiceState.arrived,
      ServiceState.completed,
      ServiceState.cancelled,
    },
    ServiceState.arrived: {
      ServiceState.completed,
      ServiceState.cancelled,
    },
    ServiceState.completed: {},
    ServiceState.cancelled: {},
  };

  Future<void> execute({
    required String serviceId,
    required ServiceState currentState,
    required ServiceState newState,
  }) async {
    if (serviceId.trim().isEmpty) {
      throw ArgumentError('O identificador do serviço é obrigatório.');
    }

    _validateTransition(currentState: currentState, newState: newState);

    await _repository.updateStatus(
      serviceId: serviceId,
      newState: newState,
    );
  }

  void _validateTransition({
    required ServiceState currentState,
    required ServiceState newState,
  }) {
    final allowedNextStates = _allowedTransitions[currentState] ?? const {};
    if (!allowedNextStates.contains(newState)) {
      throw StateError(
        'Transição inválida: ${currentState.name} -> ${newState.name}',
      );
    }
  }
}
