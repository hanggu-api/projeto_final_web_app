import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:service_101/features/auth/login_screen.dart';

void _logStep(String message) {
  debugPrint('[PATROL][LOGIN] $message');
}

void main() {
  patrolTest(
    'abre login, permite digitar e mostra guarda de ambiente controlado',
    ($) async {
      _logStep('Passo 1: abrir a tela de login em ambiente controlado.');
      await $.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginScreen())),
      );
      await $.pump(const Duration(milliseconds: 300));

      _logStep('Passo 2: validar shell principal da tela de login.');
      expect($(find.byKey(const ValueKey('login'))), findsOneWidget);
      expect($('Fazer Login'), findsOneWidget);

      final emailField = find.byKey(const ValueKey('login-email-field'));
      final passwordField = find.byKey(const ValueKey('login-password-field'));
      final submitButton = find.byKey(const ValueKey('login-submit-button'));

      _logStep('Passo 3: localizar os campos e o botão entrar.');
      expect($(emailField), findsOneWidget);
      expect($(passwordField), findsOneWidget);
      expect($(submitButton), findsOneWidget);

      _logStep('Passo 4: preencher email e senha de teste.');
      await $(emailField).enterText('email-invalido');
      await $(passwordField).enterText('123456');
      await $.pump(const Duration(milliseconds: 300));

      expect(find.text('email-invalido'), findsOneWidget);

      _logStep('Passo 5: tocar no botão entrar.');
      await $(submitButton).tap();
      await $.pump(const Duration(milliseconds: 700));

      _logStep('Passo 6: validar a mensagem de guarda do ambiente controlado.');
      expect(
        find.textContaining('Conexao com o servidor indisponivel'),
        findsOneWidget,
      );

      _logStep('Passo 7: desmontar a tela de teste.');
      await $.pumpWidget(const SizedBox.shrink());
      await $.pump(const Duration(milliseconds: 100));
    },
  );
}
