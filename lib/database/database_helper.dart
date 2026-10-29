import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_schema.dart';
import 'package:mente_saudavel/database/database_seed.dart';
import 'package:mente_saudavel/database/migracoes.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Abre (e cria, se necessário) o banco SQLite local do aparelho.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String _nomeBanco = 'mente_saudavel.db';

  Future<Database>? _dbFuture;

  /// Só para testes: caminho do banco (use `inMemoryDatabasePath` para um banco descartável).
  @visibleForTesting
  static String? caminhoParaTestes;

  /// Só para testes: fecha o banco aberto para o próximo teste começar do zero.
  @visibleForTesting
  Future<void> reiniciar() async {
    final aberto = _dbFuture;
    _dbFuture = null;
    if (aberto != null) await (await aberto).close();
  }

  Future<Database> get database => _dbFuture ??= _abrirBanco();

  Future<Database> _abrirBanco() async {
    try {
      final caminho = caminhoParaTestes ?? join(await getDatabasesPath(), _nomeBanco);

      final db = await openDatabase(
        caminho,
        version: Migracoes.versaoAtual,
        // Ativa as chaves estrangeiras (ON DELETE CASCADE) a cada conexão.
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        // 1ª execução: cria o esquema mais recente. Dados de exemplo só em builds de DEMONSTRAÇÃO.
        onCreate: (db, versao) async {
          await DatabaseSchema.criarTudo(db);
          if (kDemoMode) {
            await DatabaseSeed.executar(db);
          }
        },
        // Versão antiga -> nova: passos versionados (ver migracoes.dart), tudo em uma transação.
        onUpgrade: Migracoes.atualizar,
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
