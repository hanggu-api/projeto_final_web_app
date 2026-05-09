import '../network/backend_api_client.dart';
import 'backend_profile_state.dart';

class BackendProfileApi {
  const BackendProfileApi({BackendApiClient? client})
    : _client = client ?? const BackendApiClient();

  final BackendApiClient _client;

  Future<BackendProfileState?> fetchMyProfile() async {
    final decoded = await _client.getJson('/api/v1/profile/me');
    if (decoded == null) return null;
    return BackendProfileState.fromJson(decoded);
  }
}
