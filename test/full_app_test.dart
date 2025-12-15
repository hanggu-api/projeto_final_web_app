import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/main.dart'; 
import 'package:mobile_app/features/home/home_screen.dart';
import 'package:mobile_app/features/client/service_request_screen.dart';
import 'package:mobile_app/features/client/payment_screen.dart';
import 'package:mobile_app/features/client/confirmation_screen.dart';
import 'package:mobile_app/features/client/tracking_screen.dart';
import 'package:mobile_app/features/provider/provider_home_screen.dart';

void main() {
  testWidgets('Integration Test: Client Service Request Flow', (WidgetTester tester) async {
    // 1. App Start
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Verify Login Screen
    expect(find.text('Conserta+'), findsOneWidget);
    expect(find.text('Sou cliente'), findsOneWidget);

    // 2. Login as Client
    await tester.tap(find.text('Sou cliente'));
    await tester.pumpAndSettle();

    // Verify Home Screen
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Pedir serviço'), findsOneWidget);

    // 3. Start Service Request
    await tester.tap(find.text('Pedir serviço'));
    await tester.pumpAndSettle();

    // Verify Service Request Wizard (Category Step)
    expect(find.byType(ServiceRequestScreen), findsOneWidget);
    expect(find.text('Qual o serviço?'), findsOneWidget);

    // Select Category and Next
    await tester.tap(find.text('Encanador'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // Description Step
    expect(find.text('Descreva o problema'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Vazamento urgente na pia');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // Location Step
    expect(find.text('Onde será o serviço?'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // Review Step
    expect(find.text('Resumo do pedido'), findsOneWidget);
    expect(find.text('Encanador'), findsOneWidget);
    expect(find.text('Vazamento urgente na pia'), findsOneWidget);

    // Confirm/Pay (Logic was changed to push /payment)
    await tester.scrollUntilVisible(find.text('Confirmar e Pagar'), 50);
    await tester.tap(find.text('Confirmar e Pagar'));
    await tester.pumpAndSettle();

    // Verify Payment Screen
    expect(find.byType(PaymentScreen), findsOneWidget);
    expect(find.text('Pagamento'), findsOneWidget);
    
    // Select Payment Method (Mercado Pago / Pix)
    await tester.tap(find.text('Pix'));
    await tester.pumpAndSettle();
    
    await tester.tap(find.text('Pagar com Mercado Pago'));
    await tester.pumpAndSettle();

    // Verify Confirmation
    expect(find.byType(ConfirmationScreen), findsOneWidget);
    expect(find.text('Pagamento confirmado!'), findsOneWidget);

    // Verify Tracking
    await tester.tap(find.text('Acompanhar pedido'));
    await tester.pumpAndSettle();
    
    expect(find.byType(TrackingScreen), findsOneWidget);
    expect(find.text('Você'), findsOneWidget); // Map marker label
  });

  testWidgets('Integration Test: Provider Flow', (WidgetTester tester) async {
    // 1. App Start
    tester.view.physicalSize = const Size(1080, 2400); // Taller screen
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // 2. Login as Provider
    // The text in the code is 'Sou prestador', not 'Quero oferecer serviços' (that was subtitle)
    final providerBtn = find.text('Sou prestador'); 
    await tester.scrollUntilVisible(providerBtn, 50);
    await tester.tap(providerBtn);
    await tester.pumpAndSettle();

    // Verify Provider Home
    expect(find.byType(ProviderHomeScreen), findsOneWidget);
    // 'Saldo disponível' might be white text on gradient, verify text existence
    expect(find.text('Saldo disponível'), findsOneWidget);
    expect(find.text('Meus serviços'), findsOneWidget);

    // Verify Tabs
    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text('Concluídos'), findsOneWidget);
  });
}
