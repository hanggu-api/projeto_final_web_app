import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:service_101/features/client/payment_screen.dart';
import 'package:service_101/services/realtime_service.dart';
import 'package:service_101/core/config/supabase_config.dart';

void main() {
  final runLiveTests = Platform.environment['RUN_LIVE_TESTS'] == '1';

  if (!runLiveTests) {
    test(
      'Fake Pix flow skipped (set RUN_LIVE_TESTS=1 to run)',
      () {},
      skip: 'Requer RUN_LIVE_TESTS=1',
    );
    return;
  }

  setUpAll(() async {
    RealtimeService.mockMode = true;
    SharedPreferences.setMockInitialValues({});
    await SupabaseConfig.initialize(
      disableAuthAutoRefresh: true,
      detectSessionInUri: false,
    );
  });

  testWidgets(
    'Fake Pix Flow Test - navegacao para confirmacao',
    (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => PaymentScreen(
            extraData: const {'serviceId': '1'},
          ),
        ),
        GoRoute(
          path: '/confirmation',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Confirmacao'))),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router),
    );
    await tester.pumpAndSettle();

    final pixOption = find.text('Pix');
    await tester.ensureVisible(pixOption);
    await tester.tap(pixOption);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pay_button')));
    await tester.pumpAndSettle();

    expect(find.text('Confirmacao'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
