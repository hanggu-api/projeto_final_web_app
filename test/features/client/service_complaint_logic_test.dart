import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/features/client/service_complaint_logic.dart';

void main() {
  group('ServiceComplaintLogic.resolveClaimType', () {
    test('uses explicit claim type when provided', () {
      final result = ServiceComplaintLogic.resolveClaimType(
        claimType: 'Refund_Request',
        title: 'Abrir Reclamação',
      );

      expect(result, 'refund_request');
    });

    test('falls back to refund_request when title mentions devolucao', () {
      final result = ServiceComplaintLogic.resolveClaimType(
        claimType: '   ',
        title: 'Pedir Devolução',
      );

      expect(result, 'refund_request');
    });

    test('falls back to complaint when no explicit claim type exists', () {
      final result = ServiceComplaintLogic.resolveClaimType(
        claimType: '',
        title: 'Abrir Reclamação',
      );

      expect(result, 'complaint');
    });
  });

  group('ServiceComplaintLogic.attachmentTypeFromPath', () {
    test('classifies audio attachments', () {
      expect(
        ServiceComplaintLogic.attachmentTypeFromPath('/tmp/evidence.M4A'),
        'audio',
      );
    });

    test('classifies video attachments', () {
      expect(
        ServiceComplaintLogic.attachmentTypeFromPath('/tmp/evidence.mov'),
        'video',
      );
    });

    test('defaults unknown extensions to photo', () {
      expect(
        ServiceComplaintLogic.attachmentTypeFromPath('/tmp/evidence.jpeg'),
        'photo',
      );
    });
  });

  group('ServiceComplaintLogic.buildReason', () {
    test('includes selected quick answers, observation and advisory text', () {
      final result = ServiceComplaintLogic.buildReason(
        quickAnswers: {
          'O serviço ficou incompleto ou mal finalizado': true,
          'Houve cobrança indevida ou valor divergente': false,
          'Preciso de reanálise do pagamento ou reembolso': true,
        },
        observation: 'O prestador saiu antes de concluir.',
      );

      expect(result, contains('Respostas rápidas:'));
      expect(
        result,
        contains('- O serviço ficou incompleto ou mal finalizado'),
      );
      expect(
        result,
        contains('- Preciso de reanálise do pagamento ou reembolso'),
      );
      expect(result, isNot(contains('- Houve cobrança indevida ou valor divergente')));
      expect(result, contains('Observação do cliente:'));
      expect(result, contains('O prestador saiu antes de concluir.'));
      expect(
        result,
        contains(
          'Aviso exibido ao cliente: os dados e anexos foram enviados para análise',
        ),
      );
    });

    test('still returns advisory text when no quick answers are selected', () {
      final result = ServiceComplaintLogic.buildReason(
        quickAnswers: {
          'O prestador não executou o serviço corretamente': false,
        },
        observation: '   ',
      );

      expect(result, isNot(contains('Respostas rápidas:')));
      expect(result, isNot(contains('Observação do cliente:')));
      expect(
        result,
        equals(
          'Aviso exibido ao cliente: os dados e anexos foram enviados para análise e a resposta será enviada por e-mail em até 3 dias úteis.',
        ),
      );
    });
  });
}
