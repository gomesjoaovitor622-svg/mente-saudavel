import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/models/usuario.dart';

/// Acesso à tabela "usuarios" (e à tabela "app_sessao", do login salvo).
class UsuarioDao {
  Future<Database> get _db => DatabaseHelper.instance.database;

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
