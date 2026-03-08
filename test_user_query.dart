import 'package:supabase/supabase.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

Future<void> main() async {
  dotenv.testLoad(fileInput: File('.env').readAsStringSync());
  final supa = SupabaseClient(dotenv.env['SUPABASE_URL']!, dotenv.env['SUPABASE_ANON_KEY']!);
  
  print('Trying to fetch user 85 without auth token (Anon User)...');
  try {
    final res = await supa.from('users').select('*').eq('id', 85).maybeSingle();
    print('Result Anon: $res');
  } catch (e) {
    print('Error Anon: $e');
  }
}
