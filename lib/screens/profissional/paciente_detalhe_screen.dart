import 'package:flutter/material.dart';
import 'package:mente_saudavel/database/sessao_dao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/widgets/componentes.dart';
import 'package:mente_saudavel/widgets/sessao_sheet.dart';

/// Histórico de sessões de um paciente com o profissional logado.
class PacienteDetalheScreen extends StatefulWidget {
  final PacienteResumo paciente;

  const PacienteDetalheScreen({super.key, required this.paciente});

  @override
  State<PacienteDetalheScreen> createState() => _PacienteDetalheScreenState();
}

class _PacienteDetalheScreenState extends State<PacienteDetalheScreen> {
  final SessaoDao _dao = SessaoDao();

  List<Sessao> _sessoes = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final lista = await _dao.doProfissionalComPaciente(
        AuthService.atual.value!.id!,
        widget.paciente.id,
      );
      if (!mounted) return;
      setState(() {
        _sessoes = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, 'Erro ao carregar o histórico.', erro: true);
    }
  }

  Future<void> _abrir(Sessao sessao) async {
    final mudou = await mostrarSessaoSheet(context, sessao: sessao, comoProfissional: true);
    if (mudou) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.paciente;
    return Scaffold(
      appBar: AppBar(title: Text(p.nome)),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    const Icon(Icons.email_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p.email)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: StatCard(valor: '${p.totalSessoes}', rotulo: 'sessões')),
                    const SizedBox(width: 12),
                    Expanded(child: StatCard(valor: '${p.concluidas}', rotulo: 'concluídas')),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Histórico de sessões',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                if (_sessoes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Nenhuma sessão.', textAlign: TextAlign.center),
                  )
                else
                  ..._sessoes.map(
                    (s) => SessaoCard(
                      sessao: s,
                      comoProfissional: true,
                      onTap: () => _abrir(s),
                    ),
                  ),
              ],
            ),
    );
  }
}
