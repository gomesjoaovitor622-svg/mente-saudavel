import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/services/auth_service.dart';

/// Ações do perfil (salvar, senha, sair, excluir, LGPD). O estado do provider É o "carregando":
/// a tela só faz `ref.watch(perfilControllerProvider).isLoading` para desabilitar os botões,
/// sem `_salvando`/`setState` espalhados. Os controllers de texto continuam na tela (eles
/// pertencem ao widget, não ao estado do app).
final perfilControllerProvider = AsyncNotifierProvider<PerfilController, void>(PerfilController.new);

class PerfilController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// Roda a ação marcando "carregando"; se falhar, guarda o erro no estado E relança para a tela
  /// mostrar a mensagem certa.
  Future<T> _executar<T>(Future<T> Function() acao) async {
    state = const AsyncLoading();
    try {
      final resultado = await acao();
      state = const AsyncData(null);
      return resultado;
    } catch (e, pilha) {
      state = AsyncError(e, pilha);
      rethrow;
    }
  }

  Future<void> salvar(Usuario atualizado) => _executar(() => AuthService.atualizarPerfil(atualizado));

  Future<void> alterarSenha(String atual, String nova) => _executar(() => AuthService.alterarSenha(atual, nova));

  Future<void> sair() => _executar(AuthService.sair);

  Future<void> excluirConta() => _executar(AuthService.excluirConta);

  /// LGPD: direito à eliminação (anonimiza os dados do paciente e encerra a sessão).
  Future<void> anonimizarConta(String senha) => _executar(() => AuthService.anonimizarConta(senha));

  /// LGPD: portabilidade. Devolve todos os dados da conta em JSON legível.
  Future<String> exportarDados() => _executar(() async {
        final dados = await ApiClient.get('/auth/eu/exportar');
        return const JsonEncoder.withIndent('  ').convert(dados);
      });
}
