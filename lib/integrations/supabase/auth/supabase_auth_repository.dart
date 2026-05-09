import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/api_service.dart';
import '../../../domains/auth/data/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  @override
  String? getCurrentUserId() => ApiService().currentUserId;

  @override
  Future<void> login({
    required String email,
    required String password,
  }) async {
    final authResponse = await Supabase.instance.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final token = authResponse.session!.accessToken.trim();
    if (token.isEmpty) {
      throw Exception('Sessão inválida: accessToken ausente.');
    }
    await ApiService().saveToken(token);
  }

  /// Bootstrap técnico inevitável: cria/autentica identidade no Supabase Auth.
  /// Retorna o accessToken da sessão para uso imediato no registro de perfil.
  /// Toda lógica de UI deve chamar este método em vez de acessar
  /// Supabase.instance.client.auth diretamente.
  Future<String> signUpOrSignIn({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    Session? session;
    try {
      final authResponse = await Supabase.instance.client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim(), 'role': role},
      );
      session = authResponse.session;
    } on AuthException catch (e) {
      if (e.code == 'user_already_exists') {
        final signInResponse =
            await Supabase.instance.client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
        session = signInResponse.session;
      } else {
        rethrow;
      }
    }
    if (session == null) throw Exception('Falha na sessão de autenticação.');
    return session.accessToken;
  }
}
