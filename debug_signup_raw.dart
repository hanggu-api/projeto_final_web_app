import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  const supabaseUrl = 'https://mroesvsmylnaxelrhqtl.supabase.co';
  const anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1yb2VzdnNteWxuYXhlbHJocXRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE3ODY4NTksImV4cCI6MjA4NzM2Mjg1OX0.MFsx8h7CIVpDBC23JJ_5NRD0MFPFSIs55N_rXdgTXtU';

  final url = Uri.parse('$supabaseUrl/auth/v1/signup');
  final email =
      'debug_driver_${DateTime.now().millisecondsSinceEpoch}@example.com';

  print('🧪 Teste HTTP Direto - SignUp para $email...');

  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json', 'apikey': anonKey},
    body: jsonEncode({
      'email': email,
      'password': 'password123',
      'data': {'full_name': 'Debug Direct User', 'role': 'driver'},
    }),
  );

  print('Status Code: ${response.statusCode}');
  print('Headers: ${response.headers}');
  print('Body: ${response.body}');

  exit(0);
}
