import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/async_action_state.dart';
import '../../../integrations/supabase/auth/supabase_auth_repository.dart';
import '../domain/login_usecase.dart';

final authRepositoryProvider = Provider<SupabaseAuthRepository>(
  (ref) => SupabaseAuthRepository(),
);

final loginUseCaseProvider = Provider<LoginUseCase>(
  (ref) => LoginUseCase(ref.watch(authRepositoryProvider)),
);

final authControllerProvider = NotifierProvider<AuthController, AsyncActionState>(
  AuthController.new,
);

class AuthController extends Notifier<AsyncActionState> {
  late final LoginUseCase _loginUseCase;

  @override
  AsyncActionState build() {
    _loginUseCase = ref.watch(loginUseCaseProvider);
    return AsyncActionState.idle;
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await _loginUseCase.execute(email: email, password: password);
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
