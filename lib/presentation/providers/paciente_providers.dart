import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/services/telemetria.dart';

/// O que a tela Início do paciente mostra: próxima sessão e quantas já foram concluídas.
class InicioPaciente {
  const InicioPaciente({required this.proxima, required this.concluidas});

  final Sessao? proxima;
  final int concluidas;
}

/// Dados do Início. Recarrega ao trocar de conta ou quando a fila offline sincroniza; quem agenda ou
/// altera uma sessão chama [invalidarDadosDoPaciente].
final inicioPacienteProvider = AsyncNotifierProvider<InicioPacienteNotifier, InicioPaciente>(InicioPacienteNotifier.new);

class InicioPacienteNotifier extends AsyncNotifier<InicioPaciente> {
  @override
  Future<InicioPaciente> build() {
    final usuario = ref.watch(usuarioAtualProvider);
    ref.watch(outboxVersaoProvider);
    if (usuario?.id == null) return Future.value(const InicioPaciente(proxima: null, concluidas: 0));
    final repo = ref.watch(sessaoRepositoryProvider);
    return Telemetria.medir('paciente_inicio:dados', () async {
      final proxima = await repo.proximaDoPaciente(usuario!.id!);
      final concluidas = await repo.concluidasDoPaciente(usuario.id!);
      return InicioPaciente(proxima: proxima, concluidas: concluidas);
    });
  }

  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Depois de agendar, remarcar ou cancelar: a lista "Minhas sessões" e o Início recarregam juntos.
void invalidarDadosDoPaciente(WidgetRef ref) {
  ref.invalidate(minhasSessoesProvider);
  ref.invalidate(inicioPacienteProvider);
}
