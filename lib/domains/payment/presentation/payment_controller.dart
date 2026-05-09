import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/async_action_state.dart';
import '../../../integrations/supabase/payment/supabase_payment_repository.dart';
import '../domain/process_payment_usecase.dart';

final paymentRepositoryProvider = Provider<SupabasePaymentRepository>(
  (ref) => SupabasePaymentRepository(),
);

final processPaymentUseCaseProvider = Provider<ProcessPaymentUseCase>(
  (ref) => ProcessPaymentUseCase(ref.watch(paymentRepositoryProvider)),
);

final paymentControllerProvider =
    NotifierProvider<PaymentController, AsyncActionState>(
  PaymentController.new,
);

class PaymentController extends Notifier<AsyncActionState> {
  late final ProcessPaymentUseCase _processPaymentUseCase;

  @override
  AsyncActionState build() {
    _processPaymentUseCase = ref.watch(processPaymentUseCaseProvider);
    return AsyncActionState.idle;
  }

  Future<void> requestWithdrawal(double amount) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await _processPaymentUseCase.withdraw(amount);
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
