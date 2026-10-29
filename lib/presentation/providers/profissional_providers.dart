import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/painel_providers.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/services/telemetria.dart';
import 'package:mente_saudavel/utils/formatters.dart';

/// Dia mostrado na agenda. Volta para "hoje" quando troca a conta (ninguém herda o dia da outra pessoa).
final agendaDiaProvider = StateProvider<DateTime>((ref) {
  ref.watch(usuarioAtualProvider);
  return somenteData(DateTime.now());
});

/// Sessões do profissional logado no dia escolhido. Recarrega sozinha quando muda o dia, a conta
/// ou a fila offline sincroniza; quem altera uma sessão chama [invalidarDadosDoProfissional].
final agendaSessoesProvider = AsyncNotifierProvider<AgendaNotifier, List<Sessao>>(AgendaNotifier.new);

class AgendaNotifier extends AsyncNotifier<List<Sessao>> {
  @override
  Future<List<Sessao>> build() {
    final usuario = ref.watch(usuarioAtualProvider);
    final dia = ref.watch(agendaDiaProvider);
    ref.watch(outboxVersaoProvider);
    if (usuario?.id == null) return Future.value(const <Sessao>[]);
    final repo = ref.watch(sessaoRepositoryProvider);
    return Telemetria.medir('agenda:dados', () => repo.doProfissionalNoDia(usuario!.id!, dia));
  }

  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Texto digitado na busca de pacientes. Zera quando troca a conta (nome de paciente não vaza entre contas).
final buscaPacientesProvider = StateProvider<String>((ref) {
  ref.watch(usuarioAtualProvider);
  return '';
});

/// Pacientes que já têm (ou tiveram) sessão com o profissional logado.
final pacientesProvider = AsyncNotifierProvider<PacientesNotifier, List<PacienteResumo>>(PacientesNotifier.new);

class PacientesNotifier extends AsyncNotifier<List<PacienteResumo>> {
  @override
  Future<List<PacienteResumo>> build() {
    final usuario = ref.watch(usuarioAtualProvider);
    ref.watch(outboxVersaoProvider);
    if (usuario?.id == null) return Future.value(const <PacienteResumo>[]);
    final repo = ref.watch(sessaoRepositoryProvider);
    return Telemetria.medir('pacientes:dados', () => repo.pacientesDoProfissional(usuario!.id!));
  }

  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Lista de pacientes já filtrada pela busca (nome ou e-mail, sem diferenciar maiúsculas).
final pacientesFiltradosProvider = Provider<AsyncValue<List<PacienteResumo>>>((ref) {
  final termo = ref.watch(buscaPacientesProvider).trim().toLowerCase();
  return ref.watch(pacientesProvider).whenData(
        (lista) => termo.isEmpty
            ? lista
            : lista.where((p) => p.nome.toLowerCase().contains(termo) || p.email.toLowerCase().contains(termo)).toList(),
      );
});

/// Depois de alterar uma sessão (concluir, cancelar, anotar), tudo que depende dela recarrega.
void invalidarDadosDoProfissional(WidgetRef ref) {
  ref.invalidate(agendaSessoesProvider);
  ref.invalidate(pacientesProvider);
  ref.invalidate(painelProfissionalProvider);
  ref.invalidate(faturamentoHistoricoProvider);
}
