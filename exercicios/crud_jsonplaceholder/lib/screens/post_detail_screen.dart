import 'package:flutter/material.dart';
import 'package:crud_jsonplaceholder/models/post.dart';
import 'package:crud_jsonplaceholder/services/post_service.dart';

/// Detalhe de um post (Read): busca o post na API (GET /posts/{id}) e seus comentários.
/// Posts criados aqui (id fora de 1..100) não existem na API; mostramos os dados locais.
class PostDetailScreen extends StatefulWidget {
  final PostService service;
  final Post post;

  const PostDetailScreen({super.key, required this.service, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Future<List<Comentario>> _comentarios;

  bool get _existeNaApi => (widget.post.id ?? 0) >= 1 && (widget.post.id ?? 0) <= 100;

  @override
  void initState() {
    super.initState();
    _comentarios = _existeNaApi ? widget.service.comentarios(widget.post.id!) : Future.value(const <Comentario>[]);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return Scaffold(
      appBar: AppBar(title: Text('Post #${post.id}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(post.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Autor (userId): ${post.userId}', style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          Text(post.body),
          const Divider(height: 32),
          Text('Comentários', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<List<Comentario>>(
            future: _comentarios,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return Text('Não foi possível carregar os comentários.', style: TextStyle(color: Colors.red.shade700));
              }
              final lista = snap.data ?? const <Comentario>[];
              if (lista.isEmpty) return const Text('Sem comentários.');
              return Column(
                children: lista
                    .map(
                      (c) => Card(
                        child: ListTile(
                          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${c.email}\n${c.body}'),
                          isThreeLine: true,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
