import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/screens/paciente/agendar_sessao_screen.dart';
import 'package:mente_saudavel/widgets/componentes.dart';
import 'package:mente_saudavel/widgets/sessao_sheet.dart';

/// Aba "Minhas sessões" (primeira tela migrada para Riverpod).
///
/// Antes: `setState` + `_carregando` + `_carregar()` + `mounted` em toda ação.
/// Agora: a tela só OBSERVA `minhasSessoesProvider`; carregando, erro e dados vêm prontos
/// em `AsyncValue.when`, e recarregar é `ref.invalidate(...)`.
class MinhasSessoesTab extends ConsumerWidget {
  const MinhasSessoesTab({super.key});

  Future<void> _agendar(BuildContext context) async {
    // A tela de agendar invalida o provider ao gravar: a lista se atualiza sozinha.
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AgendarSessaoScreen()),
    );
  }

  Future<void> _abrir(BuildContext context, WidgetRef ref, Sessao sessao) async {
    final mudou = await mostrarSessaoSheet(context, sessao: sessao, comoProfissional: false);
    if (mudou) ref.invalidate(minhasSessoesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroSessoesProvider);
    final sessoes = ref.watch(minhasSessoesProvider);

    Widget chip(String rotulo, String? valor) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(rotulo),
            selected: filtro == valor,
            onSelected: (_) => ref.read(filtroSessoesProvider.notifier).state = valor,
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Minhas sessões')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                chip('Todas', null),
                chip('Agendadas', StatusSessao.agendada),
                chip('Concluídas', StatusSessao.concluida),
                chip('Canceladas', StatusSessao.cancelada),
              ],
            ),
          ),
          Expanded(
            child: sessoes.when(
              // Na troca de filtro mostra o spinner (e não a lista antiga com o filtro novo).
              skipLoadingOnReload: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Erro ao carregar as sessões.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => ref.invalidate(minhasSessoesProvider),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (lista) => lista.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhuma sessão encontrada.\nToque em + para agendar.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => ref.read(minhasSessoesProvider.notifier).recarregar(),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                        itemCount: lista.length,
                        itemBuilder: (context, i) => SessaoCard(
                          sessao: lista[i],
                          comoProfissional: false,
                          onTap: () => _abrir(context, ref, lista[i]),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _agendar(context),
        icon: const Icon(Icons.add),
        label: const Text('Agendar'),
      ),
    );
  }
}
