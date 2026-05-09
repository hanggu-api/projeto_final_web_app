abstract class PaymentRepository {
  Future<void> requestWithdrawal({
    required double amount,
  });
}
