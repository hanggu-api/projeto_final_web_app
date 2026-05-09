import 'package:flutter/foundation.dart';

import '../../../core/runtime/app_runtime_service.dart';
import '../../../core/network/backend_api_client.dart';
import '../../../domains/remote_ui/models/remote_action_request.dart';
import '../../../domains/remote_ui/models/remote_action_response.dart';

class SupabaseRemoteActionApi {
  static const _endpoint = '/api/v1/remote-ui/post-action';

  SupabaseRemoteActionApi({BackendApiClient? client})
    : _client = client ?? const BackendApiClient();

  final BackendApiClient _client;

  Future<RemoteActionResponse?> postAction(RemoteActionRequest request) async {
    try {
      final response = await _client.postJson(
        _endpoint,
        body: request.toJson(),
      );
      final payload = _readMap(response);
      if (payload.isEmpty) return null;
      return RemoteActionResponse.fromJson(payload);
    } catch (error, stackTrace) {
      debugPrint('⚠️ [RemoteUI] post_action failed: $error');
      AppRuntimeService.instance.logConfigFailure(
        'remote_ui:post_action:${request.commandKey}',
        error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static Map<String, dynamic> _readMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }
}
