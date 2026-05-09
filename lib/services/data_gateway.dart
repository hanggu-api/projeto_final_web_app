import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../core/network/backend_api_client.dart';
import 'models/chat_participant.dart';
import 'realtime_service.dart';

/// DataGateway: O ponto único de verdade para dados do App.
/// Agora utiliza Firestore para streams em tempo real (Status e Chat)
/// e API para operações de escrita/leitura pontual.
const bool _logVerboseDataGateway = false;
const String _chatParticipantsPrefsPrefix = 'chat_participants_v1::';

class DataGateway {
  static final DataGateway _instance = DataGateway._internal();
  factory DataGateway() => _instance;
  DataGateway._internal();

  final ApiService _api = ApiService();
  final BackendApiClient _backendApiClient = const BackendApiClient();
  // --- Caches de Stream para evitar múltiplas instâncias ---
  final Map<String, Stream<Map<String, dynamic>>> _serviceStreams = {};
  final Map<String, Stream<List<Map<String, dynamic>>>> _notificationStreams =
      {};
  final Map<String, Stream<List<Map<String, dynamic>>>> _dispatchQueueStreams =
      {};
  final Map<String, Stream<Map<String, dynamic>>> _providerLocationStreams = {};
  final Map<String, ({DateTime fetchedAt, Map<String, dynamic>? row})>
  _providerLocationQueryCache = {};
  static const Duration _providerLocationQueryCacheTtl = Duration(seconds: 6);

  List<Map<String, dynamic>> extractChatParticipants(
    Map<String, dynamic> details,
  ) {
    final participants = <Map<String, dynamic>>[];

    void addParticipant({
      required String role,
      dynamic id,
      String? name,
      String? avatar,
      String? phone,
      bool canSend = true,
      bool isPrimaryOperationalContact = false,
    }) {
      final normalizedId = '${id ?? ''}'.trim();
      final normalizedName = (name ?? '').trim();
      final normalizedPhone = (phone ?? '').trim();
      if (normalizedId.isEmpty &&
          normalizedName.isEmpty &&
          normalizedPhone.isEmpty) {
        return;
      }
      final dedupeKey = '$role|$normalizedId|$normalizedName|$normalizedPhone';
      if (participants.any((item) => item['dedupe_key'] == dedupeKey)) return;
      participants.add({
        'dedupe_key': dedupeKey,
        'role': role,
        'user_id': normalizedId.isEmpty ? null : normalizedId,
        'display_name': normalizedName,
        'avatar_url': avatar,
        'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
        'can_send': canSend,
        'is_primary_operational_contact': isPrimaryOperationalContact,
      });
    }

    addParticipant(
      role: 'provider',
      id: details['provider_id'] ?? details['prestador_user_id'],
      name:
          details['provider_name']?.toString() ??
          details['professional_name']?.toString() ??
          (details['provider'] is Map
              ? details['provider']['name']?.toString()
              : null),
      avatar:
          details['provider_avatar']?.toString() ??
          details['professional_avatar']?.toString(),
      phone: details['provider_phone']?.toString(),
      isPrimaryOperationalContact: true,
    );

    addParticipant(
      role: 'requester',
      id:
          details['client_id'] ??
          details['cliente_user_id'] ??
          details['user_id'],
      name:
          details['client_name']?.toString() ??
          details['user_name']?.toString() ??
          (details['client'] is Map
              ? details['client']['name']?.toString()
              : null),
      avatar:
          details['client_avatar']?.toString() ??
          details['user_avatar']?.toString(),
      phone: details['client_phone']?.toString(),
      isPrimaryOperationalContact: true,
    );

    addParticipant(
      role: 'beneficiary',
      id: details['beneficiary_user_id'] ?? details['recipient_user_id'],
      name:
          details['beneficiary_name']?.toString() ??
          details['recipient_name']?.toString(),
      avatar: details['beneficiary_avatar']?.toString(),
      phone:
          details['beneficiary_phone']?.toString() ??
          details['recipient_phone']?.toString(),
      isPrimaryOperationalContact: true,
    );

    addParticipant(
      role: 'guardian',
      id: details['guardian_user_id'] ?? details['contact_user_id'],
      name:
          details['guardian_name']?.toString() ??
          details['contact_name']?.toString(),
      avatar: details['guardian_avatar']?.toString(),
      phone:
          details['guardian_phone']?.toString() ??
          details['contact_phone']?.toString(),
    );

    return participants.map((item) {
      final normalized = Map<String, dynamic>.from(item);
      normalized.remove('dedupe_key');
      return ChatParticipant.fromMap(normalized).toMap();
    }).toList();
  }

  Future<void> saveChatParticipantsSnapshot(
    String serviceId,
    List<Map<String, dynamic>> participants,
  ) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final normalized = participants
        .map((item) => ChatParticipant.fromMap(item).toMap())
        .toList();
    await prefs.setString(
      '$_chatParticipantsPrefsPrefix$normalizedServiceId',
      jsonEncode(normalized),
    );
    unawaited(syncChatParticipantsRemote(normalizedServiceId, normalized));
  }

  Future<List<Map<String, dynamic>>> loadChatParticipantsSnapshot(
    String serviceId,
  ) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return const <Map<String, dynamic>>[];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      '$_chatParticipantsPrefsPrefix$normalizedServiceId',
    );
    if (raw == null || raw.trim().isEmpty)
      return const <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => ChatParticipant.fromMap(
              Map<String, dynamic>.from(item),
            ).toMap(),
          )
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> loadChatParticipantsRemote(
    String serviceId,
  ) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return const <Map<String, dynamic>>[];
    try {
      final response = await _backendApiClient.getJson(
        '/api/v1/chat/participants?service_id_eq=${Uri.encodeQueryComponent(normalizedServiceId)}',
      );
      final rows = response?['data'];
      if (rows is! List) return const <Map<String, dynamic>>[];
      return rows
          .whereType<Map>()
          .map(
            (item) => ChatParticipant.fromMap(
              Map<String, dynamic>.from(item),
            ).toMap(),
          )
          .toList();
    } catch (e) {
      debugPrint(
        'ℹ️ [DataGateway] Leitura remota de chat_participants indisponível: $e',
      );
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> loadChatConversations() async {
    try {
      final response = await _backendApiClient.getJson(
        '/api/v1/chat/conversations',
      );
      final rows = response?['data'];
      if (rows is! List) return const <Map<String, dynamic>>[];
      return rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (e) {
      debugPrint('⚠️ [DataGateway] loadChatConversations erro: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> loadMyServices() async {
    try {
      final role = (_api.role ?? '').toLowerCase().trim();
      final localUserId = (_api.userId ?? '').trim();
      if (role == 'provider') {
        final providerId = int.tryParse(localUserId);
        if (providerId == null || providerId <= 0) {
          return const <Map<String, dynamic>>[];
        }
        const activeStatuses = <String>[
          'pending',
          'accepted',
          'provider_near',
          'arrived',
          'in_progress',
          'schedule_proposed',
          'scheduled',
          'waiting_payment_remaining',
          'waiting_remaining_payment',
          'awaiting_confirmation',
          'waiting_client_confirmation',
          'contested',
          'open_for_schedule',
        ];
        final rows = await Supabase.instance.client
            .from('service_requests')
            .select('*')
            .eq('provider_id', providerId)
            .inFilter('status', activeStatuses)
            .order('created_at', ascending: false)
            .limit(20);
        return (rows as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }

      final snapshot = await _api.getActiveServiceSnapshot(forceRefresh: true);
      if (snapshot == null) return const <Map<String, dynamic>>[];
      return <Map<String, dynamic>>[Map<String, dynamic>.from(snapshot)];
    } catch (e) {
      debugPrint('⚠️ [DataGateway] loadMyServices erro: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<int> loadUnreadChatCount() async {
    return 0;
  }

  Future<List<Map<String, dynamic>>> loadProviderSchedules(
    String providerId,
  ) async {
    final normalizedProviderId = providerId.trim();
    if (normalizedProviderId.isEmpty) return const <Map<String, dynamic>>[];
    try {
      final response = await _backendApiClient.getJson(
        '/api/v1/providers/$normalizedProviderId/schedules',
      );
      final rows = response?['data'];
      if (rows is! List) return const <Map<String, dynamic>>[];
      return rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (e) {
      debugPrint('⚠️ [DataGateway] loadProviderSchedules erro: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> loadProviderScheduleExceptions(
    String providerId,
  ) async {
    final normalizedProviderId = providerId.trim();
    if (normalizedProviderId.isEmpty) return const <Map<String, dynamic>>[];
    try {
      final response = await _backendApiClient.getJson(
        '/api/v1/providers/$normalizedProviderId/schedule-exceptions',
      );
      final rows = response?['data'];
      if (rows is! List) return const <Map<String, dynamic>>[];
      return rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (e) {
      debugPrint('⚠️ [DataGateway] loadProviderScheduleExceptions erro: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<Set<String>> loadActivePrivateDispatchServiceIds(
    List<dynamic> services,
  ) async {
    final candidateIds = services
        .map((item) {
          if (item is! Map) return '';
          final map = Map<String, dynamic>.from(item);
          return (map['service_id'] ?? map['id'] ?? '').toString().trim();
        })
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (candidateIds.isEmpty) return <String>{};

    try {
      final queueRows = await Supabase.instance.client
          .from('service_dispatch_queue')
          .select('service_id,status')
          .inFilter('service_id', candidateIds)
          .neq('status', 'done');

      final blockedByQueue = (queueRows as List)
          .map((row) => (row as Map)['service_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final notifRows = await Supabase.instance.client
          .from('notificacao_de_servicos')
          .select('service_id,status')
          .inFilter('service_id', candidateIds)
          .inFilter('status', ['queued', 'notified']);

      final blockedByOffers = (notifRows as List)
          .map((row) => (row as Map)['service_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      return {...blockedByQueue, ...blockedByOffers};
    } catch (e) {
      debugPrint(
        '⚠️ [DataGateway] loadActivePrivateDispatchServiceIds erro: $e',
      );
      return <String>{};
    }
  }

  Future<List<Map<String, dynamic>>> loadProviderNotifiedOffers(
    String providerUserId, {
    int limit = 5,
  }) async {
    final normalizedProviderUserId = providerUserId.trim();
    if (normalizedProviderUserId.isEmpty) return const <Map<String, dynamic>>[];
    try {
      final rows = await Supabase.instance.client
          .from('notificacao_de_servicos')
          .select(
            'service_id,status,response_deadline_at,last_notified_at,ciclo_atual,queue_order',
          )
          .eq('provider_user_id', normalizedProviderUserId)
          .eq('status', 'notified')
          .order('last_notified_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (e) {
      debugPrint('⚠️ [DataGateway] loadProviderNotifiedOffers erro: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> loadServiceLogs(
    String serviceId, {
    int limit = 5,
  }) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return const <Map<String, dynamic>>[];
    try {
      final rows = await Supabase.instance.client
          .from('service_logs')
          .select('action, details, created_at')
          .eq('service_id', normalizedServiceId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (e) {
      debugPrint('⚠️ [DataGateway] loadServiceLogs erro: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<int?> resolveUserIdByAuthUid(String authUid) async {
    final normalizedAuthUid = authUid.trim();
    if (normalizedAuthUid.isEmpty) return null;
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('supabase_uid', normalizedAuthUid)
          .maybeSingle();
      final rawId = row?['id'];
      if (rawId is num) return rawId.toInt();
      return int.tryParse('$rawId');
    } catch (e) {
      debugPrint('⚠️ [DataGateway] resolveUserIdByAuthUid erro: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> loadProviderStartLocation(
    int providerUserId,
  ) async {
    try {
      final loc = await Supabase.instance.client
          .from('provider_locations')
          .select('latitude, longitude')
          .eq('provider_id', providerUserId)
          .maybeSingle();
      final lat1 = (loc?['latitude'] as num?)?.toDouble();
      final lon1 = (loc?['longitude'] as num?)?.toDouble();
      if (lat1 != null && lon1 != null) {
        return {'latitude': lat1, 'longitude': lon1};
      }

      final prov = await Supabase.instance.client
          .from('providers')
          .select('latitude, longitude')
          .eq('user_id', providerUserId)
          .maybeSingle();
      final lat2 = (prov?['latitude'] as num?)?.toDouble();
      final lon2 = (prov?['longitude'] as num?)?.toDouble();
      if (lat2 != null && lon2 != null) {
        return {'latitude': lat2, 'longitude': lon2};
      }
    } catch (e) {
      debugPrint('⚠️ [DataGateway] loadProviderStartLocation erro: $e');
    }
    return null;
  }

  Future<String?> loadTaskNameById(int taskId) async {
    if (taskId <= 0) return null;
    try {
      final row = await Supabase.instance.client
          .from('task_catalog')
          .select('name')
          .eq('id', taskId)
          .maybeSingle();
      final name = (row?['name'] ?? '').toString().trim();
      return name.isEmpty ? null : name;
    } catch (e) {
      debugPrint('⚠️ [DataGateway] loadTaskNameById erro: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> loadEmergencyOpenServices({
    int limit = 30,
  }) async {
    try {
      const openStatuses = [
        'pending',
        'open_for_schedule',
        'searching',
        'searching_provider',
        'search_provider',
        'waiting_provider',
      ];
      final rows = await Supabase.instance.client
          .from('service_requests')
          .select(
            'id,status,profession,description,address,price_estimated,price_upfront,latitude,longitude,category_id,client_id',
          )
          .inFilter('status', openStatuses)
          .isFilter('provider_id', null)
          .order('created_at', ascending: false)
          .limit(limit);

      final normalizedRows = (rows as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      final categoryIds = normalizedRows
          .map((row) => row['category_id'])
          .whereType<num>()
          .map((value) => value.toInt())
          .where((value) => value > 0)
          .toSet()
          .toList();

      Map<int, String> categoryNames = const <int, String>{};
      if (categoryIds.isNotEmpty) {
        try {
          final categoryRows = await Supabase.instance.client
              .from('service_categories')
              .select('id,name')
              .inFilter('id', categoryIds);
          categoryNames = (categoryRows as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .fold<Map<int, String>>(<int, String>{}, (acc, row) {
                final id = row['id'] is num
                    ? (row['id'] as num).toInt()
                    : int.tryParse('${row['id'] ?? ''}');
                final name = (row['name'] ?? '').toString().trim();
                if (id != null && id > 0 && name.isNotEmpty) {
                  acc[id] = name;
                }
                return acc;
              });
        } catch (e) {
          debugPrint(
            'ℹ️ [DataGateway] Falha ao enriquecer categorias abertas: $e',
          );
        }
      }

      return normalizedRows.map((row) {
        final enriched = Map<String, dynamic>.from(row);
        final categoryId = row['category_id'] is num
            ? (row['category_id'] as num).toInt()
            : int.tryParse('${row['category_id'] ?? ''}');
        final categoryName = categoryId == null
            ? null
            : categoryNames[categoryId];
        if (categoryName != null && categoryName.isNotEmpty) {
          enriched['category_name'] = categoryName;
          enriched['service_categories'] = {'name': categoryName};
        }
        return enriched;
      }).toList();
    } catch (e) {
      debugPrint('⚠️ [DataGateway] loadEmergencyOpenServices erro: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> loadServiceRequestById(String serviceId) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return null;
    try {
      final row = await Supabase.instance.client
          .from('service_requests')
          .select(
            'id,status,profession,description,address,price_estimated,price_upfront,latitude,longitude,category_id,client_id,task_id,provider_id',
          )
          .eq('id', normalizedServiceId)
          .maybeSingle();
      if (row == null) return null;
      final mapped = Map<String, dynamic>.from(row);

      final categoryId = mapped['category_id'] is num
          ? (mapped['category_id'] as num).toInt()
          : int.tryParse('${mapped['category_id'] ?? ''}');
      if (categoryId != null && categoryId > 0) {
        try {
          final categoryRow = await Supabase.instance.client
              .from('service_categories')
              .select('name')
              .eq('id', categoryId)
              .maybeSingle();
          final categoryName = (categoryRow?['name'] ?? '').toString().trim();
          if (categoryName.isNotEmpty) {
            mapped['category_name'] = categoryName;
            mapped['service_categories'] = {'name': categoryName};
          }
        } catch (e) {
          debugPrint(
            'ℹ️ [DataGateway] Falha ao enriquecer categoria do serviço $normalizedServiceId: $e',
          );
        }
      }

      return mapped;
    } catch (e) {
      debugPrint('⚠️ [DataGateway] loadServiceRequestById erro: $e');
      return null;
    }
  }

  Future<Set<String>> loadRejectedServiceIdsForProvider(
    int providerUserId,
  ) async {
    if (providerUserId <= 0) return <String>{};
    try {
      final rows = await Supabase.instance.client
          .from('notificacao_de_servicos')
          .select('service_id')
          .eq('provider_user_id', providerUserId)
          .eq('status', 'rejected');
      return (rows as List)
          .map((row) => (row as Map)['service_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      debugPrint('⚠️ [DataGateway] loadRejectedServiceIdsForProvider erro: $e');
      return <String>{};
    }
  }

  Future<void> syncChatParticipantsRemote(
    String serviceId,
    List<Map<String, dynamic>> participants,
  ) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return;
    try {
      await Supabase.instance.client
          .from('service_chat_participants')
          .delete()
          .eq('service_id', normalizedServiceId);

      if (participants.isEmpty) {
        return;
      }

      final payload = participants
          .map((item) => ChatParticipant.fromMap(item).toMap())
          .map(
            (item) => {
              'service_id': normalizedServiceId,
              'role': item['role'],
              'user_id': item['user_id'],
              'display_name': item['display_name'],
              'avatar_url': item['avatar_url'],
              'phone': item['phone'],
              'can_send': item['can_send'],
              'is_primary_operational_contact':
                  item['is_primary_operational_contact'],
            },
          )
          .toList();

      await Supabase.instance.client
          .from('service_chat_participants')
          .insert(payload);
    } catch (e) {
      debugPrint(
        'ℹ️ [DataGateway] Persistência remota de chat_participants indisponível: $e',
      );
    }
  }

  bool _isTransientRealtimeStreamError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('realtimecloseevent(code: 1006') ||
        text.contains('realtimesubscribestatus.channelerror') ||
        text.contains('realtimesubscribestatus.timedout') ||
        text.contains('websocket') ||
        text.contains('socket');
  }

  Map<String, dynamic> _normalizeFixedStreamRecord(
    Map<String, dynamic> raw,
    String serviceId,
  ) {
    return {
      ..._api.normalizeFixedServiceForUi(raw),
      'id': raw['id'] ?? serviceId,
      'not_found': false,
    };
  }

  /// Carrega detalhes do serviço diretamente do Supabase (sem backend legado).
  Future<Map<String, dynamic>> getServiceDetails(
    String serviceId, {
    ServiceDataScope scope = ServiceDataScope.auto,
  }) async {
    debugPrint('📦 [DataGateway] Carregando serviço $serviceId');
    try {
      if (scope == ServiceDataScope.mobileOnly ||
          scope == ServiceDataScope.auto) {
        final mobile = await _api.getServiceDetails(
          serviceId,
          scope: ServiceDataScope.mobileOnly,
        );
        if (mobile['not_found'] != true) {
          return mobile;
        }
      }

      if (scope == ServiceDataScope.fixedOnly ||
          scope == ServiceDataScope.auto) {
        final fixed = await _api.getServiceDetails(
          serviceId,
          scope: ServiceDataScope.fixedOnly,
        );
        if (fixed['not_found'] != true) return fixed;
      }

      if (scope == ServiceDataScope.tripOnly) {
        return {'id': serviceId, 'status': 'not_found', 'not_found': true};
      }

      if (scope != ServiceDataScope.auto) {
        return {'id': serviceId, 'status': 'not_found', 'not_found': true};
      }

      return {};
    } catch (e) {
      debugPrint('❌ [DataGateway] Erro ao carregar serviço via Supabase: $e');
      rethrow;
    }
  }

  /// Retorna um Stream do serviço diretamente do Supabase com proteção de Múltiplos Listeners
  /// Tabela: service_requests_new
  Stream<Map<String, dynamic>> watchService(
    String serviceId, {
    ServiceDataScope scope = ServiceDataScope.auto,
  }) {
    final cacheKey = '$serviceId::${scope.name}';
    if (_serviceStreams.containsKey(cacheKey)) {
      return _serviceStreams[cacheKey]!;
    }

    if (_logVerboseDataGateway) {
      debugPrint(
        '🔥 [DataGateway] Iniciando NOVO watchService (Supabase) para $serviceId',
      );
    }

    // Cria um Stream broadcast único combinado
    late StreamController<Map<String, dynamic>> controller;
    StreamSubscription? reqSub;
    Timer? retryTimer;
    bool isRestarting = false;
    int retryAttempt = 0;
    late void Function() startStream;

    Future<void> restartServiceStream([Object? error]) async {
      if (controller.isClosed || isRestarting) return;
      isRestarting = true;
      final waitSeconds = retryAttempt <= 0
          ? 1
          : (1 << retryAttempt).clamp(1, 10);
      retryAttempt = (retryAttempt + 1).clamp(0, 6);
      retryTimer?.cancel();
      retryTimer = Timer(Duration(seconds: waitSeconds), () async {
        if (controller.isClosed) {
          isRestarting = false;
          return;
        }
        try {
          await reqSub?.cancel();
          if (kIsWeb) {
            await RealtimeService().requestSocketReconnect();
          }
          startStream();
        } catch (e) {
          if (!controller.isClosed) {
            debugPrint(
              '⚠️ [DataGateway] Falha ao religar watchService($serviceId): $e',
            );
            unawaited(restartServiceStream(e));
          }
        } finally {
          isRestarting = false;
        }
      });
      if (_logVerboseDataGateway || error != null) {
        debugPrint(
          'ℹ️ [DataGateway] Reagendando watchService($serviceId) em ${waitSeconds}s${error == null ? '' : ' por $error'}',
        );
      }
    }

    startStream = () {
      if (scope == ServiceDataScope.fixedOnly) {
        reqSub = Supabase.instance.client
            .from('agendamento_servico')
            .stream(primaryKey: ['id'])
            .eq('id', serviceId)
            .map((snapshot) {
              if (snapshot.isEmpty) {
                return {
                  'status': 'not_found',
                  'id': serviceId,
                  'not_found': true,
                };
              }
              return _normalizeFixedStreamRecord(
                Map<String, dynamic>.from(snapshot.first),
                serviceId,
              );
            })
            .listen(
              (data) {
                retryAttempt = 0;
                controller.add(data);
              },
              onError: (e) {
                if (_isTransientRealtimeStreamError(e)) {
                  debugPrint(
                    'ℹ️ [DataGateway] Erro transitório no stream fixedOnly; tentando religar: $e',
                  );
                  unawaited(restartServiceStream(e));
                  return;
                }
                controller.addError(e);
              },
            );
        return;
      }

      if (scope == ServiceDataScope.tripOnly) {
        controller.add({
          'status': 'not_found',
          'id': serviceId,
          'not_found': true,
        });
        return;
      }

      reqSub = Supabase.instance.client
          .from('service_requests')
          .stream(primaryKey: ['id'])
          .eq('id', serviceId)
          .map((snapshot) {
            if (snapshot.isEmpty) {
              return {
                'status': 'not_found',
                'id': serviceId,
                'not_found': true,
              };
            }
            return snapshot.first;
          })
          .listen(
            (data) {
              retryAttempt = 0;
              if (data['status'] == 'not_found') {
                if (scope == ServiceDataScope.mobileOnly) {
                  controller.add({
                    'status': 'not_found',
                    'id': serviceId,
                    'not_found': true,
                  });
                  return;
                }
                Supabase.instance.client
                    .from('agendamento_servico')
                    .select('id')
                    .eq('id', serviceId)
                    .maybeSingle()
                    .then((rowFixo) {
                      if (rowFixo != null) {
                        reqSub?.cancel();
                        reqSub = Supabase.instance.client
                            .from('agendamento_servico')
                            .stream(primaryKey: ['id'])
                            .eq('id', serviceId)
                            .listen(
                              (snapshot) {
                                retryAttempt = 0;
                                if (snapshot.isNotEmpty) {
                                  controller.add(
                                    _normalizeFixedStreamRecord(
                                      Map<String, dynamic>.from(snapshot.first),
                                      serviceId,
                                    ),
                                  );
                                }
                              },
                              onError: (e) {
                                if (_isTransientRealtimeStreamError(e)) {
                                  debugPrint(
                                    'ℹ️ [DataGateway] Erro transitório no stream fixo (fallback interno); tentando religar: $e',
                                  );
                                  unawaited(restartServiceStream(e));
                                  return;
                                }
                                controller.addError(e);
                              },
                            );
                      } else {
                        controller.add({
                          'status': 'not_found',
                          'id': serviceId,
                          'not_found': true,
                        });
                      }
                    })
                    .catchError((e) {
                      controller.addError(e);
                      return null;
                    });
              } else {
                controller.add(data);
              }
            },
            onError: (e) {
              if (_isTransientRealtimeStreamError(e)) {
                debugPrint(
                  'ℹ️ [DataGateway] Erro transitório no stream do serviço; tentando religar: $e',
                );
                unawaited(restartServiceStream(e));
                return;
              }
              debugPrint('⚠️ [DataGateway] Erro no stream do serviço: $e');
              controller.addError(e);
            },
          );
    };

    controller = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () {
        startStream();
      },
      onCancel: () {
        retryTimer?.cancel();
        reqSub?.cancel();
      },
    );

    _serviceStreams[cacheKey] = controller.stream;
    return controller.stream;
  }

  Future<List<Map<String, dynamic>>> getDispatchQueueState(
    String serviceId,
  ) async {
    final rows = await Supabase.instance.client
        .from('notificacao_de_servicos')
        .select(
          'id,service_id,provider_user_id,status,queue_order,attempt_no,max_attempts,notification_count,response_deadline_at,last_notified_at,answered_at,skip_reason,distance',
        )
        .eq('service_id', serviceId);

    final normalized = (rows as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    normalized.sort(_compareDispatchRows);
    return normalized;
  }

  Stream<List<Map<String, dynamic>>> watchDispatchQueueState(String serviceId) {
    if (_dispatchQueueStreams.containsKey(serviceId)) {
      return _dispatchQueueStreams[serviceId]!;
    }

    final stream = Supabase.instance.client
        .from('notificacao_de_servicos')
        .stream(primaryKey: ['id'])
        .eq('service_id', serviceId)
        .map((rows) {
          final normalized = rows
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          normalized.sort(_compareDispatchRows);
          return normalized;
        })
        .asBroadcastStream();

    _dispatchQueueStreams[serviceId] = stream;
    return stream;
  }

  int _compareDispatchRows(Map<String, dynamic> a, Map<String, dynamic> b) {
    int parseInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('${value ?? ''}') ?? fallback;
    }

    final attemptCompare = parseInt(
      a['attempt_no'],
      fallback: 1,
    ).compareTo(parseInt(b['attempt_no'], fallback: 1));
    if (attemptCompare != 0) return attemptCompare;

    final queueCompare = parseInt(
      a['queue_order'],
      fallback: 99999,
    ).compareTo(parseInt(b['queue_order'], fallback: 99999));
    if (queueCompare != 0) return queueCompare;

    return parseInt(a['id']).compareTo(parseInt(b['id']));
  }

  /// Stream de localização do prestador (provider_locations) pelo `provider_id` (users.id).
  /// Retorna sempre o último registro da tabela (upsert).
  Stream<Map<String, dynamic>> watchProviderLocation(int providerId) {
    final key = 'id:$providerId';
    if (_providerLocationStreams.containsKey(key)) {
      return _providerLocationStreams[key]!;
    }

    final stream = Supabase.instance.client
        .from('provider_locations')
        .stream(primaryKey: ['provider_id'])
        .eq('provider_id', providerId)
        .map((snapshot) {
          if (snapshot.isEmpty) return <String, dynamic>{};
          return snapshot.first;
        })
        .asBroadcastStream();

    _providerLocationStreams[key] = stream;
    return stream;
  }

  /// Stream de localização do prestador (provider_locations) pelo `provider_uid` (users.supabase_uid / auth.uid).
  /// Retorna sempre o último registro da tabela (upsert).
  Stream<Map<String, dynamic>> watchProviderLocationByUid(String providerUid) {
    final uid = providerUid.trim();
    if (uid.isEmpty) {
      return const Stream.empty();
    }

    // Use a separate cache key namespace to avoid collisions with int providerId caching.
    final key = 'uid:$uid';
    if (_providerLocationStreams.containsKey(key)) {
      return _providerLocationStreams[key]!;
    }

    // provider_uid has a UNIQUE index (uuid-first), so it is safe to use as primaryKey for the stream.
    final stream = Supabase.instance.client
        .from('provider_locations')
        .stream(primaryKey: ['provider_uid'])
        .eq('provider_uid', uid)
        .map((snapshot) {
          if (snapshot.isEmpty) return <String, dynamic>{};
          return snapshot.first;
        })
        .asBroadcastStream();

    _providerLocationStreams[key] = stream;
    return stream;
  }

  Future<Map<String, dynamic>?> fetchProviderLocation({
    int? providerId,
    String? providerUid,
  }) async {
    final normalizedUid = providerUid?.trim();
    final cacheKey = normalizedUid != null && normalizedUid.isNotEmpty
        ? 'uid:$normalizedUid'
        : (providerId != null ? 'id:$providerId' : '');
    if (cacheKey.isEmpty) return null;

    final cached = _providerLocationQueryCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            _providerLocationQueryCacheTtl) {
      return cached.row;
    }

    final query = Supabase.instance.client
        .from('provider_locations')
        .select('latitude,longitude,updated_at');

    final row = normalizedUid != null && normalizedUid.isNotEmpty
        ? await query
              .eq('provider_uid', normalizedUid)
              .order('updated_at', ascending: false)
              .limit(1)
              .maybeSingle()
        : await query
              .eq('provider_id', providerId!)
              .order('updated_at', ascending: false)
              .limit(1)
              .maybeSingle();

    final normalized = row == null ? null : Map<String, dynamic>.from(row);
    _providerLocationQueryCache[cacheKey] = (
      fetchedAt: DateTime.now(),
      row: normalized,
    );
    return normalized;
  }

  Stream<Map<String, dynamic>> watchClientLocation(String serviceId) {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) {
      return const Stream.empty();
    }

    final key = 'client:$normalizedServiceId';
    if (_providerLocationStreams.containsKey(key)) {
      return _providerLocationStreams[key]!;
    }

    final stream = Supabase.instance.client
        .from('client_locations')
        .stream(primaryKey: ['service_id'])
        .eq('service_id', normalizedServiceId)
        .map((snapshot) {
          if (snapshot.isEmpty) return <String, dynamic>{};
          return snapshot.first;
        })
        .asBroadcastStream();

    _providerLocationStreams[key] = stream;
    return stream;
  }

  Future<Map<String, dynamic>?> fetchClientLocation(String serviceId) async {
    final normalizedServiceId = serviceId.trim();
    if (normalizedServiceId.isEmpty) return null;

    final cacheKey = 'client:$normalizedServiceId';
    final cached = _providerLocationQueryCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            _providerLocationQueryCacheTtl) {
      return cached.row;
    }

    final row = await Supabase.instance.client
        .from('client_locations')
        .select('latitude,longitude,tracking_status,updated_at,source')
        .eq('service_id', normalizedServiceId)
        .maybeSingle();

    final normalized = row == null ? null : Map<String, dynamic>.from(row);
    _providerLocationQueryCache[cacheKey] = (
      fetchedAt: DateTime.now(),
      row: normalized,
    );
    return normalized;
  }

  /// Retorna um Stream de mensagens do chat diretamente do Supabase.
  /// Tabela: chat_messages
  /// Sempre cria um stream novo para garantir snapshot inicial ao reabrir/recarregar.
  Stream<List<dynamic>> watchChat(String serviceId) {
    debugPrint(
      '🔥 [DataGateway] Iniciando NOVO watchChat (Supabase) para $serviceId',
    );

    return Supabase.instance.client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('service_id', serviceId)
        .order('sent_at', ascending: false) // Mais recentes primeiro
        .limit(200)
        .map((snapshot) {
          return snapshot.map((data) => data).toList();
        })
        .handleError((e) {
          debugPrint('⚠️ [DataGateway] Erro no stream do chat: $e');
          return <dynamic>[];
        });
  }

  /// Retorna um Stream de notificações do usuário do Supabase.
  /// Tabela: notifications
  Stream<List<Map<String, dynamic>>> watchNotifications(String uid) {
    if (_notificationStreams.containsKey(uid)) {
      ///  debugPrint('♻️ [DataGateway] Reutilizando watchNotifications para $uid');
      return _notificationStreams[uid]!;
    }

    debugPrint('🔥 [DataGateway] Iniciando NOVO watchNotifications para $uid');

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    StreamSubscription<List<Map<String, dynamic>>>? sub;

    final isUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(uid.trim());

    Future<void> start() async {
      try {
        String? userIdFilter;
        if (isUuid) {
          final row = await Supabase.instance.client
              .from('users')
              .select('id')
              .eq('supabase_uid', uid.trim())
              .maybeSingle();
          final resolvedId = row?['id'];
          if (resolvedId != null) userIdFilter = resolvedId.toString();
        } else {
          userIdFilter = uid.trim();
        }

        if (userIdFilter == null || userIdFilter.isEmpty) {
          controller.add(const <Map<String, dynamic>>[]);
          return;
        }

        sub = Supabase.instance.client
            .from('notifications')
            .stream(primaryKey: ['id'])
            .eq('user_id', userIdFilter)
            .order('created_at', ascending: false)
            .limit(50)
            .map((snapshot) => snapshot.map((data) => data).toList())
            .listen(controller.add, onError: controller.addError);
      } catch (e) {
        controller.addError(e);
      }
    }

    controller.onListen = () {
      start();
    };
    controller.onCancel = () async {
      await sub?.cancel();
      sub = null;
    };

    final Stream<List<Map<String, dynamic>>> stream = controller.stream;

    _notificationStreams[uid] = stream;
    return stream;
  }

  /// Marca notificação como lida
  Future<void> markNotificationRead(String uid, String notificationId) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'read': true})
          .eq('id', notificationId);
    } catch (e) {
      debugPrint('⚠️ [DataGateway] Erro ao marcar notificação como lida: $e');
    }
  }

  /// Envia mensagem de chat diretamente pelo Supabase SDK.
  Future<void> sendChatMessage(
    String serviceId,
    String content,
    String type, {
    String? recipientId,
  }) async {
    final trimmedServiceId = serviceId.trim();
    final trimmedContent = content.trim();
    try {
      final api = ApiService();
      final userId = api.userId;
      if (userId == null) {
        throw ApiException(
          message: 'Usuário não autenticado para enviar mensagem.',
          statusCode: 401,
        );
      }
      debugPrint(
        '📤 [DataGateway] Enviando mensagem para $trimmedServiceId: $trimmedContent (tipo: $type) por usuário $userId',
      );
      await api.invokeEdgeFunction('send-chat-message', {
        'service_id': trimmedServiceId,
        'content': trimmedContent,
        'type': type,
        if (recipientId != null && recipientId.trim().isNotEmpty)
          'recipient_id': recipientId.trim(),
      });
      debugPrint(
        '✅ [DataGateway] Mensagem enviada com sucesso para $trimmedServiceId',
      );
    } on TimeoutException {
      throw ApiException(
        message: 'Não foi possível enviar a mensagem (Timeout).',
        statusCode: 408,
      );
    } catch (e) {
      debugPrint('❌ [DataGateway] Erro ao enviar mensagem: $e');
      final raw = e.toString();
      final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(raw);
      final backendMessage = match?.group(1);
      throw ApiException(
        message: backendMessage ?? 'Falha ao enviar mensagem no chat.',
        statusCode: 500,
      );
    }
  }

  /// Marca uma mensagem de chat como lida.
  Future<void> markChatMessageRead(int messageId) async {
    try {
      await _api.invokeEdgeFunction('mark-chat-message-read', {
        'message_id': messageId,
      });
    } catch (e) {
      debugPrint(
        '⚠️ [DataGateway] Erro ao marcar mensagem de chat como lida: $e',
      );
    }
  }

  /// Limpa os caches de streams caso recarregados / desconectados
  void closeAndRemoveStream(String type, String id) {
    if (type == 'service') {
      _serviceStreams.remove(id);
    } else if (type == 'notification') {
      _notificationStreams.remove(id);
    }
  }

  void reset() {
    _api.clearToken();
    _serviceStreams.clear();
    _notificationStreams.clear();
  }
}
