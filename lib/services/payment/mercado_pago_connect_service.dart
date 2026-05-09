import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api_service.dart';

class MercadoPagoConnectService {
  final ApiService _api;

  MercadoPagoConnectService(this._api);

  /// Retorna a URL de autorização (Mercado Pago/Mercado Livre).
  Future<String> getAuthUrl(String userId, {String role = 'driver'}) async {
    debugPrint(
      '🔄 [MercadoPagoConnectService] Solicitando URL de autorização para: $userId (Role: $role)',
    );
    final response = await _api.invokeEdgeFunction('mp-get-auth-url', {
      'userId': userId,
      'role': role,
    });
    final map = Map<String, dynamic>.from(response as Map? ?? const {});
    final url = map['url']?.toString();
    if (url == null || url.isEmpty) {
      throw Exception('URL de autorização não recebida do servidor');
    }
    return url;
  }

  /// Obtém a URL de autorização e abre o navegador
  Future<void> connectAccount(String userId, {String role = 'driver'}) async {
    try {
      final url = await getAuthUrl(userId, role: role);

      debugPrint('🔗 [MercadoPagoConnectService] Abrindo URL: $url');
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        // Log útil para suporte: se o navegador ficar branco, o usuário pode copiar/colar esta URL.
        debugPrint('🧭 [MercadoPagoConnectService] AUTH_URL=$url');
        await launchUrl(
          uri,
          // Garante que abre fora do app (Chrome/Browser/MP se o Android capturar),
          // evitando "página interna" que pode parecer que não foi para o site.
          mode: LaunchMode.externalApplication,
        );
      } else {
        throw Exception('Não foi possível abrir o navegador para autorização');
      }
    } catch (e) {
      debugPrint('❌ [MercadoPagoConnectService] Erro ao conectar: $e');
      rethrow;
    }
  }

  /// Verifica se o usuário já possui conta conectada
  Future<bool> isConnected(String userId, {String role = 'driver'}) async {
    try {
      final intId = int.tryParse(userId);
      if (intId == null) return false;

      // Escolhe a tabela baseada no papel
      final table = role == 'driver' 
          ? 'driver_mercadopago_accounts' 
          : 'passenger_mercadopago_accounts';

      final response = await Supabase.instance.client
          .from(table)
          .select('access_token, refresh_token')
          .eq('user_id', intId)
          .maybeSingle();

      final accessToken = (response?['access_token'] ?? '').toString().trim();
      final refreshToken = (response?['refresh_token'] ?? '').toString().trim();
      return accessToken.isNotEmpty || refreshToken.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ [MercadoPagoConnectService] Erro ao verificar conexão ($role): $e');
      return false;
    }
  }
}
