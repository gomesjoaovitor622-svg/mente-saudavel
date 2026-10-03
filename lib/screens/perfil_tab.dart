import 'package:flutter/material.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/api_service.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/validators.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Perfil do usuário logado (paciente ou profissional): editar, trocar
/// senha, sair e excluir conta. Tudo grava no SQLite.
class PerfilTab extends StatefulWidget {
  const PerfilTab({super.key});

  @override
  State<PerfilTab> createState() => _PerfilTabState();
}

class _PerfilTabState extends State<PerfilTab> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _registro;
  late final TextEditingController _especialidade;
  late final TextEditingController _endereco;
  final _cep = TextEditingController();

  bool _salvando = false;
  bool _buscandoCep = false;

  Usuario get _usuario => AuthService.atual.value!;

  @override
  void initState() {
    super.initState();
    final u = _usuario;
    _nome = TextEditingController(text: u.nome);
    _registro = TextEditingController(text: u.registro ?? '');
    _especialidade = TextEditingController(text: u.especialidade ?? '');
    _endereco = TextEditingController(text: u.endereco ?? '');
  }

  @override
  void dispose() {
    _nome.dispose();
    _registro.dispose();
    _especialidade.dispose();
    _endereco.dispose();
    _cep.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      final u = _usuario;
      final atualizado = u.copyWith(
        nome: _nome.text.trim(),
        registro: u.isProfissional ? _registro.text.trim() : null,
        especialidade: u.isProfissional ? _especialidade.text.trim() : null,
        endereco: u.isProfissional ? _endereco.text.trim() : null,
      );
      await AuthService.atualizarPerfil(atualizado);
      if (!mounted) return;
      setState(() => _salvando = false);
      mostrarMensagem(context, 'Perfil atualizado com sucesso!');
    } catch (_) {
      if (!mounted) return;
      setState(() => _salvando = false);
      mostrarMensagem(context, 'Erro ao salvar o perfil.', erro: true);
    }
  }

  // API ViaCEP: preenche o endereço do consultório a partir do CEP.
  Future<void> _buscarCep() async {
    setState(() => _buscandoCep = true);
    try {
      final endereco = await ApiService.buscarCep(_cep.text);
      if (!mounted) return;
      setState(() {
        _endereco.text = endereco;
        _buscandoCep = false;
      });
      mostrarMensagem(context, 'Endereço preenchido. Complete com número e complemento.');
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _buscandoCep = false);
      mostrarMensagem(context, e.mensagem, erro: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _buscandoCep = false);
      mostrarMensagem(context, 'Erro ao consultar o CEP.', erro: true);
    }
  }

  Future<void> _alterarSenha() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _AlterarSenhaDialog(),
    );
    if (ok == true && mounted) {
      mostrarMensagem(context, 'Senha alterada com sucesso!');
    }
  }

  Future<void> _sair() async {
    final ok = await confirmar(
      context,
      titulo: 'Sair',
      mensagem: 'Deseja sair da sua conta?',
      textoConfirmar: 'Sair',
    );
    if (!ok) return;
    await AuthService.sair();
  }

  Future<void> _excluirConta() async {
    final ok = await confirmar(
      context,
      titulo: 'Excluir conta',
      mensagem: 'Isso apaga sua conta e todos os dados ligados a ela '
          '(sessões e diário de humor). Essa ação não pode ser desfeita.',
      textoConfirmar: 'Excluir conta',
    );
    if (!ok || !mounted) return;
    try {
      await AuthService.excluirConta();
    } catch (_) {
      if (!mounted) return;
      mostrarMensagem(context, 'Erro ao excluir a conta.', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _usuario;
    final inicial = u.nome.trim().isNotEmpty ? u.nome.trim()[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: Colors.green.shade100,
                child: Text(inicial, style: const TextStyle(fontSize: 30, color: verdeMarca)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              u.email,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            Center(child: Chip(label: Text(u.isProfissional ? 'Profissional' : 'Paciente'))),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nome,
                    textCapitalization: TextCapitalization.words,
                    decoration: campo('Nome', icone: Icons.person_outline),
                    validator: validarNome,
                  ),
                  if (u.isProfissional) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _registro,
                      decoration: campo('Registro profissional (CRP)', icone: Icons.badge_outlined),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o CRP.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _especialidade,
                      decoration: campo('Especialidade', icone: Icons.psychology_outlined),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Informe a especialidade.' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _cep,
                            keyboardType: TextInputType.number,
                            decoration: campo('CEP do consultório', icone: Icons.pin_drop_outlined),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _buscandoCep ? null : _buscarCep,
                          child: _buscandoCep
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Buscar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _endereco,
                      maxLines: 2,
                      decoration: campo(
                        'Endereço do consultório',
                        icone: Icons.map_outlined,
                        dica: 'Usado nas sessões presenciais',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon: const Icon(Icons.save),
                      label: Text(_salvando ? 'Salvando...' : 'Salvar alterações'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _alterarSenha,
              icon: const Icon(Icons.lock_reset),
              label: const Text('Alterar senha'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _sair,
              icon: const Icon(Icons.logout),
              label: const Text('Sair'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _excluirConta,
              icon: Icon(Icons.delete_forever, color: Colors.red.shade700),
              label: Text('Excluir minha conta', style: TextStyle(color: Colors.red.shade700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlterarSenhaDialog extends StatefulWidget {
  const _AlterarSenhaDialog();

  @override
  State<_AlterarSenhaDialog> createState() => _AlterarSenhaDialogState();
}

class _AlterarSenhaDialogState extends State<_AlterarSenhaDialog> {
  final _atual = TextEditingController();
  final _nova = TextEditingController();
  String? _erro;
  bool _salvando = false;

  @override
  void dispose() {
    _atual.dispose();
    _nova.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final erroSenha = validarSenha(_nova.text);
    if (erroSenha != null) {
      setState(() => _erro = erroSenha);
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await AuthService.alterarSenha(_atual.text, _nova.text);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _salvando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao alterar a senha.';
        _salvando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Alterar senha'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _atual,
            obscureText: true,
            decoration: campo('Senha atual'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nova,
            obscureText: true,
            decoration: campo('Nova senha'),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 10),
            Text(_erro!, style: TextStyle(color: Colors.red.shade700)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
