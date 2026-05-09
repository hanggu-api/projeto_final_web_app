import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  static final LocalDatabase _instance = LocalDatabase._internal();
  static Database? _database;

  LocalDatabase._internal();

  factory LocalDatabase() => _instance;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'app_local_v1.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Tabela de cache para busca IA
    await db.execute('''
      CREATE TABLE ai_search_cache (
        query TEXT PRIMARY KEY,
        response_json TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    // Podemos adicionar outras tabelas aqui no futuro
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
