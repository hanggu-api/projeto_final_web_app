import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('🧪 Testando JWT Connection na Edge Function verify-face (HTTP DIRECT) Marina! Marina! Marina!...');

  // Configuração extraída do projeto
  const supabaseUrl = 'https://mroesvsmylnaxelrhqtl.supabase.co';
  // Usando a chave anon que você forneceu no curl
  const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1yb2VzdnNteWxuYXhlbHJocXRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE3ODY4NTksImV4cCI6MjA4NzM2Mjg1OX0.MFsx8h7CIVpDBC23JJ_5NRD0MFPFSIs55N_rXdgTXtU';
  const functionUrl = '$supabaseUrl/functions/v1/verify-face';

  try {
    print('🧠 Invocando verify-face COM JWT (Anon Key como Bearer para teste)...');
    
    final payload = {
      'cnhPath': 'invalid/path/test.jpg',
      'selfiePath': 'invalid/path/selfie.jpg',
    };

    final response = await http.post(
      Uri.parse(functionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $anonKey',
        'apikey': anonKey,
      },
      body: jsonEncode(payload),
    );

    print('\n--- RESULTADO ---');
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');

    // Com o fix do admin.auth.getUser(token), se passarmos uma anon key, 
    // ela deve ser reconhecida como role 'anon'. 
    // Se a função exigir PROFILE, ela dará 403. Se der 401, o JWT fix falhou.
    
    if (response.statusCode == 400 && response.body.contains('Falha ao baixar imagens do Storage')) {
      print('\n✨ SUCESSO: O JWT foi aceito e o Deno conseguiu processar a função!');
      print('🚀 CONCLUSÃO: A CAMADA DE JWT ESTÁ FUNCIONANDO MARINA! MARINA! MARINA!');
    } else if (response.statusCode == 403) {
      print('\nℹ️ INFO: JWT Aceito, mas o usuário não tem perfil (403). Isso confirma que o JWT está conectado!');
    } else if (response.statusCode == 401) {
      print('\n❌ FALHA: JWT Inválido (401). A correção não surtiu efeito.');
    } else {
      print('\n❓ Resultado Inesperado: ${response.statusCode} - ${response.body}');
    }

    exit(0);
  } catch (e) {
    print('\n💥 ERRO: $e');
    exit(1);
  }
}
