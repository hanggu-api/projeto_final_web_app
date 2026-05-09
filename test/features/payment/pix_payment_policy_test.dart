import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/features/payment/models/pix_payment_contract.dart';
import 'package:service_101/features/payment/models/pix_payment_policy.dart';

void main() {
  group('PixPaymentArgs.fromUnknown', () {
    test('hidrata campos principais a partir de map', () {
      final args = PixPaymentArgs.fromUnknown({
        'intentId': 'pix-1',
        'title': 'Pagamento Pix',
        'description': 'Descricao',
        'providerName': 'Salao A',
        'serviceLabel': 'Corte',
        'qrCode': '000201',
        'qrCodeImage': 'data:image/png;base64,abc',
        'amount': '29.9',
        'successRoute': '/scheduled-service/1',
        'statusSource': 'service',
        'paymentStage': 'remaining',
      });

      expect(args.resourceId, 'pix-1');
      expect(args.providerName, 'Salao A');
      expect(args.serviceLabel, 'Corte');
      expect(args.amount, 29.9);
      expect(args.statusSource, 'service');
      expect(args.paymentStage, 'remaining');
    });

    test('usa fallback seguro quando extra é inválido', () {
      final args = PixPaymentArgs.fromUnknown(null);

      expect(args.resourceId, '');
      expect(args.title, 'Pagamento Pix');
      expect(args.amount, 0);
      expect(args.statusSource, 'pending_fixed_booking');
    });
  });

  group('PixPaymentPolicy', () {
    test('prioriza fiscalDescription quando fornecida', () {
      const args = PixPaymentArgs(
        resourceId: 'pix-2',
        title: 'Pagamento Pix',
        description: 'Desc',
        qrCode: 'code',
        qrCodeImage: 'img',
        amount: 10,
        fiscalDescription: 'Descricao fiscal customizada',
      );

      expect(
        PixPaymentPolicy.buildDetailedPaymentReason(args),
        'Descricao fiscal customizada',
      );
    });

    test('considera paid_manual como pago para pending_fixed_booking', () {
      const args = PixPaymentArgs(
        resourceId: 'pix-3',
        title: 'Pagamento Pix',
        description: 'Desc',
        qrCode: 'code',
        qrCodeImage: 'img',
        amount: 10,
      );

      expect(
        PixPaymentPolicy.isPaid(args, {
          'status': 'pending',
          'payment_status': 'paid_manual',
        }),
        isTrue,
      );
    });

    test('considera service remaining pago pelo payment_remaining_status', () {
      const args = PixPaymentArgs(
        resourceId: 'svc-1',
        title: 'Pagamento Pix',
        description: 'Desc',
        qrCode: 'code',
        qrCodeImage: 'img',
        amount: 10,
        statusSource: 'service',
        paymentStage: 'remaining',
      );

      expect(
        PixPaymentPolicy.isPaid(args, {
          'status': 'in_progress',
          'payment_remaining_status': 'approved',
        }),
        isTrue,
      );
    });

    test('considera pending_fixed_booking terminal quando expirado', () {
      const args = PixPaymentArgs(
        resourceId: 'pix-4',
        title: 'Pagamento Pix',
        description: 'Desc',
        qrCode: 'code',
        qrCodeImage: 'img',
        amount: 10,
      );

      expect(
        PixPaymentPolicy.isTerminal(args, {
          'status': 'pending',
          'payment_status': 'pending',
          'hold_status': 'expired',
        }),
        isTrue,
      );
    });

    test('retorna label correta do botão de voltar por contexto', () {
      const serviceRemaining = PixPaymentArgs(
        resourceId: 'svc-2',
        title: 'Pagamento Pix',
        description: 'Desc',
        qrCode: 'code',
        qrCodeImage: 'img',
        amount: 10,
        statusSource: 'service',
        paymentStage: 'remaining',
      );
      const serviceDeposit = PixPaymentArgs(
        resourceId: 'svc-3',
        title: 'Pagamento Pix',
        description: 'Desc',
        qrCode: 'code',
        qrCodeImage: 'img',
        amount: 10,
        statusSource: 'service',
      );
      const booking = PixPaymentArgs(
        resourceId: 'pix-5',
        title: 'Pagamento Pix',
        description: 'Desc',
        qrCode: 'code',
        qrCodeImage: 'img',
        amount: 10,
      );

      expect(
        PixPaymentPolicy.backButtonLabel(serviceRemaining),
        'Voltar ao acompanhamento',
      );
      expect(
        PixPaymentPolicy.backButtonLabel(serviceDeposit),
        'Voltar ao serviço',
      );
      expect(PixPaymentPolicy.backButtonLabel(booking), 'Voltar');
    });

    test('resolve rota de sucesso por contexto do Pix', () {
      const serviceDeposit = PixPaymentArgs(
        resourceId: 'svc-10',
        title: 'Pagamento Pix',
        description: 'Desc',
        qrCode: 'code',
        qrCodeImage: 'img',
        amount: 10,
        statusSource: 'service',
        paymentStage: 'deposit',
      );
      const serviceRemaining = PixPaymentArgs(
        resourceId: 'svc-11',
        title: 'Pagamento Pix',
        description: 'Desc',
        qrCode: 'code',
        qrCodeImage: 'img',
        amount: 10,
        statusSource: 'service',
        paymentStage: 'remaining',
      );
      const explicit = PixPaymentArgs(
        resourceId: 'svc-12',
        title: 'Pagamento Pix',
        description: 'Desc',
        qrCode: 'code',
        qrCodeImage: 'img',
        amount: 10,
        statusSource: 'service',
        successRoute: '/rota-customizada',
      );
      const booking = PixPaymentArgs(
        resourceId: 'pix-6',
        title: 'Pagamento Pix',
        description: 'Desc',
        qrCode: 'code',
        qrCodeImage: 'img',
        amount: 10,
      );

      expect(
        PixPaymentPolicy.successRoute(serviceDeposit, 'svc-10'),
        '/service-busca-prestador-movel/svc-10',
      );
      expect(
        PixPaymentPolicy.successRoute(serviceRemaining, 'svc-11'),
        '/service-tracking/svc-11',
      );
      expect(
        PixPaymentPolicy.successRoute(explicit, 'svc-12'),
        '/rota-customizada',
      );
      expect(
        PixPaymentPolicy.successRoute(booking, 'booking-1'),
        '/scheduled-service/booking-1',
      );
    });
  });
}
