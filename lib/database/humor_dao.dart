import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/app/dependencias.dart';
import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:mente_saudavel/data/remote/humor_perfil_remoto.dart';
import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/models/humor.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Acesso ao diário de humor do paciente.
///
/// Modo local: tabela "humor_registros" no SQLite do aparelho.
/// Modo servidor ("offline-first"): tenta a API; sem internet, o registro vai para a fila (Outbox) com uma
/// chave de idempotência e aparece na lista como `pendente` (id negativo). Offline, a lista vem do cache da
/// última resposta, com a fila por cima. Só falta de REDE vira fila; recusas do servidor sobem para a tela.
class HumorDao {
  HumorDao({
    bool? servidor,
    HumorRemoto? remoto,
    OutboxRepository? outbox,
    CacheKv? cache,
    int? Function()? usuarioId,
    void Function()? aoMudarFila,
  })  : _servidor = servidor ?? usaServidor,
        _remoto = remoto ?? HumorRemoto(),
        _outboxInjetado = outbox,
        _cacheInjetado = cache,
        _usuarioInjetado = usuarioId,
        _aoMudarFilaInjetado = aoMudarFila;

  final bool _servidor;
  final HumorRemoto _remoto;
  final OutboxRepository? _outboxInjetado;
  final CacheKv? _cacheInjetado;
  final int? Function()? _usuarioInjetado;
  final void Function()? _aoMudarFilaInjetado;

  Future<Database> get _db => DatabaseHelper.instance.database;

  // Sem injeção (app de verdade), usa a fila e o sincronizador criados no main(). Null no navegador.
  Dependencias? get _deps {
    try {
      return Dependencias.instancia;
    } on StateError {
      return null;
    }
  }

  OutboxRepository? get _outbox => _outboxInjetado ?? _deps?.outbox;
  CacheKv? get _cache => _cacheInjetado ?? _deps?.cache;
  int? _usuario() => (_usuarioInjetado ?? () => AuthService.atual.value?.id)();

  void _avisarFila() {
    final aviso = _aoMudarFilaInjetado;
    if (aviso != null) {
      aviso();
      return;
    }
    final sincronizador = _deps?.sincronizador;
    sincronizador?.notificar();
    unawaited(sincronizador?.sincronizar()); // se a internet já voltou, envia na hora
  }

  String _chaveCache(int usuarioId) => 'humor_$usuarioId';

  /// Devolve o id do registro, ou um número NEGATIVO (`-idDoItem`) se ficou na fila por falta de internet.
  Future<int> inserir(HumorRegistro registro) async {
    if (_servidor) {
      final chave = OutboxRepository.gerarChave();
      try {
        return await _remoto.registrar(
          nivel: registro.nivel,
          nota: registro.nota,
          dataHora: registro.dataHora,
          chaveIdempotencia: chave,
        );
      } on SemConexaoException {
        final outbox = _outbox;
        final dono = _usuario();
        if (outbox == null || dono == null) rethrow; // navegador: sem fila offline
        final item = await outbox.enfileirar(
          dono,
          TipoOutbox.humor,
          {'nivel': registro.nivel, 'nota': registro.nota, 'data_hora': registro.dataHora.toIso8601String()},
          chave: chave,
        );
        _avisarFila();
        return -item.id;
      }
    }
    final db = await _db;
    return db.insert('humor_registros', registro.toMap());
  }

  Future<List<HumorRegistro>> listar(int usuarioId, {int limite = 50}) async {
    if (_servidor) {
      final base = (await _doServidorOuCache(usuarioId, {'limite': '$limite'}, guardar: true)).lista;
      final lista = [...base, ...await _pendentes(usuarioId)]..sort((a, b) => b.dataHora.compareTo(a.dataHora));
      return lista.take(limite).toList();
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
    if (_servidor) {
      final desde = DateTime.now().subtract(Duration(days: dias));
      final resposta = await _doServidorOuCache(usuarioId, {'dias': '$dias', 'limite': '1000'}, guardar: false);
      // Do servidor, o período já vem filtrado; do cache (offline), filtra aqui.
      final base = resposta.doCache ? resposta.lista.where((r) => !r.dataHora.isBefore(desde)).toList() : resposta.lista;
      final todos = [
        ...base,
        ...(await _pendentes(usuarioId)).where((r) => !r.dataHora.isBefore(desde)),
      ];
      if (todos.isEmpty) return null;
      return todos.fold<int>(0, (soma, r) => soma + r.nivel) / todos.length;
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

  /// Exclui um registro. Um registro ainda na fila (id negativo) é só removido da fila: nunca chegou ao servidor.
  Future<int> excluir(int id) async {
    if (_servidor) {
      if (id < 0) {
        await _outbox?.remover(-id);
        _deps?.sincronizador?.notificar();
        return 1;
      }
      await ApiClient.delete('/humor/$id');
      return 1;
    }
    final db = await _db;
    return db.delete('humor_registros', where: 'id = ?', whereArgs: [id]);
  }

  /// Lista do servidor (e guarda no cache); sem internet, a última lista guardada. Sem cache nenhum, o erro de
  /// conexão sobe (não há o que mostrar).
  Future<({List<HumorRegistro> lista, bool doCache})> _doServidorOuCache(
    int usuarioId,
    Map<String, String> consulta, {
    required bool guardar,
  }) async {
    try {
      final r = await ApiClient.get('/humor', consulta: consulta);
      final mapas = ApiClient.comoLista(r);
      if (guardar) {
        try {
          await _cache?.gravar(_chaveCache(usuarioId), mapas);
        } catch (_) {
          // Sem cache: só perde a visão offline.
        }
      }
      return (lista: mapas.map(HumorRegistro.fromMap).toList(), doCache: false);
    } on SemConexaoException {
      Object? guardado;
      try {
        guardado = await _cache?.ler(_chaveCache(usuarioId));
      } catch (_) {
        guardado = null;
      }
      if (guardado is! List) rethrow;
      return (
        lista: guardado.map((e) => HumorRegistro.fromMap(Map<String, Object?>.from(e as Map))).toList(),
        doCache: true,
      );
    }
  }

  /// Registros ainda na fila (aguardando internet), como `pendente`. Os que FALHARAM aparecem na tela de pendências.
  Future<List<HumorRegistro>> _pendentes(int usuarioId) async {
    final outbox = _outbox;
    if (outbox == null) return const [];
    try {
      final fila = await outbox.todos(usuarioId);
      return [
        for (final i in fila.where((i) => i.tipo == TipoOutbox.humor && i.pendente))
          HumorRegistro(
            id: -i.id,
            usuarioId: usuarioId,
            nivel: i.payload['nivel']! as int,
            nota: (i.payload['nota'] as String?) ?? '',
            dataHora: DateTime.parse(i.payload['data_hora']! as String),
          ),
      ];
    } catch (_) {
      return const []; // fila ilegível: mostra só o que veio do servidor
    }
  }
}
