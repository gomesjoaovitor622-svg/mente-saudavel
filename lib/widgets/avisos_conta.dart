import 'package:flutter/material.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Avisos no topo da tela inicial: "confirme seu e-mail" (paciente e profissional) e
/// "cadastro em análise" (profissional ainda não aprovado). Some sozinho quando não há nada a avisar.
class AvisosConta extends StatelessWidget {
  const AvisosConta({super.key, required this.usuario});

  final Usuario? usuario;

  @override
  Widget build(BuildContext context) {
    final u = usuario;
    if (u == null) return const SizedBox.shrink();
    final avisos = <Widget>[
      if (u.isProfissional && !u.verificado) const _AvisoEmAnalise(),
      if (u.precisaVerificarEmail) const _AvisoEmail(),
    ];
    if (avisos.isEmpty) return const SizedBox.shrink();
    return Column(children: [...avisos, const SizedBox(height: 12)]);
  }
}

class _Caixa extends StatelessWidget {
  const _Caixa({required this.icone, required this.titulo, required this.texto, this.acao});

  final IconData icone;
  final String titulo;
  final String texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: Colors.amber.shade900),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(texto, style: TextStyle(color: Colors.grey.shade800)),
                if (acao != null) ...[const SizedBox(height: 8), acao!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoEmAnalise extends StatelessWidget {
  const _AvisoEmAnalise();

  @override
  Widget build(BuildContext context) {
    return _Caixa(
      icone: Icons.hourglass_top,
      titulo: 'Cadastro em análise',
      texto: 'Estamos conferindo o seu registro profissional (CRP). Até a aprovação, você ainda não aparece '
          'na busca nem recebe agendamentos.',
      acao: TextButton(
        onPressed: () async {
          try {
            await AuthService.recarregarUsuario();
          } on AppException catch (e) {
            if (context.mounted) mostrarMensagem(context, e.mensagem, erro: true);
          }
        },
        child: const Text('Já fui aprovado? Atualizar'),
      ),
    );
  }
}

class _AvisoEmail extends StatelessWidget {
  const _AvisoEmail();

  @override
  Widget build(BuildContext context) {
    return _Caixa(
      icone: Icons.mark_email_unread_outlined,
      titulo: 'Confirme seu e-mail',
      texto: 'Enviamos um código de 6 dígitos para o seu e-mail. Sem a confirmação não é possível agendar sessões.',
      acao: TextButton(
        onPressed: () => showDialog<void>(context: context, builder: (_) => const _DialogoCodigo()),
        child: const Text('Digitar código'),
      ),
    );
  }
}

class _DialogoCodigo extends StatefulWidget {
  const _DialogoCodigo();

  @override
  State<_DialogoCodigo> createState() => _DialogoCodigoState();
}

class _DialogoCodigoState extends State<_DialogoCodigo> {
  final _codigo = TextEditingController();
  bool _carregando = false;
  String? _erro;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_codigo.text.trim())) {
      setState(() => _erro = 'Digite os 6 números.');
      return;
    }
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      await AuthService.verificarEmail(_codigo.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      mostrarMensagem(context, 'E-mail confirmado!');
    } on AppException catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _reenviar() async {
    try {
      await AuthService.reenviarCodigoEmail();
      if (mounted) mostrarMensagem(context, 'Enviamos um novo código.');
    } on AppException catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirmar e-mail'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _codigo,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: campo('Código de 6 dígitos', icone: Icons.pin_outlined),
          ),
          if (_erro != null) Text(_erro!, style: TextStyle(color: Colors.red.shade700)),
        ],
      ),
      actions: [
        TextButton(onPressed: _carregando ? null : _reenviar, child: const Text('Reenviar código')),
        FilledButton(onPressed: _carregando ? null : _confirmar, child: const Text('Confirmar')),
      ],
    );
  }
}
