class TaskAutocomplete {
  static String normalizePt(String input) {
    var s = (input).toLowerCase();

    // Remove common PT-BR diacritics (best-effort, no external deps)
    const map = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };
    map.forEach((k, v) => s = s.replaceAll(k, v));

    // Keep letters/digits/spaces only
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static const _stopWords = {
    'eu',
    'quero',
    'preciso',
    'de',
    'um',
    'uma',
    'para',
    'com',
    'no',
    'na',
    'do',
    'da',
    'a',
    'o',
    'os',
    'as',
    'e',
    'ta',
    'esta',
    'meu',
    'minha',
    'seu',
    'sua',
  };

  static List<String> _tokens(String s) {
    final n = normalizePt(s);
    if (n.isEmpty) return const [];
    return n
        .split(' ')
        .where((t) => t.length >= 2 && !_stopWords.contains(t))
        .toList();
  }

  static double _jaccardTokens(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final sa = a.toSet();
    final sb = b.toSet();
    final inter = sa.intersection(sb).length;
    final uni = sa.union(sb).length;
    if (uni == 0) return 0;
    return inter / uni;
  }

  static Set<String> _trigrams(String s) {
    final n = normalizePt(s);
    if (n.length < 3) return {n};
    final out = <String>{};
    for (var i = 0; i <= n.length - 3; i++) {
      out.add(n.substring(i, i + 3));
    }
    return out;
  }

  static double _trigramSimilarity(String a, String b) {
    final ta = _trigrams(a);
    final tb = _trigrams(b);
    if (ta.isEmpty || tb.isEmpty) return 0;
    final inter = ta.intersection(tb).length;
    final uni = ta.union(tb).length;
    if (uni == 0) return 0;
    return inter / uni;
  }

  static String _expandSynonyms(String query) {
    var out = normalizePt(query);
    if (out.isEmpty) return out;

    out = out.replaceAll(RegExp(r'\bpenu\b'), 'pneu');
    out = out.replaceAll(RegExp(r'\braizes\b'), 'raiz');

    // Verb -> Noun expansion
    out = out.replaceAll(RegExp(r'\b(corta|cortar)\b'), 'corte barbear');
    out = out.replaceAll(RegExp(r'\b(pintar|pintar)\b'), 'pintura coloracao');
    out = out.replaceAll(RegExp(r'\b(lava|lavar)\b'), 'lavagem limpeza');
    out = out.replaceAll(
      RegExp(r'\b(fura|furar|furei)\b'),
      'furo pneu borracheiro',
    );
    out = out.replaceAll(
      RegExp(r'\b(concerta|concertar|conserta|consertar)\b'),
      'reparo manutencao conserto',
    );
    out = out.replaceAll(RegExp(r'\b(limpa|limpar)\b'), 'limpeza faxina');
    out = out.replaceAll(
      RegExp(r'\b(copia|copiaa|copiar)\b'),
      'copia chave duplicar',
    );
    out = out.replaceAll(
      RegExp(r'\b(chave|chaves)\b'),
      'chave chaveiro fechadura',
    );

    // Add anchors
    if (RegExp(r'\b(retoc|retoque)\b').hasMatch(out) &&
        RegExp(r'\braiz\b').hasMatch(out)) {
      out = '$out cabelo coloracao tintura';
    }
    if (RegExp(r'\bar\b').hasMatch(out) &&
        RegExp(r'\b(nao|gel|frio)\b').hasMatch(out)) {
      out = '$out ar condicionado split refrigeracao';
    }

    return out;
  }

  static List<Map<String, dynamic>> suggestTasks(
    String query,
    List<Map<String, dynamic>> catalog, {
    int limit = 10,
  }) {
    final queryNorm = normalizePt(query);
    if (queryNorm.length < 2) return const [];

    final qExpanded = _expandSynonyms(query);
    final qTokens = _tokens(qExpanded);
    if (qTokens.isEmpty) return const [];

    double scoreTask(Map<String, dynamic> t) {
      final name = (t['name'] ?? t['task_name'] ?? '').toString();
      final keywords = (t['keywords'] ?? '').toString();
      final prof = (t['profession_name'] ?? '').toString();

      final nameNorm = normalizePt(name);
      final kwNorm = normalizePt(keywords);
      final profNorm = normalizePt(prof);

      var score = 0.0;

      // Match Types
      if (nameNorm == queryNorm) score += 5.0;
      if (nameNorm.startsWith(queryNorm)) score += 3.0;
      if (nameNorm.contains(queryNorm)) score += 1.5;

      final nameTokens = _tokens(nameNorm);
      final kwTokens = _tokens(kwNorm);
      final profTokens = _tokens(profNorm);

      score += 2.0 * _jaccardTokens(qTokens, nameTokens);
      score += 1.0 * _jaccardTokens(qTokens, kwTokens);
      score += 0.4 * _jaccardTokens(qTokens, profTokens);

      // Fuzzy
      score += 1.2 * _trigramSimilarity(queryNorm, nameNorm);
      score += 0.5 * _trigramSimilarity(queryNorm, kwNorm);

      // Price nudge
      final price = t['unit_price'] ?? t['price'];
      if (price != null) score += 0.1;

      return score;
    }

    final scored =
        catalog
            .map((t) => Map<String, dynamic>.from(t)..['score'] = scoreTask(t))
            .where((t) => (t['score'] as double) >= 0.45)
            .toList()
          ..sort(
            (a, b) => (b['score'] as double).compareTo(a['score'] as double),
          );

    // Deduplication
    final seen = <String>{};
    final uniqueResults = <Map<String, dynamic>>[];

    for (var res in scored) {
      final name = (res['name'] ?? res['task_name'] ?? '').toString();
      final nameNorm = normalizePt(name);
      if (!seen.contains(nameNorm)) {
        seen.add(nameNorm);
        uniqueResults.add(res);
      }
    }

    return uniqueResults.take(limit).toList();
  }
}
