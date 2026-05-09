import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../services/api_service.dart';
import '../config/supabase_config.dart';

class BackendApiClient {
  static const String _compileBaseUrl = String.fromEnvironment(
    'BACKEND_API_URL',
    defaultValue: '',
  );

  const BackendApiClient();

  String _normalizePathForBase(String baseUrl, String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    // Quando o fallback usa Supabase Edge Functions (`.../functions/v1`),
    // o nome da função fica logo após esse prefixo.
    // Nossos endpoints canônicos vêm como `/api/v1/...`; para função `api`,
    // o caminho correto é `/api/...` (sem o `/v1` duplicado no segmento da função).
    if (baseUrl.endsWith('/functions/v1') &&
        normalizedPath.startsWith('/api/v1/')) {
      return normalizedPath.replaceFirst('/api/v1/', '/api/');
    }
    return normalizedPath;
  }

  String? resolveBaseUrl() {
    String normalizeForRuntime(String raw) {
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          (raw.contains('127.0.0.1') || raw.contains('localhost'))) {
        return raw
            .replaceAll('127.0.0.1', '10.0.2.2')
            .replaceAll('localhost', '10.0.2.2');
      }
      return raw;
    }

    if (_compileBaseUrl.trim().isNotEmpty) {
      return normalizeForRuntime(_compileBaseUrl.trim());
    }
    final supabaseUrl = SupabaseConfig.url.trim();
    if (supabaseUrl.isNotEmpty) {
      return normalizeForRuntime('$supabaseUrl/functions/v1');
    }
    return null;
  }

  List<String> _resolveBaseUrlCandidates() {
    final out = <String>[];
    final primary = resolveBaseUrl();
    if (primary != null && primary.isNotEmpty) out.add(primary);
    final supabaseUrl = SupabaseConfig.url.trim();
    if (supabaseUrl.isNotEmpty) {
      final fallback = '$supabaseUrl/functions/v1';
      if (!out.contains(fallback)) out.add(fallback);
    }
    return out;
  }

  Future<Map<String, String>> buildHeaders() async {
    final headers = <String, String>{'content-type': 'application/json'};
    var token = ApiService().currentToken;
    if (token == null || token.trim().isEmpty) {
      try {
        await ApiService().loadToken();
        token = ApiService().currentToken;
      } catch (e) {
        debugPrint(
          '⚠️ [BackendApiClient] Falha ao recarregar token antes da request: $e',
        );
      }
    }
    final supabaseAnonKey = SupabaseConfig.anonKey.trim();
    if (token != null && token.trim().isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    } else if (supabaseAnonKey.isNotEmpty) {
      // Alguns endpoints de bootstrap exigem explicitamente Authorization.
      headers['authorization'] = 'Bearer $supabaseAnonKey';
    }
    if (supabaseAnonKey.isNotEmpty) {
      headers['apikey'] = supabaseAnonKey;
    }

    return headers;
  }

  Future<Map<String, dynamic>?> getJson(
    String path, {
    Duration timeout = const Duration(seconds: 10),
    int maxRetries = 3,
  }) async {
    final baseCandidates = _resolveBaseUrlCandidates();
    if (baseCandidates.isEmpty) {
      debugPrint(
        'ℹ️ [BackendApiClient] BACKEND_API_URL indisponível; endpoint=$path será ignorado.',
      );
      return null;
    }
    final headers = await buildHeaders();
    for (final baseUrl in baseCandidates) {
      final normalizedPath = _normalizePathForBase(baseUrl, path);
      final uri = Uri.parse('$baseUrl$normalizedPath');
      int attempt = 0;
      while (attempt < maxRetries) {
        attempt++;
        try {
          final response = await http
              .get(uri, headers: headers)
              .timeout(timeout);

          if (response.statusCode < 200 || response.statusCode >= 300) {
            debugPrint(
              '⚠️ [BackendApiClient] GET $normalizedPath falhou status=${response.statusCode} body=${response.body}',
            );
            // Não faz retry para erros 4xx (exceto 408/429)
            if (response.statusCode >= 400 &&
                response.statusCode < 500 &&
                response.statusCode != 408 &&
                response.statusCode != 429) {
              return null;
            }
            // Para 5xx e 408/429, tenta retry
            if (attempt < maxRetries) {
              final delay = Duration(milliseconds: 500 * attempt);
              await Future.delayed(delay);
              continue;
            }
            return null;
          }

          try {
            final decoded = jsonDecode(response.body);
            if (decoded is! Map<String, dynamic>) return null;
            return decoded;
          } on FormatException catch (e) {
            debugPrint(
              '⚠️ [BackendApiClient] JSON malformado em GET $normalizedPath: $e',
            );
            debugPrint(
              'Resposta recebida: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
            );
            return null;
          }
        } on TimeoutException catch (e) {
          debugPrint(
            '⚠️ [BackendApiClient] Timeout GET $normalizedPath (tentativa $attempt/$maxRetries): $e',
          );
          if (attempt < maxRetries) {
            final delay = Duration(milliseconds: 1000 * attempt);
            await Future.delayed(delay);
            continue;
          }
        } on SocketException catch (e) {
          debugPrint(
            '⚠️ [BackendApiClient] Erro de rede GET $normalizedPath (tentativa $attempt/$maxRetries): $e',
          );
          if (attempt < maxRetries) {
            final delay = Duration(milliseconds: 1000 * attempt);
            await Future.delayed(delay);
            continue;
          }
        } on HttpException catch (e) {
          debugPrint('⚠️ [BackendApiClient] Erro HTTP GET $normalizedPath: $e');
          break;
        } catch (e) {
          debugPrint(
            '⚠️ [BackendApiClient] Erro inesperado GET $normalizedPath: $e',
          );
          break;
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> postJson(
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
    int maxRetries = 3,
  }) async {
    final baseUrl = resolveBaseUrl();
    if (baseUrl == null || baseUrl.isEmpty) {
      debugPrint(
        'ℹ️ [BackendApiClient] BACKEND_API_URL indisponível; endpoint=$path será ignorado.',
      );
      return null;
    }

    final normalizedPath = _normalizePathForBase(baseUrl, path);
    final uri = Uri.parse('$baseUrl$normalizedPath');
    final headers = await buildHeaders();

    int attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      try {
        final response = await http
            .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(timeout);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          debugPrint(
            '⚠️ [BackendApiClient] POST $normalizedPath falhou status=${response.statusCode} body=${response.body}',
          );
          // Não faz retry para erros 4xx (cliente)
          if (response.statusCode >= 400 &&
              response.statusCode < 500 &&
              response.statusCode != 408 &&
              response.statusCode != 429) {
            return null;
          }
          if (attempt < maxRetries) {
            final delay = Duration(milliseconds: 500 * attempt);
            await Future.delayed(delay);
            continue;
          }
          return null;
        }

        try {
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) return null;
          return decoded;
        } on FormatException catch (e) {
          debugPrint(
            '⚠️ [BackendApiClient] JSON malformado em POST $normalizedPath: $e',
          );
          debugPrint(
            'Resposta recebida: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
          );
          return null;
        }
      } on TimeoutException catch (e) {
        debugPrint(
          '⚠️ [BackendApiClient] Timeout POST $normalizedPath (tentativa $attempt/$maxRetries): $e',
        );
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 1000 * attempt);
          await Future.delayed(delay);
          continue;
        }
        return null;
      } on SocketException catch (e) {
        debugPrint(
          '⚠️ [BackendApiClient] Erro de rede POST $normalizedPath (tentativa $attempt/$maxRetries): $e',
        );
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 1000 * attempt);
          await Future.delayed(delay);
          continue;
        }
        return null;
      } on HttpException catch (e) {
        debugPrint('⚠️ [BackendApiClient] Erro HTTP POST $normalizedPath: $e');
        return null;
      } catch (e) {
        debugPrint(
          '⚠️ [BackendApiClient] Erro inesperado POST $normalizedPath: $e',
        );
        return null;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> putJson(
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
    int maxRetries = 3,
  }) async {
    final baseUrl = resolveBaseUrl();
    if (baseUrl == null || baseUrl.isEmpty) {
      debugPrint(
        'ℹ️ [BackendApiClient] BACKEND_API_URL indisponível; endpoint=$path será ignorado.',
      );
      return null;
    }

    final normalizedPath = _normalizePathForBase(baseUrl, path);
    final uri = Uri.parse('$baseUrl$normalizedPath');
    final headers = await buildHeaders();

    int attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      try {
        final response = await http
            .put(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(timeout);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          debugPrint(
            '⚠️ [BackendApiClient] PUT $normalizedPath falhou status=${response.statusCode} body=${response.body}',
          );
          // Não faz retry para erros 4xx (cliente)
          if (response.statusCode >= 400 &&
              response.statusCode < 500 &&
              response.statusCode != 408 &&
              response.statusCode != 429) {
            return null;
          }
          if (attempt < maxRetries) {
            final delay = Duration(milliseconds: 500 * attempt);
            await Future.delayed(delay);
            continue;
          }
          return null;
        }

        try {
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) return null;
          return decoded;
        } on FormatException catch (e) {
          debugPrint(
            '⚠️ [BackendApiClient] JSON malformado em PUT $normalizedPath: $e',
          );
          debugPrint(
            'Resposta recebida: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
          );
          return null;
        }
      } on TimeoutException catch (e) {
        debugPrint(
          '⚠️ [BackendApiClient] Timeout PUT $normalizedPath (tentativa $attempt/$maxRetries): $e',
        );
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 1000 * attempt);
          await Future.delayed(delay);
          continue;
        }
        return null;
      } on SocketException catch (e) {
        debugPrint(
          '⚠️ [BackendApiClient] Erro de rede PUT $normalizedPath (tentativa $attempt/$maxRetries): $e',
        );
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 1000 * attempt);
          await Future.delayed(delay);
          continue;
        }
        return null;
      } on HttpException catch (e) {
        debugPrint('⚠️ [BackendApiClient] Erro HTTP PUT $normalizedPath: $e');
        return null;
      } catch (e) {
        debugPrint(
          '⚠️ [BackendApiClient] Erro inesperado PUT $normalizedPath: $e',
        );
        return null;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> deleteJson(
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
    int maxRetries = 3,
  }) async {
    final baseUrl = resolveBaseUrl();
    if (baseUrl == null || baseUrl.isEmpty) {
      debugPrint(
        'ℹ️ [BackendApiClient] BACKEND_API_URL indisponível; endpoint=$path será ignorado.',
      );
      return null;
    }

    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalizedPath');
    final headers = await buildHeaders();

    int attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      try {
        final response = await http
            .delete(
              uri,
              headers: headers,
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(timeout);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          debugPrint(
            '⚠️ [BackendApiClient] DELETE $normalizedPath falhou status=${response.statusCode} body=${response.body}',
          );
          // Não faz retry para erros 4xx (cliente)
          if (response.statusCode >= 400 &&
              response.statusCode < 500 &&
              response.statusCode != 408 &&
              response.statusCode != 429) {
            return null;
          }
          if (attempt < maxRetries) {
            final delay = Duration(milliseconds: 500 * attempt);
            await Future.delayed(delay);
            continue;
          }
          return null;
        }

        // DELETE pode retornar body vazio ou JSON
        if (response.body.isEmpty) {
          return <String, dynamic>{};
        }

        try {
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) return null;
          return decoded;
        } on FormatException catch (e) {
          debugPrint(
            '⚠️ [BackendApiClient] JSON malformado em DELETE $normalizedPath: $e',
          );
          debugPrint(
            'Resposta recebida: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
          );
          return null;
        }
      } on TimeoutException catch (e) {
        debugPrint(
          '⚠️ [BackendApiClient] Timeout DELETE $normalizedPath (tentativa $attempt/$maxRetries): $e',
        );
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 1000 * attempt);
          await Future.delayed(delay);
          continue;
        }
        return null;
      } on SocketException catch (e) {
        debugPrint(
          '⚠️ [BackendApiClient] Erro de rede DELETE $normalizedPath (tentativa $attempt/$maxRetries): $e',
        );
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 1000 * attempt);
          await Future.delayed(delay);
          continue;
        }
        return null;
      } on HttpException catch (e) {
        debugPrint(
          '⚠️ [BackendApiClient] Erro HTTP DELETE $normalizedPath: $e',
        );
        return null;
      } catch (e) {
        debugPrint(
          '⚠️ [BackendApiClient] Erro inesperado DELETE $normalizedPath: $e',
        );
        return null;
      }
    }
    return null;
  }
}
