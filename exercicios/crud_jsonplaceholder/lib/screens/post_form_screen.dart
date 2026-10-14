import 'package:flutter/material.dart';
import 'package:crud_jsonplaceholder/models/post.dart';
import 'package:crud_jsonplaceholder/services/post_service.dart';

/// Formulário usado para CRIAR (post == null) e para EDITAR (post != null).
/// Ao salvar, chama a API e devolve o Post resultante para a tela anterior.
class PostFormScreen extends StatefulWidget {
  final PostService service;
  final Post? post;

  const PostFormScreen({super.key, required this.service, this.post});

  @override
  State<PostFormScreen> createState() => _PostFormScreenState();
}

class _PostFormScreenState extends State<PostFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titulo = TextEditingController(text: widget.post?.title ?? '');
  late final TextEditingController _corpo = TextEditingController(text: widget.post?.body ?? '');
  bool _salvando = false;

  bool get _editando => widget.post != null;

  @override
  void dispose() {
    _titulo.dispose();
    _corpo.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      final dados = Post(
        id: widget.post?.id,
        userId: widget.post?.userId ?? 1,
        title: _titulo.text.trim(),
        body: _corpo.text.trim(),
      );
      final resultado = _editando ? await widget.service.atualizar(dados) : await widget.service.criar(dados);
      if (!mounted) return;
      Navigator.pop(context, resultado);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensagem), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar post #${widget.post!.id}' : 'Novo post')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('titulo'),
              controller: _titulo,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Informe o título.';
                if (t.length < 3) return 'O título precisa ter ao menos 3 caracteres.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('corpo'),
              controller: _corpo,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Texto', alignLabelWithHint: true, border: OutlineInputBorder()),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o texto do post.' : null,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                key: const Key('salvar'),
                onPressed: _salvando ? null : _salvar,
                icon: _salvando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_salvando ? 'Salvando...' : (_editando ? 'Salvar alterações' : 'Criar post')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
