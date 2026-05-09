import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:service_101/features/home/home_search_screen.dart';

void _logStep(String message) {
  debugPrint('[PATROL][BUSCA] $message');
}

void main() {
  patrolTest('abre a tela Buscar serviços e permite digitar na busca', (
    $,
  ) async {
    _logStep('Passo 1: abrir a tela Buscar serviços em ambiente controlado.');
    await $.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HomeSearchScreen())),
    );
    await $.pump(const Duration(milliseconds: 300));

    _logStep('Passo 2: validar título e barra principal da tela.');
    expect($('Buscar serviços'), findsOneWidget);
    expect(
      $(find.byKey(const ValueKey('home-search-screen-bar'))),
      findsOneWidget,
    );

    final searchField = find.byKey(const ValueKey('home-search-text-field'));
    _logStep('Passo 3: localizar o campo de busca.');
    expect($(searchField), findsOneWidget);

    _logStep('Passo 4: digitar "chaveiro" no campo.');
    await $(searchField).enterText('chaveiro');
    await $.pump(const Duration(milliseconds: 300));

    _logStep('Passo 5: confirmar que o texto foi digitado e a tela continua estável.');
    expect(find.text('chaveiro'), findsOneWidget);
    expect($('Buscar serviços'), findsOneWidget);

    _logStep('Passo 6: desmontar a tela de teste.');
    await $.pumpWidget(const SizedBox.shrink());
    await $.pump(const Duration(milliseconds: 100));
  });
}
