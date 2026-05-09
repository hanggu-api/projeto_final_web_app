import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:service_101/features/uber/widgets/uber_ride_selection_panel.dart';
import 'package:service_101/services/uber_service.dart';

void main() {
  testWidgets('mostra PIX + Cartão (No app) + Cartão (Direto com Motorista)', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: UberRideSelectionPanel(
              vehicleFares: const {1: {'fare': 10}},
              selectedVehicleId: 1,
              selectedPaymentMethod: 'PIX',
              isPaymentExpanded: false,
              isLoading: false,
              predefinedVehicles: const [],
              savedCards: const [],
              onRequestRide: (_) {},
              onVehicleSelected: (_) {},
              onTogglePaymentExpanded: () {},
              onPaymentMethodSelected: (_) {},
              uberService: UberService(),
              hasDriversWithCardMachine: true,
            ),
          ),
        ),
        GoRoute(
          path: '/payment-methods',
          builder: (context, state) => const Scaffold(body: Text('payment-methods')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // abre modal de forma de pagamento
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();

    expect(find.text('Forma de pagamento'), findsOneWidget);
    expect(find.text('PIX'), findsWidgets);
    expect(find.text('Cartão (No app)'), findsOneWidget);
    expect(find.text('Cartão (Direto com Motorista)'), findsOneWidget);
  });

  testWidgets('cartão direto mostra indisponível quando motorista não aceita maquininha', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: UberRideSelectionPanel(
              vehicleFares: const {1: {'fare': 10}},
              selectedVehicleId: 1,
              selectedPaymentMethod: 'PIX',
              isPaymentExpanded: false,
              isLoading: false,
              predefinedVehicles: const [],
              savedCards: const [],
              onRequestRide: (_) {},
              onVehicleSelected: (_) {},
              onTogglePaymentExpanded: () {},
              onPaymentMethodSelected: (_) {},
              uberService: UberService(),
              hasDriversWithCardMachine: false,
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();

    expect(find.text('Cartão (Direto com Motorista)'), findsOneWidget);
    expect(find.text('Indisponível no momento'), findsOneWidget);
  });

  testWidgets('se não tem cartão salvo, tocar em Cartão (No app) navega para /payment-methods', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: UberRideSelectionPanel(
              vehicleFares: const {1: {'fare': 10}},
              selectedVehicleId: 1,
              selectedPaymentMethod: 'PIX',
              isPaymentExpanded: false,
              isLoading: false,
              predefinedVehicles: const [],
              savedCards: const [], // sem cartão
              onRequestRide: (_) {},
              onVehicleSelected: (_) {},
              onTogglePaymentExpanded: () {},
              onPaymentMethodSelected: (_) {},
              uberService: UberService(),
              hasDriversWithCardMachine: true,
            ),
          ),
        ),
        GoRoute(
          path: '/payment-methods',
          builder: (context, state) => const Scaffold(body: Text('payment-methods')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cartão (No app)'));
    await tester.pumpAndSettle();

    expect(find.text('payment-methods'), findsOneWidget);
  });
}

