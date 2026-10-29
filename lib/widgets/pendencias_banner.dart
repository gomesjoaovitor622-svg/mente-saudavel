import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Faixa que aparece só quando há ações guardadas sem internet: mostra quantas faltam enviar,
/// deixa tentar agora e permite descartar o que o servidor recusou (ex.: horário que foi ocupado).
class PendenciasBanner extends ConsumerWidget {
  const PendenciasBanner({super.key});

  String _descricao(ItemOutbox i) => switch (i.tipo) {
        TipoOutbox.agendar => 'Agendamento',
        TipoOutbox.remarcar => 'Remarcação',
        _ => 'Alteração de sessão',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itens = ref.watch(pendenciasOutboxProvider).valueOrNull ?? const <ItemOutbox>[];
    if (itens.isEmpty) return const SizedBox.shrink();
    final sincronizador = ref.watch(sincronizadorProvider);
    final aguardando = itens.where((i) => i.pendente).length;
    final recusados = itens.where((i) => !i.pendente).toList();

    return Card(
      key: const Key('pendencias-banner'),
      color: Colors.amber.shade50,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (aguardando > 0)
              Row(
                children: [
                  const Icon(Icons.cloud_off, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      aguardando == 1
                          ? '1 ação aguardando internet para ser enviada.'
                          : '$aguardando ações aguardando internet para serem enviadas.',
                    ),
                  ),
                  TextButton(
                    onPressed: sincronizador == null
                        ? null
                        : () async {
                            final r = await sincronizador.sincronizar();
                            if (!context.mounted) return;
                            mostrarMensagem(
                              context,
                              r.semConexao ? 'Ainda sem conexão. Tentaremos de novo.' : 'Sincronização concluída.',
                              erro: r.semConexao,
                            );
                          },
                    child: const Text('Sincronizar agora'),
                  ),
                ],
              ),
            for (final i in recusados)
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 20, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${_descricao(i)} não enviado: ${i.ultimoErro ?? 'recusado pelo servidor'}')),
                  TextButton(
                    onPressed: sincronizador == null ? null : () => sincronizador.descartar(i.id),
                    child: const Text('Descartar'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
