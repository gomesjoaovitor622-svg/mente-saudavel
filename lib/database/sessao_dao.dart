import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Acesso à tabela "sessoes" (agendamentos entre paciente e profissional).
class SessaoDao {
  Future<Database> get _db => DatabaseHelper.instance.database;

  // SELECT base: traz também os nomes do paciente e do profissional (JOIN).
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

  // ---------- CREATE ----------
  Future<int> inserir(Sessao sessao) async {
    if (usaServidor) {
      final r = await ApiClient.post('/sessoes', corpo: {
        'profissional_id': sessao.profissionalId,
        'data_hora': sessao.dataHora.toIso8601String(),
        'modalidade': sessao.modalidade,
      }) as Map<String, dynamic>;
      return r['id'] as int;
    }
    final db = await _db;
    return db.insert('sessoes', sessao.toMap());
  }

  // ---------- READ: paciente ----------
  Future<List<Sessao>> _remotoLista(Map<String, String> consulta) async {
    final r = await ApiClient.get('/sessoes', consulta: consulta);
    return ApiClient.comoLista(r).map(Sessao.fromMap).toList();
  }

  Future<List<Sessao>> doPaciente(int pacienteId, {String? status}) async {
    if (usaServidor) return _remotoLista({if (status != null) 'status': status});
    final db = await _db;
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

  Future<Sessao?> proximaDoPaciente(int pacienteId) async {
    if (usaServidor) {
      final lista = await _remotoLista({
        'status': StatusSessao.agendada,
        'de': DateTime.now().toIso8601String(),
      });
      return lista.isEmpty ? null : lista.first; // o servidor ordena do mais próximo
    }
    final db = await _db;
    final linhas = await db.rawQuery(
      '''$_select
         WHERE s.paciente_id = ? AND s.status = 'agendada' AND s.data_hora >= ?
         ORDER BY s.data_hora ASC LIMIT 1''',
      [pacienteId, DateTime.now().toIso8601String()],
    );
    if (linhas.isEmpty) return null;
    return Sessao.fromMap(linhas.first);
  }

  Future<int> concluidasDoPaciente(int pacienteId) async {
    if (usaServidor) return (await _remotoLista({'status': StatusSessao.concluida})).length;
    final db = await _db;
    final r = await db.rawQuery(
      "SELECT COUNT(*) FROM sessoes WHERE paciente_id = ? AND status = 'concluida'",
      [pacienteId],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  // ---------- READ: profissional ----------
  Future<List<Sessao>> doProfissionalNoDia(
    int profissionalId,
    DateTime dia, {
    bool incluirCanceladas = true,
  }) async {
    if (usaServidor) {
      final inicio = somenteData(dia);
      final fim = DateTime(dia.year, dia.month, dia.day + 1);
      return _remotoLista({
        'de': inicio.toIso8601String(),
        'ate': fim.toIso8601String(),
        if (!incluirCanceladas) 'nao_canceladas': 'true',
      });
    }
    final db = await _db;
    final inicio = somenteData(dia);
    final fim = DateTime(dia.year, dia.month, dia.day + 1);
    final filtroStatus = incluirCanceladas ? '' : "AND s.status != 'cancelada'";
    final linhas = await db.rawQuery(
      '''$_select
         WHERE s.profissional_id = ? AND s.data_hora >= ? AND s.data_hora < ? $filtroStatus
         ORDER BY s.data_hora ASC''',
      [profissionalId, inicio.toIso8601String(), fim.toIso8601String()],
    );
    return linhas.map(Sessao.fromMap).toList();
  }

  Future<int> atendimentosHoje(int profissionalId) async {
    if (usaServidor) {
      return (await doProfissionalNoDia(profissionalId, DateTime.now(), incluirCanceladas: false)).length;
    }
    final db = await _db;
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

  Future<int> pacientesAtivos(int profissionalId) async {
    if (usaServidor) return (await pacientesDoProfissional(profissionalId)).length;
    final db = await _db;
    final r = await db.rawQuery(
      '''SELECT COUNT(DISTINCT paciente_id) FROM sessoes
         WHERE profissional_id = ? AND status != 'cancelada'
      ''',
      [profissionalId],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<PacienteResumo>> pacientesDoProfissional(int profissionalId) async {
    if (usaServidor) {
      final r = await ApiClient.get('/profissional/pacientes');
      return ApiClient.comoLista(r).map(PacienteResumo.fromMap).toList();
    }
    final db = await _db;
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

  Future<List<Sessao>> doProfissionalComPaciente(int profissionalId, int pacienteId) async {
    if (usaServidor) return _remotoLista({'paciente_id': '$pacienteId'});
    final db = await _db;
    final linhas = await db.rawQuery(
      '''$_select
         WHERE s.profissional_id = ? AND s.paciente_id = ?
         ORDER BY s.data_hora DESC''',
      [profissionalId, pacienteId],
    );
    return linhas.map(Sessao.fromMap).toList();
  }

  // ---------- Disponibilidade ----------
  /// Horas (0-23) já ocupadas pelo profissional em um dia.
  Future<Set<int>> horasOcupadas(int profissionalId, DateTime dia) async {
    if (usaServidor) {
      final r = await ApiClient.get('/profissionais/$profissionalId/horas-ocupadas',
          consulta: {'dia': somenteData(dia).toIso8601String()});
      return (r as List<dynamic>).map((e) => e as int).toSet();
    }
    final db = await _db;
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

  /// Retorna uma mensagem de erro se houver conflito de horário, ou null se livre.
  Future<String?> verificarConflito({
    required int profissionalId,
    required int pacienteId,
    required DateTime dataHora,
    int? ignorarId,
  }) async {
    if (usaServidor) {
      final r = await ApiClient.get('/sessoes/conflito', consulta: {
        'profissional_id': '$profissionalId',
        'data_hora': dataHora.toIso8601String(),
        'ignorar_id': '${ignorarId ?? -1}',
      }) as Map<String, dynamic>;
      return r['mensagem'] as String?;
    }
    final db = await _db;
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

  // ---------- UPDATE ----------
  Future<int> atualizarStatus(int id, String status) async {
    if (usaServidor) {
      await ApiClient.patch('/sessoes/$id', corpo: {'status': status});
      return 1;
    }
    final db = await _db;
    return db.update('sessoes', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> atualizarAnotacoes(int id, String anotacoes) async {
    if (usaServidor) {
      await ApiClient.patch('/sessoes/$id', corpo: {'anotacoes': anotacoes});
      return 1;
    }
    final db = await _db;
    return db.update('sessoes', {'anotacoes': anotacoes}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> remarcar(int id, DateTime novaDataHora) async {
    if (usaServidor) {
      await ApiClient.patch('/sessoes/$id', corpo: {'data_hora': novaDataHora.toIso8601String()});
      return 1;
    }
    final db = await _db;
    return db.update(
      'sessoes',
      {'data_hora': novaDataHora.toIso8601String(), 'status': StatusSessao.agendada},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------- DELETE ----------
  Future<int> excluir(int id) async {
    if (usaServidor) {
      await ApiClient.delete('/sessoes/$id');
      return 1;
    }
    final db = await _db;
    return db.delete('sessoes', where: 'id = ?', whereArgs: [id]);
  }
}
