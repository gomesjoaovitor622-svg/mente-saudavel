import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/domain/repositories/sessao_repository.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/formatters.dart';

/// Sessões no SQLite do aparelho. Todas as consultas usam parâmetros (`?`).
///
/// Operações de VÁRIAS etapas ([agendar], [remarcar]) rodam em `db.transaction`: conferir o
/// horário e gravar são um bloco só (tudo ou nada). Além disso, o índice único do banco
/// (`uq_sessao_*_horario`) é a última barreira contra horário duplicado.
class SessaoRepositoryLocal implements SessaoRepository {
  /// [abrirBanco] existe para os testes usarem um banco em memória.
  SessaoRepositoryLocal({Future<Database> Function()? abrirBanco})
      : _abrir = abrirBanco ?? (() => DatabaseHelper.instance.database);

  final Future<Database> Function() _abrir;

  // SELECT base: traz também os nomes do paciente e do profissional (JOIN). Texto constante.
  static const String _select = '''
    SELECT s.*,
           pac.nome          AS paciente_nome,
           pro.nome          AS profissional_nome,
           pro.registro      AS profissional_registro,
           pro.especialidade AS profissional_especialidade,
           pro.endereco      AS profissional_endereco
    FROM sessoes s
    JOIN usuarios pac ON pac.id = s.paciente_id
    JOIN usuarios pro ON pro.id = s.profissional_id
  ''';

  // ---------- CREATE (transação: conferir + gravar) ----------
  @override
  Future<int> agendar({
    required int pacienteId,
    required int profissionalId,
    required DateTime dataHora,
    required String modalidade,
  }) async {
    if (!dataHora.isAfter(DateTime.now())) {
      throw const AppException('Escolha um horário no futuro.');
    }
    final db = await _abrir();
    try {
      return await db.transaction((txn) async {
        final profissional = await txn.query(
          'usuarios',
          columns: ['valor_sessao_centavos'],
          where: 'id = ? AND perfil = ?',
          whereArgs: [profissionalId, 'profissional'],
          limit: 1,
        );
        if (profissional.isEmpty) throw const AppException('Profissional não encontrado.');

        final conflito = await _mensagemConflito(
          txn,
          profissionalId: profissionalId,
          pacienteId: pacienteId,
          dataHora: dataHora,
        );
        if (conflito != null) throw ConflitoException(conflito);

        final sessao = Sessao(
          pacienteId: pacienteId,
          profissionalId: profissionalId,
          dataHora: dataHora,
          modalidade: modalidade,
          status: StatusSessao.agendada,
          // Congela o preço vigente na hora do agendamento (mudar o preço depois não afeta este).
          valorCentavos: (profissional.first['valor_sessao_centavos'] as num?)?.toInt() ?? 0,
        );
        return txn.insert('sessoes', sessao.toMap());
      });
    } on DatabaseException catch (e) {
      throw _traduzir(e);
    }
  }

  // ---------- READ: paciente ----------
  @override
  Future<List<Sessao>> doPaciente(int pacienteId, {String? status}) async {
    final db = await _abrir();
    final linhas = status == null
        ? await db.rawQuery(
            '$_select WHERE s.paciente_id = ? ORDER BY s.data_hora DESC',
            [pacienteId],
          )
        : await db.rawQuery(
            '$_select WHERE s.paciente_id = ? AND s.status = ? ORDER BY s.data_hora DESC',
            [pacienteId, status],
          );
    return linhas.map(Sessao.fromMap).toList();
  }

  @override
  Future<Sessao?> proximaDoPaciente(int pacienteId) async {
    final db = await _abrir();
    final linhas = await db.rawQuery(
      '''$_select
         WHERE s.paciente_id = ? AND s.status = 'agendada' AND s.data_hora >= ?
         ORDER BY s.data_hora ASC LIMIT 1''',
      [pacienteId, DateTime.now().toIso8601String()],
    );
    if (linhas.isEmpty) return null;
    return Sessao.fromMap(linhas.first);
  }

  @override
  Future<int> concluidasDoPaciente(int pacienteId) async {
    final db = await _abrir();
    final r = await db.rawQuery(
      "SELECT COUNT(*) FROM sessoes WHERE paciente_id = ? AND status = 'concluida'",
      [pacienteId],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  // ---------- READ: profissional ----------
  @override
  Future<List<Sessao>> doProfissionalNoDia(
    int profissionalId,
    DateTime dia, {
    bool incluirCanceladas = true,
  }) async {
    final db = await _abrir();
    final inicio = somenteData(dia);
    final fim = DateTime(dia.year, dia.month, dia.day + 1);
    // Interpolação SÓ de um trecho constante (nunca de entrada do usuário).
    final filtroStatus = incluirCanceladas ? '' : "AND s.status != 'cancelada'";
    final linhas = await db.rawQuery(
      '''$_select
         WHERE s.profissional_id = ? AND s.data_hora >= ? AND s.data_hora < ? $filtroStatus
         ORDER BY s.data_hora ASC''',
      [profissionalId, inicio.toIso8601String(), fim.toIso8601String()],
    );
    return linhas.map(Sessao.fromMap).toList();
  }

  @override
  Future<int> atendimentosHoje(int profissionalId) async {
    final db = await _abrir();
    final hoje = somenteData(DateTime.now());
    final amanha = DateTime(hoje.year, hoje.month, hoje.day + 1);
    final r = await db.rawQuery(
      '''SELECT COUNT(*) FROM sessoes
         WHERE profissional_id = ? AND status != 'cancelada'
           AND data_hora >= ? AND data_hora < ?''',
      [profissionalId, hoje.toIso8601String(), amanha.toIso8601String()],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  @override
  Future<int> pacientesAtivos(int profissionalId) async {
    final db = await _abrir();
    final r = await db.rawQuery(
      '''SELECT COUNT(DISTINCT paciente_id) FROM sessoes
         WHERE profissional_id = ? AND status != 'cancelada'
      ''',
      [profissionalId],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  @override
  Future<List<PacienteResumo>> pacientesDoProfissional(int profissionalId) async {
    final db = await _abrir();
    final linhas = await db.rawQuery(
      '''SELECT u.id, u.nome, u.email,
                COUNT(s.id) AS total,
                SUM(CASE WHEN s.status = 'concluida' THEN 1 ELSE 0 END) AS concluidas,
                MIN(CASE WHEN s.status = 'agendada' AND s.data_hora >= ?
                         THEN s.data_hora END) AS proxima
         FROM sessoes s
         JOIN usuarios u ON u.id = s.paciente_id
         WHERE s.profissional_id = ? AND s.status != 'cancelada'
         GROUP BY u.id
         ORDER BY u.nome COLLATE NOCASE ASC''',
      [DateTime.now().toIso8601String(), profissionalId],
    );
    return linhas.map(PacienteResumo.fromMap).toList();
  }

  @override
  Future<List<Sessao>> doProfissionalComPaciente(int profissionalId, int pacienteId) async {
    final db = await _abrir();
    final linhas = await db.rawQuery(
      '''$_select
         WHERE s.profissional_id = ? AND s.paciente_id = ?
         ORDER BY s.data_hora DESC''',
      [profissionalId, pacienteId],
    );
    return linhas.map(Sessao.fromMap).toList();
  }

  // ---------- Disponibilidade ----------
  @override
  Future<Set<int>> horasOcupadas(int profissionalId, DateTime dia) async {
    final db = await _abrir();
    final inicio = somenteData(dia);
    final fim = DateTime(dia.year, dia.month, dia.day + 1);
    final linhas = await db.rawQuery(
      '''SELECT data_hora FROM sessoes
         WHERE profissional_id = ? AND status != 'cancelada'
           AND data_hora >= ? AND data_hora < ?''',
      [profissionalId, inicio.toIso8601String(), fim.toIso8601String()],
    );
    return linhas.map((l) => DateTime.parse(l['data_hora'] as String).hour).toSet();
  }

  /// Mensagem de erro se houver conflito de horário, ou null se livre.
  /// Recebe o [DatabaseExecutor] para rodar DENTRO da transação de quem chamou.
  Future<String?> _mensagemConflito(
    DatabaseExecutor db, {
    required int profissionalId,
    required int pacienteId,
    required DateTime dataHora,
    int? ignorarId,
  }) async {
    final quando = dataHora.toIso8601String();
    final ignorar = ignorarId ?? -1;

    final doProfissional = Sqflite.firstIntValue(await db.rawQuery(
          '''SELECT COUNT(*) FROM sessoes
             WHERE profissional_id = ? AND data_hora = ? AND status != 'cancelada' AND id != ?''',
          [profissionalId, quando, ignorar],
        )) ??
        0;
    if (doProfissional > 0) return 'O profissional já tem uma sessão neste horário.';

    final doPaciente = Sqflite.firstIntValue(await db.rawQuery(
          '''SELECT COUNT(*) FROM sessoes
             WHERE paciente_id = ? AND data_hora = ? AND status != 'cancelada' AND id != ?''',
          [pacienteId, quando, ignorar],
        )) ??
        0;
    if (doPaciente > 0) return 'Você já tem uma sessão neste horário.';

    return null;
  }

  /// Se o índice único recusou a gravação (corrida), vira o mesmo erro de conflito da API (409).
  Object _traduzir(DatabaseException e) {
    if (e.isUniqueConstraintError()) {
      return const ConflitoException('Este horário acabou de ser ocupado. Escolha outro.');
    }
    return e;
  }

  // ---------- UPDATE ----------
  @override
  Future<void> atualizarStatus(int id, String status) async {
    final db = await _abrir();
    await db.update('sessoes', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> atualizarAnotacoes(int id, String anotacoes) async {
    final db = await _abrir();
    await db.update('sessoes', {'anotacoes': anotacoes}, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> remarcar(int id, DateTime novaDataHora) async {
    final db = await _abrir();
    try {
      await db.transaction((txn) async {
        final atual = await txn.query(
          'sessoes',
          columns: ['profissional_id', 'paciente_id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (atual.isEmpty) throw const AppException('Sessão não encontrada.');

        final conflito = await _mensagemConflito(
          txn,
          profissionalId: atual.first['profissional_id'] as int,
          pacienteId: atual.first['paciente_id'] as int,
          dataHora: novaDataHora,
          ignorarId: id,
        );
        if (conflito != null) throw ConflitoException(conflito);

        await txn.update(
          'sessoes',
          {'data_hora': novaDataHora.toIso8601String(), 'status': StatusSessao.agendada},
          where: 'id = ?',
          whereArgs: [id],
        );
      });
    } on DatabaseException catch (e) {
      throw _traduzir(e);
    }
  }

  // ---------- DELETE ----------
  @override
  Future<void> excluir(int id) async {
    final db = await _abrir();
    await db.delete('sessoes', where: 'id = ?', whereArgs: [id]);
  }
}
