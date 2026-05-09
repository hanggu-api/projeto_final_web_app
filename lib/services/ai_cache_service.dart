import 'dart:convert';
import '../core/database/local_database.dart';
import 'package:sqflite/sqflite.dart';

class AiCacheService {
  static final AiCacheService _instance = AiCacheService._internal();
  final LocalDatabase _dbHelper = LocalDatabase();

  AiCacheService._internal();

  factory AiCacheService() => _instance;

  // Normaliza a query para evitar duplicatas por causa de espaços ou caixa alta
  String _normalize(String query) => query.trim().toLowerCase();

  Future<void> saveCache(String query, List<dynamic> suggestions) async {
    final db = await _dbHelper.database;
    final normalizedQuery = _normalize(query);
    
    await db.insert(
      'ai_search_cache',
      {
        'query': normalizedQuery,
        'response_json': jsonEncode(suggestions),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<dynamic>?> getCache(String query) async {
    final db = await _dbHelper.database;
    final normalizedQuery = _normalize(query);

    final List<Map<String, dynamic>> maps = await db.query(
      'ai_search_cache',
      where: 'query = ?',
      whereArgs: [normalizedQuery],
    );

    if (maps.isEmpty) return null;

    final result = maps.first;
    final timestamp = result['timestamp'] as int;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Cache expira em 24 horas (86.400.000 ms)
    if (now - timestamp > 86400000) {
      // Opcional: deletar o item expirado
      await db.delete('ai_search_cache', where: 'query = ?', whereArgs: [normalizedQuery]);
      return null;
    }

    return jsonDecode(result['response_json'] as String) as List<dynamic>;
  }

  Future<void> clearAllCache() async {
    final db = await _dbHelper.database;
    await db.delete('ai_search_cache');
  }
}
