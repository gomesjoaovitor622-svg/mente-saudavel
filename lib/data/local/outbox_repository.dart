import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_helper.dart';

/// Tipos de ação que podem ficar na fila.
class TipoOutbox {
  static const String agendar = 'agendar';
  static const String status = 'status';
  static const String remarcar = 'remarcar';
}

/// Estados de um item da fila.
class EstadoOutbox {
  static const String pendente = 'pendente'; // aguardando internet/servidor
  static const String conflito = 'conflito'; // o servidor recusou (ex.: horário ocupado): precisa da pessoa
  static const String falhou = 'falhou'; // recusa definitiva (dados inválidos) ou tentativas esgotadas
}

/// Uma ação feita sem internet, esperando para ser enviada ao servidor.
class ItemOutbox {
  const ItemOutbox({
    required this.id,
    required this.usuarioId,
    required this.tipo,
    required this.payload,
    required this.chave,
    required this.estado,
    required this.tentativas,
    required this.criadoEm,
    this.ultimoErro,
  });

  final int id;
  final int usuarioId;
  final String tipo;
  final Map<String, Object?> payload;

  /// Chave de idempotência enviada ao servidor (cabeçalho `Idempotency-Key`).
  final String chave;
  final String estado;
  final int tentativas;
  final String? ultimoErro;
  final String criadoEm;

  bool get pendente => estado == EstadoOutbox.pendente;

  static ItemOutbox fromMap(Map<String, Object?> m) => ItemOutbox(
        id: m['id']! as int,
        usuarioId: m['usuario_id']! as int,
        tipo: m['tipo']! as String,
        payload: Map<String, Object?>.from(jsonDecode(m['payload']! as String) as Map),
        chave: m['chave']! as String,
        estado: m['estado']! as String,
        tentativas: m['tentativas']! as int,
        ultimoErro: m['ultimo_erro'] as String?,
        criadoEm: m['criado_em']! as String,
      );
}

/// Fila de ações offline no SQLite do aparelho (Outbox Pattern).
///
/// Por que uma tabela e não uma lista na memória: se o app for fechado (ou o celular reiniciar)
/// com a internet fora, as ações NÃO se perdem. Cada item tem uma chave de idempotência única,
/// então reenviar depois de um timeout nunca cria a sessão duas vezes.
class OutboxRepository {
  OutboxRepository({Future<Database> Function()? abrirBanco})
      : _abrir = abrirBanco ?? (() => DatabaseHelper.instance.database);

  final Future<Database> Function() _abrir;

  /// Chave aleatória de 32 caracteres hexadecimais (aceita pelo servidor: 8 a 64 de [A-Za-z0-9_-]).
  static String gerarChave() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<ItemOutbox> enfileirar(int usuarioId, String tipo, Map<String, Object?> payload, {String? chave}) async {
    final db = await _abrir();
    final linha = {
      'usuario_id': usuarioId,
      'tipo': tipo,
      'payload': jsonEncode(payload),
      'chave': chave ?? gerarChave(),
      'estado': EstadoOutbox.pendente,
      'tentativas': 0,
      'criado_em': DateTime.now().toIso8601String(),
    };
    final id = await db.insert('outbox', linha);
    return ItemOutbox.fromMap({...linha, 'id': id});
  }

  /// Todos os itens da pessoa (qualquer estado), do mais antigo para o mais novo.
  Future<List<ItemOutbox>> todos(int usuarioId) async {
    final db = await _abrir();
    final linhas = await db.query('outbox', where: 'usuario_id = ?', whereArgs: [usuarioId], orderBy: 'id ASC');
    return linhas.map(ItemOutbox.fromMap).toList();
  }

  Future<List<ItemOutbox>> pendentes(int usuarioId) async =>
      (await todos(usuarioId)).where((i) => i.pendente).toList();

  Future<void> marcar(int id, String estado, {String? erro, bool contarTentativa = false}) async {
    final db = await _abrir();
    await db.rawUpdate(
      'UPDATE outbox SET estado = ?, ultimo_erro = ?, tentativas = tentativas + ? WHERE id = ?',
      [estado, erro, contarTentativa ? 1 : 0, id],
    );
  }

  Future<void> remover(int id) async {
    final db = await _abrir();
    await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  /// Apaga a fila da pessoa (ex.: ao excluir/anonimizar a conta).
  Future<void> limparUsuario(int usuarioId) async {
    final db = await _abrir();
    await db.delete('outbox', where: 'usuario_id = ?', whereArgs: [usuarioId]);
  }
}

/// Última resposta do servidor guardada no aparelho, para mostrar dados sem internet.
class CacheKv {
  CacheKv({Future<Database> Function()? abrirBanco})
      : _abrir = abrirBanco ?? (() => DatabaseHelper.instance.database);

  final Future<Database> Function() _abrir;

  Future<void> gravar(String chave, Object valor) async {
    final db = await _abrir();
    await db.insert(
      'cache_kv',
      {'chave': chave, 'valor': jsonEncode(valor), 'atualizado_em': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Object?> ler(String chave) async {
    final db = await _abrir();
    final linhas = await db.query('cache_kv', where: 'chave = ?', whereArgs: [chave], limit: 1);
    if (linhas.isEmpty) return null;
    return jsonDecode(linhas.first['valor']! as String);
  }

  /// Chamado no logout: dados de saúde não ficam no aparelho depois que a pessoa sai.
  Future<void> limpar() async {
    final db = await _abrir();
    await db.delete('cache_kv');
  }
}
