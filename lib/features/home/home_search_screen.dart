import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../core/network/backend_api_client.dart';
import '../../core/home/backend_home_api.dart';
import '../../core/utils/fixed_schedule_gate.dart';
import '../../services/task_autocomplete.dart';
import '../../services/task_semantic_search_service.dart';
import '../../services/api_service.dart';
import 'mobile_service_request_review_screen.dart';
import 'widgets/home_search_bar.dart';

class HomeSearchScreen extends StatefulWidget {
  final String initialQuery;
  final String? initialProfessionName;

  const HomeSearchScreen({
    super.key,
    this.initialQuery = '',
    this.initialProfessionName,
  });

  @override
  State<HomeSearchScreen> createState() => _HomeSearchScreenState();
}

class _HomeSearchScreenState extends State<HomeSearchScreen> {
  static const String _synonymLexiconCacheKey = 'home_synonym_lexicon_v1';

  final BackendHomeApi _backendHomeApi = const BackendHomeApi();
  final BackendApiClient _backendApiClient = const BackendApiClient();
  final TaskSemanticSearchService _semanticSearch = TaskSemanticSearchService();
  final ApiService _apiService = ApiService();

  final Map<String, List<Map<String, dynamic>>> _autocompleteHintsCache = {};
  final Map<String, Set<String>> _synonymLexicon = {};

  List<Map<String, dynamic>> _remoteAutocompleteHints = [];
  List<Map<String, dynamic>> _autocompleteCatalogRows = [];
  List<Map<String, dynamic>> _professionQuickAccessItems = [];

  Timer? _autocompleteDebounce;
  Timer? _noResultDelayTimer;
  String _searchText = '';
  int _searchSeedVersion = 0;
  int _autocompleteRequestVersion = 0;
  int _searchTraceSeq = 0;
  bool _isLoadingCatalog = true;
  bool _allowNoResultsMessage = false;

  @override
  void initState() {
    super.initState();
    _searchText = widget.initialQuery.trim();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _restoreSynonymLexiconFromCache();
    await _loadServiceAutocompleteCatalog();

    if (!mounted) return;
    if (widget.initialProfessionName != null &&
        widget.initialProfessionName!.trim().isNotEmpty) {
      _openProfessionQuickAccessByName(widget.initialProfessionName!.trim());
      return;
    }

    if (_searchText.isNotEmpty) {
      _fetchRemoteAutocompleteHints(_searchText);
    }
  }

  @override
  void dispose() {
    _autocompleteDebounce?.cancel();
    _noResultDelayTimer?.cancel();
    _autocompleteDebounce = null;
    _noResultDelayTimer = null;
    _remoteAutocompleteHints.clear();
    _autocompleteCatalogRows.clear();
    _professionQuickAccessItems.clear();
    _autocompleteHintsCache.clear();
    _synonymLexicon.clear();
    super.dispose();
  }

  void _armNoResultMessageDelay(String query) {
    _noResultDelayTimer?.cancel();
    if (query.trim().isEmpty) {
      if (_allowNoResultsMessage) {
        setState(() => _allowNoResultsMessage = false);
      }
      return;
    }
    if (_allowNoResultsMessage) {
      setState(() => _allowNoResultsMessage = false);
    }
    _noResultDelayTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (_searchText.trim().isEmpty) return;
      setState(() => _allowNoResultsMessage = true);
    });
  }

  Future<void> _restoreSynonymLexiconFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_synonymLexiconCacheKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _synonymLexicon.clear();
      decoded.forEach((key, value) {
        final token = key.toString().trim();
        if (token.isEmpty) return;
        if (value is List) {
          _synonymLexicon[token] = value
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toSet();
        }
      });
    } catch (_) {}
  }

  Future<void> _persistSynonymLexiconToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, List<String>>{};
      _synonymLexicon.forEach((key, value) {
        if (key.isEmpty || value.isEmpty) return;
        payload[key] = value.toList()..sort();
      });
      await prefs.setString(_synonymLexiconCacheKey, jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _loadServiceAutocompleteCatalog() async {
    try {
      final snapshot = await _backendHomeApi.fetchClientHome();
      var catalog = List<Map<String, dynamic>>.from(snapshot?.services ?? []);
      if (catalog.isEmpty) {
        catalog = await _loadTaskCatalogFallback();
      }
      if (catalog.isEmpty) {
        catalog = await _loadServicesCatalogFallback();
      }
      if (!mounted) return;

      String norm(String value) => value
          .toLowerCase()
          .replaceAll('á', 'a')
          .replaceAll('à', 'a')
          .replaceAll('â', 'a')
          .replaceAll('ã', 'a')
          .replaceAll('ä', 'a')
          .replaceAll('é', 'e')
          .replaceAll('ê', 'e')
          .replaceAll('è', 'e')
          .replaceAll('ë', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ì', 'i')
          .replaceAll('î', 'i')
          .replaceAll('ï', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ò', 'o')
          .replaceAll('ô', 'o')
          .replaceAll('õ', 'o')
          .replaceAll('ö', 'o')
          .replaceAll('ú', 'u')
          .replaceAll('ù', 'u')
          .replaceAll('û', 'u')
          .replaceAll('ü', 'u')
          .replaceAll('ç', 'c');

      final tokenReg = RegExp(r'[a-z0-9]{3,}');
      const baseGroups = <List<String>>[
        ['corte', 'cortar', 'aparar', 'degrade', 'degradee'],
        ['barba', 'barbear', 'barbeiro'],
        ['sobrancelha', 'designer', 'design'],
        ['maquiagem', 'maquiar', 'make'],
        ['hidratar', 'hidratacao', 'hidra'],
        ['escova', 'escovar'],
        ['limpeza', 'faxina', 'higienizacao', 'higienizar'],
        ['encanador', 'encanamento', 'hidraulico', 'bombeiro'],
        ['eletricista', 'eletrica', 'eletrico'],
        ['montagem', 'montar', 'instalacao', 'instalar'],
        ['grama', 'jardinagem', 'jardineiro', 'paisagismo'],
        ['pintura', 'pintor', 'pintar'],
      ];

      _synonymLexicon.clear();
      for (final group in baseGroups) {
        final g = group.map(norm).toSet();
        for (final token in g) {
          _synonymLexicon.putIfAbsent(token, () => <String>{}).addAll(g);
        }
      }

      final rows = catalog
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      for (final row in rows) {
        final profession = norm((row['profession_name'] ?? '').toString());
        final task = norm((row['task_name'] ?? row['name'] ?? '').toString());
        final keywords = norm((row['keywords'] ?? '').toString());
        final pool = '$profession $task $keywords';
        final tokens = tokenReg
            .allMatches(pool)
            .map((m) => m.group(0)!)
            .toSet()
            .where((t) => t.length >= 3)
            .toList();
        for (final t in tokens) {
          _synonymLexicon.putIfAbsent(t, () => <String>{}).add(t);
        }
        for (var i = 0; i < tokens.length; i++) {
          for (var j = i + 1; j < tokens.length; j++) {
            final a = tokens[i];
            final b = tokens[j];
            if (a.length < 4 || b.length < 4) continue;
            _synonymLexicon[a]!.add(b);
            _synonymLexicon[b]!.add(a);
          }
        }
      }

      setState(() {
        _autocompleteCatalogRows = rows;
        _professionQuickAccessItems = _buildProfessionQuickAccessItems(rows);
        _autocompleteHintsCache.clear();
        _isLoadingCatalog = false;
      });
      _persistSynonymLexiconToCache();
    } catch (_) {
      try {
        var fallbackCatalog = await _loadTaskCatalogFallback();
        if (fallbackCatalog.isEmpty) {
          fallbackCatalog = await _loadServicesCatalogFallback();
        }
        if (!mounted) return;
        setState(() {
          _autocompleteCatalogRows = fallbackCatalog;
          _professionQuickAccessItems = _buildProfessionQuickAccessItems(
            fallbackCatalog,
          );
          _autocompleteHintsCache.clear();
          _isLoadingCatalog = false;
        });
      } catch (_) {
        if (mounted) {
          setState(() => _isLoadingCatalog = false);
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadServicesCatalogFallback() async {
    final res = await _backendApiClient.getJson(
      '/api/v1/services?order=desc&limit=500',
    );
    final list = (res?['data'] as List? ?? const []);
    return list.whereType<Map>().map((raw) {
      final row = Map<String, dynamic>.from(raw);
      row['task_name'] =
          (row['task_name'] ?? row['name'] ?? row['description'] ?? '')
              .toString();
      row['profession_name'] =
          (row['profession_name'] ?? row['profession'] ?? '').toString();
      row['unit_price'] =
          row['unit_price'] ?? row['price'] ?? row['price_estimated'];
      return row;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadTaskCatalogFallback() async {
    final res = await _backendApiClient.getJson(
      '/api/v1/tasks?active_eq=true&limit=2000',
    );
    final list = (res?['data'] as List? ?? const []);
    return list.whereType<Map>().map((raw) {
      final row = Map<String, dynamic>.from(raw);
      final profession = row['professions'];
      if (profession is Map) {
        row['profession_name'] =
            (profession['name'] ?? row['profession_name'] ?? '').toString();
        row['profession_id'] =
            profession['id'] ?? row['profession_id'] ?? row['professionId'];
        row['service_type'] =
            (profession['service_type'] ?? row['service_type'] ?? '')
                .toString();
      }
      row['task_name'] = (row['task_name'] ?? row['name'] ?? '').toString();
      return row;
    }).toList();
  }

  String _nextTraceId(String query) {
    _searchTraceSeq += 1;
    return 'HS-${_searchTraceSeq.toString().padLeft(4, '0')}:${TaskAutocomplete.normalizePt(query)}';
  }

  void _traceSearch(String traceId, String msg) {
    if (!kDebugMode) return;
    debugPrint('[HomeSearch][$traceId] $msg');
  }

  Map<String, dynamic>? _normalizeSuggestion(
    Map<String, dynamic> row, {
    required String fallbackQuery,
  }) {
    final taskName =
        (row['task_name'] ?? row['name'] ?? row['description'] ?? '')
            .toString()
            .trim();
    final profession = (row['profession_name'] ?? row['profession'] ?? '')
        .toString()
        .trim();
    final resolvedTask = taskName.isNotEmpty ? taskName : fallbackQuery.trim();
    if (resolvedTask.isEmpty) return null;
    if (_isBlockedQueryOrSuggestion(resolvedTask, profession: profession)) {
      return null;
    }
    return <String, dynamic>{
      'task_name': resolvedTask,
      'profession_name': profession,
      'unit_price': row['unit_price'] ?? row['price'] ?? row['price_estimated'],
      'score': row['score'] ?? 0.0,
      'service_type': (row['service_type'] ?? '').toString().trim(),
      'service': Map<String, dynamic>.from(row),
    };
  }

  List<Map<String, dynamic>> _normalizeSuggestions(
    Iterable<Map<String, dynamic>> rows, {
    required String fallbackQuery,
    int limit = 8,
  }) {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final row in rows) {
      final normalized = _normalizeSuggestion(
        row,
        fallbackQuery: fallbackQuery,
      );
      if (normalized == null) continue;
      final key =
          '${TaskAutocomplete.normalizePt((normalized['task_name'] ?? '').toString())}|${TaskAutocomplete.normalizePt((normalized['profession_name'] ?? '').toString())}';
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(normalized);
      if (out.length >= limit) break;
    }
    return out;
  }

  List<Map<String, dynamic>> _findCatalogMatches(String query) {
    final q = TaskAutocomplete.normalizePt(query);
    if (q.isEmpty) return [];
    final matches = _autocompleteCatalogRows
        .where((row) {
          final task = TaskAutocomplete.normalizePt(
            (row['task_name'] ?? row['name'] ?? '').toString(),
          );
          final description = TaskAutocomplete.normalizePt(
            (row['description'] ?? '').toString(),
          );
          final profession = TaskAutocomplete.normalizePt(
            (row['profession'] ?? row['profession_name'] ?? '').toString(),
          );
          return task.contains(q) ||
              description.contains(q) ||
              profession.contains(q);
        })
        .map((r) => Map<String, dynamic>.from(r));
    return _normalizeSuggestions(matches, fallbackQuery: query, limit: 8);
  }

  List<Map<String, dynamic>> _readNonEmptyCache(String query) {
    final cached = _autocompleteHintsCache[query.toLowerCase()];
    if (cached == null || cached.isEmpty) return const [];
    return cached;
  }

  List<Map<String, dynamic>> _readPrefixCache(String query) {
    final q = TaskAutocomplete.normalizePt(query);
    if (q.length < 3) return const [];
    for (int i = q.length - 1; i >= 3; i--) {
      final prefix = q.substring(0, i);
      final cached = _autocompleteHintsCache[prefix];
      if (cached == null || cached.isEmpty) continue;
      final filtered = cached.where((row) {
        final task = TaskAutocomplete.normalizePt(
          (row['task_name'] ?? row['name'] ?? '').toString(),
        );
        final profession = TaskAutocomplete.normalizePt(
          (row['profession_name'] ?? row['profession'] ?? '').toString(),
        );
        return task.contains(q) || profession.contains(q);
      }).toList();
      if (filtered.isNotEmpty) return filtered;
    }
    return const [];
  }

  void _writeNonEmptyCache(String query, List<Map<String, dynamic>> items) {
    if (items.isEmpty) return;
    _autocompleteHintsCache[TaskAutocomplete.normalizePt(query)] = items;
  }

  bool _isBlockedQueryOrSuggestion(String text, {String? profession}) {
    return false;
  }

  void _fetchRemoteAutocompleteHints(String rawQuery) {
    _autocompleteDebounce?.cancel();
    final query = rawQuery.trim();
    final traceId = _nextTraceId(query);
    _armNoResultMessageDelay(query);
    _traceSearch(
      traceId,
      'input="$query" norm="${TaskAutocomplete.normalizePt(query)}" reqVer=${_autocompleteRequestVersion + 1}',
    );
    if (query.length < 2) {
      _autocompleteRequestVersion++;
      if (_remoteAutocompleteHints.isNotEmpty) {
        setState(() => _remoteAutocompleteHints = []);
      }
      _traceSearch(traceId, 'query<2 -> clear hints');
      return;
    }
    if (_isBlockedQueryOrSuggestion(query)) {
      _autocompleteRequestVersion++;
      if (_remoteAutocompleteHints.isNotEmpty) {
        setState(() => _remoteAutocompleteHints = []);
      }
      _traceSearch(traceId, 'blocked_query -> clear hints');
      return;
    }

    final instantLocal = _findCatalogMatches(query);
    _traceSearch(traceId, 'instantLocal=${instantLocal.length}');
    if (instantLocal.isNotEmpty) {
      _writeNonEmptyCache(query, instantLocal);
      setState(() => _remoteAutocompleteHints = instantLocal);
      _traceSearch(
        traceId,
        'render source=instantLocal items=${instantLocal.length} first="${instantLocal.first['task_name']}"',
      );
      return;
    }

    final cached = _readNonEmptyCache(query);
    _traceSearch(traceId, 'cache=${cached.length}');
    if (cached.isNotEmpty) {
      setState(() => _remoteAutocompleteHints = cached);
      _traceSearch(traceId, 'render source=cache items=${cached.length}');
      return;
    }

    final prefixCached = _readPrefixCache(query);
    if (prefixCached.isNotEmpty) {
      setState(() => _remoteAutocompleteHints = prefixCached);
      _traceSearch(
        traceId,
        'render source=prefixCache items=${prefixCached.length}',
      );
    }

    final requestVersion = ++_autocompleteRequestVersion;
    _autocompleteDebounce = Timer(const Duration(milliseconds: 220), () async {
      try {
        final semanticRaw = await _semanticSearch.search(
          query: query,
          catalog: _autocompleteCatalogRows,
          context: 'home_search_screen',
          limit: 12,
        );
        if (!mounted || requestVersion != _autocompleteRequestVersion) return;
        final semantic = _normalizeSuggestions(
          semanticRaw.map((e) => Map<String, dynamic>.from(e)),
          fallbackQuery: query,
          limit: 8,
        );
        _traceSearch(traceId, 'semantic=${semantic.length}');
        if (semantic.isNotEmpty) {
          _writeNonEmptyCache(query, semantic);
          setState(() => _remoteAutocompleteHints = semantic);
          _traceSearch(
            traceId,
            'render source=semantic items=${semantic.length}',
          );
          return;
        }

        final catalogScored = _normalizeSuggestions(
          TaskAutocomplete.suggestTasks(
            query,
            _autocompleteCatalogRows,
            limit: 12,
          ).map((e) => Map<String, dynamic>.from(e)),
          fallbackQuery: query,
          limit: 8,
        );
        _traceSearch(traceId, 'catalogScored=${catalogScored.length}');
        if (catalogScored.isNotEmpty) {
          _writeNonEmptyCache(query, catalogScored);
          setState(() => _remoteAutocompleteHints = catalogScored);
          _traceSearch(
            traceId,
            'render source=catalogScored items=${catalogScored.length}',
          );
          return;
        }

        final snapshot = await _backendHomeApi.fetchClientHome();
        if (!mounted || requestVersion != _autocompleteRequestVersion) return;
        final services = List<Map<String, dynamic>>.from(
          snapshot?.services ?? const [],
        );
        final fromServices = _normalizeSuggestions(
          services
              .where((row) {
                final qNorm = TaskAutocomplete.normalizePt(query);
                final desc = TaskAutocomplete.normalizePt(
                  (row['description'] ?? row['task_name'] ?? row['name'] ?? '')
                      .toString(),
                );
                final prof = TaskAutocomplete.normalizePt(
                  (row['profession'] ?? row['profession_name'] ?? '')
                      .toString(),
                );
                return desc.contains(qNorm) || prof.contains(qNorm);
              })
              .map((r) => Map<String, dynamic>.from(r)),
          fallbackQuery: query,
          limit: 8,
        );
        _traceSearch(traceId, 'fromServices=${fromServices.length}');
        if (fromServices.isNotEmpty) {
          _writeNonEmptyCache(query, fromServices);
          setState(() => _remoteAutocompleteHints = fromServices);
          _traceSearch(
            traceId,
            'render source=fromServices items=${fromServices.length}',
          );
          return;
        }

        final hintNames = await _apiService.fetchServiceAutocompleteHints(
          query,
          limit: 8,
        );
        if (!mounted || requestVersion != _autocompleteRequestVersion) return;
        final remoteFallback = _normalizeSuggestions(
          hintNames.map(
            (name) => <String, dynamic>{
              'task_name': name,
              'name': name,
              'profession_name': '',
            },
          ),
          fallbackQuery: query,
          limit: 8,
        );
        _traceSearch(traceId, 'tasksAutocomplete=${remoteFallback.length}');
        if (remoteFallback.isNotEmpty) {
          _writeNonEmptyCache(query, remoteFallback);
          setState(() => _remoteAutocompleteHints = remoteFallback);
          _traceSearch(
            traceId,
            'render source=tasksAutocomplete items=${remoteFallback.length}',
          );
          return;
        }
      } catch (e) {
        _traceSearch(traceId, 'pipeline exception=$e');
      }

      final typedSuggestion = _normalizeSuggestions(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'task_name': query.trim(),
            'name': query.trim(),
            'description': query.trim(),
            'profession_name': 'Sugestão digitada',
          },
        ],
        fallbackQuery: query,
        limit: 1,
      );
      _writeNonEmptyCache(query, typedSuggestion);
      setState(() => _remoteAutocompleteHints = typedSuggestion);
      _traceSearch(traceId, 'render source=typedSuggestion');
    });
  }

  List<Map<String, dynamic>> _buildProfessionQuickAccessItems(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final professionName = _stringValue(row['profession_name']);
      if (professionName.isEmpty) continue;
      final professionId = int.tryParse('${row['profession_id'] ?? ''}');
      final key =
          '${professionId ?? professionName}|${professionName.toLowerCase()}';
      final taskName = _stringValue(
        row['task_name'],
        fallback: _stringValue(row['name']),
      );
      final score = _extractProfessionRankingScore(row);

      final current = grouped[key];
      if (current == null) {
        grouped[key] = {
          'profession_id': professionId,
          'profession_name': professionName,
          'task_count': 1,
          'ranking_score': score,
          'sample_task': taskName,
          'service_type': _stringValue(row['service_type']),
        };
        continue;
      }

      current['task_count'] = (current['task_count'] as int) + 1;
      current['ranking_score'] = (current['ranking_score'] as int) + score;
      if ((_stringValue(current['sample_task'])).isEmpty &&
          taskName.isNotEmpty) {
        current['sample_task'] = taskName;
      }
    }

    final items = grouped.values
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final hasRankingData = items.any(
      (item) => ((item['ranking_score'] ?? 0) as int) > 0,
    );

    if (hasRankingData) {
      items.sort((a, b) {
        final byScore = ((b['ranking_score'] ?? 0) as int).compareTo(
          (a['ranking_score'] ?? 0) as int,
        );
        if (byScore != 0) return byScore;
        final byCount = ((b['task_count'] ?? 0) as int).compareTo(
          (a['task_count'] ?? 0) as int,
        );
        if (byCount != 0) return byCount;
        return _stringValue(
          a['profession_name'],
        ).compareTo(_stringValue(b['profession_name']));
      });
    } else {
      final random = math.Random();
      items.shuffle(random);
    }

    return items.take(12).toList();
  }

  int _extractProfessionRankingScore(Map<String, dynamic> row) {
    const candidates = [
      'completed_services_count',
      'services_completed_count',
      'service_count',
      'completed_count',
      'total_completed',
      'bookings_count',
      'requests_count',
    ];

    for (final key in candidates) {
      final raw = row[key];
      final parsed = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (parsed != null && parsed > 0) return parsed;
    }

    return 0;
  }

  bool _hasProfessionUsageRanking(Map<String, dynamic> item) {
    return _extractProfessionRankingScore(item) > 0;
  }

  String _professionQuickAccessMetricLabel(Map<String, dynamic> item) {
    final rankingScore = _extractProfessionRankingScore(item);
    if (rankingScore > 0) {
      return rankingScore == 1
          ? '1 atendimento concluido'
          : '$rankingScore atendimentos concluidos';
    }
    final taskCount = item['task_count'] is num
        ? (item['task_count'] as num).toInt()
        : int.tryParse('${item['task_count'] ?? ''}') ?? 0;
    if (taskCount > 1) {
      return '$taskCount servicos disponiveis';
    }
    if (taskCount == 1) {
      return '1 servico disponivel';
    }
    return 'Toque para ver servicos';
  }

  String _professionQuickAccessSummary(Map<String, dynamic> item) {
    final taskCount = item['task_count'] is num
        ? (item['task_count'] as num).toInt()
        : int.tryParse('${item['task_count'] ?? ''}') ?? 0;
    final sampleTask = _stringValue(item['sample_task']);
    if (_hasProfessionUsageRanking(item)) {
      return 'Mais usada na plataforma';
    }
    if (taskCount > 1) {
      return '$taskCount servicos nessa profissao';
    }
    if (sampleTask.isNotEmpty) {
      return sampleTask;
    }
    return 'Toque para ver os servicos';
  }

  IconData _resolveProfessionIcon(String professionName) {
    final normalized = professionName.toLowerCase();
    if (normalized.contains('barb') ||
        normalized.contains('cabelo') ||
        normalized.contains('beleza') ||
        normalized.contains('estet') ||
        normalized.contains('manicure')) {
      return Icons.content_cut_rounded;
    }
    if (normalized.contains('eletric')) {
      return Icons.electrical_services_rounded;
    }
    if (normalized.contains('encan') || normalized.contains('hidraul')) {
      return Icons.plumbing_rounded;
    }
    if (normalized.contains('pint')) {
      return Icons.format_paint_rounded;
    }
    if (normalized.contains('jardin')) {
      return Icons.yard_rounded;
    }
    if (normalized.contains('limpeza') || normalized.contains('faxina')) {
      return Icons.cleaning_services_rounded;
    }
    if (normalized.contains('mont') || normalized.contains('instal')) {
      return Icons.handyman_rounded;
    }
    return Icons.build_circle_outlined;
  }

  Color _resolveProfessionAccent(String professionName) {
    final normalized = professionName.toLowerCase();
    if (normalized.contains('barb') ||
        normalized.contains('cabelo') ||
        normalized.contains('beleza') ||
        normalized.contains('estet')) {
      return const Color(0xFFB45309);
    }
    if (normalized.contains('eletric')) {
      return const Color(0xFF2563EB);
    }
    if (normalized.contains('encan') || normalized.contains('hidraul')) {
      return const Color(0xFF0891B2);
    }
    if (normalized.contains('pint')) {
      return const Color(0xFF7C3AED);
    }
    if (normalized.contains('jardin')) {
      return const Color(0xFF15803D);
    }
    return const Color(0xFF1D4ED8);
  }

  bool _isBeautyProfession(Map<String, dynamic> profession) {
    final normalized = _stringValue(
      profession['profession_name'],
    ).toLowerCase().trim();
    final keywords = _stringValue(
      profession['profession_keywords'],
    ).toLowerCase().trim();
    const beautyTokens = [
      'barb',
      'cabel',
      'beleza',
      'estet',
      'manicure',
      'pedicure',
      'maqui',
      'depil',
      'sobrancel',
      'podolog',
      'massag',
      'sal',
      'spa',
      'escova',
      'unha',
    ];
    final matchesBeautyToken =
        beautyTokens.any(normalized.contains) ||
        beautyTokens.any(keywords.contains);
    if (matchesBeautyToken) {
      return true;
    }
    return isCanonicalFixedServiceRecord(profession) &&
        (normalized.contains('designer') || normalized.contains('studio'));
  }

  bool _isCanonicalFixedSuggestion(Map<String, dynamic> suggestion) {
    final service = suggestion['service'] is Map
        ? Map<String, dynamic>.from(suggestion['service'] as Map)
        : <String, dynamic>{};
    final seed = <String, dynamic>{...service, ...suggestion};
    return isCanonicalFixedServiceRecord(seed);
  }

  void _openProfessionQuickAccessByName(String professionName) {
    final normalizedProfession = professionName.toLowerCase().trim();
    final suggestions = _autocompleteCatalogRows
        .where(
          (row) =>
              _stringValue(row['profession_name']).toLowerCase().trim() ==
              normalizedProfession,
        )
        .map(
          (row) => {
            'task_name': _stringValue(
              row['task_name'],
              fallback: _stringValue(row['name']),
            ),
            'profession_name': professionName,
            'unit_price': row['unit_price'] ?? row['price'],
            'unit_name': _stringValue(row['unit_name']),
            'pricing_type': _stringValue(row['pricing_type']),
            'score': row['score'] ?? 0.0,
            'service_type': _stringValue(row['service_type']),
            'is_profession_seed': true,
            'service': row,
          },
        )
        .where((row) => _stringValue(row['task_name']).isNotEmpty)
        .toList();

    suggestions.sort((a, b) {
      final aTask = _stringValue(a['task_name']).toLowerCase();
      final bTask = _stringValue(b['task_name']).toLowerCase();
      return aTask.compareTo(bTask);
    });

    setState(() {
      _searchText = professionName;
      _remoteAutocompleteHints = suggestions;
      _searchSeedVersion++;
    });

    _autocompleteHintsCache[normalizedProfession] = suggestions;
  }

  void _handleSearchChanged(String rawQuery) {
    final query = rawQuery.trim();
    if (_searchText != query) {
      setState(() => _searchText = query);
    }
    _fetchRemoteAutocompleteHints(rawQuery);
  }

  void _handleSearchSubmitted(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return;
    if (_searchText != query) {
      setState(() => _searchText = query);
    }
    _fetchRemoteAutocompleteHints(query);
  }

  void _handleSearchClose() {
    setState(() {
      _searchText = '';
      _remoteAutocompleteHints = [];
      _searchSeedVersion++;
    });
  }

  void _openServicesQuickAccess() {
    if (_searchText.isNotEmpty) {
      _fetchRemoteAutocompleteHints(_searchText);
    }
  }

  void _openBeautyQuickAccess() {
    const beautySeed = 'beleza';
    if (_searchText != beautySeed) {
      setState(() {
        _searchText = beautySeed;
        _searchSeedVersion++;
      });
    }
    _fetchRemoteAutocompleteHints(beautySeed);
  }

  Future<void> _handleSuggestionSelected(
    Map<String, dynamic> suggestion,
  ) async {
    final query = (suggestion['task_name'] ?? suggestion['name'] ?? '')
        .toString()
        .trim();
    if (query.isEmpty) return;

    if ((suggestion['kind'] ?? '').toString() == 'provider_profile') {
      final providerId = int.tryParse('${suggestion['provider_id'] ?? ''}');
      if (providerId == null) return;
      await context.push('/provider-profile', extra: providerId);
      return;
    }

    if (_searchText != query) {
      setState(() {
        _searchText = query;
        _searchSeedVersion++;
      });
    }
    _fetchRemoteAutocompleteHints(query);

    Map<String, dynamic> effectiveSuggestion = Map<String, dynamic>.from(
      suggestion,
    );
    final hasExplicitType =
        _stringValue(effectiveSuggestion['service_type']).isNotEmpty ||
        (effectiveSuggestion['service'] is Map &&
            _stringValue(
              (effectiveSuggestion['service'] as Map)['service_type'],
            ).isNotEmpty);

    if (!hasExplicitType) {
      try {
        final classified = await _apiService.classifyService(query);
        final classifiedType = _stringValue(classified['service_type']);
        if (classifiedType.isNotEmpty) {
          effectiveSuggestion['service_type'] = classifiedType;
        }
        final classifiedProfession = _stringValue(classified['profissao']);
        if (classifiedProfession.isNotEmpty &&
            _stringValue(effectiveSuggestion['profession_name']).isEmpty) {
          effectiveSuggestion['profession_name'] = classifiedProfession;
        }
        final mergedService = <String, dynamic>{
          if (effectiveSuggestion['service'] is Map)
            ...(effectiveSuggestion['service'] as Map).cast<String, dynamic>(),
          'task_name': _stringValue(classified['task_name'], fallback: query),
          'profession_name': classifiedProfession,
          'profession_id': classified['profession_id'],
          'service_type': classifiedType,
          'task_id': classified['task_id'],
        }..removeWhere((_, value) => value == null);
        effectiveSuggestion['service'] = mergedService;
      } catch (_) {
        // Mantém fallback heurístico abaixo.
      }
    }

    final suggestionType = _resolveSuggestionServiceType(effectiveSuggestion);
    if (suggestionType == 'on_site') {
      await _showMobileServiceConfirmModal(effectiveSuggestion);
      return;
    }

    if (suggestionType == 'at_provider') {
      await context.push(
        '/beauty-booking',
        extra: {'q': query, 'service': effectiveSuggestion},
      );
    }
  }

  String _resolveSuggestionServiceType(Map<String, dynamic> suggestion) {
    final raw =
        (suggestion['service_type'] ??
                (suggestion['service'] is Map
                    ? (suggestion['service'] as Map)['service_type']
                    : null) ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    if (raw == 'on_site' || raw == 'at_provider' || raw == 'fixed') {
      return raw == 'fixed' ? 'at_provider' : raw;
    }

    if (_isCanonicalFixedSuggestion(suggestion)) {
      return 'at_provider';
    }

    final taskName =
        (suggestion['task_name'] ??
                suggestion['name'] ??
                (suggestion['service'] is Map
                    ? (suggestion['service'] as Map)['task_name']
                    : ''))
            .toString()
            .toLowerCase();
    final profession =
        (suggestion['profession_name'] ??
                (suggestion['service'] is Map
                    ? (suggestion['service'] as Map)['profession_name']
                    : ''))
            .toString()
            .toLowerCase();
    final category =
        (suggestion['category_name'] ??
                (suggestion['service'] is Map
                    ? (suggestion['service'] as Map)['category_name']
                    : ''))
            .toString()
            .toLowerCase();

    final looksFixed =
        profession.contains('barba') ||
        profession.contains('barbe') ||
        profession.contains('cabelo') ||
        profession.contains('estet') ||
        profession.contains('beleza') ||
        category.contains('beleza') ||
        taskName.contains('manicure') ||
        taskName.contains('pedicure') ||
        taskName.contains('sobrancelha') ||
        taskName.contains('unha');

    return looksFixed ? 'at_provider' : 'on_site';
  }

  Future<void> _showMobileServiceConfirmModal(
    Map<String, dynamic> suggestion,
  ) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MobileServiceRequestReviewScreen(suggestion: suggestion),
      ),
    );
  }

  String _stringValue(dynamic raw, {String fallback = ''}) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  Widget _buildQuickCategoryChip({
    required IconData icon,
    required String label,
    required String metric,
    required String summary,
    required Color accentColor,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    final backgroundColor = highlighted ? AppTheme.primaryYellow : Colors.white;
    final borderColor = highlighted
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.grey.shade200;
    final summaryColor = highlighted
        ? Colors.black.withValues(alpha: 0.76)
        : Colors.grey.shade700;
    final metricBackground = highlighted
        ? Colors.white.withValues(alpha: 0.78)
        : Colors.white;
    final metricTextColor = highlighted ? Colors.black : accentColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: highlighted
                          ? Colors.black
                          : accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      color: highlighted ? Colors.white : accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: metricBackground,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: highlighted
                                  ? Colors.black.withValues(alpha: 0.08)
                                  : accentColor.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Text(
                            metric,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: metricTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: summaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfessionQuickAccessGroup({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
    bool highlighted = false,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final displayedItems = items.take(6).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: highlighted
              ? Colors.black.withValues(alpha: 0.18)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: highlighted
                  ? Colors.black.withValues(alpha: 0.74)
                  : Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final useSingleColumn =
                  highlighted ||
                  displayedItems.length == 1 ||
                  constraints.maxWidth < 520;
              final chipWidth = useSingleColumn
                  ? constraints.maxWidth
                  : math.max((constraints.maxWidth - 10) / 2, 160.0);
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: displayedItems.map((profession) {
                  final professionName = _stringValue(
                    profession['profession_name'],
                  );
                  final isHighlighted =
                      highlighted || _hasProfessionUsageRanking(profession);
                  final resolvedAccent = _resolveProfessionAccent(
                    professionName,
                  );
                  return SizedBox(
                    width: chipWidth,
                    child: _buildQuickCategoryChip(
                      icon: _resolveProfessionIcon(professionName),
                      label: professionName,
                      metric: _professionQuickAccessMetricLabel(profession),
                      summary: _professionQuickAccessSummary(profession),
                      accentColor: resolvedAccent,
                      onTap: () =>
                          _openProfessionQuickAccessByName(professionName),
                      highlighted: isHighlighted,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final beautyProfessions = _professionQuickAccessItems
        .where(_isBeautyProfession)
        .toList();
    final generalProfessions = _professionQuickAccessItems
        .where((item) => !_isBeautyProfession(item))
        .toList();
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxSearchPanelHeight = math.max(
      120.0,
      MediaQuery.sizeOf(context).height * 0.956,
    );
    if (kDebugMode) {
      final branch = _isLoadingCatalog
          ? 'loading'
          : _searchText.trim().isEmpty
          ? 'quick-access'
          : _remoteAutocompleteHints.isNotEmpty
          ? 'suggestions'
          : _allowNoResultsMessage
          ? 'no-results'
          : 'idle-search';
      debugPrint(
        '[HomeSearch][build] q="${_searchText.trim()}" hints=${_remoteAutocompleteHints.length} allowNoResults=$_allowNoResultsMessage branch=$branch',
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Buscar serviços'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0B3),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxSearchPanelHeight),
                  child: SingleChildScrollView(
                    primary: false,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: HomeSearchBar(
                      key: const ValueKey('home-search-screen-bar'),
                      currentAddress: 'O que você precisa hoje?',
                      isLoadingLocation: false,
                      isEnabled: true,
                      autoFocus: true,
                      prominent: true,
                      onSuggestionSelected: _handleSuggestionSelected,
                      onQueryChanged: _handleSearchChanged,
                      onQuerySubmitted: _handleSearchSubmitted,
                      onCloseTap: _handleSearchClose,
                      autocompleteItems: List<Map<String, dynamic>>.from(
                        _remoteAutocompleteHints,
                      ),
                      seedQuery: _searchText,
                      seedVersion: _searchSeedVersion,
                      useInternalSearch: false,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (_isLoadingCatalog)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_searchText.trim().isEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildQuickCategoryChip(
                              icon: Icons.build_rounded,
                              label: 'Serviços',
                              metric: 'Atendimento móvel',
                              summary:
                                  'Manutenção, instalação e ajuda perto de você.',
                              accentColor: const Color(0xFF1D4ED8),
                              onTap: _openServicesQuickAccess,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildQuickCategoryChip(
                              icon: Icons.content_cut_rounded,
                              label: 'Beleza',
                              metric: 'Salão e barbearia',
                              summary:
                                  'Agenda, estética e atendimento em local parceiro.',
                              accentColor: const Color(0xFFB45309),
                              onTap: _openBeautyQuickAccess,
                              highlighted: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (beautyProfessions.isNotEmpty)
                        _buildProfessionQuickAccessGroup(
                          title: 'Beleza e estética',
                          subtitle:
                              'Profissões com agenda, salão e cuidados pessoais em destaque.',
                          items: beautyProfessions,
                          highlighted: true,
                        ),
                      if (beautyProfessions.isNotEmpty &&
                          generalProfessions.isNotEmpty)
                        const SizedBox(height: 12),
                      if (generalProfessions.isNotEmpty)
                        _buildProfessionQuickAccessGroup(
                          title: 'Outras profissões',
                          subtitle:
                              'Serviços móveis, reparos e atendimentos próximos de você.',
                          items: generalProfessions,
                        ),
                    ] else if (_remoteAutocompleteHints.isEmpty &&
                        _allowNoResultsMessage) ...[
                      InkWell(
                        onTap: () =>
                            _handleSuggestionSelected(<String, dynamic>{
                              'task_name': _searchText.trim(),
                              'name': _searchText.trim(),
                              'description': _searchText.trim(),
                              'profession_name': 'Sugestão digitada',
                              'service': <String, dynamic>{
                                'task_name': _searchText.trim(),
                                'name': _searchText.trim(),
                                'description': _searchText.trim(),
                              },
                            }),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Nenhum resultado encontrado para "${_searchText.trim()}".',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Toque para continuar com "${_searchText.trim()}".',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
