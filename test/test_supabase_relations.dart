import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Test Supabase Relations', () async {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://xxx.supabase.co');
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'xxx');

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    try {
      final res = await Supabase.instance.client
          .from('service_requests_new')
          .select('*, users!client_id(full_name)')
          .limit(1);
      print('SUCCESS users!client_id: $res');
    } catch(e) {
      print('FAILED users!client_id => $e');
    }
  });
}
