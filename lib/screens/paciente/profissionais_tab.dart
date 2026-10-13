import 'package:flutter/material.dart';
import 'package:mente_saudavel/database/avaliacao_dao.dart';
import 'package:mente_saudavel/models/avaliacao.dart';
import 'package:mente_saudavel/screens/paciente/agendar_sessao_screen.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/avaliacao_widgets.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Busca de profissionais por nome ou especialidade, com nota média.
class ProfissionaisTab extends StatefulWidget {
  const ProfissionaisTab({super.key});

  @override
  State<ProfissionaisTab> createState() => _ProfissionaisTabState();
}

class _ProfissionaisTabState extends State<ProfissionaisTab> {
  final AvaliacaoDao _dao = AvaliacaoDao();
  final TextEditingController _busca = TextEditingController();

  List<ProfissionalResumo> _lista = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final lista = await _dao.buscarProfissionais(termo: _busca.text);
      if (!mounted) return;
      setState(() {
        _lista = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, 'Erro ao buscar profissionais.', erro: true);
    }
  }

  Future<void> _abrir(ProfissionalResumo p) async {
    final agendar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetalheProfissional(profissional: p),
    );
    if (agendar == true && mounted) {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => AgendarSessaoScreen(profissionalId: p.id)),
      );
      if (mounted) _carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profissionais')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _busca,
              textInputAction: TextInputAction.search,
              onChanged: (_) => _carregar(),
              decoration: campo('Buscar por nome ou especialidade', icone: Icons.search),
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _lista.isEmpty
                    ? const Center(child: Text('Nenhum profissional encontrado.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _lista.length,
                        itemBuilder: (context, i) {
                          final p = _lista[i];
                          return Card(
                            child: ListTile(
                              onTap: () => _abrir(p),
                              leading: const CircleAvatar(child: Icon(Icons.psychology_alt)),
                              title: Text(p.nome),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if ((p.especialidade ?? '').isNotEmpty) Text(p.especialidade!),
                                  const SizedBox(height: 2),
                                  p.media == null
                                      ? Text('Sem avaliações ainda',
                                          style: TextStyle(color: Colors.grey.shade700))
                                      : Row(
                                          children: [
                                            Estrelas(nota: p.media!, tamanho: 16),
                                            const SizedBox(width: 6),
                                            Text('${p.media!.toStringAsFixed(1)} (${p.totalAvaliacoes})'),
                                          ],
                                        ),
                                ],
                              ),
                              isThreeLine: (p.especialidade ?? '').isNotEmpty,
                              trailing: const Icon(Icons.chevron_right),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _DetalheProfissional extends StatelessWidget {
  final ProfissionalResumo profissional;

  const _DetalheProfissional({required this.profissional});

  @override
  Widget build(BuildContext context) {
    final p = profissional;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: FutureBuilder<List<Avaliacao>>(
          future: AvaliacaoDao().doProfissional(p.id),
          builder: (context, snap) {
            final avaliacoes = snap.data ?? const <Avaliacao>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(p.nome, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                if ((p.registro ?? '').isNotEmpty)
                  Text('CRP ${p.registro}', style: TextStyle(color: Colors.grey.shade700)),
                if ((p.especialidade ?? '').isNotEmpty) Text(p.especialidade!),
                if ((p.endereco ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.place_outlined, size: 18, color: Colors.grey.shade700),
                        const SizedBox(width: 6),
                        Expanded(child: Text(p.endereco!)),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('Avaliações', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (avaliacoes.isEmpty)
                  Text('Ainda sem avaliações.', style: TextStyle(color: Colors.grey.shade700))
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView(
                      shrinkWrap: true,
                      children: avaliacoes
                          .map(
                            (a) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Row(
                                children: [
                                  Estrelas(nota: a.nota.toDouble(), tamanho: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      a.pacienteNome?.split(' ').first ?? 'Paciente',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                a.comentario.isEmpty
                                    ? formatarDataCurta(a.criadoEm)
                                    : '${formatarDataCurta(a.criadoEm)} · ${a.comentario}',
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.event_available),
                  label: const Text('Agendar sessão'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
