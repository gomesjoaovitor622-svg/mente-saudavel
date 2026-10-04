import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/utils/app_exception.dart';

/// Resultado de uma consulta: nomes das colunas + linhas.
class ResultadoConsulta {
  final List<String> colunas;
  final List<List<Object?>> linhas;

  const ResultadoConsulta(this.colunas, this.linhas);
}

/// Ferramenta de leitura do banco, usada pela tela "Ver banco de dados".
/// Só lê: qualquer comando que altere dados é bloqueado.
class DbInspector {
  static const Set<String> _sensiveis = {'senha_hash', 'salt'};
  static const int _limiteLinhas = 200;

  Future<Database> get _db => DatabaseHelper.instance.database;

  bool _ehSensivel(String coluna) => _sensiveis.contains(coluna.toLowerCase());

  // Senhas (hash e sal) nunca são exibidas nem exportadas.
  Object? _mascarar(String coluna, Object? valor) {
    if (valor != null && _ehSensivel(coluna)) return '••••••';
    return valor;
  }

  ResultadoConsulta _montar(List<Map<String, Object?>> linhas, {List<String>? colunasPadrao}) {
    if (linhas.isEmpty) {
      return ResultadoConsulta(colunasPadrao ?? const [], const []);
    }
    final colunas = linhas.first.keys.toList();
    final dados = linhas.map((l) => colunas.map((c) => _mascarar(c, l[c])).toList()).toList();
    return ResultadoConsulta(colunas, dados);
  }

  Future<List<String>> listarTabelas() async {
    final db = await _db;
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%' ORDER BY name",
    );
    return r.map((l) => l['name'] as String).toList();
  }

  // Garante que o nome da tabela é um nome que realmente existe no banco.
  Future<void> _validarTabela(String tabela) async {
    final tabelas = await listarTabelas();
    if (!tabelas.contains(tabela)) {
      throw const AppException('Tabela inexistente.');
    }
  }

  Future<int> contar(String tabela) async {
    await _validarTabela(tabela);
    final db = await _db;
    final r = await db.rawQuery('SELECT COUNT(*) FROM "$tabela"');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// Colunas da tabela (equivale a PRAGMA table_info).
  Future<ResultadoConsulta> estrutura(String tabela) async {
    await _validarTabela(tabela);
    final db = await _db;
    final info = await db.rawQuery('PRAGMA table_info("$tabela")');
    final linhas = info
        .map(
          (c) => <Object?>[
            c['name'],
            c['type'],
            (c['notnull'] as int) == 1 ? 'sim' : 'não',
            (c['pk'] as int) > 0 ? 'sim' : 'não',
          ],
        )
        .toList();
    return ResultadoConsulta(const ['Coluna', 'Tipo', 'Obrigatório', 'Chave primária'], linhas);
  }

  /// Primeiras linhas da tabela (equivale a SELECT * FROM tabela LIMIT 200).
  Future<ResultadoConsulta> dados(String tabela) async {
    await _validarTabela(tabela);
    final db = await _db;
    final linhas = await db.rawQuery('SELECT * FROM "$tabela" LIMIT $_limiteLinhas');
    final info = await db.rawQuery('PRAGMA table_info("$tabela")');
    return _montar(linhas, colunasPadrao: info.map((c) => c['name'] as String).toList());
  }

  /// Executa uma consulta SELECT digitada pelo usuário (somente leitura).
  Future<ResultadoConsulta> consultar(String sql) async {
    var texto = sql.trim();
    while (texto.endsWith(';')) {
      texto = texto.substring(0, texto.length - 1).trimRight();
    }
    if (texto.isEmpty) {
      throw const AppException('Digite uma consulta SQL.');
    }
    if (texto.contains(';')) {
      throw const AppException('Execute uma consulta por vez (sem ponto e vírgula no meio).');
    }
    final minusculo = texto.toLowerCase();
    if (!(minusculo.startsWith('select') || minusculo.startsWith('with'))) {
      throw const AppException('Somente consultas SELECT são permitidas aqui.');
    }
    final proibidas = RegExp(
      r'\b(insert|update|delete|drop|alter|create|replace|attach|detach|vacuum|reindex|pragma)\b',
    );
    if (proibidas.hasMatch(minusculo)) {
      throw const AppException('Esta tela é somente leitura: comandos que alteram o banco são bloqueados.');
    }

    final db = await _db;
    final linhas = await db.rawQuery(texto);
    final limitadas = linhas.length > 500 ? linhas.sublist(0, 500) : linhas;
    return _montar(limitadas);
  }

  String _literal(Object? valor) {
    if (valor == null) return 'NULL';
    if (valor is num) return valor.toString();
    final texto = valor.toString().replaceAll("'", "''");
    return "'$texto'";
  }

  /// Gera um script SQL completo (CREATE TABLE + INSERT) do banco atual.
  /// Pode ser colado em qualquer ferramenta SQLite (DB Browser, DBeaver...).
  Future<String> gerarDump() async {
    final db = await _db;
    final tabelas = await listarTabelas();
    final saida = StringBuffer();

    saida.writeln('-- Mente Saudável: exportação do banco SQLite (mente_saudavel.db)');
    saida.writeln('-- Gerado em: ${DateTime.now().toIso8601String()}');
    saida.writeln('-- As colunas senha_hash e salt foram ocultadas (REDACTED).');
    saida.writeln('PRAGMA foreign_keys = OFF;');
    saida.writeln('BEGIN TRANSACTION;');

    for (final tabela in tabelas) {
      final esquema = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
        [tabela],
      );
      saida.writeln();
      saida.writeln('${esquema.first['sql']};');

      final linhas = await db.rawQuery('SELECT * FROM "$tabela"');
      for (final linha in linhas) {
        final colunas = linha.keys.toList();
        final nomes = colunas.map((c) => '"$c"').join(', ');
        final valores = colunas
            .map((c) => (_ehSensivel(c) && linha[c] != null) ? "'REDACTED'" : _literal(linha[c]))
            .join(', ');
        saida.writeln('INSERT INTO "$tabela" ($nomes) VALUES ($valores);');
      }
    }

    final indices = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL ORDER BY name",
    );
    if (indices.isNotEmpty) {
      saida.writeln();
      for (final indice in indices) {
        saida.writeln('${indice['sql']};');
      }
    }

    saida.writeln();
    saida.writeln('COMMIT;');
    saida.writeln('PRAGMA foreign_keys = ON;');
    return saida.toString();
  }
}
