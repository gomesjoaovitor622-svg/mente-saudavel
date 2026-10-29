import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/models/avaliacao.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Acesso à tabela "avaliacoes" e à busca de profissionais com nota média.
class AvaliacaoDao {
  Future<Database> get _db => DatabaseHelper.instance.database;

  /// Cria ou atualiza a avaliação da sessão (cada sessão tem no máximo uma).
  Future<void> salvar(Avaliacao a) async {
    if (usaServidor) {
      await ApiClient.put('/sessoes/${a.sessaoId}/avaliacao',
          corpo: {'nota': a.nota, 'comentario': a.comentario});
      return;
    }
    final db = await _db;
    // Transação: conferir a sessão e gravar a nota são um bloco só (a mesma regra do servidor).
    await db.transaction((txn) async {
      final sessao = await txn.query(
        'sessoes',
        columns: ['paciente_id', 'status'],
        where: 'id = ?',
        whereArgs: [a.sessaoId],
        limit: 1,
      );
      if (sessao.isEmpty || sessao.first['paciente_id'] != a.pacienteId) {
        throw const AppException('Sessão não encontrada.');
      }
      if (sessao.first['status'] != 'concluida') {
        throw const AppException('Só é possível avaliar sessões concluídas.');
      }
      await txn.insert('avaliacoes', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<Avaliacao?> daSessao(int sessaoId) async {
    if (usaServidor) {
      final r = await ApiClient.get('/sessoes/$sessaoId/avaliacao');
      if (r == null) return null;
      return Avaliacao.fromMap(Map<String, Object?>.from(r as Map));
    }
    final db = await _db;
    final linhas =
        await db.query('avaliacoes', where: 'sessao_id = ?', whereArgs: [sessaoId], limit: 1);
    if (linhas.isEmpty) return null;
    return Avaliacao.fromMap(linhas.first);
  }

  Future<List<Avaliacao>> doProfissional(int profissionalId, {int limite = 30}) async {
    if (usaServidor) {
      final r = await ApiClient.get('/profissionais/$profissionalId/avaliacoes',
          consulta: {'limite': '$limite'});
      return ApiClient.comoLista(r).map(Avaliacao.fromMap).toList();
    }
    final db = await _db;
    final linhas = await db.rawQuery(
      '''SELECT a.*, u.nome AS paciente_nome
         FROM avaliacoes a JOIN usuarios u ON u.id = a.paciente_id
         WHERE a.profissional_id = ?
         ORDER BY a.criado_em DESC LIMIT ?''',
      [profissionalId, limite],
    );
    return linhas.map(Avaliacao.fromMap).toList();
  }

  /// Lista profissionais, filtrando por nome/especialidade, com média das notas.
  /// Os melhores avaliados aparecem primeiro.
  Future<List<ProfissionalResumo>> buscarProfissionais({String termo = ''}) async {
    if (usaServidor) {
      final r = await ApiClient.get('/profissionais', consulta: {'q': termo.trim()});
      return ApiClient.comoLista(r).map(ProfissionalResumo.fromMap).toList();
    }
    final db = await _db;
    final t = '%${termo.trim()}%';
    final linhas = await db.rawQuery(
      '''SELECT u.id, u.nome, u.registro, u.especialidade, u.endereco,
                AVG(a.nota) AS media, COUNT(a.id) AS total
         FROM usuarios u
         LEFT JOIN avaliacoes a ON a.profissional_id = u.id
         WHERE u.perfil = 'profissional'
           AND (u.nome LIKE ? OR IFNULL(u.especialidade, '') LIKE ?)
         GROUP BY u.id
         ORDER BY (AVG(a.nota) IS NULL) ASC, AVG(a.nota) DESC, u.nome COLLATE NOCASE ASC''',
      [t, t],
    );
    return linhas.map(ProfissionalResumo.fromMap).toList();
  }
}
