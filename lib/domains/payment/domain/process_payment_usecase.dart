import '../data/payment_repository.dart';

class ProcessPaymentUseCase {
  ProcessPaymentUseCase(this._repository);

  final PaymentRepository _repository;

  Future<void> withdraw(double amount) async {
    if (amount <= 0) {
      throw ArgumentError('O valor do saque deve ser maior que zero.');
    }

    await _repository.requestWithdrawal(amount: amount);
  }
}
