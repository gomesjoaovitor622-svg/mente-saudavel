import 'package:flutter/foundation.dart';
import 'package:mente_saudavel/database/usuario_dao.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/seguranca.dart';
import 'package:mente_saudavel/utils/app_exception.dart';

/// Cadastro, login e usuário logado. O login fica gravado no SQLite.
class AuthService {
  /// Usuário logado (null = ninguém logado). A tela raiz "escuta" este valor.
  static final ValueNotifier<Usuario?> atual = ValueNotifier<Usuario?>(null);

  static final UsuarioDao _dao = UsuarioDao();

  /// Chamado na abertura do app: restaura o login salvo, se existir.
  static Future<void> carregarSessao() async {
    final id = await _dao.lerSessao();
    if (id == null) return;
    atual.value = await _dao.buscarPorId(id);
  }

  static Future<bool> emailDisponivel(String email) async {
    return await _dao.buscarPorEmail(email) == null;
  }

  static Future<Usuario> cadastrar({
    required String nome,
    required String email,
    required String senha,
    required String perfil,
    String? registro,
    String? especialidade,
  }) async {
    if (!await emailDisponivel(email)) {
      throw const AppException('Este e-mail já está cadastrado.');
    }
    final salt = Seguranca.gerarSalt();
    final novo = Usuario(
      nome: nome.trim(),
      email: email.trim().toLowerCase(),
      senhaHash: Seguranca.hashSenha(senha, salt),
      salt: salt,
      perfil: perfil,
      registro: registro?.trim(),
      especialidade: especialidade?.trim(),
      criadoEm: DateTime.now().toIso8601String(),
    );
    final id = await _dao.inserir(novo);
    final salvo = novo.copyWith(id: id);
    await _dao.salvarSessao(id);
    atual.value = salvo;
    return salvo;
  }

  static Future<void> entrar(String email, String senha) async {
    final usuario = await _dao.buscarPorEmail(email);
    if (usuario == null || Seguranca.hashSenha(senha, usuario.salt) != usuario.senhaHash) {
      throw const AppException('E-mail ou senha incorretos.');
    }
    await _dao.salvarSessao(usuario.id!);
    atual.value = usuario;
  }

  static Future<void> sair() async {
    await _dao.limparSessao();
    atual.value = null;
  }

  static Future<void> atualizarPerfil(Usuario atualizado) async {
    await _dao.atualizarPerfil(atualizado);
    atual.value = atualizado;
  }

  static Future<void> alterarSenha(String senhaAtual, String novaSenha) async {
    final usuario = atual.value!;
    if (Seguranca.hashSenha(senhaAtual, usuario.salt) != usuario.senhaHash) {
      throw const AppException('A senha atual está incorreta.');
    }
    final salt = Seguranca.gerarSalt();
    final hash = Seguranca.hashSenha(novaSenha, salt);
    await _dao.atualizarSenha(usuario.id!, hash, salt);
    atual.value = usuario.copyWith(senhaHash: hash, salt: salt);
  }

  static Future<void> excluirConta() async {
    final usuario = atual.value!;
    await _dao.excluir(usuario.id!);
    await _dao.limparSessao();
    atual.value = null;
  }
}
