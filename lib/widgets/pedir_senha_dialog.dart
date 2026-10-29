import 'package:flutter/material.dart';

/// Pede a senha para confirmar uma ação sem volta (ex.: anonimizar a conta).
/// Devolve a senha digitada, ou null se a pessoa cancelar.
Future<String?> pedirSenha(
  BuildContext context, {
  required String titulo,
  required String mensagem,
  required String textoConfirmar,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PedirSenhaDialog(titulo: titulo, mensagem: mensagem, textoConfirmar: textoConfirmar),
  );
}

class _PedirSenhaDialog extends StatefulWidget {
  const _PedirSenhaDialog({required this.titulo, required this.mensagem, required this.textoConfirmar});

  final String titulo;
  final String mensagem;
  final String textoConfirmar;

  @override
  State<_PedirSenhaDialog> createState() => _PedirSenhaDialogState();
}

class _PedirSenhaDialogState extends State<_PedirSenhaDialog> {
  final _senha = TextEditingController();

  @override
  void dispose() {
    _senha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.mensagem),
          const SizedBox(height: 12),
          TextField(
            key: const Key('senha-confirmacao'),
            controller: _senha,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Sua senha', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _senha.text.isEmpty ? null : () => Navigator.pop(context, _senha.text),
          child: Text(widget.textoConfirmar),
        ),
      ],
    );
  }
}
