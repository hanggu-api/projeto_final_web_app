class CentralPaymentPolicy {
  static const double feePixPlataforma = 0.02;
  static const double feeMercadoPagoPlataforma = 0.05;
  static const double feeCartaoPlataforma = 0.05;
  static const double feeCartaoMaquina = 0.05;

  static double calculateFareWithFees(double baseFare, String paymentMethod) {
    final normalized = paymentMethod.trim().toLowerCase();
    switch (paymentMethod) {
      case 'PIX':
      case 'PIX Direto':
        return baseFare;
      case 'Dinheiro/Direto':
      case 'Dinheiro':
        return baseFare;
      case 'pix_direct':
        return baseFare;
      case 'MercadoPago':
      case 'Saldo Mercado Pago':
        return baseFare * (1 + feeMercadoPagoPlataforma);
      case 'Card':
      default:
        if (paymentMethod == 'Card' ||
            paymentMethod.startsWith('Card_') ||
            paymentMethod.contains('Cartão')) {
          return baseFare * (1 + feeCartaoPlataforma);
        }
        if (normalized.startsWith('card_machine')) {
          return baseFare * (1 + feeCartaoMaquina);
        }
        return baseFare;
    }
  }
}
