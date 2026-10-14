import 'package:flutter/material.dart';
import 'package:crud_jsonplaceholder/models/post.dart';
import 'package:crud_jsonplaceholder/screens/post_detail_screen.dart';
import 'package:crud_jsonplaceholder/screens/post_form_screen.dart';
import 'package:crud_jsonplaceholder/services/post_service.dart';

/// Tela principal: LISTA os posts (Read) e leva às telas de criar, editar e excluir.
///
/// A API não grava nada de verdade, então esta tela mantém a lista em memória e a
/// atualiza depois de cada operação — assim o CRUD "funciona" visualmente.
class PostsScreen extends StatefulWidget {
  final PostService service;

  const PostsScreen({super.key, required this.service});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

enum _Acao { editar, excluir }

class _PostsScreenState extends State<PostsScreen> {
  List<Post> _posts = [];
  bool _carregando = true;
  String? _erro;
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await widget.service.listar();
      if (!mounted) return;
      setState(() {
        _posts = lista;
        _carregando = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _carregando = false;
      });
    }
  }

  void _aviso(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(texto), backgroundColor: erro ? Colors.red.shade700 : null),
      );
  }

  /// A API devolve sempre id 101 ao criar; se já existir na lista, gera o próximo id local.
  int _proximoIdLivre(int? sugerido) {
    final usados = _posts.map((p) => p.id).whereType<int>().toSet();
    if (sugerido != null && !usados.contains(sugerido)) return sugerido;
    final maior = usados.isEmpty ? 0 : usados.reduce((a, b) => a > b ? a : b);
    return maior + 1;
  }

  // ------------------------------------------------------------ CREATE
  Future<void> _novo() async {
    final criado = await Navigator.push<Post>(
      context,
      MaterialPageRoute(builder: (_) => PostFormScreen(service: widget.service)),
    );
    if (criado == null || !mounted) return;
    setState(() => _posts = [criado.copyWith(id: _proximoIdLivre(criado.id)), ..._posts]);
    _aviso('Post criado (a API simula: nada é gravado no servidor).');
  }

  // ------------------------------------------------------------ UPDATE
  Future<void> _editar(Post post) async {
    final editado = await Navigator.push<Post>(
      context,
      MaterialPageRoute(builder: (_) => PostFormScreen(service: widget.service, post: post)),
    );
    if (editado == null || !mounted) return;
    setState(() => _posts = _posts.map((p) => p.id == post.id ? editado.copyWith(id: post.id) : p).toList());
    _aviso('Post atualizado (a API simula: nada é gravado no servidor).');
  }

  // ------------------------------------------------------------ DELETE
  Future<void> _excluir(Post post) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir post'),
        content: Text('Deseja excluir "${post.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('confirmar-exclusao'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;
    try {
      await widget.service.excluir(post.id!);
      if (!mounted) return;
      setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
      _aviso('Post excluído (a API simula: nada é apagado no servidor).');
    } on ApiException catch (e) {
      if (!mounted) return;
      _aviso(e.mensagem, erro: true);
    }
  }

  // -------------------------------------------------------------- READ
  Future<void> _abrir(Post post) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => PostDetailScreen(service: widget.service, post: post)),
    );
  }

  List<Post> get _filtrados {
    final termo = _busca.trim().toLowerCase();
    if (termo.isEmpty) return _posts;
    return _posts.where((p) => p.title.toLowerCase().contains(termo) || p.body.toLowerCase().contains(termo)).toList();
  }

  Widget _corpo() {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 56),
              const SizedBox(height: 12),
              Text(_erro!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _carregar, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
    }
    final lista = _filtrados;
    if (lista.isEmpty) return const Center(child: Text('Nenhum post encontrado.'));
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: lista.length,
        itemBuilder: (context, i) {
          final post = lista[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              onTap: () => _abrir(post),
              leading: CircleAvatar(child: Text('${post.id}')),
              title: Text(post.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(post.body.replaceAll('\n', ' '), maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: PopupMenuButton<_Acao>(
                key: Key('menu-${post.id}'),
                tooltip: 'Ações',
                onSelected: (acao) => acao == _Acao.editar ? _editar(post) : _excluir(post),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _Acao.editar, child: Text('Editar')),
                  PopupMenuItem(value: _Acao.excluir, child: Text('Excluir')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Posts (JSONPlaceholder)'),
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Recarregar da API'),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _busca = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por título ou texto',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: _corpo()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('novo-post'),
        onPressed: _novo,
        icon: const Icon(Icons.add),
        label: const Text('Novo post'),
      ),
    );
  }
}
