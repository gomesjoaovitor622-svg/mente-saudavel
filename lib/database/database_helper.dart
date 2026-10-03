import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_schema.dart';
import 'package:mente_saudavel/database/database_seed.dart';

/// Abre (e cria, se necessário) o banco SQLite local do aparelho.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String _nomeBanco = 'mente_saudavel.db';
  static const int _versaoBanco = 1;

  Future<Database>? _dbFuture;

  Future<Database> get database => _dbFuture ??= _abrirBanco();

  Future<Database> _abrirBanco() async {
    try {
      final pasta = await getDatabasesPath();
      final caminho = join(pasta, _nomeBanco);

      final db = await openDatabase(
        caminho,
        version: _versaoBanco,
        // Ativa as chaves estrangeiras (ON DELETE CASCADE) a cada conexão.
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        // 1ª execução: cria as tabelas e grava os dados de demonstração.
        onCreate: (db, versao) async {
          await DatabaseSchema.executar(db);
          await DatabaseSeed.executar(db);
        },
        // Toda abertura: garante que as tabelas existem (auto-correção).
        onOpen: (db) async {
          await DatabaseSchema.executar(db);
        },
      );

      if (kDebugMode) {
        debugPrint('[SQLite] Banco aberto em: $caminho');
      }
      return db;
    } catch (e) {
      // Descarta o Future com erro para que a próxima chamada tente de novo.
      _dbFuture = null;
      rethrow;
    }
  }
}
