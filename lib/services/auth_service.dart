import 'package:flutter/foundation.dart';
import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:mente_saudavel/database/usuario_dao.dart';
import 'package:mente_saudavel/legal/textos_legais.dart';
import 'package:mente_saudavel/services/consentimento_service.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/seguranca.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Cadastro, login e usuário logado. O login fica gravado no SQLite.
class AuthService {
  // Hash válido de uma senha que ninguém tem: usado quando o e-mail não existe.
  static final String _hashFalso = '${Seguranca.prefixo}\$${Seguranca.iteracoes}\$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

  /// Usuário logado (null = ninguém logado). A tela raiz "escuta" este valor.
  static final ValueNotifier<Usuario?> atual = ValueNotifier<Usuario?>(null);

  static final UsuarioDao _dao = UsuarioDao();

  /// Chamado na abertura do app: restaura o login salvo, se existir.
  static Future<void> carregarSessao() async {
    await Consentimento.carregar();
    if (usaServidor) {
      // Se o servidor responder 401 em qualquer tela, volta para o login.
      ApiClient.aoExpirar = () => atual.value = null;
      final token = await ApiClient.carregarToken();
      // Web: não há token legível (o cookie HttpOnly vai sozinho); pergunta ao servidor.
      if (token == null && !ApiClient.usaCookie) return;
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
        'aceite_termos_versao': kVersaoTermos, // o aceite foi dado na tela de termos, antes do cadastro
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
      senhaHash: await Seguranca.criarHash(senha, salt),
      salt: salt,
      perfil: perfil,
      registro: registro?.trim(),
      especialidade: especialidade?.trim(),
      criadoEm: DateTime.now().toIso8601String(),
      aceiteTermosVersao: kVersaoTermos,
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
    // Sem conta, confere contra um hash falso: o tempo de resposta não revela se o e-mail existe.
    final resultado = usuario == null
        ? await Seguranca.verificar(senha, _hashFalso, 'sal-falso')
        : await Seguranca.verificar(senha, usuario.senhaHash, usuario.salt);
    if (usuario == null || resultado == ResultadoSenha.invalida) {
      throw const AppException('E-mail ou senha incorretos.');
    }
    var logado = usuario;
    if (resultado == ResultadoSenha.validaPrecisaAtualizar) {
      // Conta com hash antigo (SHA-256): troca pelo PBKDF2 agora que a senha está em mãos.
      final salt = Seguranca.gerarSalt();
      final hash = await Seguranca.criarHash(senha, salt);
      await _dao.atualizarSenha(usuario.id!, hash, salt);
      logado = usuario.copyWith(senhaHash: hash, salt: salt);
    }
    await _dao.salvarSessao(logado.id!);
    atual.value = logado;
  }

  // ---- Recuperação de senha e confirmação de e-mail (só no modo servidor) ----

  /// Pede o código de 6 dígitos por e-mail. A resposta é a mesma exista a conta ou não.
  static Future<void> esqueciSenha(String email) async {
    await ApiClient.post('/auth/senha/esqueci', autenticado: false, corpo: {'email': email.trim()});
  }

  static Future<void> redefinirSenha(String email, String codigo, String novaSenha) async {
    await ApiClient.post('/auth/senha/redefinir', autenticado: false, corpo: {
      'email': email.trim(),
      'codigo': codigo.trim(),
      'nova_senha': novaSenha,
    });
  }

  static Future<void> reenviarCodigoEmail() async {
    await ApiClient.post('/auth/email/codigo');
  }

  /// Confere o código e recarrega o usuário (some o aviso "confirme seu e-mail").
  static Future<void> verificarEmail(String codigo) async {
    await ApiClient.post('/auth/email/verificar', corpo: {'codigo': codigo.trim()});
    atual.value = _doServidor(await ApiClient.get('/auth/eu'));
  }

  /// Recarrega o usuário (ex.: depois que o administrador aprovou o profissional).
  static Future<void> recarregarUsuario() async {
    if (!usaServidor) return;
    atual.value = _doServidor(await ApiClient.get('/auth/eu'));
  }

  static Future<void> sair() async {
    if (usaServidor) {
      await ApiClient.encerrarSessao();
      // Dados de saúde em cache não ficam no aparelho depois do logout.
      try {
        await CacheKv().limpar();
      } catch (_) {}
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
        'valor_sessao_centavos': atualizado.valorSessaoCentavos,
      });
      atual.value = _doServidor(r);
      return;
    }
    await _dao.atualizarPerfil(atualizado);
    atual.value = atualizado;
  }

  static Future<void> alterarSenha(String senhaAtual, String novaSenha) async {
    if (usaServidor) {
      final r = await ApiClient.post('/auth/senha', corpo: {'senha_atual': senhaAtual, 'nova_senha': novaSenha});
      // O servidor revoga os tokens antigos ao trocar a senha e devolve um novo para este aparelho.
      if (r is Map && r['token'] is String) await ApiClient.salvarToken(r['token'] as String);
      return;
    }
    final usuario = atual.value!;
    final resultado = await Seguranca.verificar(senhaAtual, usuario.senhaHash, usuario.salt);
    if (resultado == ResultadoSenha.invalida) {
      throw const AppException('A senha atual está incorreta.');
    }
    final salt = Seguranca.gerarSalt();
    final hash = await Seguranca.criarHash(novaSenha, salt);
    await _dao.atualizarSenha(usuario.id!, hash, salt);
    atual.value = usuario.copyWith(senhaHash: hash, salt: salt);
  }

  static Future<void> excluirConta() async {
    if (usaServidor) {
      await ApiClient.delete('/auth/eu');
      await ApiClient.encerrarSessao();
      atual.value = null;
      return;
    }
    final usuario = atual.value!;
    await _dao.excluir(usuario.id!);
    await _dao.limparSessao();
    atual.value = null;
  }

  /// Registra na CONTA o aceite da versão atual dos termos (quem já tinha conta antes da LGPD,
  /// ou quando os textos mudam).
  static Future<void> registrarAceite() async {
    await Consentimento.aceitarNoAparelho();
    if (usaServidor) {
      atual.value = _doServidor(await ApiClient.post('/auth/eu/aceite', corpo: {'versao': kVersaoTermos}));
      return;
    }
    final usuario = atual.value;
    if (usuario == null) return;
    await _dao.registrarAceite(usuario.id!, kVersaoTermos);
    atual.value = usuario.copyWith(aceiteTermosVersao: kVersaoTermos);
  }

  /// Direito à eliminação (LGPD, art. 18): anonimiza os dados do PACIENTE e encerra a sessão.
  /// Pede a senha para confirmar que é a própria pessoa (a ação não tem volta).
  static Future<void> anonimizarConta(String senha) async {
    final usuario = atual.value!;
    if (usuario.isProfissional) {
      throw const AppException('Profissionais usam "Excluir conta" (os pacientes dependem do histórico).');
    }
    if (usaServidor) {
      await ApiClient.post('/auth/eu/anonimizar', corpo: {'senha': senha});
      try {
        await OutboxRepository().limparUsuario(usuario.id!); // ações pendentes dela não devem mais ser enviadas
        await CacheKv().limpar();
      } catch (_) {}
      await ApiClient.limparToken();
      atual.value = null;
      return;
    }
    final resultado = await Seguranca.verificar(senha, usuario.senhaHash, usuario.salt);
    if (resultado == ResultadoSenha.invalida) throw const AppException('Senha incorreta.');
    await _dao.anonimizar(usuario.id!);
    atual.value = null;
  }
}

