import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final supabaseUrl = 'https://mroesvsmylnaxelrhqtl.supabase.co';
  final supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1yb2VzdnNteWxuYXhlbHJocXRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE3ODY4NTksImV4cCI6MjA4NzM2Mjg1OX0.MFsx8h7CIVpDBC23JJ_5NRD0MFPFSIs55N_rXdgTXtU';

  final client = SupabaseClient(supabaseUrl, supabaseAnonKey);

  print(
    '🔎 Consultando estado do usuário Ricardo Lima (limalimao6@gmail.com)...',
  );

  try {
    // 1. Buscar na tabela users
    final userRes = await client
        .from('users')
        .select('id, email, role, supabase_uid')
        .eq('email', 'limalimao6@gmail.com')
        .maybeSingle();

    if (userRes != null) {
      print('✅ Usuário encontrado na tabela public.users:');
      print('ID: ${userRes['id']}');
      print('Role: ${userRes['role']}');
      print('Supabase UID: ${userRes['supabase_uid']}');

      final userId = userRes['id'];

      // 2. Buscar na tabela users (campos Mercado Pago)
      final providerRes = await client
          .from('users')
          .select('mp_account_status, mp_collector_id')
          .eq('id', userId)
          .maybeSingle();

      if (providerRes != null) {
        print('\n✅ Dados de Provedor encontrados (Mercado Pago):');
        print('MP Account Status: ${providerRes['mp_account_status']}');
        print('MP Collector ID: ${providerRes['mp_collector_id']}');
      } else {
        print(
          '\n❌ NENHUM registro na tabela users encontrado para os campos MP.',
        );
      }
    } else {
      print('❌ Usuário NÃO encontrado na tabela public.users.');
    }
  } catch (e) {
    print('❌ Erro na consulta: $e');
  }

  exit(0);
}
