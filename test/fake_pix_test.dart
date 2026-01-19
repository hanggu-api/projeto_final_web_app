import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:service_101/features/client/payment_screen.dart';
import 'package:service_101/services/api_service.dart';
import 'package:service_101/services/payment_service.dart';
import 'package:service_101/services/realtime_service.dart';

class RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = RealHttpOverrides();
    RealtimeService.mockMode = true;
    SharedPreferences.setMockInitialValues({
      'api_base_url': 'http://127.0.0.1:4011/api',
    });
  });

  testWidgets('Fake Pix Flow Test - Localhost', (WidgetTester tester) async {
    // 1. Setup Service ID (Create a real service in backend first or mock it)
    // Since we want to test the full flow including backend auto-approve, we need a real service.
    // We can use the API to create one.

    final api = ApiService();

    // Register User
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final email = 'pix_test_$timestamp@test.com';
    await api.post('/auth/register', {
      'email': email,
      'password': 'password123',
      'name': 'Pix Tester',
      'role': 'client',
      'phone': '11999999999',
    });

    await api.post('/auth/login', {'email': email, 'password': 'password123'});
    // final token = loginRes['token'];
    // final userId = loginRes['user']['id'];

    // Create Service
    final serviceRes = await api.post('/services', {
      'category_id': 1,
      'description': 'Test Pix Flow',
      'latitude': -23.55,
      'longitude': -46.63,
      'address': 'Rua Teste',
      'price_estimated': 10.0,
      'price_upfront': 1.0, // 1 real upfront
    });
    final serviceId = serviceRes['service']['id'];
    debugPrint('Service Created: $serviceId');

    // 2. Pump Widget
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentScreen(
          extraData: {'serviceId': serviceId},
          paymentService: PaymentService(),
        ),
      ),
    );

    // 3. Select Pix
    final pixOption = find.text('Pix');
    await tester.ensureVisible(pixOption);
    await tester.tap(pixOption);
    await tester.pump();

    // 4. Click Pay
    // Source uses _buildSummary() -> ElevatedButton.
    // Let's use find.byType(ElevatedButton) if unique.

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(); // Start request

    // 5. Verify Dialog appears (Fake Pix QR Code)
    // It might take a moment for the backend to respond
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Código Pix (Copia e Cola)'), findsOneWidget);
    expect(find.text('Aguardando pagamento...'), findsOneWidget);

    // 6. Wait for Auto-Approve (Backend delay is 5s, polling is 3s)
    // We wait 10s to be safe
    debugPrint('Waiting for Backend Auto-Approve...');
    await tester.pump(const Duration(seconds: 10));

    // 7. Verify Dialog Closed (or Success Message)
    // If success, it navigates to '/confirmation'.
    // Since we wrapped in MaterialApp without GoRouter, it might just pop the dialog?
    // The code uses context.go('/confirmation').
    // Without GoRouter in the test tree, context.go might throw or do nothing if not configured?
    // Ah, PaymentScreen uses context.go.
    // We should inject a MockGoRouter or wrap in GoRouter.
  });
}
