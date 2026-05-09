import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/logger.dart';

/// Centraliza o ciclo de vida do JWT do Supabase (access + refresh).
/// Garante refresh único e propaga falhas como SessionExpired.
class TokenManager {
  TokenManager._();
  static final TokenManager instance = TokenManager._();

  bool _isRefreshing = false;
  Completer<Session?>? _refreshCompleter;

  /// Obtém um access token válido, refrescando quando necessário.
  Future<String> getValidAccessToken({bool forceRefresh = false}) async {
    final session = await ensureSession(forceRefresh: forceRefresh);
    if (session == null || session.accessToken.isEmpty) {
      throw AuthException('Sessão inválida ou expirada.');
    }
    return session.accessToken;
  }

  /// Loga informações do token atual para auditoria de 401/Invalid JWT.
  /// Não imprime o token completo; apenas prefixo e claims principais.
  Future<void> auditCurrentToken({String prefix = ''}) async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;

    if (session == null) {
      debugPrint('🔍 [TokenAudit] $prefix sem sessão atual');
      return;
    }

    final token = session.accessToken;
    final expiresAt = session.expiresAt != null
        ? DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)
        : null;

    Map<String, dynamic> header = {};
    Map<String, dynamic> payload = {};
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        header = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))));
        payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      }
    } catch (e) {
      debugPrint('🔍 [TokenAudit] $prefix erro ao decodificar token: $e');
    }

    final safePrefix = token.length > 12 ? token.substring(0, 12) : token;
    debugPrint(
      '🔍 [TokenAudit] $prefix token=$safePrefix... exp=$expiresAt alg=${header['alg']} sub=${payload['sub']} role=${payload['role']} iss=${payload['iss']}',
    );
  }

  /// Garante sessão válida (refresh se perto de expirar ou se solicitado).
  Future<Session?> ensureSession({bool forceRefresh = false}) async {
    final client = Supabase.instance.client;
    Session? session = client.auth.currentSession;

    if (session == null) {
      return null;
    }

    final expiresAt = session.expiresAt != null
        ? DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)
        : null;

    final shouldRefresh = forceRefresh ||
        (expiresAt != null && DateTime.now().isAfter(expiresAt
            .subtract(const Duration(minutes: 5))));

    if (!shouldRefresh) return session;

    // Evita refresh concorrente
    if (_isRefreshing) {
      return _refreshCompleter!.future;
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<Session?>();

    try {
      final newSession = await client.auth.refreshSession();
      _refreshCompleter?.complete(newSession.session);
      return newSession.session;
    } on AuthException catch (e) {
      AppLogger.erro('TokenManager refresh falhou: ${e.message}', e);
      await client.auth.signOut();
      _refreshCompleter?.complete(null);
      return null;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  /// Força revalidação inicial (útil após Supabase.initialize).
  Future<void> warmUp() async {
    try {
      await ensureSession(forceRefresh: true);
    } catch (_) {
      // ignore: purposely silent, será tratado na próxima chamada.
    }
  }
}
