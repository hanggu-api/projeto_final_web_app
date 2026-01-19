import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final _uuid = const Uuid();
  String? _currentSessionId;
  final List<Map<String, dynamic>> _queue = [];
  bool _isProcessing = false;

  /// Inicializa a sessão (Ex: ao abrir o App ou Logar)
  Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    _currentSessionId = prefs.getString('current_session_id');
    
    if (_currentSessionId == null) {
      _currentSessionId = _uuid.v4();
      await prefs.setString('current_session_id', _currentSessionId!);
    }
  }

  /// Limpa a sessão (Ex: Logout)
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_session_id');
    _currentSessionId = null;
  }

  /// Registra um evento genérico na fila interna (Fire and forget)
  void logEvent(String actionType, {Map<String, dynamic>? details}) {
    // Busca user_id (Zero se offline local)
    int? userId;
    try {
        final apiId = ApiService().userId; 
        userId = apiId;
    } catch(e) {}

    // Sem userId num app logado não se enquadra na regra de negócio atual,
    // mas se for app deslogado não rastreia por agora.
    if (userId == null && actionType != 'APP_OPENED') return; 

    final event = {
      'user_id': userId, // Se null, é descartado na batch da Cloudflare
      'session_id': _currentSessionId,
      'action_type': actionType,
      'action_details': details != null ? jsonEncode(details) : null,
      'created_at': DateTime.now().toIso8601String()
    };

    _queue.add(event);
    _processQueue(); // Aciona async para dar flush na Cloudflare
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    try {
      final api = ApiService();
      if (!api.isLoggedIn) {
         _isProcessing = false;
         return; 
      }

      // Tira um "recorte" da fila atual
      final batch = List<Map<String, dynamic>>.from(_queue);
      _queue.clear();

      final response = await api.postRaw('/analytics/log', batch);
      
      if (response.statusCode != 200) {
        // Se falhou por HTTP err, devolve para a fila pra tentar no proximo tick
        if (_queue.length < 100) { // Limite estrito de memory-leak local
           _queue.insertAll(0, batch); 
        }
      }
    } catch (e) {
      debugPrint('⚠️ [AnalyticsService] Error pushing logs: $e');
    } finally {
      _isProcessing = false;
    }
  }
}
