import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/paciente_providers.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/screens/paciente/agendar_sessao_screen.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/avisos_conta.dart';
import 'package:mente_saudavel/widgets/componentes.dart';
import 'package:mente_saudavel/widgets/medir_tela.dart';
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

/// Início do paciente. A tela só observa [inicioPacienteProvider] (carregando, erro e dados).
class PacienteInicioTab extends ConsumerWidget {
  final VoidCallback onVerSessoes;

  const PacienteInicioTab({super.key, required this.onVerSessoes});

  Future<void> _agendar(BuildContext context, WidgetRef ref) async {
    final agendou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AgendarSessaoScreen()),
    );
    if (agendou == true) invalidarDadosDoPaciente(ref);
  }

  Future<void> _abrirProxima(BuildContext context, WidgetRef ref, Sessao sessao) async {
    final mudou = await mostrarSessaoSheet(context, sessao: sessao, comoProfissional: false);
    if (mudou) invalidarDadosDoPaciente(ref);
  }

  Widget _cartaoProxima(BuildContext context, WidgetRef ref, Sessao? s) {
    if (s == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('Você não tem sessões agendadas.'),
              const SizedBox(height: 10),
              FilledButton(onPressed: () => _agendar(context, ref), child: const Text('Agendar agora')),
            ],
          ),
        ),
      );
    }

    final registro = s.profissionalRegistro ?? '';
    return Card(
      child: InkWell(
        onTap: () => _abrirProxima(context, ref, s),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(usuarioAtualProvider);
    final inicio = ref.watch(inicioPacienteProvider);
    final agora = DateTime.now();
    final diaDoAno = diasEntre(DateTime(agora.year, 1, 1), agora);
    final frase = _frases[diaDoAno % _frases.length];

    return MedirTela(
      nome: 'paciente_inicio',
      child: Scaffold(
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => ref.read(inicioPacienteProvider.notifier).recarregar(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Olá, ${primeiroNome(usuario?.nome ?? '')}!',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                AvisosConta(usuario: usuario),
                ...inicio.when(
                  skipLoadingOnReload: false,
                  loading: () => const [
                    Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
                  ],
                  error: (_, __) => [
                    Text('Erro ao carregar seus dados.', style: TextStyle(color: Colors.red.shade700)),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: () => ref.invalidate(inicioPacienteProvider),
                        child: const Text('Tentar novamente'),
                      ),
                    ),
                  ],
                  data: (d) => [
                    _cartaoProxima(context, ref, d.proxima),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: StatCard(valor: '${d.concluidas}', rotulo: 'sessões concluídas')),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            valor: d.proxima == null ? '-' : '${diasEntre(agora, d.proxima!.dataHora)}',
                            rotulo: 'dias até a próxima',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('Ações rápidas', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _agendar(context, ref),
                            icon: const Icon(Icons.calendar_month),
                            label: const Text('Agendar sessão'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onVerSessoes,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
