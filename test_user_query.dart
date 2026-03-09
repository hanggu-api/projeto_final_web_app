import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await dotenv.load(fileName: '.env');
  final supa = SupabaseClient(
    dotenv.env['SUPABASE_URL']!,
    dotenv.env['SUPABASE_ANON_KEY']!,
  );

  debugPrint('Trying to fetch user 85 without auth token (Anon User)...');
  try {
    final res = await supa.from('users').select('*').eq('id', 85).maybeSingle();
    debugPrint('Result Anon: $res');
  } catch (e) {
    debugPrint('Error Anon: $e');
  }
}
