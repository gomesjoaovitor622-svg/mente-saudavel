import 'package:flutter/material.dart';
import 'package:mente_saudavel/screens/cadastro_screen.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/validators.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _carregando = false;
  bool _ocultarSenha = true;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      // Em caso de sucesso, a tela raiz (AuthGate) troca esta tela sozinha.
      await AuthService.entrar(_email.text, _senha.text);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao acessar o banco de dados.';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: LogoMente(tamanho: 72)),
                  const SizedBox(height: 28),
                  const Text(
                    'Entrar',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Acesse sua conta para continuar',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 20),
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
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _entrar(),
                    decoration: campo(
                      'Senha',
                      icone: Icons.lock_outline,
                      sufixo: IconButton(
                        icon: Icon(_ocultarSenha ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _ocultarSenha = !_ocultarSenha),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Informe a senha.' : null,
                  ),
                  if (_erro != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _erro!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _carregando ? null : _entrar,
                      child: _carregando
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _carregando
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CadastroScreen()),
                              ),
                      child: const Text('Criar uma conta'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'Contas de demonstração\n'
                      'Profissional: helena@mentesaudavel.app / mente123\n'
                      'Paciente: carlos@email.com / 123456',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
