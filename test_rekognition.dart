import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

void main() async {
  print('🧪 Testando AWS Rekognition Integration...');

  try {
    // 1. Carregar Config
    await dotenv.load(fileName: '.env');
    final supabaseUrl = dotenv.env['SUPABASE_URL']!;
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']!;

    // Inicializar Supabase
    await Supabase.initialize(url: supabaseUrl, anonKey: anonKey);
    final supa = Supabase.instance.client;

    print('✅ Supabase Inicializado.');

    // 2. Definir caminhos das imagens geradas
    final selfiePathLocal =
        '/home/servirce/.gemini/antigravity/brain/c3391644-26c0-4896-aaba-6339bc791c4c/test_selfie_driver_1773289822849.png';
    final cnhPathLocal =
        '/home/servirce/.gemini/antigravity/brain/c3391644-26c0-4896-aaba-6339bc791c4c/test_cnh_card_1773289846065.png';

    print('📂 Lendo arquivos locais...');
    final selfieBytes = await File(selfiePathLocal).readAsBytes();
    final cnhBytes = await File(cnhPathLocal).readAsBytes();

    // 3. Upload para Storage (Pasta Test)
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final selfieRemotePath = 'test/selfie_$timestamp.png';
    final cnhRemotePath = 'test/cnh_$timestamp.png';

    print('☁️ Fazendo upload das imagens para o Storage (id-verification)...');

    await supa.storage
        .from('id-verification')
        .uploadBinary(
          selfieRemotePath,
          selfieBytes,
          fileOptions: const FileOptions(contentType: 'image/png'),
        );

    await supa.storage
        .from('id-verification')
        .uploadBinary(
          cnhRemotePath,
          cnhBytes,
          fileOptions: const FileOptions(contentType: 'image/png'),
        );

    print('✅ Upload concluído.');

    // 4. Invocar Edge Function
    print('🧠 Invocando Edge Function verify-face...');
    // Simulando o formato enviado pelo ApiService (bucket/path)
    final payload = {
      'cnhPath': 'id-verification/$cnhRemotePath',
      'selfiePath': 'id-verification/$selfieRemotePath',
    };

    final result = await supa.functions.invoke('verify-face', body: payload);

    print('\n--- RESULTADO ---');
    print('Status: ${result.status}');
    print('Data: ${result.data}');

    if (result.status == 200 && result.data['success'] == true) {
      print('\n✨ SUCESSO: A API respondeu corretamente!');
      print('Match: ${result.data['match']}');
      print('Similarity: ${result.data['similarity']}%');
    } else {
      print('\n❌ FALHA: A API retornou um erro ou não houve match esperado.');
    }

    exit(0);
  } catch (e) {
    print('\n💥 ERRO: $e');
    exit(1);
  }
}
