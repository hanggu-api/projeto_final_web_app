// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:service_101/main.dart';

import 'test_supabase_setup.dart';

void main() {
  testWidgets('App builds without runtime exceptions', (
    WidgetTester tester,
  ) async {
    await initializeSupabaseForTests();
    tester.binding.window.physicalSizeTestValue = const Size(1440, 3120);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(() {
      tester.binding.window.clearPhysicalSizeTestValue();
      tester.binding.window.clearDevicePixelRatioTestValue();
    });
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
