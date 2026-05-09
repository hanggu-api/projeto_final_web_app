import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/features/provider/medical_agenda_view.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'test_supabase_setup.dart';

void main() {
  final runFlowTests = Platform.environment['RUN_APP_FLOWS'] == '1';
  if (!runFlowTests) {
    test(
      'Barber/medical flows skipped (set RUN_APP_FLOWS=1 to run)',
      () {},
      skip: 'Requer RUN_APP_FLOWS=1 para habilitar fluxo completo com dados.',
    );
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
    await initializeSupabaseForTests();
  });

  testWidgets('MedicalAgendaView renders and interacts correctly', (
    WidgetTester tester,
  ) async {
    await initializeDateFormatting('pt_BR', null);

    // Mock Data
    final appointments = [
      {
        'start_time': DateTime.now()
            .add(const Duration(hours: 2))
            .toIso8601String(),
        'client_name': 'João',
        'service_name': 'Corte',
      },
    ];
    // Explicitly typed list to avoid inference issues with firstWhere orElse
    final List<dynamic> schedules = [
      {
        'day_of_week': DateTime.now().weekday == 7 ? 0 : DateTime.now().weekday,
        'is_enabled': true,
        'start_time': '08:00',
        'end_time': '18:00',
      },
    ];

    bool dateSelected = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('pt', 'BR')],
        locale: const Locale('pt', 'BR'),
        home: Scaffold(
          body: MedicalAgendaView(
            appointments: appointments,
            schedules: schedules,
            onDateSelected: (date) {
              dateSelected = true;
            },
          ),
        ),
      ),
    );

    // Verify Date Header (DateFormat usage)
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);

    // Verify Slots are generated
    expect(find.text('08:00'), findsOneWidget);

    // Verify Interaction
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pump();

    expect(dateSelected, isTrue);
  });
}
