import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:mente_saudavel/data/remote/sessao_repository_remoto.dart';
import 'package:mente_saudavel/utils/app_exception.dart';

/// Resultado de uma rodada de sincronização.
class ResultadoSincronizacao {
  const ResultadoSincronizacao({this.enviados = 0, this.conflitos = 0, this.falhas = 0, this.semConexao = false});
  final int enviados;
  final int conflitos;
  final int falhas;

  /// `true` se parou porque a internet ainda não voltou (o resto continua na fila).
  final bool semConexao;
}

/// Envia a fila offline ao servidor, em ordem, quando a conexão volta.
///
/// Regras (cada uma tem teste):
///  * Falta de internet: PARA a rodada e mantém tudo na fila (tenta de novo no próximo ciclo).
///  * Sucesso: remove o item. Conflito (409): marca `conflito` e segue para o próximo.
///  * Recusa 4xx (dados inválidos, sem permissão): marca `falhou`, sem insistir.
///  * Erro 5xx: tenta de novo nos próximos ciclos, até [maxTentativas]; depois marca `falhou`.
///  * 401 (sessão expirada): para sem mexer na fila; o envio continua depois do novo login.
///  * Uma rodada por vez (nunca duas ao mesmo tempo).
class SincronizadorOutbox {
  SincronizadorOutbox({
    required this.outbox,
    required this.remoto,
    required this.usuarioId,
    this.maxTentativas = 8,
  });

  final OutboxRepository outbox;
  final SessaoRepositoryRemoto remoto;
  final int? Function() usuarioId;
  final int maxTentativas;

  /// Sobe a cada mudança na fila ou nos dados. Providers e telas "escutam" para recarregar.
  final ValueNotifier<int> versao = ValueNotifier<int>(0);

  Timer? _timer;
  bool _rodando = false;

  void notificar() => versao.value++;

  /// Tenta enviar a fila a cada [intervalo] enquanto houver alguém logado.
  void iniciar({Duration intervalo = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _timer = Timer.periodic(intervalo, (_) => unawaited(sincronizar()));
  }

  void parar() {
    _timer?.cancel();
    _timer = null;
  }

  Future<ResultadoSincronizacao> sincronizar() async {
    final dono = usuarioId();
    if (dono == null || _rodando) return const ResultadoSincronizacao();
    _rodando = true;
    var enviados = 0, conflitos = 0, falhas = 0;
    var semConexao = false;
    try {
      for (final item in await outbox.pendentes(dono)) {
        try {
          await _enviar(item);
          await outbox.remover(item.id);
          enviados++;
        } on SemConexaoException {
          semConexao = true;
          break;
        } on ConflitoException catch (e) {
          await outbox.marcar(item.id, EstadoOutbox.conflito, erro: e.mensagem);
          conflitos++;
        } on AppException catch (e) {
          final status = e.statusHttp ?? 0;
          if (status == 401) break; // sessão expirada: nada a fazer agora
          final definitivo = status >= 400 && status < 500;
          final esgotou = item.tentativas + 1 >= maxTentativas;
          if (definitivo || esgotou) {
            await outbox.marcar(item.id, EstadoOutbox.falhou, erro: e.mensagem, contarTentativa: true);
            falhas++;
          } else {
            await outbox.marcar(item.id, EstadoOutbox.pendente, erro: e.mensagem, contarTentativa: true);
          }
        }
      }
    } finally {
      _rodando = false;
      notificar();
    }
    return ResultadoSincronizacao(enviados: enviados, conflitos: conflitos, falhas: falhas, semConexao: semConexao);
  }

  Future<void> _enviar(ItemOutbox item) async {
    final p = item.payload;
    switch (item.tipo) {
      case TipoOutbox.agendar:
        await remoto.agendar(
          pacienteId: item.usuarioId,
          profissionalId: p['profissional_id']! as int,
          dataHora: DateTime.parse(p['data_hora']! as String),
          modalidade: p['modalidade']! as String,
          chaveIdempotencia: item.chave,
        );
      case TipoOutbox.status:
        await remoto.atualizarStatus(p['id']! as int, p['status']! as String);
      case TipoOutbox.remarcar:
        await remoto.remarcar(p['id']! as int, DateTime.parse(p['data_hora']! as String));
      default:
        throw AppException('Tipo de ação desconhecido: ${item.tipo}', statusHttp: 400);
    }
  }

  /// Descarta um item (ex.: o conflito que a pessoa decidiu abandonar).
  Future<void> descartar(int idItem) async {
    await outbox.remover(idItem);
    notificar();
  }
}
