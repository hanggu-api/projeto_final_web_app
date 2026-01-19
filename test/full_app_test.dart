import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/main.dart'; 
import 'package:service_101/features/provider/provider_home_screen.dart';

void main() {
  testWidgets('Smoke: MyApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProviderHomeScreen: layout e abas', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(
      home: ProviderHomeScreen(loadOnInit: false, connectRealtime: false),
    ));
    await tester.pump();

    expect(find.text('Painel de Serviços'), findsOneWidget);
    expect(find.text('Disponíveis'), findsOneWidget);
    expect(find.text('Meus'), findsOneWidget);
    expect(find.text('Finalizados'), findsOneWidget);

    await tester.drag(find.byType(NestedScrollView), const Offset(0, -500));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Meus'));
    await tester.pump();
    await tester.tap(find.text('Finalizados'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
