import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:service_101/features/client/mobile_provider_search_page.dart';

void main() {
  testWidgets('mostra a busca e redireciona quando prestador aceita', (
    tester,
  ) async {
    final stream = StreamController<Map<String, dynamic>>();
    addTearDown(stream.close);

    final router = GoRouter(
      initialLocation: '/service-busca-prestador-movel/svc-1',
      routes: [
        GoRoute(
          path: '/service-busca-prestador-movel/:serviceId',
          builder: (context, state) => MobileProviderSearchPage(
            serviceId: state.pathParameters['serviceId'] ?? '',
            showMap: false,
            dispatchTimelineOverride: const Text('timeline mock'),
            serviceStream: stream.stream,
            loadService: (_) async => {
              'id': 'svc-1',
              'status': 'searching_provider',
              'payment_status': 'paid',
              'description': 'Copia de chave simples',
            },
            cancelService: (_) async {},
          ),
        ),
        GoRoute(
          path: '/service-tracking/:serviceId',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('tracking aberto'))),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('home'))),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Busca de prestador'), findsOneWidget);
    expect(find.text('Buscando prestador disponível'), findsOneWidget);
    expect(find.text('timeline mock'), findsOneWidget);

    stream.add({'id': 'svc-1', 'status': 'accepted', 'provider_id': 42});
    await tester.pumpAndSettle();

    expect(find.text('tracking aberto'), findsOneWidget);
  });
}
