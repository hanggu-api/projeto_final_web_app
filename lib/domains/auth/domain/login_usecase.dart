import '../data/auth_repository.dart';

class LoginUseCase {
  LoginUseCase(this._repository);

  final AuthRepository _repository;

  Future<void> execute({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw ArgumentError('Email e senha são obrigatórios.');
    }

    await _repository.login(
      email: email.trim(),
      password: password,
    );
  }
}
