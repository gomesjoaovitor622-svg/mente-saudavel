import 'package:flutter/material.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/utils/validators.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Cadastro em passos, como no vídeo:
/// 0) e-mail e senha  ->  1) nome  ->  2) paciente ou profissional
/// ->  3) dados profissionais (somente para profissional).
class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  final _formConta = GlobalKey<FormState>();
  final _formNome = GlobalKey<FormState>();
  final _formProfissional = GlobalKey<FormState>();

  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _nome = TextEditingController();
  final _registro = TextEditingController();
  final _especialidade = TextEditingController();

  int _passo = 0;
  bool _ocultarSenha = true;
  bool _carregando = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    _nome.dispose();
    _registro.dispose();
    _especialidade.dispose();
    super.dispose();
  }

  void _voltar() {
    if (_passo == 0) {
      Navigator.pop(context);
    } else {
      setState(() {
        _passo -= 1;
        _erro = null;
      });
    }
  }

  Future<void> _continuarConta() async {
    if (!_formConta.currentState!.validate()) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final livre = await AuthService.emailDisponivel(_email.text);
      if (!mounted) return;
      if (!livre) {
        setState(() {
          _erro = 'Este e-mail já está cadastrado.';
          _carregando = false;
        });
        return;
      }
      setState(() {
        _carregando = false;
        _passo = 1;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao acessar o banco de dados.';
        _carregando = false;
      });
    }
  }

  void _continuarNome() {
    if (!_formNome.currentState!.validate()) return;
    setState(() {
      _passo = 2;
      _erro = null;
    });
  }

  void _escolherPerfil(String perfil) {
    if (perfil == Perfil.paciente) {
      _finalizar(Perfil.paciente);
    } else {
      setState(() {
        _passo = 3;
        _erro = null;
      });
    }
  }

  void _continuarProfissional() {
    if (!_formProfissional.currentState!.validate()) return;
    _finalizar(Perfil.profissional);
  }

  Future<void> _finalizar(String perfil) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      await AuthService.cadastrar(
        nome: _nome.text,
        email: _email.text,
        senha: _senha.text,
        perfil: perfil,
        registro: perfil == Perfil.profissional ? _registro.text : null,
        especialidade: perfil == Perfil.profissional ? _especialidade.text : null,
      );
      if (!mounted) return;
      // Volta até a raiz: o AuthGate já está mostrando o painel do usuário.
      Navigator.popUntil(context, (rota) => rota.isFirst);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao salvar o cadastro.';
        _carregando = false;
      });
    }
  }

  Widget _botao(String texto, VoidCallback? onPressed) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: _carregando ? null : onPressed,
        child: _carregando
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(texto),
      ),
    );
  }

  Widget _titulo(String titulo, String subtitulo) {
    return Column(
      children: [
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          subtitulo,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _mensagemErro() {
    if (_erro == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        _erro!,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.red.shade700),
      ),
    );
  }

  Widget _passoConta() {
    return Form(
      key: _formConta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo('Criar uma conta', 'Insira suas credenciais para se cadastrar'),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: campo('E-mail', icone: Icons.email_outlined),
            validator: validarEmail,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _senha,
            obscureText: _ocultarSenha,
            decoration: campo(
              'Senha',
              icone: Icons.lock_outline,
              sufixo: IconButton(
                icon: Icon(_ocultarSenha ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _ocultarSenha = !_ocultarSenha),
              ),
            ),
            validator: validarSenha,
          ),
          _mensagemErro(),
          const SizedBox(height: 16),
          _botao('Continuar', _continuarConta),
        ],
      ),
    );
  }

  Widget _passoNome() {
    return Form(
      key: _formNome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo('Psicoterapia acessível', 'Como podemos te chamar?'),
          TextFormField(
            controller: _nome,
            textCapitalization: TextCapitalization.words,
            decoration: campo('Seu nome', icone: Icons.person_outline),
            validator: validarNome,
            onFieldSubmitted: (_) => _continuarNome(),
          ),
          const SizedBox(height: 16),
          _botao('Continuar', _continuarNome),
        ],
      ),
    );
  }

  Widget _passoPerfil() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Seja bem vindo, ${primeiroNome(_nome.text)}!\nVocê é',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        _botao('Paciente', () => _escolherPerfil(Perfil.paciente)),
        const SizedBox(height: 10),
        _botao('Profissional', () => _escolherPerfil(Perfil.profissional)),
        _mensagemErro(),
      ],
    );
  }

  Widget _passoProfissional() {
    return Form(
      key: _formProfissional,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo('Dados profissionais', 'Essas informações aparecem para os pacientes'),
          TextFormField(
            controller: _registro,
            textInputAction: TextInputAction.next,
            decoration: campo('Registro profissional (CRP)', icone: Icons.badge_outlined, dica: 'Ex.: 06/12345'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o CRP.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _especialidade,
            textCapitalization: TextCapitalization.sentences,
            decoration: campo('Especialidade', icone: Icons.psychology_outlined, dica: 'Ex.: Psicologia clínica'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe a especialidade.' : null,
          ),
          _mensagemErro(),
          const SizedBox(height: 16),
          _botao('Concluir cadastro', _continuarProfissional),
        ],
      ),
    );
  }

  Widget _conteudo() {
    switch (_passo) {
      case 0:
        return _passoConta();
      case 1:
        return _passoNome();
      case 2:
        return _passoPerfil();
      default:
        return _passoProfissional();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _carregando ? null : _voltar,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: LogoMente(tamanho: 64)),
                const SizedBox(height: 24),
                _conteudo(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
