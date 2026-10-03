import 'package:flutter/material.dart';
import 'package:mente_saudavel/database/sessao_dao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/componentes.dart';
import 'package:mente_saudavel/widgets/sessao_sheet.dart';

/// Agenda do profissional, dia a dia.
class AgendaTab extends StatefulWidget {
  const AgendaTab({super.key});

  @override
  State<AgendaTab> createState() => _AgendaTabState();
}

class _AgendaTabState extends State<AgendaTab> {
  final SessaoDao _dao = SessaoDao();

  DateTime _dia = somenteData(DateTime.now());
  List<Sessao> _sessoes = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final lista = await _dao.doProfissionalNoDia(AuthService.atual.value!.id!, _dia);
      if (!mounted) return;
      setState(() {
        _sessoes = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, 'Erro ao carregar a agenda.', erro: true);
    }
  }

  void _mudarDia(int dias) {
    setState(() => _dia = DateTime(_dia.year, _dia.month, _dia.day + dias));
    _carregar();
  }

  Future<void> _escolherDia() async {
    final escolhido = await showDatePicker(
      context: context,
      initialDate: _dia,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (escolhido == null || !mounted) return;
    setState(() => _dia = somenteData(escolhido));
    _carregar();
  }

  Future<void> _abrir(Sessao sessao) async {
    final mudou = await mostrarSessaoSheet(context, sessao: sessao, comoProfissional: true);
    if (mudou) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final ehHoje = mesmoDia(_dia, DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          if (!ehHoje)
            TextButton(
              onPressed: () {
                setState(() => _dia = somenteData(DateTime.now()));
                _carregar();
              },
              child: const Text('Hoje'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Dia anterior',
                  onPressed: () => _mudarDia(-1),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _escolherDia,
                    child: Text(
                      '${formatarDataExtenso(_dia)} · ${formatarDataCurta(_dia)}',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Próximo dia',
                  onPressed: () => _mudarDia(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _sessoes.isEmpty
                    ? const Center(child: Text('Nenhuma sessão neste dia.'))
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _sessoes.length,
                          itemBuilder: (context, i) {
                            final s = _sessoes[i];
                            return SessaoCard(
                              sessao: s,
                              comoProfissional: true,
                              mostrarData: false,
                              onTap: () => _abrir(s),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
