import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await dotenv.load(fileName: '.env');
  final url = dotenv.env['SUPABASE_URL']!;
  final key = dotenv.env['SUPABASE_ANON_KEY']!;
  
  final supa = SupabaseClient(url, key);

  print('🔍 Buscando motoristas ativos na tabela providers...');
  try {
    final res = await supa
        .from('providers')
        .select('*, users!inner(*)')
        .limit(5);
    
    if (res.isEmpty) {
      print('❌ Nenhum motorista encontrado.');
      return;
    }

    print('✅ Motoristas encontrados:');
    for (var provider in res) {
      final user = provider['users'];
      print('---');
      print('ID: ${user['id']}');
      print('Nome: ${user['full_name']}');
      print('Email: ${user['email']}');
      print('Stripe Account: ${provider['stripe_account_id']}');
      print('Status Onboarding: ${provider['stripe_onboarding_completed']}');
    }
  } catch (e) {
    print('❌ Erro: $e');
  }
}
