import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/profissional_providers.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/componentes.dart';
import 'package:mente_saudavel/widgets/medir_tela.dart';
import 'package:mente_saudavel/widgets/sessao_sheet.dart';

/// Agenda do profissional, dia a dia. A tela só observa [agendaSessoesProvider]; o dia escolhido
/// fica em [agendaDiaProvider] e trocá-lo recarrega a lista sozinho.
class AgendaTab extends ConsumerWidget {
  const AgendaTab({super.key});

  void _irParaDia(WidgetRef ref, DateTime dia) => ref.read(agendaDiaProvider.notifier).state = somenteData(dia);

  Future<void> _escolherDia(BuildContext context, WidgetRef ref, DateTime atual) async {
    final escolhido = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (escolhido != null) _irParaDia(ref, escolhido);
  }

  Future<void> _abrir(BuildContext context, WidgetRef ref, Sessao sessao) async {
    final mudou = await mostrarSessaoSheet(context, sessao: sessao, comoProfissional: true);
    if (mudou) invalidarDadosDoProfissional(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dia = ref.watch(agendaDiaProvider);
    final sessoes = ref.watch(agendaSessoesProvider);
    final ehHoje = mesmoDia(dia, DateTime.now());
    return MedirTela(
      nome: 'agenda',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Agenda'),
          actions: [
            if (!ehHoje) TextButton(onPressed: () => _irParaDia(ref, DateTime.now()), child: const Text('Hoje')),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Dia anterior',
                    onPressed: () => _irParaDia(ref, DateTime(dia.year, dia.month, dia.day - 1)),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () => _escolherDia(context, ref, dia),
                      child: Text('${formatarDataExtenso(dia)} · ${formatarDataCurta(dia)}', style: const TextStyle(fontSize: 15)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Próximo dia',
                    onPressed: () => _irParaDia(ref, DateTime(dia.year, dia.month, dia.day + 1)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: sessoes.when(
                // Na troca de dia mostra o spinner, e não a lista do dia anterior com a data nova.
                skipLoadingOnReload: false,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Erro ao carregar a agenda.'),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: () => ref.invalidate(agendaSessoesProvider), child: const Text('Tentar novamente')),
                      ],
                    ),
                  ),
                ),
                data: (lista) => lista.isEmpty
                    ? const Center(child: Text('Nenhuma sessão neste dia.'))
                    : RefreshIndicator(
                        onRefresh: () => ref.read(agendaSessoesProvider.notifier).recarregar(),
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: lista.length,
                          itemBuilder: (context, i) => SessaoCard(
                            sessao: lista[i],
                            comoProfissional: true,
                            mostrarData: false,
                            onTap: () => _abrir(context, ref, lista[i]),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
