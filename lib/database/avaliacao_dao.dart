import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/models/avaliacao.dart';

/// Acesso à tabela "avaliacoes" e à busca de profissionais com nota média.
class AvaliacaoDao {
  Future<Database> get _db => DatabaseHelper.instance.database;

  /// Cria ou atualiza a avaliação da sessão (cada sessão tem no máximo uma).
  Future<void> salvar(Avaliacao a) async {
    final db = await _db;
    await db.insert('avaliacoes', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Avaliacao?> daSessao(int sessaoId) async {
    final db = await _db;
    final linhas =
        await db.query('avaliacoes', where: 'sessao_id = ?', whereArgs: [sessaoId], limit: 1);
    if (linhas.isEmpty) return null;
    return Avaliacao.fromMap(linhas.first);
  }

  Future<List<Avaliacao>> doProfissional(int profissionalId, {int limite = 30}) async {
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
