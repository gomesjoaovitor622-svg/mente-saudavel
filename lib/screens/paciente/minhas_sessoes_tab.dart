import 'package:flutter/material.dart';
import 'package:mente_saudavel/database/sessao_dao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/screens/paciente/agendar_sessao_screen.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/widgets/componentes.dart';
import 'package:mente_saudavel/widgets/sessao_sheet.dart';

class MinhasSessoesTab extends StatefulWidget {
  const MinhasSessoesTab({super.key});

  @override
  State<MinhasSessoesTab> createState() => _MinhasSessoesTabState();
}

class _MinhasSessoesTabState extends State<MinhasSessoesTab> {
  final SessaoDao _dao = SessaoDao();

  List<Sessao> _sessoes = [];
  String? _filtro; // null = todas
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final lista = await _dao.doPaciente(AuthService.atual.value!.id!, status: _filtro);
      if (!mounted) return;
      setState(() {
        _sessoes = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, 'Erro ao carregar as sessões.', erro: true);
    }
  }

  Future<void> _agendar() async {
    final agendou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AgendarSessaoScreen()),
    );
    if (agendou == true) _carregar();
  }

  Future<void> _abrir(Sessao sessao) async {
    final mudou = await mostrarSessaoSheet(context, sessao: sessao, comoProfissional: false);
    if (mudou) _carregar();
  }

  Widget _chip(String rotulo, String? valor) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(rotulo),
        selected: _filtro == valor,
        onSelected: (_) {
          setState(() => _filtro = valor);
          _carregar();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minhas sessões')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                _chip('Todas', null),
                _chip('Agendadas', StatusSessao.agendada),
                _chip('Concluídas', StatusSessao.concluida),
                _chip('Canceladas', StatusSessao.cancelada),
              ],
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _sessoes.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Nenhuma sessão encontrada.\nToque em + para agendar.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                          itemCount: _sessoes.length,
                          itemBuilder: (context, i) {
                            final s = _sessoes[i];
                            return SessaoCard(
                              sessao: s,
                              comoProfissional: false,
                              onTap: () => _abrir(s),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agendar,
        icon: const Icon(Icons.add),
        label: const Text('Agendar'),
      ),
    );
  }
}
