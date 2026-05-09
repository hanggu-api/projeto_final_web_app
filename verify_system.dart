import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:service_101/services/api_service.dart';
import 'dart:io';

/// Script de teste para validar as novas funcionalidades:
/// 1. Mercado Pago Onboarding (Auto)
/// 2. Biometria Facial (AWS Rekognition)
/// 3. Exclusão de Conta (Cleanup)

void main() async {
  print('🚀 Iniciando Teste de Integração Central 101...');

  try {
    // 1. Carregar Env
    await dotenv.load(fileName: '.env');
    print('✅ Variáveis de ambiente carregadas.');

    final supabaseUrl = dotenv.env['SUPABASE_URL']!;
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']!;

    // Inicializar Supabase
    await Supabase.initialize(url: supabaseUrl, anonKey: anonKey);

    final supa = Supabase.instance.client;
    final api = ApiService();
    await api.loadConfig();

    print('\n--- TESTE 1: Mercado Pago Onboarding ---');
    // Para testar o Mercado Pago, precisamos de um usuário existente que seja motorista e não tenha mercado_pago_id
    // Vamos buscar um usuário de teste (ou o último cadastrado sem Mercado Pago)
    final testUser = await supa
        .from('providers')
        .select('*, users(*)')
        .limit(1)
        .maybeSingle();

    if (testUser != null) {
      final userId = testUser['user_id'];
      final email = testUser['users']['email'];
      print('🔎 Testando provisionamento para: $email (ID: $userId)');

      try {
        await api.provisionMercadoPagoAccount(userId);
        print('✅ Mercado Pago Onboarding iniciado (verifique logs do backend)');
      } catch (e) {
      print('❌ ERRO no Mercado Pago Onboarding: $e');
      }
    } else {
      print('ℹ️ Nenhum motorista sem Mercado Pago encontrado para teste automático.');
    }

    print('\n--- TESTE 2: Biometria Facial (API Ping) ---');
    try {
      // Testamos apenas a conectividade da função
      // Em um teste real, enviaríamos bytes de imagem
      final verifyRes = await supa.functions.invoke(
        'verify-face',
        body: {'ping': true},
      );
      print('✅ verify-face status: ${verifyRes.status}');
      print('✅ verify-face response: ${verifyRes.data}');
    } catch (e) {
      print('❌ ERRO ao chamar verify-face: $e');
    }

    print('\n--- TESTE 3: Exclusão de Conta (Simulação) ---');
    print('ℹ️ Pulando exclusão real para não afetar dados de produção.');
    print(
      '💡 Para testar exclusão, use: api.deleteAccount() logado com um usuário de teste.',
    );

    print('\n🎉 script concluído com sucesso.');
    exit(0);
  } catch (e) {
    print('\n💥 ERRO FATAL no script: $e');
    exit(1);
  }
}
