import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:service_101/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App starts and loads', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();
    
    // Adicione verificações aqui conforme necessário
    // expect(find.text('Login'), findsOneWidget);
  });
}
