import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/painel_providers.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/utils/build_flags.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/componentes.dart';
import 'package:mente_saudavel/widgets/sessao_sheet.dart';

/// Painel do profissional (Riverpod). Antes: 8 variáveis de estado + `_carregar()` + `setState`.
/// Agora a tela só observa `painelProfissionalProvider` e `faturamentoHistoricoProvider`.
class PainelTab extends ConsumerWidget {
  final VoidCallback onVerAgenda;

  const PainelTab({super.key, required this.onVerAgenda});

  Future<void> _abrir(BuildContext context, WidgetRef ref, Sessao sessao) async {
    final mudou = await mostrarSessaoSheet(context, sessao: sessao, comoProfissional: true);
    if (mudou) ref.invalidate(painelProfissionalProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(usuarioAtualProvider);
    final painel = ref.watch(painelProfissionalProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(painelProfissionalProvider.notifier).recarregar(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Dr(a). ${usuario?.nome ?? ''}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text('Painel do Profissional', style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 16),
              painel.when(
                loading: () => const Center(
                  child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
                ),
                error: (_, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Erro ao carregar o painel.', style: TextStyle(color: Colors.red.shade700)),
                    TextButton(
                      onPressed: () => ref.invalidate(painelProfissionalProvider),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
                data: (p) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: StatCard(valor: '${p.atendimentosHoje}', rotulo: 'atendimentos hoje')),
                        const SizedBox(width: 12),
                        Expanded(child: StatCard(valor: '${p.pacientesAtivos}', rotulo: 'pacientes ativos')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    StatCard(
                      valor: p.notaMedia == null ? '—' : p.notaMedia!.toStringAsFixed(1),
                      rotulo: p.totalAvaliacoes == 0
                          ? 'avaliação média (sem avaliações ainda)'
                          : 'avaliação média (${p.totalAvaliacoes} avaliações)',
                    ),
                    if (usaServidor) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: StatCard(valor: formatarReais(p.recebidoCentavos), rotulo: 'recebido neste mês')),
                          const SizedBox(width: 12),
                          Expanded(child: StatCard(valor: formatarReais(p.aReceberCentavos), rotulo: 'a receber (agendadas)')),
                        ],
                      ),
                      const HistoricoFaturamento(),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Agenda de Hoje', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                        TextButton(onPressed: onVerAgenda, child: const Text('Ver agenda')),
                      ],
                    ),
                    if (p.agendaHoje.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Nenhum atendimento hoje.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      )
                    else
                      ...p.agendaHoje.map(
                        (s) => SessaoCard(
                          sessao: s,
                          comoProfissional: true,
                          mostrarData: false,
                          onTap: () => _abrir(context, ref, s),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faturamento dos últimos meses (modo servidor).
class HistoricoFaturamento extends ConsumerWidget {
  const HistoricoFaturamento({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historico = ref.watch(faturamentoHistoricoProvider).valueOrNull ?? const <Faturamento>[];
    if (historico.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const Key('historico-faturamento'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Histórico de faturamento', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final m in historico)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(width: 72, child: Text(m.rotulo)),
                    Expanded(child: Text('recebido ${formatarReais(m.recebidoCentavos)}')),
                    Text('a receber ${formatarReais(m.aReceberCentavos)}', style: TextStyle(color: Colors.grey.shade700)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
