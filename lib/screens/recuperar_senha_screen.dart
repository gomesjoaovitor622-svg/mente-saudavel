import 'package:flutter/material.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/validators.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// "Esqueci minha senha": 1) informa o e-mail e recebe um código de 6 dígitos; 2) digita o código e a nova senha.
class RecuperarSenhaScreen extends StatefulWidget {
  const RecuperarSenhaScreen({super.key, this.emailInicial = ''});

  final String emailInicial;

  @override
  State<RecuperarSenhaScreen> createState() => _RecuperarSenhaScreenState();
}

class _RecuperarSenhaScreenState extends State<RecuperarSenhaScreen> {
  final _formEmail = GlobalKey<FormState>();
  final _formCodigo = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(text: widget.emailInicial);
  final _codigo = TextEditingController();
  final _senha = TextEditingController();
  bool _codigoEnviado = false;
  bool _carregando = false;
  bool _ocultar = true;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _codigo.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _executar(Future<void> Function() acao) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      await acao();
    } on AppException catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não foi possível concluir. Verifique a conexão e tente de novo.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _pedirCodigo() async {
    if (!_formEmail.currentState!.validate()) return;
    await _executar(() async {
      await AuthService.esqueciSenha(_email.text);
      if (mounted) setState(() => _codigoEnviado = true);
    });
  }

  Future<void> _redefinir() async {
    if (!_formCodigo.currentState!.validate()) return;
    await _executar(() async {
      await AuthService.redefinirSenha(_email.text, _codigo.text, _senha.text);
      if (!mounted) return;
      mostrarMensagem(context, 'Senha alterada. Entre com a nova senha.');
      Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar senha')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _codigoEnviado ? _passoCodigo() : _passoEmail(),
        ),
      ),
    );
  }

  Widget _passoEmail() {
    return Form(
      key: _formEmail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Informe o e-mail da sua conta. Enviaremos um código de 6 dígitos.'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: campo('E-mail', icone: Icons.email_outlined),
            validator: validarEmail,
          ),
          if (_erro != null) _mensagemErro(),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _carregando ? null : _pedirCodigo,
              child: const Text('Enviar código'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passoCodigo() {
    return Form(
      key: _formCodigo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Se existir uma conta com esse e-mail, enviamos um código de 6 dígitos (vale por 15 minutos). '
            'Veja também a caixa de spam.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _codigo,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: campo('Código de 6 dígitos', icone: Icons.pin_outlined),
            validator: (v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim()) ? null : 'Digite os 6 números do e-mail.',
          ),
          TextFormField(
            controller: _senha,
            obscureText: _ocultar,
            decoration: campo(
              'Nova senha',
              icone: Icons.lock_outline,
              sufixo: IconButton(
                icon: Icon(_ocultar ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _ocultar = !_ocultar),
              ),
            ),
            validator: validarSenha,
          ),
          if (_erro != null) _mensagemErro(),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _carregando ? null : _redefinir,
              child: const Text('Alterar senha'),
            ),
          ),
          TextButton(
            onPressed: _carregando ? null : () => setState(() => _codigoEnviado = false),
            child: const Text('Pedir um novo código'),
          ),
        ],
      ),
    );
  }

  Widget _mensagemErro() => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(_erro!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade700)),
      );
}
