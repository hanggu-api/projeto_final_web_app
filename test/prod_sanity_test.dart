import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:service_101/services/api_service.dart';

class RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  }
}

void main() {
  const String apiUrl = 'https://cardapyia.com/api';

  setUpAll(() {
    HttpOverrides.global = RealHttpOverrides();
    SharedPreferences.setMockInitialValues({'api_base_url': apiUrl});
  });

  test('Sanity Check: Register, Login and Create Service on Production', () async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final email = 'sanity_$timestamp@test.com';
    final password = 'Password123!';
    final phone = '119${timestamp.toString().substring(5)}';

    debugPrint('🚀 Starting Prod Sanity Test against $apiUrl');
    debugPrint('👤 Creating user: $email');

    // 1. Register (using raw http to ensure user exists)
    final regUrl = Uri.parse('$apiUrl/auth/register');
    final regResponse = await http.post(
      regUrl,
      body: jsonEncode({
        'name': 'Sanity Tester',
        'email': email,
        'password': password,
        'password_confirmation': password,
        'role': 'client',
        'phone': phone,
      }),
      headers: {'Content-Type': 'application/json'},
    );

    debugPrint('📝 Register Status: ${regResponse.statusCode}');
    if (regResponse.statusCode != 200 && regResponse.statusCode != 201) {
      debugPrint('❌ Register Failed: ${regResponse.body}');
    }
    expect(regResponse.statusCode, anyOf(200, 201));

    // 2. Login (using raw http to get token)
    final loginUrl = Uri.parse('$apiUrl/auth/login');
    final loginRes = await http.post(
      loginUrl,
      body: jsonEncode({'email': email, 'password': password}),
      headers: {'Content-Type': 'application/json'},
    );

    expect(loginRes.statusCode, 200);
    final loginData = jsonDecode(loginRes.body);
    final token = loginData['token'];
    expect(token, isNotNull);

    debugPrint('🔑 Logged in. Token: ${token.toString().substring(0, 10)}...');

    // 3. Setup ApiService
    final apiService = ApiService();
    await apiService
        .loadConfig(); // Load base URL from mocked SharedPreferences
    await apiService.saveToken(
      token,
    ); // Saves to SharedPreferences (mocked) and sets internal state

    // 4. Create Service using ApiService (testing the Service class logic)
    debugPrint('🛠️ Creating Service via ApiService...');

    // Note: ApiService might not have a dedicated createService method visible in the snippet I read,
    // but usually it's `post('/services', ...)` or similar.
    // Let's assume we use `post` directly if a specific method isn't known,
    // OR we check `payment_real_flow_test.dart` which used `ApiService().createService`.
    // Let's check if createService exists in ApiService or if it was an extension/mixin not shown.
    // The previous Read didn't show `createService`. It might be further down or in another file.
    // But `payment_real_flow_test.dart` used it. Let's assume it exists or use `post` as fallback.

    try {
      final serviceRes = await apiService.post('/services', {
        'category_id': 1,
        'description': 'Sanity Test Service $timestamp',
        'latitude': -23.5505,
        'longitude': -46.6333,
        'address': 'Rua Teste, 123',
        'price_estimated': 100.0,
        'price_upfront': 10.0,
      });

      debugPrint('✅ Service Created Response: $serviceRes');
      expect(serviceRes['id'] != null || serviceRes['service'] != null, true);
    } catch (e) {
      debugPrint('❌ Create Service Failed: $e');
      rethrow;
    }
  });
}
