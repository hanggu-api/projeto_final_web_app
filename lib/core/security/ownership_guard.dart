import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OwnershipGuard {
  /// Valida se o usuário atual é dono do registro antes de executar a operação.
  static Future<T> secureMutation<T>({
    required String table,
    required String idColumn,
    required String recordId,
    required Set<String> ownerFields, // ex: {'client_id', 'provider_id'}
    required Future<T> Function() operation,
    SupabaseClient? client,
  }) async {
    final supaClient = client ?? Supabase.instance.client;
    final currentUserId = supaClient.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw SecurityException('Usuário não autenticado');
    }

    // 1. Busca rápida apenas os campos de posse
    final res = await supaClient
        .from(table)
        .select(ownerFields.join(','))
        .eq(idColumn, recordId)
        .maybeSingle();

    if (res == null) throw SecurityException('Registro não encontrado');

    // 2. Validação de posse (funciona com int ou string)
    final isOwner = ownerFields.any((field) {
      final val = res[field];
      if (val == null) return false;
      return val.toString() == currentUserId || val.toString() == currentUserId.split('-').last;
    });

    if (!isOwner) {
      // Log para monitoramento de tentativas de IDOR
      debugPrint('🚨 [OwnershipGuard] Tentativa de acesso indevido bloqueada: table=$table id=$recordId');
      throw SecurityException('Acesso negado: tentativa de modificar dado alheio');
    }

    // 3. Se passou, executa a operação real
    return await operation();
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  @override String toString() => message;
}
