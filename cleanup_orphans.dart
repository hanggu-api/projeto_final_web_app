import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  // Use as mesmas credenciais do verify_final.dart ou config do projeto
  const supabaseUrl = 'https://mroesvsmylnaxelrhqtl.supabase.co';
  const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'; // Substitua pela real

  final supabase = SupabaseClient(supabaseUrl, supabaseAnonKey);

  print('🔍 Buscando usuários órfãos (Existe no Auth mas não no Public)...');

  // Nota: Como não temos a Service Role Key aqui para o Admin Auth API,
  // vamos tentar buscar via RPC ou uma query SQL simplificada se você tiver acesso ao dashboard.

  // No Dashboard do Supabase (SQL Editor), execute:
  /*
  SELECT au.id, au.email, au.created_at
  FROM auth.users au
  LEFT JOIN public.users pu ON au.id = pu.supabase_uid
  WHERE pu.id IS NULL
  ORDER BY au.created_at DESC;
  */

  print(
    '💡 DICA: O erro 422 (Email taken) ocorre porque o email já está no Auth.',
  );
  print(
    'Vá em: Dashboard Supabase > Authentication > Users e procure por limalimao6@gmail.com',
  );
  print(
    'Se ele estiver lá mas não aparecer no aplicativo, EXCLUA-O manualmente no Dashboard.',
  );
  print(
    'Depois apply a migração fix_auth_trigger_resilience.sql e tente novamente.',
  );
}
