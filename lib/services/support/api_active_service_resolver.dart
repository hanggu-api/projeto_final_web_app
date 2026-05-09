import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/network/backend_api_client.dart';

import '../models/api_identity_snapshot.dart';
import 'api_session_bootstrap.dart';
import 'api_active_service_policy.dart';

typedef ApiServiceNormalizer =
    Map<String, dynamic> Function(
      Map<String, dynamic> data, {
      required bool isFixed,
    });
typedef ApiFixedBookingEnricher =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> service);

class ApiActiveServiceResolution {
  final Map<String, dynamic>? service;
  final ApiIdentitySnapshot? hydratedIdentity;

  const ApiActiveServiceResolution({
    required this.service,
    required this.hydratedIdentity,
  });
}

class ApiActiveServiceResolver {
  static const BackendApiClient _backendApiClient = BackendApiClient();

  static List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<ApiActiveServiceResolution> resolve({
    required SupabaseClient client,
    required String authUid,
    required int? currentUserId,
    required String? currentRole,
    required bool Function(dynamic value) parseBool,
    required ApiServiceNormalizer normalizeNewService,
    required ApiFixedBookingEnricher enrichFixedBooking,
  }) async {
    var userId = currentUserId;
    var role = currentRole;
    ApiIdentitySnapshot? hydratedIdentity;

    if (userId == null || role == null) {
      try {
        final encodedUid = Uri.encodeQueryComponent(authUid);
        final userResponse = await _backendApiClient.getJson(
          '/api/v1/users?supabase_uid_eq=$encodedUid&limit=1',
        );
        final userRows = _asMapList(userResponse?['data']);
        final userRow = userRows.isEmpty ? null : userRows.first;
        if (userRow != null) {
          hydratedIdentity = ApiSessionBootstrap.identityFromUserRow(
            userRow,
            parseBool: parseBool,
          );
          userId = hydratedIdentity.userId ?? userId;
          role = hydratedIdentity.role ?? role;
        }
      } catch (e) {
        debugPrint(
          '⚠️ [ApiActiveServiceResolver] Falha ao reidratar identidade: $e',
        );
      }
    }

    final fixedResponse = await _backendApiClient.getJson(
      '/api/v1/bookings/fixed?auth_uid_eq=${Uri.encodeQueryComponent(authUid)}&limit=20&order=created_at.desc',
    );
    final fixedRows = _asMapList(fixedResponse?['data']);
    for (final raw in fixedRows) {
      final normalized = await enrichFixedBooking(
        normalizeNewService(
          raw,
          isFixed: true,
        ),
      );
      if (ApiActiveServicePolicy.isActiveForCurrentRole(
        service: normalized,
        authUid: authUid,
        userId: userId,
        role: role,
      )) {
        return ApiActiveServiceResolution(
          service: normalized,
          hydratedIdentity: hydratedIdentity,
        );
      }
    }

    final filters = <String>[
      'client_uid.eq.$authUid',
      'provider_uid.eq.$authUid',
    ];
    if (userId != null) {
      filters.add('client_id.eq.$userId');
      filters.add('provider_id.eq.$userId');
    }
    final mobileResponse = await _backendApiClient.getJson(
      '/api/v1/services/active?auth_uid_eq=${Uri.encodeQueryComponent(authUid)}'
      '${userId != null ? '&user_id_eq=$userId' : ''}&limit=30&order=created_at.desc',
    );
    final mobileRows = _asMapList(mobileResponse?['data']);
    for (final raw in mobileRows) {
      final normalized = normalizeNewService(
        raw,
        isFixed: false,
      );
      if (ApiActiveServicePolicy.isActiveForCurrentRole(
        service: normalized,
        authUid: authUid,
        userId: userId,
        role: role,
      )) {
        return ApiActiveServiceResolution(
          service: normalized,
          hydratedIdentity: hydratedIdentity,
        );
      }
    }

    return ApiActiveServiceResolution(
      service: null,
      hydratedIdentity: hydratedIdentity,
    );
  }
}
