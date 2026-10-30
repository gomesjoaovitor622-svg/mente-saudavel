import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/presentation/providers/perfil_providers.dart';
import 'package:mente_saudavel/screens/termos_screen.dart';
import 'package:mente_saudavel/utils/build_flags.dart';
import 'package:mente_saudavel/services/api_service.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/utils/validators.dart';
import 'package:mente_saudavel/widgets/componentes.dart';
import 'package:mente_saudavel/widgets/pedir_senha_dialog.dart';

/// Perfil do usuário logado (paciente ou profissional): editar, trocar
/// senha, sair e excluir conta. Tudo grava no SQLite.
class PerfilTab extends ConsumerStatefulWidget {
  const PerfilTab({super.key});

  @override
  ConsumerState<PerfilTab> createState() => _PerfilTabState();
}

class _PerfilTabState extends ConsumerState<PerfilTab> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _registro;
  late final TextEditingController _especialidade;
  late final TextEditingController _endereco;
  late final TextEditingController _valor;
  final _cep = TextEditingController();

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
    final centavos = u.valorSessaoCentavos;
    _valor = TextEditingController(
      text: centavos == null ? '' : (centavos / 100).toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _nome.dispose();
    _registro.dispose();
    _especialidade.dispose();
    _endereco.dispose();
    _valor.dispose();
    _cep.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final u = _usuario;
      final atualizado = u.copyWith(
        nome: _nome.text.trim(),
        registro: u.isProfissional ? _registro.text.trim() : null,
        especialidade: u.isProfissional ? _especialidade.text.trim() : null,
        endereco: u.isProfissional ? _endereco.text.trim() : null,
        valorSessaoCentavos: (u.isProfissional && usaServidor) ? centavosDeTexto(_valor.text) : null,
      );
      // O "carregando" vive no provider (a tela só observa `perfilControllerProvider`).
      await ref.read(perfilControllerProvider.notifier).salvar(atualizado);
      if (!mounted) return;
      mostrarMensagem(context, 'Perfil atualizado com sucesso!');
    } catch (_) {
      if (!mounted) return;
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

  /// LGPD (portabilidade): mostra todos os dados da conta em JSON, com botão de copiar.
  Future<void> _exportarDados() async {
    try {
      final texto = await ref.read(perfilControllerProvider.notifier).exportarDados();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Meus dados'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(child: SelectableText(texto, style: const TextStyle(fontSize: 12))),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: texto));
                if (ctx.mounted) mostrarMensagem(ctx, 'Dados copiados.');
              },
              child: const Text('Copiar'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          ],
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      mostrarMensagem(context, e.mensagem, erro: true);
    } catch (_) {
      if (!mounted) return;
      mostrarMensagem(context, 'Não foi possível exportar os dados.', erro: true);
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
    await ref.read(perfilControllerProvider.notifier).sair();
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
      await ref.read(perfilControllerProvider.notifier).excluirConta();
    } catch (_) {
      if (!mounted) return;
      mostrarMensagem(context, 'Erro ao excluir a conta.', erro: true);
    }
  }

  /// LGPD, direito à eliminação: anonimiza os dados do paciente e encerra a sessão.
  Future<void> _anonimizar() async {
    final senha = await pedirSenha(
      context,
      titulo: 'Direito ao esquecimento',
      mensagem: 'Seus dados pessoais serão anonimizados: nome e e-mail são apagados, o diário de humor e os '
          'comentários de avaliação são excluídos e as sessões futuras são canceladas. O histórico das sessões '
          'passadas fica sem identificar você (o profissional precisa guardá-lo por obrigação legal). '
          'Essa ação não pode ser desfeita. Digite sua senha para confirmar.',
      textoConfirmar: 'Anonimizar meus dados',
    );
    if (senha == null || !mounted) return;
    try {
      await ref.read(perfilControllerProvider.notifier).anonimizarConta(senha);
    } on AppException catch (e) {
      if (!mounted) return;
      mostrarMensagem(context, e.mensagem, erro: true);
    } catch (_) {
      if (!mounted) return;
      mostrarMensagem(context, 'Não foi possível anonimizar os dados.', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final salvando = ref.watch(perfilControllerProvider).isLoading;
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
                    if (usaServidor) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _valor,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: campo('Valor da sessão (R\$)', icone: Icons.payments_outlined, dica: 'Ex.: 150,00'),
                        validator: (v) => (v == null || v.trim().isEmpty || centavosDeTexto(v) != null)
                            ? null
                            : 'Valor inválido (use de 0 a 10000, ex.: 150,00).',
                      ),
                    ],
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
                      onPressed: salvando ? null : _salvar,
                      icon: const Icon(Icons.save),
                      label: Text(salvando ? 'Salvando...' : 'Salvar alterações'),
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
            if (usaServidor) ...[
              OutlinedButton.icon(
                onPressed: _exportarDados,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Exportar meus dados'),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _sair,
              icon: const Icon(Icons.logout),
              label: const Text('Sair'),
            ),
            const SizedBox(height: 8),
            const Divider(height: 32),
            Text('Privacidade e LGPD', style: Theme.of(context).textTheme.titleSmall),
            ListTile(
              key: const Key('abrir-termos'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: const Text('Termos de Uso'),
              onTap: () => abrirTermosDeUso(context),
            ),
            ListTile(
              key: const Key('abrir-politica'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Política de Privacidade'),
              onTap: () => abrirPoliticaDePrivacidade(context),
            ),
            if (!u.isProfissional)
              OutlinedButton.icon(
                key: const Key('botao-anonimizar'),
                onPressed: _anonimizar,
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Direito ao esquecimento (anonimizar meus dados)'),
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
