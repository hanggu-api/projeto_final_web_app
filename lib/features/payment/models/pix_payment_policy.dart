import 'pix_payment_contract.dart';
import '../../../core/utils/fixed_booking_hold_policy.dart';

class PixPaymentPolicy {
  const PixPaymentPolicy._();

  static String buildDetailedPaymentReason(PixPaymentArgs args) {
    final providerName = (args.providerName ?? '').trim();
    final serviceLabel = (args.serviceLabel ?? '').trim();
    final fiscalDescription = (args.fiscalDescription ?? '').trim();
    if (fiscalDescription.isNotEmpty) return fiscalDescription;

    final target = providerName.isNotEmpty
        ? providerName
        : 'prestador parceiro';
    if (args.statusSource == 'pending_fixed_booking') {
      final label = serviceLabel.isNotEmpty ? serviceLabel : 'agendamento';
      return 'Este Pix corresponde à taxa de intermediação e reserva do $label com $target. O pagamento identifica a cobrança na plataforma, apoia a conciliação tributária da intermediação e não substitui o valor principal do atendimento, que continua vinculado ao serviço agendado.';
    }

    final label = serviceLabel.isNotEmpty ? serviceLabel : 'serviço solicitado';
    if (args.paymentStage == 'remaining') {
      return 'Este Pix corresponde à liquidação final intermediada do $label relacionado a $target. O pagamento é identificado de forma detalhada para fins de conciliação operacional e tributária da plataforma.';
    }
    return 'Este Pix corresponde ao sinal de intermediação do $label vinculado a $target. O pagamento identifica a cobrança da plataforma, registra o motivo do recebimento e ajuda no enquadramento correto da intermediação para conciliação e tributação.';
  }

  static bool isPaid(PixPaymentArgs args, Map<String, dynamic> intent) {
    if (args.statusSource == 'service') {
      final paymentStatus = (intent['payment_status'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final paymentRemainingStatus = (intent['payment_remaining_status'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final status = (intent['status'] ?? '').toString().toLowerCase().trim();
      if (args.paymentStage == 'remaining') {
        return paymentRemainingStatus == 'paid' ||
            paymentRemainingStatus == 'approved' ||
            paymentRemainingStatus == 'paid_manual';
      }
      return paymentStatus == 'paid' ||
          paymentStatus == 'approved' ||
          paymentStatus == 'partially_paid' ||
          paymentStatus == 'paid_manual' ||
          {
            'accepted',
            'scheduled',
            'confirmed',
            'client_departing',
            'client_arrived',
            'arrived',
            'in_progress',
            'completed',
          }.contains(status);
    }

    final status = (intent['status'] ?? '').toString().toLowerCase().trim();
    return status == 'paid' || FixedBookingHoldPolicy.isIntentPaid(intent);
  }

  static bool isTerminal(PixPaymentArgs args, Map<String, dynamic> intent) {
    if (args.statusSource == 'service') {
      final status = (intent['status'] ?? '').toString().toLowerCase().trim();
      final paymentStatus = (intent['payment_status'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final paymentRemainingStatus = (intent['payment_remaining_status'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      if (args.paymentStage == 'remaining') {
        return {'cancelled', 'failed'}.contains(status) ||
            {'cancelled', 'failed'}.contains(paymentRemainingStatus);
      }
      return {'cancelled', 'failed'}.contains(status) ||
          {'cancelled', 'failed'}.contains(paymentStatus);
    }

    return FixedBookingHoldPolicy.resolveIntent(intent).isReleased;
  }

  static String backButtonLabel(PixPaymentArgs args) {
    if (args.statusSource == 'service' && args.paymentStage == 'remaining') {
      return 'Voltar ao acompanhamento';
    }
    if (args.statusSource == 'service') {
      return 'Voltar ao serviço';
    }
    return 'Voltar';
  }

  static String successRoute(PixPaymentArgs args, String createdServiceId) {
    final explicitRoute = (args.successRoute ?? '').trim();
    if (explicitRoute.isNotEmpty) return explicitRoute;
    if (args.statusSource == 'service') {
      if (args.paymentStage == 'remaining') {
        return '/service-tracking/$createdServiceId';
      }
      return '/service-busca-prestador-movel/$createdServiceId';
    }
    return '/scheduled-service/$createdServiceId';
  }
}
