import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:service_101/features/auth/register_screen.dart';
import 'package:service_101/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_supabase_setup.dart';

void main() {
  setUpAll(() async {
    await initializeSupabaseForTests();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Registration Flow: Gesseiro (Construction) -> Basic Info -> Services',
    (WidgetTester tester) async {
      // 1. Mock API
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        debugPrint('API Call: $path');

        // Mock Professions
        if (path.endsWith('/professions')) {
          return http.Response(
            jsonEncode({
              'professions': [
                {
                  'id': 1,
                  'name': 'Gesseiro',
                  'service_type': 'construction',
                  'keywords': 'gesso',
                },
                {
                  'id': 2,
                  'name': 'Pedreiro',
                  'service_type': 'construction',
                  'keywords': 'obra',
                },
              ],
            }),
            200,
          );
        }

        // Mock Tasks for Gesseiro (ID 1)
        if (path.contains('/services/professions/1/tasks')) {
          return http.Response(
            jsonEncode({
              'tasks': [
                {
                  'name': 'Instalação de Sanca',
                  'price': 50.0,
                  'keywords': 'Duração: 1h',
                },
                {
                  'name': 'Forro de Gesso',
                  'price': 40.0,
                  'keywords': 'Duração: 1h',
                },
              ],
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      ApiService().setClient(mockClient);

      // 2. Pump Widget
      await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
      await tester.pumpAndSettle(); // Wait for professions to load

      // 3. Verify Profession Step
      await tester.pumpAndSettle();
      if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
        debugPrint('Still loading...');
      }

      expect(find.text('Qual é a sua profissão?'), findsOneWidget);

      // Debug: Print all Text widgets
      find.byType(Text).evaluate().forEach((w) {
        debugPrint('Text found: ${(w.widget as Text).data}');
      });

      // 4. Search and Select Profession
      debugPrint(
        'TextFields found: ${find.byType(TextField).evaluate().length}',
      );
      debugPrint(
        'Key found: ${find.byKey(const Key('profession_search_field')).evaluate().length}',
      );
      debugPrint(
        'EditableText found: ${find.byType(EditableText).evaluate().length}',
      );

      // Try tapping first to ensure focus/build
      await tester.tap(find.byKey(const Key('profession_search_field')));
      await tester.pump();

      // Use testTextInput directly
      tester.testTextInput.enterText('Ges');
      await tester.pumpAndSettle();

      expect(find.text('Gesseiro'), findsOneWidget);
      await tester.tap(find.text('Gesseiro'));
      await tester.pumpAndSettle();

      // 5. Verify Basic Info Step (Standard Flow)
      // BasicInfoStep usually has fields like "Nome Completo", "Email", etc.
      // We assume the title or a field is present.
      expect(find.byType(TextFormField), findsAtLeastNWidgets(3));

      // 6. Fill Basic Info
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome Completo'),
        'João Gesseiro',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'joao@test.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        '123456',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'CPF/CNPJ'),
        '123.456.789-00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Celular'),
        '(11) 99999-9999',
      );

      // Pump to update state
      await tester.pump();

      // 7. Tap Next (Assuming there is a "Próximo" button)
      final nextButton = find.text('Próximo');
      expect(nextButton, findsOneWidget);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      // 8. Verify Service Step
      expect(find.text('Selecione os procedimentos'), findsOneWidget);

      // 9. Verify Profession Name Display (New Feature)
      expect(find.text('Gesseiro'), findsOneWidget);

      // 10. Verify Services Loaded
      // Wait for async loading
      if (find.text('Instalação de Sanca').evaluate().isEmpty) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Instalação de Sanca'), findsOneWidget);
      expect(find.text('Forro de Gesso'), findsOneWidget);
    },
  );
}
