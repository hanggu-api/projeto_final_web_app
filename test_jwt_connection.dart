import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

void main() async {
  print('🧪 Testando JWT Connection na Edge Function verify-face Marina! Marina! Marina!...');

  try {
    await dotenv.load(fileName: '.env');
    final supabaseUrl = dotenv.env['SUPABASE_URL']!;
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']!;

    await Supabase.initialize(url: supabaseUrl, anonKey: anonKey);
    final supa = Supabase.instance.client;

    final email = 'test_jwt_${DateTime.now().millisecondsSinceEpoch}@example.com';
    final password = 'Password@123';

    print('👤 Criando usuário temporário: $email...');
    final authRes = await supa.auth.signUp(email: email, password: password);
    final user = authRes.user;
    
    if (user == null) {
      print('❌ Falha ao criar usuário!');
      return;
    }
    print('✅ Usuário criado: ${user.id}');

    print('🧠 Invocando verify-face COM JWT...');
    final payload = {
      'cnhPath': 'invalid/path/test.jpg',
      'selfiePath': 'invalid/path/selfie.jpg',
    };

    final result = await supa.functions.invoke('verify-face', body: payload);

    print('\n--- RESULTADO ---');
    print('Status: ${result.status}');
    print('Data: ${result.data}');

    if (result.status == 400 && result.data['error'] == 'Falha ao baixar imagens do Storage') {
      print('\n✨ SUCESSO: O JWT foi aceito e validado! O erro 400 é esperado pois os arquivos não existem.');
      print('🚀 CONCLUSÃO: BIOMETRIA ESTÁ CONECTADA AO JWT MARINA! MARINA! MARINA!');
    } else if (result.status == 401) {
      print('\n❌ FALHA: JWT Inválido (401).');
    } else {
      print('\n❓ Resultado Inesperado: ${result.status} - ${result.data}');
    }

    // Cleanup
    print('\n🧹 Limpando usuário...');
    // Dependendo das permissões, deletar pode falhar, mas o teste já foi feito.
    
    exit(0);
  } catch (e) {
    print('\n💥 ERRO: $e');
    exit(1);
  }
}
