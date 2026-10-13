import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/models/humor.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Acesso à tabela "humor_registros" (diário de humor do paciente).
class HumorDao {
  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<int> inserir(HumorRegistro registro) async {
    if (usaServidor) {
      final r = await ApiClient.post('/humor', corpo: {
        'nivel': registro.nivel,
        'nota': registro.nota,
        'data_hora': registro.dataHora.toIso8601String(),
      }) as Map<String, dynamic>;
      return r['id'] as int;
    }
    final db = await _db;
    return db.insert('humor_registros', registro.toMap());
  }

  Future<List<HumorRegistro>> listar(int usuarioId, {int limite = 50}) async {
    if (usaServidor) {
      final r = await ApiClient.get('/humor', consulta: {'limite': '$limite'});
      return ApiClient.comoLista(r).map(HumorRegistro.fromMap).toList();
    }
    final db = await _db;
    final linhas = await db.query(
      'humor_registros',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'data_hora DESC',
      limit: limite,
    );
    return linhas.map(HumorRegistro.fromMap).toList();
  }

  /// Média do nível de humor nos últimos [dias] dias (null se não há registros).
  Future<double?> mediaUltimosDias(int usuarioId, int dias) async {
    if (usaServidor) {
      final r = await ApiClient.get('/humor', consulta: {'dias': '$dias', 'limite': '1000'});
      final lista = ApiClient.comoLista(r);
      if (lista.isEmpty) return null;
      final soma = lista.fold<int>(0, (acc, m) => acc + (m['nivel'] as int));
      return soma / lista.length;
    }
    final db = await _db;
    final desde = DateTime.now().subtract(Duration(days: dias));
    final r = await db.rawQuery(
      'SELECT AVG(nivel) AS media FROM humor_registros WHERE usuario_id = ? AND data_hora >= ?',
      [usuarioId, desde.toIso8601String()],
    );
    final media = r.first['media'] as num?;
    return media?.toDouble();
  }

  Future<int> excluir(int id) async {
    if (usaServidor) {
      await ApiClient.delete('/humor/$id');
      return 1;
    }
    final db = await _db;
    return db.delete('humor_registros', where: 'id = ?', whereArgs: [id]);
  }
}
