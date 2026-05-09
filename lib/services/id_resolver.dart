import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/network/backend_api_client.dart';

/// Single source of truth for mapping Supabase Auth UUID (auth.uid) <-> public.users.id (BIGINT).
///
/// - `authUid` is stable for the authenticated session.
/// - `usersId` is the legacy numeric id used by several tables (e.g., `provider_locations.provider_id`).
class IdResolver {
  static final IdResolver _instance = IdResolver._internal();
  factory IdResolver() => _instance;
  IdResolver._internal();

  String? _cachedAuthUid;
  int? _cachedUsersId;
  final BackendApiClient _backendApiClient = const BackendApiClient();

  String? get authUid => Supabase.instance.client.auth.currentUser?.id;

  void clearCache() {
    _cachedAuthUid = null;
    _cachedUsersId = null;
  }

  Future<int?> getUsersId({Duration timeout = const Duration(seconds: 5)}) async {
    final currentUid = authUid;
    if (currentUid == null || currentUid.trim().isEmpty) return null;

    if (_cachedAuthUid == currentUid && _cachedUsersId != null) {
      return _cachedUsersId;
    }

    final encodedUid = Uri.encodeQueryComponent(currentUid);
    final response = await _backendApiClient.getJson(
      '/api/v1/users?supabase_uid_eq=$encodedUid&limit=1',
      timeout: timeout,
    );
    final rows = (response?['data'] as List? ?? const <dynamic>[]);
    final first = rows.isNotEmpty && rows.first is Map
        ? Map<String, dynamic>.from(rows.first as Map)
        : null;
    final id = first?['id'];
    final usersId = id is num ? id.toInt() : int.tryParse(id?.toString() ?? '');

    _cachedAuthUid = currentUid;
    _cachedUsersId = usersId;
    return usersId;
  }
}
