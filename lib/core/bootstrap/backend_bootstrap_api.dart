import '../network/backend_api_client.dart';
import 'backend_bootstrap_state.dart';

class BackendBootstrapApi {
  const BackendBootstrapApi({BackendApiClient? client}) : _client = client ?? const BackendApiClient();

  final BackendApiClient _client;

  Future<BackendBootstrapState?> fetchBootstrap() async {
    final decoded = await _client.getJson('/api/v1/auth/bootstrap');
    if (decoded == null) {
      return null;
    }
    return BackendBootstrapState.fromJson(decoded);
  }
}
