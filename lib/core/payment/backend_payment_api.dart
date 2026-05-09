import '../network/backend_api_client.dart';

class BackendPaymentApi {
  const BackendPaymentApi({BackendApiClient? client})
    : _client = client ?? const BackendApiClient();

  final BackendApiClient _client;

  Future<Map<String, dynamic>?> fetchWallet() async {
    final decoded = await _client.getJson('/api/v1/payments/wallet');
    if (decoded == null) return null;
    final data = decoded['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  Future<bool> requestWithdrawal({required double amount}) async {
    if (amount <= 0) return false;
    final decoded = await _client.postJson(
      '/api/v1/payments/withdrawals',
      body: {'amount': amount},
    );
    return decoded != null;
  }
}
