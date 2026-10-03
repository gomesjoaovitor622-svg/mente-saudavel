import 'package:flutter/material.dart';
import 'package:mente_saudavel/database/humor_dao.dart';
import 'package:mente_saudavel/models/humor.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Diário de humor: o paciente registra como se sente (1 a 5) e uma nota.
class HumorTab extends StatefulWidget {
  const HumorTab({super.key});

  @override
  State<HumorTab> createState() => _HumorTabState();
}

class _HumorTabState extends State<HumorTab> {
  final HumorDao _dao = HumorDao();
  final TextEditingController _nota = TextEditingController();

  List<HumorRegistro> _registros = [];
  double? _media;
  int? _nivel;
  bool _carregando = true;
  bool _salvando = false;

  int get _usuarioId => AuthService.atual.value!.id!;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final lista = await _dao.listar(_usuarioId);
      final media = await _dao.mediaUltimosDias(_usuarioId, 7);
      if (!mounted) return;
      setState(() {
        _registros = lista;
        _media = media;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, 'Erro ao carregar o diário de humor.', erro: true);
    }
  }

  Future<void> _salvar() async {
    final nivel = _nivel;
    if (nivel == null) {
      mostrarMensagem(context, 'Escolha como você está se sentindo.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      await _dao.inserir(
        HumorRegistro(
          usuarioId: _usuarioId,
          nivel: nivel,
          nota: _nota.text.trim(),
          dataHora: DateTime.now(),
        ),
      );
      if (!mounted) return;
      _nota.clear();
      setState(() {
        _nivel = null;
        _salvando = false;
      });
      mostrarMensagem(context, 'Humor registrado!');
      await _carregar();
    } catch (_) {
      if (!mounted) return;
      setState(() => _salvando = false);
      mostrarMensagem(context, 'Erro ao registrar o humor.', erro: true);
    }
  }

  Future<void> _excluir(HumorRegistro registro) async {
    final ok = await confirmar(
      context,
      titulo: 'Excluir registro',
      mensagem: 'Deseja excluir este registro do diário?',
      textoConfirmar: 'Excluir',
    );
    if (!ok || !mounted) return;
    try {
      await _dao.excluir(registro.id!);
      if (!mounted) return;
      mostrarMensagem(context, 'Registro excluído.');
      await _carregar();
    } catch (_) {
      if (!mounted) return;
      mostrarMensagem(context, 'Erro ao excluir o registro.', erro: true);
    }
  }

  Widget _seletorHumor() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(5, (i) {
        final nivel = i + 1;
        final selecionado = _nivel == nivel;
        return InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: () => setState(() => _nivel = nivel),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selecionado ? Colors.green.shade100 : Colors.transparent,
              border: Border.all(
                color: selecionado ? verdeMarca : Colors.transparent,
                width: 2,
              ),
            ),
            child: Text(HumorRegistro.emojis[i], style: const TextStyle(fontSize: 32)),
          ),
        );
      }),
    );
  }

  Widget _resumoSemana() {
    final media = _media;
    if (media == null) return const SizedBox.shrink();
    final arredondado = media.round();
    final indice = (arredondado < 1 ? 1 : (arredondado > 5 ? 5 : arredondado)) - 1;
    final emoji = HumorRegistro.emojis[indice];
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Média dos últimos 7 dias: ${media.toStringAsFixed(1)} de 5',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diário de humor')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Como você está se sentindo agora?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _seletorHumor(),
                if (_nivel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      HumorRegistro.rotulos[_nivel! - 1],
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nota,
                  maxLines: 2,
                  decoration: campo('Quer anotar algo? (opcional)'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: const Icon(Icons.add),
                  label: Text(_salvando ? 'Salvando...' : 'Registrar humor'),
                ),
                const SizedBox(height: 16),
                _resumoSemana(),
                const SizedBox(height: 8),
                const Text('Histórico', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (_registros.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Nenhum registro ainda.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  )
                else
                  ..._registros.map(
                    (r) => Card(
                      child: ListTile(
                        leading: Text(r.emoji, style: const TextStyle(fontSize: 28)),
                        title: Text(r.rotulo),
                        subtitle: Text(
                          r.nota.isEmpty
                              ? formatarDataHora(r.dataHora)
                              : '${formatarDataHora(r.dataHora)}\n${r.nota}',
                        ),
                        isThreeLine: r.nota.isNotEmpty,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Excluir',
                          onPressed: () => _excluir(r),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
