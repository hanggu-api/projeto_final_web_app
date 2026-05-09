import '../services/api_service.dart';
import '../services/ai_cache_service.dart';
import '../services/task_autocomplete.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

class TaskSemanticSearchService {
  TaskSemanticSearchService._();

  static final TaskSemanticSearchService _instance =
      TaskSemanticSearchService._();
  factory TaskSemanticSearchService() => _instance;

  final ApiService _api = ApiService();
  final AiCacheService _cache = AiCacheService();
  static const bool _useEdgeSemanticSearch = false;

  String _cacheKey(
    String query, {
    required String context,
    String? serviceTypeHint,
    int limit = 10,
  }) {
    final norm = TaskAutocomplete.normalizePt(query);
    final hint = (serviceTypeHint ?? '').trim().toLowerCase();
    return 'semantic:v2:$context:$hint:$limit:$norm';
  }

  List<Map<String, dynamic>> _normalizeResults(List<dynamic> raw) {
    return raw
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map((row) {
          final taskName = (row['task_name'] ?? row['name'] ?? '')
              .toString()
              .trim();
          debugPrint(
            '🔍 [Search Result] Task: $taskName, ServiceType: ${row['service_type']}',
          );
          return <String, dynamic>{
            ...row,
            'id': row['task_id'] ?? row['id'],
            'task_id': row['task_id'] ?? row['id'],
            'name': taskName,
            'task_name': taskName,
            'profession_name': (row['profession_name'] ?? '').toString(),
            'service_type': (row['service_type'] ?? '').toString(),
            'score': (double.tryParse((row['score'] ?? '0').toString()) ?? 0.0)
                .clamp(0.0, 1.0),
            'unit_price': row['unit_price'] ?? row['price'],
          };
        })
        .where((row) => (row['task_name'] as String).isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> search({
    required String query,
    required List<Map<String, dynamic>> catalog,
    required String context,
    String? serviceTypeHint,
    int limit = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final cacheKey = _cacheKey(
      trimmed,
      context: context,
      serviceTypeHint: serviceTypeHint,
      limit: limit,
    );

    if (!kIsWeb) {
      try {
        final cache = await _cache.getCache(cacheKey);
        if (cache != null && cache.isNotEmpty) {
          return _normalizeResults(cache);
        }
      } catch (e) {
        debugPrint('⚠️ [semantic-search] cache read falhou: $e');
      }
    }

    if (_useEdgeSemanticSearch) {
      try {
        final edgeResults = await _api.semanticTaskSearch(
          query: trimmed,
          context: context,
          serviceTypeHint: serviceTypeHint,
          limit: limit,
        );
        final normalized = _normalizeResults(edgeResults);
        if (normalized.isNotEmpty) {
          if (!kIsWeb) {
            try {
              await _cache.saveCache(cacheKey, normalized);
            } catch (e) {
              debugPrint('⚠️ [semantic-search] cache write falhou: $e');
            }
          }
          return normalized;
        }
      } catch (e) {
        debugPrint('❌ [semantic-search] edge falhou: $e');
      }
    }

    final local = TaskAutocomplete.suggestTasks(trimmed, catalog, limit: limit);
    final normalizedLocal = _normalizeResults(local);
    if (normalizedLocal.isNotEmpty) {
      if (!kIsWeb) {
        try {
          await _cache.saveCache(cacheKey, normalizedLocal);
        } catch (e) {
          debugPrint('⚠️ [semantic-search] cache write local falhou: $e');
        }
      }
    }
    return normalizedLocal;
  }
}
