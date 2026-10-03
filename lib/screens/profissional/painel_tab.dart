import 'package:flutter/material.dart';
import 'package:mente_saudavel/database/sessao_dao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/widgets/componentes.dart';
import 'package:mente_saudavel/widgets/sessao_sheet.dart';

/// Painel do profissional. Todos os números vêm de consultas ao SQLite.
class PainelTab extends StatefulWidget {
  final VoidCallback onVerAgenda;

  const PainelTab({super.key, required this.onVerAgenda});

  @override
  State<PainelTab> createState() => _PainelTabState();
}

class _PainelTabState extends State<PainelTab> {
  final SessaoDao _dao = SessaoDao();

  int _atendimentosHoje = 0;
  int _pacientesAtivos = 0;
  List<Sessao> _agendaHoje = [];
  bool _carregando = true;
  String? _erro;

  Usuario get _usuario => AuthService.atual.value!;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final id = _usuario.id!;
      final atendimentos = await _dao.atendimentosHoje(id);
      final pacientes = await _dao.pacientesAtivos(id);
      final agenda = await _dao.doProfissionalNoDia(id, DateTime.now(), incluirCanceladas: false);
      if (!mounted) return;
      setState(() {
        _atendimentosHoje = atendimentos;
        _pacientesAtivos = pacientes;
        _agendaHoje = agenda;
        _carregando = false;
        _erro = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Erro ao carregar o painel.';
      });
    }
  }

  Future<void> _abrir(Sessao sessao) async {
    final mudou = await mostrarSessaoSheet(context, sessao: sessao, comoProfissional: true);
    if (mudou) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Dr(a). ${_usuario.nome}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text('Painel do Profissional', style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 16),
              if (_carregando)
                const Center(
                  child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
                )
              else if (_erro != null)
                Text(_erro!, style: TextStyle(color: Colors.red.shade700))
              else ...[
                Row(
                  children: [
                    Expanded(child: StatCard(valor: '$_atendimentosHoje', rotulo: 'atendimentos hoje')),
                    const SizedBox(width: 12),
                    Expanded(child: StatCard(valor: '$_pacientesAtivos', rotulo: 'pacientes ativos')),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Agenda de Hoje',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(onPressed: widget.onVerAgenda, child: const Text('Ver agenda')),
                  ],
                ),
                if (_agendaHoje.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Nenhum atendimento hoje.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  )
                else
                  ..._agendaHoje.map(
                    (s) => SessaoCard(
                      sessao: s,
                      comoProfissional: true,
                      mostrarData: false,
                      onTap: () => _abrir(s),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
