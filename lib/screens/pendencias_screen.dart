import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/services/sincronizador_outbox.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Tudo o que foi feito sem internet e ainda não chegou ao servidor, em três grupos:
///  * aguardando envio (o app tenta sozinho a cada 30 s);
///  * com falha (recusado ou 20 tentativas esgotadas): a pessoa pode REENVIAR ou descartar;
///  * precisam de decisão (ex.: o horário foi ocupado): só descartar.
/// Nada some em silêncio: um item só sai daqui quando é enviado ou quando a pessoa o descarta.
class PendenciasScreen extends ConsumerWidget {
  const PendenciasScreen({super.key});

  static String descricao(ItemOutbox i) => switch (i.tipo) {
        TipoOutbox.agendar => 'Agendamento',
        TipoOutbox.remarcar => 'Remarcação',
        TipoOutbox.humor => 'Registro de humor',
        TipoOutbox.perfil => 'Atualização de cadastro',
        _ => 'Alteração de sessão',
      };

  /// Data da sessão (quando o item tem uma), para a pessoa reconhecer de qual se trata.
  static String? quando(ItemOutbox i) {
    final bruto = i.payload['data_hora'];
    final data = bruto is String ? DateTime.tryParse(bruto) : null;
    return data == null ? null : formatarDataHora(data);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itens = ref.watch(pendenciasOutboxProvider).valueOrNull ?? const <ItemOutbox>[];
    final sincronizador = ref.watch(sincronizadorProvider);
    final aguardando = itens.where((i) => i.pendente).toList();
    final falhas = itens.where((i) => i.falhou).toList();
    final conflitos = itens.where((i) => i.emConflito).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Pendências de envio')),
      body: itens.isEmpty
          ? const Center(
              key: Key('pendencias-vazio'),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done_outlined, size: 48),
                    SizedBox(height: 12),
                    Text('Tudo enviado. Nenhuma pendência.'),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (aguardando.isNotEmpty) ...[
                  _Titulo('Aguardando envio (${aguardando.length})'),
                  for (final i in aguardando) _Linha(item: i, sincronizador: sincronizador),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('sincronizar-agora'),
                      onPressed: sincronizador == null ? null : () => _rodar(context, sincronizador.sincronizar),
                      icon: const Icon(Icons.sync),
                      label: const Text('Sincronizar agora'),
                    ),
                  ),
                ],
                if (falhas.isNotEmpty) ...[
                  _Titulo('Com falha (${falhas.length})'),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Não foram enviadas. Reenvie quando a conexão estiver boa ou descarte o que não vale mais.'),
                  ),
                  for (final i in falhas) _Linha(item: i, sincronizador: sincronizador),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const Key('reenviar-todas'),
                      onPressed: sincronizador == null ? null : () => _rodar(context, () => sincronizador.reenviar()),
                      icon: const Icon(Icons.replay),
                      label: const Text('Reenviar todas'),
                    ),
                  ),
                ],
                if (conflitos.isNotEmpty) ...[
                  _Titulo('Precisam da sua decisão (${conflitos.length})'),
                  for (final i in conflitos) _Linha(item: i, sincronizador: sincronizador),
                ],
              ],
            ),
    );
  }
}

Future<void> _rodar(BuildContext context, Future<ResultadoSincronizacao> Function() acao) async {
  final r = await acao();
  if (!context.mounted) return;
  if (r.semConexao) {
    mostrarMensagem(context, 'Ainda sem conexão. Tentaremos de novo.', erro: true);
  } else if (r.falhas > 0 || r.conflitos > 0) {
    mostrarMensagem(context, 'Alguns itens continuam com problema. Veja o motivo em cada um.', erro: true);
  } else {
    mostrarMensagem(context, 'Envio concluído.');
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(texto, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _Linha extends StatelessWidget {
  const _Linha({required this.item, required this.sincronizador});
  final ItemOutbox item;
  final SincronizadorOutbox? sincronizador;

  @override
  Widget build(BuildContext context) {
    final data = PendenciasScreen.quando(item);
    final erro = item.ultimoErro;
    return Card(
      key: Key('pendencia-${item.id}'),
      child: ListTile(
        leading: Icon(
          item.pendente ? Icons.schedule : Icons.error_outline,
          color: item.pendente ? null : Colors.red,
        ),
        title: Text(data == null ? PendenciasScreen.descricao(item) : '${PendenciasScreen.descricao(item)} · $data'),
        subtitle: Text([
          if (erro != null && erro.isNotEmpty) erro,
          if (item.tentativas > 0) '${item.tentativas} tentativa(s)',
        ].join('\n')),
        isThreeLine: erro != null && erro.isNotEmpty && item.tentativas > 0,
        trailing: Wrap(
          children: [
            if (item.falhou)
              IconButton(
                key: Key('reenviar-${item.id}'),
                tooltip: 'Reenviar',
                icon: const Icon(Icons.replay),
                onPressed: sincronizador == null ? null : () => _rodar(context, () => sincronizador!.reenviar(idItem: item.id)),
              ),
            if (!item.pendente)
              IconButton(
                key: Key('descartar-${item.id}'),
                tooltip: 'Descartar',
                icon: const Icon(Icons.delete_outline),
                onPressed: sincronizador == null
                    ? null
                    : () async {
                        final ok = await confirmar(
                          context,
                          titulo: 'Descartar',
                          mensagem: 'Esta ação não será enviada ao servidor. Descartar mesmo?',
                          textoConfirmar: 'Descartar',
                        );
                        if (ok) await sincronizador!.descartar(item.id);
                      },
              ),
          ],
        ),
      ),
    );
  }
}
