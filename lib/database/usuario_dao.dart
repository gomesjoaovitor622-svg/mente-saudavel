import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Acesso à tabela "usuarios" (e à tabela "app_sessao", do login salvo).
class UsuarioDao {
  UsuarioDao({Future<Database> Function()? abrirBanco})
      : _abrir = abrirBanco ?? (() => DatabaseHelper.instance.database);

  final Future<Database> Function() _abrir;

  Future<Database> get _db => _abrir();

  // ---------- CREATE ----------
  Future<int> inserir(Usuario usuario) async {
    final db = await _db;
    return db.insert('usuarios', usuario.toMap());
  }

  // ---------- READ ----------
  Future<Usuario?> buscarPorId(int id) async {
    final db = await _db;
    final linhas = await db.query('usuarios', where: 'id = ?', whereArgs: [id], limit: 1);
    if (linhas.isEmpty) return null;
    return Usuario.fromMap(linhas.first);
  }

  Future<Usuario?> buscarPorEmail(String email) async {
    final db = await _db;
    final linhas = await db.query(
      'usuarios',
      where: 'email = ?', // a coluna é COLLATE NOCASE: ignora maiúsculas
      whereArgs: [email.trim()],
      limit: 1,
    );
    if (linhas.isEmpty) return null;
    return Usuario.fromMap(linhas.first);
  }

  Future<List<Usuario>> listarProfissionais() async {
    if (usaServidor) {
      final r = await ApiClient.get('/profissionais');
      return ApiClient.comoLista(r)
          .map((m) => Usuario.fromMap({...m, 'perfil': 'profissional'}))
          .toList();
    }
    final db = await _db;
    final linhas = await db.query(
      'usuarios',
      where: 'perfil = ?',
      whereArgs: ['profissional'],
      orderBy: 'nome COLLATE NOCASE ASC',
    );
    return linhas.map(Usuario.fromMap).toList();
  }

  // ---------- UPDATE ----------
  Future<int> atualizarPerfil(Usuario u) async {
    final db = await _db;
    return db.update(
      'usuarios',
      {
        'nome': u.nome,
        'registro': u.registro,
        'especialidade': u.especialidade,
        'endereco': u.endereco,
        'valor_sessao_centavos': u.valorSessaoCentavos,
      },
      where: 'id = ?',
      whereArgs: [u.id],
    );
  }

  Future<int> atualizarSenha(int id, String hash, String salt) async {
    final db = await _db;
    return db.update(
      'usuarios',
      {'senha_hash': hash, 'salt': salt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------- LGPD ----------
  /// Registra qual versão dos Termos/Política a pessoa aceitou e quando (prova do consentimento).
  Future<void> registrarAceite(int id, String versao) async {
    final db = await _db;
    await db.update(
      'usuarios',
      {'aceite_termos_versao': versao, 'aceite_termos_em': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Direito à eliminação (LGPD, art. 18): exclusão lógica + anonimização da conta de PACIENTE,
  /// tudo em UMA transação (ou anonimiza tudo ou nada).
  ///
  /// Apaga o diário de humor e os comentários das avaliações, troca nome/e-mail por valores
  /// anônimos, bloqueia o login e cancela as sessões futuras. As sessões passadas ficam, sem
  /// identificar a pessoa: o profissional guarda o prontuário e os registros financeiros por
  /// obrigação legal (art. 16, I).
  Future<void> anonimizar(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('humor_registros', where: 'usuario_id = ?', whereArgs: [id]);
      await txn.update('avaliacoes', {'comentario': ''}, where: 'paciente_id = ?', whereArgs: [id]);
      await txn.update(
        'sessoes',
        {'status': 'cancelada'},
        where: "paciente_id = ? AND status = 'agendada' AND data_hora > ?",
        whereArgs: [id, DateTime.now().toIso8601String()],
      );
      await txn.update(
        'usuarios',
        {
          'nome': 'Paciente anonimizado',
          'email': 'anonimizado-$id@anonimizado.invalid',
          'senha_hash': 'bloqueado', // nenhum hash de verdade é igual a isto: o login nunca confere
          'salt': 'bloqueado',
          'aceite_termos_em': null,
          'anonimizado_em': DateTime.now().toIso8601String(),
        },
        where: "id = ? AND perfil = 'paciente'",
        whereArgs: [id],
      );
      await txn.delete('app_sessao');
    });
  }

  // ---------- DELETE ----------
  // As sessões, os registros de humor e o login salvo são apagados em cascata.
  Future<int> excluir(int id) async {
    final db = await _db;
    return db.delete('usuarios', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Login salvo (tabela app_sessao) ----------
  Future<void> salvarSessao(int usuarioId) async {
    final db = await _db;
    await db.insert(
      'app_sessao',
      {'id': 1, 'usuario_id': usuarioId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int?> lerSessao() async {
    final db = await _db;
    final linhas = await db.query('app_sessao', where: 'id = 1', limit: 1);
    if (linhas.isEmpty) return null;
    return linhas.first['usuario_id'] as int?;
  }

  Future<void> limparSessao() async {
    final db = await _db;
    await db.delete('app_sessao');
  }
}
