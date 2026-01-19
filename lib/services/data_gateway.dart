import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'realtime_service.dart';

/// DataGateway: O ponto único de verdade para dados do App.
/// Agora utiliza Firestore para streams em tempo real (Status e Chat)
/// e API para operações de escrita/leitura pontual.
class DataGateway {
  static final DataGateway _instance = DataGateway._internal();
  factory DataGateway() => _instance;
  DataGateway._internal();

  final ApiService _api = ApiService();
  final RealtimeService _realtime = RealtimeService();

  /// Carrega detalhes do serviço via API (D1) como fallback ou carga inicial.
  Future<Map<String, dynamic>> getServiceDetails(String serviceId) async {
    debugPrint('📦 [DataGateway] Carregando serviço $serviceId via API (D1)');
    try {
      final response = await _api.get('/services/$serviceId');
      return response['service'] ?? response;
    } catch (e) {
      debugPrint('❌ [DataGateway] Erro ao carregar serviço via API: $e');
      rethrow;
    }
  }

  /// Retorna um Stream do serviço diretamente do Supabase.
  /// Tabela: service_requests_new
  Stream<Map<String, dynamic>> watchService(String serviceId) {
    debugPrint('🔥 [DataGateway] Iniciando watchService (Supabase) para $serviceId');
    return Supabase.instance.client
        .from('service_requests_new')
        .stream(primaryKey: ['id'])
        .eq('id', serviceId)
        .map((snapshot) {
          if (snapshot.isEmpty) {
            return {'status': 'deleted', 'id': serviceId};
          }
          final data = snapshot.first;
          return data;
        })
        .handleError((e) {
          debugPrint('⚠️ [DataGateway] Erro no stream do serviço: $e');
          throw e; 
        });
  }

  /// Retorna um Stream de mensagens do chat diretamente do Supabase.
  /// Tabela: chat_messages
  Stream<List<dynamic>> watchChat(String serviceId) {
    debugPrint('🔥 [DataGateway] Iniciando watchChat (Supabase) para $serviceId');
    return Supabase.instance.client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('service_id', serviceId)
        .order('sent_at', ascending: false) // Mais recentes primeiro
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
    debugPrint('🔥 [DataGateway] Iniciando watchNotifications para $uid');
    
    // Tratativa para UID sendo Integer historicamente, e Supabase Auth id sendo UUID:
    // O ideal será buscar pelo user_id interno, mas se `uid` for o UUID (string longa):
    return Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid) // Assume que o banco sabe rotear via supabase_uid ou id dependendo do schema atual
        .order('created_at', ascending: false)
        .limit(50)
        .map((snapshot) {
          return snapshot.map((data) => data).toList();
        });
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

  /// Envia mensagens via API do Backend.
  Future<void> sendChatMessage(String serviceId, String content, String type) async {
    await _api.post('/chat/$serviceId/messages', {
      'content': content,
      'type': type,
    });
  }

  void reset() {
    _api.clearToken();
    _realtime.dispose();
  }
}
