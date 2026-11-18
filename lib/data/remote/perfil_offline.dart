import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:mente_saudavel/data/remote/humor_perfil_remoto.dart';
import 'package:mente_saudavel/utils/app_exception.dart';

/// Atualização cadastral "offline-first": tenta a API; sem internet, guarda na fila e o app segue com o valor
/// novo. Só a alteração MAIS RECENTE fica na fila (a última gravação vence). Recusas do servidor (422...) sobem
/// para a tela como sempre; só falta de rede ([SemConexaoException]) vira fila.
class PerfilOffline {
  PerfilOffline({required this.remoto, required this.outbox, required this.usuarioId, this.aoMudarFila});

  final PerfilRemoto remoto;
  final OutboxRepository outbox;
  final int? Function() usuarioId;
  final void Function()? aoMudarFila;

  /// Devolve a resposta do servidor, ou `null` se ficou na fila por falta de internet.
  Future<dynamic> salvar(Map<String, Object?> campos) async {
    try {
      return await remoto.atualizar(campos);
    } on SemConexaoException {
      final dono = usuarioId();
      if (dono == null) rethrow;
      await outbox.enfileirarUnico(dono, TipoOutbox.perfil, campos);
      aoMudarFila?.call();
      return null;
    }
  }
}
