import 'package:flutter/foundation.dart';
import 'package:mente_saudavel/database/usuario_dao.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/seguranca.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Cadastro, login e usuário logado. O login fica gravado no SQLite.
class AuthService {
  /// Usuário logado (null = ninguém logado). A tela raiz "escuta" este valor.
  static final ValueNotifier<Usuario?> atual = ValueNotifier<Usuario?>(null);

  static final UsuarioDao _dao = UsuarioDao();

  /// Chamado na abertura do app: restaura o login salvo, se existir.
  static Future<void> carregarSessao() async {
    if (usaServidor) {
      // Se o servidor responder 401 em qualquer tela, volta para o login.
      ApiClient.aoExpirar = () => atual.value = null;
      final token = await ApiClient.carregarToken();
      if (token == null) return;
      try {
        atual.value = _doServidor(await ApiClient.get('/auth/eu'));
      } on AppException {
        // Token inválido/expirado já foi limpo pelo ApiClient; erro de rede segue para a tela.
        if (await ApiClient.carregarToken() != null) rethrow;
      }
      return;
    }
    final id = await _dao.lerSessao();
    if (id == null) return;
    atual.value = await _dao.buscarPorId(id);
  }

  static Usuario _doServidor(dynamic dados) =>
      Usuario.fromMap(Map<String, Object?>.from(dados as Map));

  static Future<void> _entrouNoServidor(dynamic resposta) async {
    final mapa = resposta as Map<String, dynamic>;
    await ApiClient.salvarToken(mapa['token'] as String);
    atual.value = _doServidor(mapa['usuario']);
  }

  static Future<bool> emailDisponivel(String email) async {
    // No servidor a checagem é feita (de forma segura) no próprio cadastro: devolve 409.
    if (usaServidor) return true;
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
    if (usaServidor) {
      await _entrouNoServidor(await ApiClient.post('/auth/cadastro', autenticado: false, corpo: {
        'nome': nome.trim(),
        'email': email.trim().toLowerCase(),
        'senha': senha,
        'perfil': perfil,
        if (perfil == Perfil.profissional) 'registro': registro?.trim(),
        if (perfil == Perfil.profissional) 'especialidade': especialidade?.trim(),
      }));
      return atual.value!;
    }
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
    if (usaServidor) {
      await _entrouNoServidor(await ApiClient.post('/auth/entrar', autenticado: false, corpo: {
        'email': email.trim(),
        'senha': senha,
      }));
      return;
    }
    final usuario = await _dao.buscarPorEmail(email);
    if (usuario == null || Seguranca.hashSenha(senha, usuario.salt) != usuario.senhaHash) {
      throw const AppException('E-mail ou senha incorretos.');
    }
    await _dao.salvarSessao(usuario.id!);
    atual.value = usuario;
  }

  static Future<void> sair() async {
    if (usaServidor) {
      await ApiClient.limparToken();
      atual.value = null;
      return;
    }
    await _dao.limparSessao();
    atual.value = null;
  }

  static Future<void> atualizarPerfil(Usuario atualizado) async {
    if (usaServidor) {
      final r = await ApiClient.patch('/auth/eu', corpo: {
        'nome': atualizado.nome,
        'registro': atualizado.registro,
        'especialidade': atualizado.especialidade,
        'endereco': atualizado.endereco,
      });
      atual.value = _doServidor(r);
      return;
    }
    await _dao.atualizarPerfil(atualizado);
    atual.value = atualizado;
  }

  static Future<void> alterarSenha(String senhaAtual, String novaSenha) async {
    if (usaServidor) {
      await ApiClient.post('/auth/senha', corpo: {'senha_atual': senhaAtual, 'nova_senha': novaSenha});
      return;
    }
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
    if (usaServidor) {
      await ApiClient.delete('/auth/eu');
      await ApiClient.limparToken();
      atual.value = null;
      return;
    }
    final usuario = atual.value!;
    await _dao.excluir(usuario.id!);
    await _dao.limparSessao();
    atual.value = null;
  }
}
