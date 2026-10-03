import 'package:flutter/material.dart';
import 'package:mente_saudavel/database/sessao_dao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/screens/paciente/agendar_sessao_screen.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/componentes.dart';
import 'package:mente_saudavel/widgets/sessao_sheet.dart';

const List<String> _frases = [
  'Pequenos passos todos os dias levam a grandes mudanças.',
  'Cuidar da mente é um ato de coragem.',
  'Você não precisa ter tudo resolvido para pedir ajuda.',
  'Respire fundo: um momento de cada vez.',
  'Sentir é humano. Falar sobre isso ajuda.',
  'Descansar também faz parte do caminho.',
  'Seu bem-estar importa, hoje e sempre.',
];

class PacienteInicioTab extends StatefulWidget {
  final VoidCallback onVerSessoes;

  const PacienteInicioTab({super.key, required this.onVerSessoes});

  @override
  State<PacienteInicioTab> createState() => _PacienteInicioTabState();
}

class _PacienteInicioTabState extends State<PacienteInicioTab> {
  final SessaoDao _dao = SessaoDao();

  Sessao? _proxima;
  int _concluidas = 0;
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
      final proxima = await _dao.proximaDoPaciente(_usuario.id!);
      final concluidas = await _dao.concluidasDoPaciente(_usuario.id!);
      if (!mounted) return;
      setState(() {
        _proxima = proxima;
        _concluidas = concluidas;
        _carregando = false;
        _erro = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Erro ao carregar seus dados.';
      });
    }
  }

  Future<void> _agendar() async {
    final agendou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AgendarSessaoScreen()),
    );
    if (agendou == true) _carregar();
  }

  Future<void> _abrirProxima(Sessao sessao) async {
    final mudou = await mostrarSessaoSheet(context, sessao: sessao, comoProfissional: false);
    if (mudou) _carregar();
  }

  Widget _cartaoProxima() {
    final s = _proxima;
    if (s == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('Você não tem sessões agendadas.'),
              const SizedBox(height: 10),
              FilledButton(onPressed: _agendar, child: const Text('Agendar agora')),
            ],
          ),
        ),
      );
    }

    final registro = s.profissionalRegistro ?? '';
    return Card(
      child: InkWell(
        onTap: () => _abrirProxima(s),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sua próxima sessão', style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 10),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.green.shade100,
                    child: const Icon(Icons.person, color: verdeMarca),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.profissionalNome ?? 'Profissional',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          registro.isEmpty ? 'Psicólogo(a)' : 'Psicólogo(a) CRP $registro',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.schedule, size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Text(formatarDataHora(s.dataHora)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    s.modalidade == Modalidade.online ? Icons.videocam_outlined : Icons.place_outlined,
                    size: 18,
                    color: Colors.grey.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(s.modalidade),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final agora = DateTime.now();
    final diaDoAno = diasEntre(DateTime(agora.year, 1, 1), agora);
    final frase = _frases[diaDoAno % _frases.length];
    final dias = _proxima == null ? '-' : '${diasEntre(agora, _proxima!.dataHora)}';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Olá, ${primeiroNome(_usuario.nome)}!',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (_carregando)
                const Center(
                  child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
                )
              else if (_erro != null)
                Text(_erro!, style: TextStyle(color: Colors.red.shade700))
              else ...[
                _cartaoProxima(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: StatCard(valor: '$_concluidas', rotulo: 'sessões concluídas')),
                    const SizedBox(width: 12),
                    Expanded(child: StatCard(valor: dias, rotulo: 'dias até a próxima')),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Ações rápidas', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _agendar,
                        icon: const Icon(Icons.calendar_month),
                        label: const Text('Agendar sessão'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onVerSessoes,
                        icon: const Icon(Icons.history),
                        label: const Text('Minhas sessões'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.format_quote, color: verdeMarca),
                        const SizedBox(width: 10),
                        Expanded(child: Text(frase, style: const TextStyle(fontStyle: FontStyle.italic))),
                      ],
                    ),
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
