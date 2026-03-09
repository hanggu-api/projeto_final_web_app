import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:service_101/main.dart' as app;
import 'package:service_101/services/api_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Service Flow Integration Tests', () {
    testWidgets('Complete service flow - Client perspective', (
      WidgetTester tester,
    ) async {
      // Start app
      app.main();
      await tester.pumpAndSettle();

      // Test 1: Login as client
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('email_field')),
        'test-client@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password_field')),
        'test123',
      );
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify login successful
      expect(find.text('Início'), findsOneWidget);

      // Test 2: Create service
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('description_field')),
        'Teste automatizado - Instalação elétrica',
      );
      await tester.tap(find.text('Solicitar Serviço'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify service created
      expect(find.text('Aguardando Pagamento'), findsOneWidget);

      // Test 3: Simulate payment
      await tester.tap(find.text('Confirmar Pagamento (TESTE)'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify status changed to searching
      expect(find.textContaining('Buscando'), findsOneWidget);

      // Test 4: Wait for provider acceptance (simulated)
      await tester.pumpAndSettle(const Duration(seconds: 10));

      // Test 5: Verify card updates when provider accepts
      // This should happen automatically via real-time listener
      expect(find.textContaining('Prestador a Caminho'), findsOneWidget);

      // Test 6: Verify arrival notification
      await tester.pumpAndSettle(const Duration(seconds: 10));
      expect(find.text('Pagar Restante'), findsOneWidget);

      // Test 7: Pay remaining amount
      await tester.tap(find.text('Pagar Restante'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar Pagamento (TESTE)'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Test 8: Verify completion flow
      await tester.pumpAndSettle(const Duration(seconds: 10));
      expect(find.text('Confirmar Conclusão'), findsOneWidget);

      await tester.tap(find.text('Confirmar Conclusão'));
      await tester.pumpAndSettle();

      // Test 9: Submit rating
      await tester.tap(find.byIcon(Icons.star).at(4)); // 5 stars
      await tester.enterText(
        find.byKey(const ValueKey('review_comment')),
        'Excelente serviço!',
      );
      await tester.tap(find.text('Enviar Avaliação'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify service completed
      expect(find.text('Concluído'), findsOneWidget);
    });

    testWidgets('Real-time card updates test', (WidgetTester tester) async {
      // Start app
      app.main();
      await tester.pumpAndSettle();

      // Login
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('email_field')),
        'test-client@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password_field')),
        'test123',
      );
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Create service
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('description_field')),
        'Teste de atualização em tempo real',
      );
      await tester.tap(find.text('Solicitar Serviço'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Simulate payment
      await tester.tap(find.text('Confirmar Pagamento (TESTE)'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Record initial status
      final initialStatus = find.textContaining('Buscando');
      expect(initialStatus, findsOneWidget);

      // Wait for real-time update (should happen in < 5 seconds)
      final stopwatch = Stopwatch()..start();

      while (stopwatch.elapsed.inSeconds < 10) {
        await tester.pump(const Duration(milliseconds: 500));

        // Check if status changed
        if (find.textContaining('Prestador a Caminho').evaluate().isNotEmpty) {
          stopwatch.stop();
          break;
        }
      }

      // Verify update happened within 5 seconds
      expect(stopwatch.elapsed.inSeconds, lessThan(5));
      expect(find.textContaining('Prestador a Caminho'), findsOneWidget);
    });

    testWidgets('FCM Notification test', (WidgetTester tester) async {
      // This test verifies that FCM token is registered
      app.main();
      await tester.pumpAndSettle();

      // Login as provider
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('email_field')),
        'test-provider@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password_field')),
        'test123',
      );
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify FCM token was registered
      final apiService = ApiService();
      expect(apiService.fcmToken, isNotNull);
      expect(apiService.fcmToken, isNotEmpty);

      // Wait for notification (this would be triggered by backend)
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify notification modal appears
      // This depends on backend sending a notification
      // For automated testing, we can verify the listener is set up
    });

    testWidgets('Cancellation flow test', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Login
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('email_field')),
        'test-client@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password_field')),
        'test123',
      );
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Create service
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('description_field')),
        'Teste de cancelamento',
      );
      await tester.tap(find.text('Solicitar Serviço'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Simulate payment
      await tester.tap(find.text('Confirmar Pagamento (TESTE)'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Cancel service
      await tester.tap(find.text('Cancelar solicitação'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sim, Cancelar'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify service was cancelled
      expect(find.text('Cancelado'), findsOneWidget);
    });
  });
}
