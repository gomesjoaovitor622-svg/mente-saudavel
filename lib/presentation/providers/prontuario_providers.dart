import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/models/prontuario.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/services/prontuario_api.dart';

/// Acesso ao servidor. Nos testes, troque por um falso.
final prontuarioApiProvider = Provider<ProntuarioApi>((ref) => ProntuarioApi());

/// Registros do prontuário de UM paciente. `autoDispose`: ao sair da tela o conteúdo clínico sai da memória
/// (nada fica guardado no app). Troca de conta também descarta tudo.
final prontuarioProvider =
    AsyncNotifierProvider.autoDispose.family<ProntuarioNotifier, List<EntradaProntuario>, int>(ProntuarioNotifier.new);

class ProntuarioNotifier extends AutoDisposeFamilyAsyncNotifier<List<EntradaProntuario>, int> {
  @override
  Future<List<EntradaProntuario>> build(int pacienteId) {
    final usuario = ref.watch(usuarioAtualProvider);
    if (usuario?.id == null) return Future.value(const <EntradaProntuario>[]);
    return ref.watch(prontuarioApiProvider).listar(pacienteId);
  }

  /// Erros do servidor (AppException) sobem para a tela mostrar a mensagem.
  Future<void> criar({required String tipo, required String conteudo, int? sessaoId}) async {
    await ref.read(prontuarioApiProvider).criar(arg, tipo: tipo, conteudo: conteudo, sessaoId: sessaoId);
    ref.invalidateSelf();
    await future;
  }

  Future<void> editar(EntradaProntuario entrada, String conteudo) async {
    await ref.read(prontuarioApiProvider).editar(entrada.id, conteudo: conteudo, versaoEsperada: entrada.versao);
    ref.invalidateSelf();
    await future;
  }

  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Versões anteriores de um registro (carregadas só quando a pessoa abre o histórico).
final revisoesProvider = FutureProvider.autoDispose.family<List<RevisaoProntuario>, int>(
  (ref, entradaId) => ref.watch(prontuarioApiProvider).revisoes(entradaId),
);
