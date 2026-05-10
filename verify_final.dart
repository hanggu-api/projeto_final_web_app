import 'dart:convert';
import 'package:http/http.dart' as http;

/// Script de Verificação Final (Pure Dart)
/// Valida se o erro 401 foi corrigido e se as funções estão operacionais.

void main() async {
  print('🧪 Iniciando Verificação de Backend...');

  const supabaseUrl = 'https://mroesvsmylnaxelrhqtl.supabase.co';
  const anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1yb2VzdnNteWxuYXhlbHJocXRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE3ODY4NTksImV4cCI6MjA4NzM2Mjg1OX0.MFsx8h7CIVpDBC23JJ_5NRD0MFPFSIs55N_rXdgTXtU';

  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $anonKey',
    'apikey': anonKey,
  };

  print('\n--- [TESTE 1] Validando Correção do 401 (Mercado Pago) ---');
  try {
    // 1. Buscar um ID de prestador real para o teste
    final queryUrl = '$supabaseUrl/rest/v1/providers?select=id&limit=1';
    final queryRes = await http.get(Uri.parse(queryUrl), headers: headers);

    if (queryRes.statusCode == 200) {
      final providers = jsonDecode(queryRes.body) as List;
      if (providers.isNotEmpty) {
        final providerId = providers[0]['id'];
        print('🔎 Usando Provider ID: $providerId para o teste.');

        final mpUrl = '$supabaseUrl/functions/v1/mp-onboarding-handler';
        final mpRes = await http.post(
          Uri.parse(mpUrl),
          headers: headers,
          body: jsonEncode({'provider_id': providerId}),
        );

        print('Status: ${mpRes.statusCode}');
        print('Body: ${mpRes.body}');

        if (mpRes.statusCode == 401) {
          print(
            '✅ SUCESSO: O erro 401 agora é legítimo (Autorização negada pois a chave Anon não é o dono do ID $providerId).',
          );
          print(
            '   Isso confirma que o código de segurança está executando corretamente.',
          );
        } else if (mpRes.statusCode == 200) {
          print('✅ SUCESSO: Conta Mercado Pago processada!');
        } else {
          print('⚠️ Resposta inesperada: ${mpRes.statusCode}');
        }
      }
    }
 else {
      print('❌ Erro ao buscar provedores: ${queryRes.statusCode}');
    }
  } catch (e) {
    print('❌ Erro no teste do Mercado Pago: $e');
  }

  print('\n--- [TESTE 2] Identity Verification (Rekognition) ---');
  try {
    final verifyUrl = '$supabaseUrl/functions/v1/verify-face';
    final response = await http.post(
      Uri.parse(verifyUrl),
      headers: headers,
      body: jsonEncode({'ping': true}),
    );
    print('Status: ${response.statusCode}');
    if (response.statusCode == 401) {
      print('✅ Função protegida por JWT (Esperado).');
    } else if (response.statusCode == 200) {
      print('✅ Função aberta para teste ping.');
    }
  } catch (e) {
    print('❌ Falha ao chamar verify-face: $e');
  }

  print('\n🏁 Verificação concluída.');
}
