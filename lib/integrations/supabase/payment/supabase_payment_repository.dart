import '../../../core/payment/backend_payment_api.dart';
import '../../../domains/payment/data/payment_repository.dart';

class SupabasePaymentRepository implements PaymentRepository {
  SupabasePaymentRepository({
    BackendPaymentApi backendPaymentApi = const BackendPaymentApi(),
  }) : _backendPaymentApi = backendPaymentApi;

  final BackendPaymentApi _backendPaymentApi;

  @override
  Future<void> requestWithdrawal({required double amount}) async {
    final ok = await _backendPaymentApi.requestWithdrawal(amount: amount);
    if (!ok) {
      throw Exception('Falha ao solicitar saque no backend canônico.');
    }
  }
}
