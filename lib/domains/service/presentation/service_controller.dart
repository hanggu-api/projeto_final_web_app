import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/async_action_state.dart';
import '../../../integrations/supabase/service/supabase_service_repository.dart';
import '../domain/change_service_status_usecase.dart';
import '../models/service_state.dart';

final serviceRepositoryProvider = Provider<SupabaseServiceRepository>(
  (ref) => SupabaseServiceRepository(),
);

final changeServiceStatusUseCaseProvider = Provider<ChangeServiceStatusUseCase>(
  (ref) => ChangeServiceStatusUseCase(ref.watch(serviceRepositoryProvider)),
);

final serviceControllerProvider =
    NotifierProvider<ServiceController, AsyncActionState>(
  ServiceController.new,
);

class ServiceController extends Notifier<AsyncActionState> {
  late final ChangeServiceStatusUseCase _changeServiceStatusUseCase;

  @override
  AsyncActionState build() {
    _changeServiceStatusUseCase = ref.watch(changeServiceStatusUseCaseProvider);
    return AsyncActionState.idle;
  }

  Future<void> changeStatus({
    required String serviceId,
    required ServiceState currentState,
    required ServiceState newState,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await _changeServiceStatusUseCase.execute(
        serviceId: serviceId,
        currentState: currentState,
        newState: newState,
      );
      state = state.copyWith(isLoading: false, clearError: true);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }
}
