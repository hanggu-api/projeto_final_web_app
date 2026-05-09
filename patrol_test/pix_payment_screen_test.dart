import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:service_101/features/payment/models/pix_payment_contract.dart';
import 'package:service_101/features/payment/screens/pix_payment_screen.dart';

void _logStep(String message) {
  debugPrint('[PATROL][PIX] $message');
}

void main() {
  patrolTest('abre pagamento pix controlado e copia o codigo', ($) async {
    const args = PixPaymentArgs(
      resourceId: 'pix_test_001',
      title: 'Pagamento do serviço',
      description: 'Conclua o Pix para liberar o acompanhamento do serviço.',
      providerName: 'Prestador Teste',
      serviceLabel: 'Chaveiro residencial',
      qrCode: '000201PIXTESTE123456789',
      qrCodeImage: '',
      amount: 5.55,
      statusSource: 'service',
      paymentStage: 'deposit',
    );

    _logStep('Passo 1: abrir a tela Pagamento Pix com dados controlados.');
    await $.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PixPaymentScreen(args: args)),
      ),
    );
    await $.pump(const Duration(milliseconds: 400));

    _logStep('Passo 2: validar título, valor e motivo da cobrança.');
    expect($('Pagamento Pix'), findsOneWidget);
    expect($('Pagamento do serviço'), findsOneWidget);
    expect(find.textContaining('R\$ 5,55'), findsWidgets);
    expect($('Motivo da cobranca'), findsOneWidget);
    expect(find.textContaining('Prestador Teste'), findsWidgets);

    final listView = find.byType(ListView);
    for (var i = 0; i < 4 && $('Copiar Pix').evaluate().isEmpty; i++) {
      _logStep('Passo 3: rolar a tela até o botão Copiar Pix entrar no viewport.');
      await $.tester.drag(listView, const Offset(0, -300));
      await $.pump(const Duration(milliseconds: 250));
    }

    _logStep('Passo 4: validar presença do botão Copiar Pix.');
    expect($('Copiar Pix'), findsOneWidget);

    _logStep('Passo 5: tocar no botão para copiar o código Pix.');
    await $('Copiar Pix').tap();
    await $.pump(const Duration(milliseconds: 400));

    _logStep('Passo 6: validar o snackbar de confirmação da cópia.');
    expect($('Código Pix copiado!'), findsOneWidget);

    _logStep('Passo 7: desmontar a tela de teste.');
    await $.pumpWidget(const SizedBox.shrink());
    await $.pump(const Duration(milliseconds: 100));
  });
}
