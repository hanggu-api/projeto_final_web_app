/// Payment method identifiers used across the app.
///
/// Note: Two different formats coexist in the codebase:
/// 1. Display/legacy formats: 'PIX', 'Card', 'MercadoPago', etc.
/// 2. Backend/edge-function formats: 'pix', 'credit_card', 'mercado_pago', etc.
abstract final class PaymentMethodDisplay {
  static const pix = 'PIX';
  static const pixDirect = 'pix_direct';
  static const card = 'Card';
  static const cardMachine = 'card_machine';
  static const cash = 'Dinheiro';
  static const mercadoPago = 'MercadoPago';
  static const wallet = 'Wallet';
}

abstract final class PaymentMethodBackend {
  static const pix = 'pix';
  static const creditCard = 'credit_card';
  static const debitCard = 'debit_card';
  static const mercadoPago = 'mercado_pago';
}
