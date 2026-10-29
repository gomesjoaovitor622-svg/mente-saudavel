import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/database/avaliacao_dao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Faturamento de um mês (modo servidor). Valores em centavos.
class Faturamento {
  const Faturamento({
    required this.mes,
    required this.recebidoCentavos,
    required this.aReceberCentavos,
    required this.concluidas,
    required this.agendadas,
  });

  /// "2026-10"
  final String mes;
  final int recebidoCentavos;
  final int aReceberCentavos;
  final int concluidas;
  final int agendadas;

  factory Faturamento.fromMap(Map<String, Object?> m) => Faturamento(
        mes: m['mes']! as String,
        recebidoCentavos: (m['recebido_centavos']! as num).toInt(),
        aReceberCentavos: (m['a_receber_centavos']! as num).toInt(),
        concluidas: (m['sessoes_concluidas']! as num).toInt(),
        agendadas: (m['sessoes_agendadas']! as num).toInt(),
      );

  /// "2026-10" -> "Out/2026"
  String get rotulo {
    const nomes = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
    final partes = mes.split('-');
    return '${nomes[int.parse(partes[1]) - 1]}/${partes[0]}';
  }
}

/// Histórico de faturamento dos últimos 6 meses (o mais recente primeiro).
/// No modo local não há preço por sessão, então a lista é vazia e a tela esconde a seção.
final faturamentoHistoricoProvider = FutureProvider<List<Faturamento>>((ref) async {
  if (!usaServidor) return const <Faturamento>[];
  ref.watch(usuarioAtualProvider);
  ref.watch(outboxVersaoProvider); // concluir uma sessão muda o faturamento
  final r = await ApiClient.get('/profissional/financeiro/historico', consulta: {'meses': '6'});
  return ApiClient.comoLista(r).map(Faturamento.fromMap).toList();
});

final avaliacaoDaoProvider = Provider<AvaliacaoDao>((ref) => AvaliacaoDao());

/// Tudo que o painel do profissional mostra.
class PainelProfissional {
  const PainelProfissional({
    required this.atendimentosHoje,
    required this.pacientesAtivos,
    required this.notaMedia,
    required this.totalAvaliacoes,
    required this.recebidoCentavos,
    required this.aReceberCentavos,
    required this.agendaHoje,
  });

  final int atendimentosHoje;
  final int pacientesAtivos;
  final double? notaMedia;
  final int totalAvaliacoes;
  final int recebidoCentavos; // mês atual (modo servidor)
  final int aReceberCentavos;
  final List<Sessao> agendaHoje;
}

final painelProfissionalProvider = AsyncNotifierProvider<PainelProfissionalNotifier, PainelProfissional>(
  PainelProfissionalNotifier.new,
);

class PainelProfissionalNotifier extends AsyncNotifier<PainelProfissional> {
  @override
  Future<PainelProfissional> build() async {
    final usuario = ref.watch(usuarioAtualProvider);
    ref.watch(outboxVersaoProvider);
    final id = usuario?.id;
    if (id == null) throw StateError('Nenhum usuário logado.');

    final repo = ref.watch(sessaoRepositoryProvider);
    final atendimentos = await repo.atendimentosHoje(id);
    final pacientes = await repo.pacientesAtivos(id);
    final agenda = await repo.doProfissionalNoDia(id, DateTime.now(), incluirCanceladas: false);
    final avaliacoes = await ref.watch(avaliacaoDaoProvider).doProfissional(id, limite: 1000);
    final faturamento = await ref.watch(faturamentoHistoricoProvider.future);

    return PainelProfissional(
      atendimentosHoje: atendimentos,
      pacientesAtivos: pacientes,
      totalAvaliacoes: avaliacoes.length,
      notaMedia: avaliacoes.isEmpty ? null : avaliacoes.fold<int>(0, (soma, a) => soma + a.nota) / avaliacoes.length,
      recebidoCentavos: faturamento.isEmpty ? 0 : faturamento.first.recebidoCentavos,
      aReceberCentavos: faturamento.isEmpty ? 0 : faturamento.first.aReceberCentavos,
      agendaHoje: agenda,
    );
  }

  /// Puxar para atualizar: recarrega tudo e só termina quando os dados novos chegam.
  Future<void> recarregar() async {
    ref.invalidateSelf();
    ref.invalidate(faturamentoHistoricoProvider);
    await future;
  }
}
