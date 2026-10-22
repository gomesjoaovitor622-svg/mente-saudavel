import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:mente_saudavel/domain/repositories/sessao_repository.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/services/sincronizador_outbox.dart';
import 'package:mente_saudavel/services/telemetria.dart';

/// Repositório de sessões. O valor real é injetado no `main()` (composition root, via
/// `overrideWithValue`); nos testes basta trocar por um falso.
final sessaoRepositoryProvider = Provider<SessaoRepository>(
  (ref) => throw UnimplementedError('Injete o repositório no ProviderScope (veja main.dart).'),
);

/// Usuário logado, como provider. Acompanha o `AuthService.atual` (login/logout) e reconstrói
/// tudo o que depende dele, então nunca sobra lista de outra conta na tela.
final usuarioAtualProvider = Provider<Usuario?>((ref) {
  final notificador = AuthService.atual;
  void aoMudar() => ref.invalidateSelf();
  notificador.addListener(aoMudar);
  ref.onDispose(() => notificador.removeListener(aoMudar));
  return notificador.value;
});

/// Sincronizador da fila offline (só existe no modo servidor; null no modo local e nos testes).
final sincronizadorProvider = Provider<SincronizadorOutbox?>((ref) => null);

/// Muda sempre que a fila offline ou os dados sincronizados mudam. Quem depende dela recarrega.
final outboxVersaoProvider = Provider<int>((ref) {
  final sincronizador = ref.watch(sincronizadorProvider);
  if (sincronizador == null) return 0;
  void aoMudar() => ref.invalidateSelf();
  sincronizador.versao.addListener(aoMudar);
  ref.onDispose(() => sincronizador.versao.removeListener(aoMudar));
  return sincronizador.versao.value;
});

/// Itens da fila offline da pessoa logada (pendentes, em conflito ou que falharam).
final pendenciasOutboxProvider = FutureProvider<List<ItemOutbox>>((ref) async {
  ref.watch(outboxVersaoProvider);
  final sincronizador = ref.watch(sincronizadorProvider);
  final usuario = ref.watch(usuarioAtualProvider);
  if (sincronizador == null || usuario?.id == null) return const <ItemOutbox>[];
  return sincronizador.outbox.todos(usuario!.id!);
});

/// Filtro escolhido nos chips: null = todas, ou um `StatusSessao`.
final filtroSessoesProvider = StateProvider<String?>((ref) => null);

/// Lista "Minhas sessões" do paciente. Recarrega sozinha quando o filtro ou o usuário mudam, e
/// quem agenda/altera uma sessão só precisa chamar `ref.invalidate(minhasSessoesProvider)`.
final minhasSessoesProvider = AsyncNotifierProvider<MinhasSessoesNotifier, List<Sessao>>(
  MinhasSessoesNotifier.new,
);

class MinhasSessoesNotifier extends AsyncNotifier<List<Sessao>> {
  @override
  Future<List<Sessao>> build() {
    final usuario = ref.watch(usuarioAtualProvider);
    final filtro = ref.watch(filtroSessoesProvider);
    ref.watch(outboxVersaoProvider); // sincronizou algo? recarrega a lista
    if (usuario?.id == null) return Future.value(const <Sessao>[]);
    final repo = ref.watch(sessaoRepositoryProvider);
    return Telemetria.medir('minhas_sessoes:dados', () => repo.doPaciente(usuario!.id!, status: filtro));
  }

  /// Puxar para atualizar: recarrega e só termina quando a nova lista chega.
  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }
}
