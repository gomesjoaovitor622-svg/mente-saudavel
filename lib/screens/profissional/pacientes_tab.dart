import 'package:flutter/material.dart';
import 'package:mente_saudavel/database/sessao_dao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/screens/profissional/paciente_detalhe_screen.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Pacientes que já têm (ou tiveram) sessão com o profissional.
class PacientesTab extends StatefulWidget {
  const PacientesTab({super.key});

  @override
  State<PacientesTab> createState() => _PacientesTabState();
}

class _PacientesTabState extends State<PacientesTab> {
  final SessaoDao _dao = SessaoDao();
  final TextEditingController _busca = TextEditingController();

  List<PacienteResumo> _pacientes = [];
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
      final lista = await _dao.pacientesDoProfissional(AuthService.atual.value!.id!);
      if (!mounted) return;
      setState(() {
        _pacientes = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, 'Erro ao carregar os pacientes.', erro: true);
    }
  }

  List<PacienteResumo> get _filtrados {
    final termo = _busca.text.trim().toLowerCase();
    if (termo.isEmpty) return _pacientes;
    return _pacientes
        .where((p) => p.nome.toLowerCase().contains(termo) || p.email.toLowerCase().contains(termo))
        .toList();
  }

  Future<void> _abrir(PacienteResumo paciente) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => PacienteDetalheScreen(paciente: paciente)),
    );
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      appBar: AppBar(title: const Text('Pacientes')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _busca,
                    onChanged: (_) => setState(() {}),
                    decoration: campo(
                      'Buscar paciente',
                      icone: Icons.search,
                      sufixo: _busca.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _busca.clear();
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: lista.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _pacientes.isEmpty
                                  ? 'Você ainda não tem pacientes.\nEles aparecem aqui quando agendarem uma sessão com você.'
                                  : 'Nenhum paciente encontrado.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _carregar,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: lista.length,
                            itemBuilder: (context, i) {
                              final p = lista[i];
                              final proxima = p.proxima == null
                                  ? 'Sem sessão futura'
                                  : 'Próxima: ${formatarDataHora(p.proxima!)}';
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.green.shade100,
                                    child: Text(
                                      p.nome.isNotEmpty ? p.nome[0].toUpperCase() : '?',
                                      style: const TextStyle(color: verdeMarca),
                                    ),
                                  ),
                                  title: Text(p.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    '${p.concluidas} concluída(s) de ${p.totalSessoes}\n$proxima',
                                  ),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _abrir(p),
                                ),
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
