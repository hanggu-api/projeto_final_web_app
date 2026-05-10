import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final supabaseUrl = 'https://mroesvsmylnaxelrhqtl.supabase.co';
  final supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1yb2VzdnNteWxuYXhlbHJocXRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE3ODY4NTksImV4cCI6MjA4NzM2Mjg1OX0.MFsx8h7CIVpDBC23JJ_5NRD0MFPFSIs55N_rXdgTXtU';

  final client = SupabaseClient(supabaseUrl, supabaseAnonKey);

  print('🧪 Testando SignUp para depurar erro 422...');
  final email =
      'test_driver_${DateTime.now().millisecondsSinceEpoch}@example.com';

  try {
    print('Enviando requisição de SignUp para $email...');
    final authResponse = await client.auth.signUp(
      email: email,
      password: 'password123',
      data: {'full_name': 'Test Debug Driver', 'role': 'driver'},
    );

    print('Resposta recebida.');
    final user = authResponse.user;
    if (user != null) {
      print('✅ Sucesso no Auth! User ID: ${user.id}');
      print('Email: $email');

      // Tentar verificar se o trigger criou o perfil público
      print('🔎 Verificando perfil público...');
      try {
        final publicUser = await client
            .from('users')
            .select()
            .eq('supabase_uid', user.id)
            .maybeSingle();

        if (publicUser != null) {
          print('✅ Perfil público criado com sucesso!');
          print('Dados: $publicUser');
        } else {
          print(
            '❌ Perfil público NÃO encontrado. O trigger pode ter falhado ou demorado.',
          );
        }
      } catch (e) {
        print('❌ Erro ao buscar perfil público: $e');
      }
    } else {
      print(
        '⚠️ Auth retornado sem usuário. Verifique se há configurações de confirmação de email.',
      );
      if (authResponse.session != null) {
        print('Sessão ativa encontrada.');
      }
    }
  } on AuthException catch (e) {
    print('\n❌ Erro de Autenticação (Possível 422):');
    print('Status Code: ${e.statusCode}');
    print('Mensagem: ${e.message}');
  } catch (e, stack) {
    print('\n❌ Erro Inesperado: $e');
    print('Stack trace:\n$stack');
  }

  print('\n🏁 Fim do teste.');
  exit(0);
}
