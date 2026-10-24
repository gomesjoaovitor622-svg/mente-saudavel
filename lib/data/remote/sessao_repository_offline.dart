import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:mente_saudavel/data/remote/sessao_repository_remoto.dart';
import 'package:mente_saudavel/domain/repositories/sessao_repository.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/utils/app_exception.dart';

/// Repositório "offline-first" do modo servidor: tenta a API; se faltar internet, guarda a ação
/// na fila (Outbox) e devolve uma resposta otimista. Quem reenvia é o `SincronizadorOutbox`.
///
/// Leitura: a última lista de sessões do paciente fica em cache; offline, a tela mostra esse cache
/// com as ações ainda não enviadas aplicadas por cima (sessões "pendentes").
/// Só erros de REDE ([SemConexaoException]) vão para a fila. Recusas do servidor (409, 422...)
/// sobem para a tela como sempre.
class SessaoRepositoryOffline implements SessaoRepository {
  SessaoRepositoryOffline({
    required this.remoto,
    required this.outbox,
    required this.cache,
    required this.usuarioId,
    this.aoMudarFila,
  });

  final SessaoRepositoryRemoto remoto;
  final OutboxRepository outbox;
  final CacheKv cache;

  /// Id da pessoa logada (null = ninguém).
  final int? Function() usuarioId;

  /// Avisa que a fila mudou (a tela de pendências e a lista se atualizam).
  final void Function()? aoMudarFila;

  String _chaveCache(int pacienteId) => 'sessoes_paciente_$pacienteId';

  // ---------------------------------------------------------------- escrita
  /// Devolve o id da sessão, ou um número NEGATIVO (`-idDoItem`) se ficou na fila por falta de internet.
  @override
  Future<int> agendar({
    required int pacienteId,
    required int profissionalId,
    required DateTime dataHora,
    required String modalidade,
    String? chaveIdempotencia,
  }) async {
    final chave = chaveIdempotencia ?? OutboxRepository.gerarChave();
    try {
      return await remoto.agendar(
        pacienteId: pacienteId,
        profissionalId: profissionalId,
        dataHora: dataHora,
        modalidade: modalidade,
        chaveIdempotencia: chave,
      );
    } on SemConexaoException catch (semRede) {
      try {
        final item = await outbox.enfileirar(
          pacienteId,
          TipoOutbox.agendar,
          {
            'profissional_id': profissionalId,
            'data_hora': dataHora.toIso8601String(),
            'modalidade': modalidade,
          },
          chave: chave, // a MESMA chave: se o 1º envio chegou ao servidor, o reenvio não duplica
        );
        aoMudarFila?.call();
        return -item.id;
      } catch (_) {
        throw semRede; // sem fila local disponível: a tela mostra "sem conexão", como antes
      }
    }
  }

  @override
  Future<void> atualizarStatus(int id, String status) => _ouFila(
        TipoOutbox.status,
        {'id': id, 'status': status},
        () => remoto.atualizarStatus(id, status),
      );

  @override
  Future<void> remarcar(int id, DateTime novaDataHora) => _ouFila(
        TipoOutbox.remarcar,
        {'id': id, 'data_hora': novaDataHora.toIso8601String()},
        () => remoto.remarcar(id, novaDataHora),
      );

  Future<void> _ouFila(String tipo, Map<String, Object?> payload, Future<void> Function() enviar) async {
    try {
      await enviar();
    } on SemConexaoException catch (semRede) {
      final dono = usuarioId();
      if (dono == null) rethrow;
      try {
        await outbox.enfileirar(dono, tipo, payload);
      } catch (_) {
        throw semRede; // sem fila local disponível: a tela mostra "sem conexão"
      }
      aoMudarFila?.call();
    }
  }

  // ---------------------------------------------------------------- leitura do paciente
  @override
  Future<List<Sessao>> doPaciente(int pacienteId, {String? status}) async {
    List<Sessao> base;
    try {
      final completa = await remoto.doPaciente(pacienteId);
      try {
        await cache.gravar(_chaveCache(pacienteId), completa.map((s) => s.toCache()).toList());
      } catch (_) {
        // O cache é um bônus: se o armazenamento local falhar, a lista online continua valendo.
      }
      base = completa;
    } on SemConexaoException {
      Object? guardado;
      try {
        guardado = await cache.ler(_chaveCache(pacienteId));
      } catch (_) {
        guardado = null;
      }
      if (guardado is! List) rethrow; // nunca abriu online neste aparelho: nada para mostrar
      base = guardado.map((e) => Sessao.fromMap(Map<String, Object?>.from(e as Map))).toList();
    }
    var fila = const <ItemOutbox>[];
    try {
      fila = await outbox.todos(pacienteId);
    } catch (_) {
      // Sem fila local: mostra só o que veio do servidor.
    }
    final comFila = aplicarFila(base, fila, pacienteId);
    final filtrada = status == null ? comFila : comFila.where((s) => s.status == status).toList();
    filtrada.sort((a, b) => b.dataHora.compareTo(a.dataHora));
    return filtrada;
  }

  /// Aplica por cima da lista do servidor o que ainda está na fila:
  /// agendamentos viram sessões `pendente`, e mudanças de status/horário aparecem já alteradas.
  static List<Sessao> aplicarFila(List<Sessao> base, List<ItemOutbox> fila, int pacienteId) {
    final lista = List<Sessao>.of(base);
    for (final item in fila.where((i) => i.estado != EstadoOutbox.falhou)) {
      final p = item.payload;
      switch (item.tipo) {
        case TipoOutbox.agendar:
          lista.add(Sessao(
            id: -item.id,
            pacienteId: pacienteId,
            profissionalId: p['profissional_id']! as int,
            dataHora: DateTime.parse(p['data_hora']! as String),
            modalidade: p['modalidade']! as String,
            status: StatusSessao.agendada,
            pendente: true,
          ));
        case TipoOutbox.status:
          final i = lista.indexWhere((s) => s.id == p['id']);
          if (i >= 0) lista[i] = lista[i].copyWith(status: p['status']! as String);
        case TipoOutbox.remarcar:
          final i = lista.indexWhere((s) => s.id == p['id']);
          if (i >= 0) lista[i] = lista[i].copyWith(dataHora: DateTime.parse(p['data_hora']! as String));
      }
    }
    return lista;
  }

  // ---------------------------------------------------------------- o resto: direto na API
  @override
  Future<Sessao?> proximaDoPaciente(int pacienteId) => remoto.proximaDoPaciente(pacienteId);
  @override
  Future<int> concluidasDoPaciente(int pacienteId) => remoto.concluidasDoPaciente(pacienteId);
  @override
  Future<List<Sessao>> doProfissionalNoDia(int profissionalId, DateTime dia, {bool incluirCanceladas = true}) =>
      remoto.doProfissionalNoDia(profissionalId, dia, incluirCanceladas: incluirCanceladas);
  @override
  Future<int> atendimentosHoje(int profissionalId) => remoto.atendimentosHoje(profissionalId);
  @override
  Future<int> pacientesAtivos(int profissionalId) => remoto.pacientesAtivos(profissionalId);
  @override
  Future<List<PacienteResumo>> pacientesDoProfissional(int profissionalId) =>
      remoto.pacientesDoProfissional(profissionalId);
  @override
  Future<List<Sessao>> doProfissionalComPaciente(int profissionalId, int pacienteId) =>
      remoto.doProfissionalComPaciente(profissionalId, pacienteId);
  @override
  Future<Set<int>> horasOcupadas(int profissionalId, DateTime dia) => remoto.horasOcupadas(profissionalId, dia);
  @override
  Future<void> atualizarAnotacoes(int id, String anotacoes) => remoto.atualizarAnotacoes(id, anotacoes);
  @override
  Future<void> excluir(int id) => remoto.excluir(id);
}
