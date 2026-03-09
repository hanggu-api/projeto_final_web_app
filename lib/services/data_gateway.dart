import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// DataGateway: O ponto único de verdade para dados do App.
/// Agora utiliza Firestore para streams em tempo real (Status e Chat)
/// e API para operações de escrita/leitura pontual.
class DataGateway {
  static final DataGateway _instance = DataGateway._internal();
  factory DataGateway() => _instance;
  DataGateway._internal();

  final ApiService _api = ApiService();
  // --- Caches de Stream para evitar múltiplas instâncias ---
  final Map<String, Stream<Map<String, dynamic>>> _serviceStreams = {};
  final Map<String, Stream<List<Map<String, dynamic>>>> _notificationStreams =
      {};

  /// Carrega detalhes do serviço diretamente do Supabase (sem backend legado).
  Future<Map<String, dynamic>> getServiceDetails(String serviceId) async {
    debugPrint(
      '📦 [DataGateway] Carregando serviço $serviceId via Supabase SDK',
    );
    try {
      final response = await Supabase.instance.client
          .from('service_requests_new')
          .select(
            '*, users!client_id(full_name, avatar_url), providers!provider_id(users!user_id(full_name, avatar_url)), service_categories!category_id(name)',
          )
          .eq('id', serviceId)
          .maybeSingle();

      if (response != null) {
        return response;
      }

      // Fallback para buscar na tabela trips caso não seja um service_requests_new
      debugPrint(
        '📦 [DataGateway] Serviço não encontrado em service_requests_new, tentando trips...',
      );
      final tripResponse = await Supabase.instance.client
          .from('trips')
          .select(
            '*, passenger:users!client_id(full_name, avatar_url), driver_user:users!driver_id(full_name, avatar_url)',
          )
          .eq('id', serviceId)
          .maybeSingle();

      if (tripResponse != null) {
        debugPrint('📦 [DataGateway] Trip encontrada: $tripResponse');
        // Adaptar o formato da corrida para o formato esperado pelo ChatScreen
        final mappedTrip = {
          ...tripResponse,
          'client_id': tripResponse['client_id'],
          'provider_id': tripResponse['driver_id'],
          'users': tripResponse['passenger'],
          'providers': {'users': tripResponse['driver_user']},
        };
        return mappedTrip;
      }

      return {};
    } catch (e) {
      debugPrint('❌ [DataGateway] Erro ao carregar serviço via Supabase: $e');
      rethrow;
    }
  }

  /// Retorna um Stream do serviço diretamente do Supabase com proteção de Múltiplos Listeners
  /// Tabela: service_requests_new
  Stream<Map<String, dynamic>> watchService(String serviceId) {
    if (_serviceStreams.containsKey(serviceId)) {
      debugPrint(
        '♻️ [DataGateway] Reutilizando watchService (Supabase) ativo para $serviceId',
      );
      return _serviceStreams[serviceId]!;
    }

    debugPrint(
      '🔥 [DataGateway] Iniciando NOVO watchService (Supabase) para $serviceId',
    );

    // Cria um Stream broadcast único combinado
    late StreamController<Map<String, dynamic>> controller;
    StreamSubscription? reqSub;
    StreamSubscription? tripSub;

    controller = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () {
        reqSub = Supabase.instance.client
            .from('service_requests_new')
            .stream(primaryKey: ['id'])
            .eq('id', serviceId)
            .map((snapshot) {
              if (snapshot.isEmpty) {
                return {'status': 'deleted', 'id': serviceId};
              }
              return snapshot.first;
            })
            .listen(
              (data) {
                if (data['status'] == 'deleted') {
                  // Se deletado ou não existe em service_requests_new, tenta em trips
                  tripSub ??= Supabase.instance.client
                      .from('trips')
                      .stream(primaryKey: ['id'])
                      .eq('id', serviceId)
                      .map((snapshot) {
                        if (snapshot.isEmpty) {
                          return {'status': 'deleted', 'id': serviceId};
                        }
                        final tripData = snapshot.first;
                        return {
                          ...tripData,
                          'client_id': tripData['passenger_id'],
                          'provider_id': tripData['driver_id'],
                        };
                      })
                      .listen((tripMap) => controller.add(tripMap));
                } else {
                  controller.add(data);
                }
              },
              onError: (e) {
                debugPrint('⚠️ [DataGateway] Erro no stream do serviço: $e');
                controller.addError(e);
              },
            );
      },
      onCancel: () {
        reqSub?.cancel();
        tripSub?.cancel();
      },
    );

    _serviceStreams[serviceId] = controller.stream;
    return controller.stream;
  }

  /// Retorna um Stream de mensagens do chat diretamente do Supabase.
  /// Tabela: chat_messages
  /// Sempre cria um stream novo para garantir snapshot inicial ao reabrir/recarregar.
  Stream<List<dynamic>> watchChat(String serviceId) {
    debugPrint('🔥 [DataGateway] Iniciando NOVO watchChat (Supabase) para $serviceId');

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
      debugPrint('♻️ [DataGateway] Reutilizando watchNotifications para $uid');
      return _notificationStreams[uid]!;
    }

    debugPrint('🔥 [DataGateway] Iniciando NOVO watchNotifications para $uid');

    // Tratativa para UID sendo Integer historicamente, e Supabase Auth id sendo UUID:
    // O ideal será buscar pelo user_id interno, mas se `uid` for o UUID (string longa):
    final Stream<List<Map<String, dynamic>>> stream = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq(
          'user_id',
          uid,
        ) // Assume que o banco sabe rotear via supabase_uid ou id dependendo do schema atual
        .order('created_at', ascending: false)
        .limit(50)
        .map((snapshot) {
          return snapshot.map((data) => data).toList();
        })
        .asBroadcastStream();

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
    String type,
  ) async {
    try {
      final userId = ApiService().userId;
      if (userId == null) {
        throw ApiException(
          message: 'Usuário não autenticado para enviar mensagem.',
          statusCode: 401,
        );
      }
      debugPrint(
        '📤 [DataGateway] Enviando mensagem para $serviceId: $content (tipo: $type) por usuário $userId',
      );
      await Supabase.instance.client
          .from('chat_messages')
          .insert({
            'service_id': serviceId,
            'sender_id': userId,
            'content': content,
            'type': type,
            'sent_at': DateTime.now().toIso8601String(),
          })
          .timeout(const Duration(seconds: 15));
      debugPrint(
        '✅ [DataGateway] Mensagem enviada com sucesso para $serviceId',
      );
    } on TimeoutException {
      throw ApiException(
        message: 'Não foi possível enviar a mensagem (Timeout).',
        statusCode: 408,
      );
    } catch (e) {
      debugPrint('❌ [DataGateway] Erro ao enviar mensagem: $e');
      throw ApiException(
        message: 'Falha ao enviar mensagem no chat.',
        statusCode: 500,
      );
    }
  }

  /// Marca uma mensagem de chat como lida.
  Future<void> markChatMessageRead(int messageId) async {
    try {
      await Supabase.instance.client
          .from('chat_messages')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('id', messageId);
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
