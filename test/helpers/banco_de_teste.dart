import 'dart:io';

import 'package:mente_saudavel/database/database_schema.dart';
import 'package:mente_saudavel/database/migracoes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Banco SQLite de verdade (arquivo temporário) para os testes, sem celular nem emulador.
void iniciarSqliteDeTeste() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

Future<String> caminhoTemporario() async {
  final pasta = await Directory.systemTemp.createTemp('ms_teste_');
  return '${pasta.path}/teste.db';
}

/// Banco NOVO, já no esquema mais recente (o mesmo que o app cria na 1ª execução).
Future<Database> abrirBancoNovo([String? caminho]) async {
  return databaseFactory.openDatabase(
    caminho ?? inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: Migracoes.versaoAtual,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => DatabaseSchema.criarTudo(db),
    ),
  );
}

Future<int> novoUsuario(Database db, String nome, String perfil, {int? valorCentavos}) {
  return db.insert('usuarios', {
    'nome': nome,
    'email': '${nome.toLowerCase()}@teste.com',
    'senha_hash': 'x',
    'salt': 'y',
    'perfil': perfil,
    if (valorCentavos != null) 'valor_sessao_centavos': valorCentavos,
    'criado_em': DateTime.now().toIso8601String(),
  });
}
