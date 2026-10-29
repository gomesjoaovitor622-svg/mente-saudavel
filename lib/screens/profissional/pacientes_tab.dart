import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/profissional_providers.dart';
import 'package:mente_saudavel/screens/profissional/paciente_detalhe_screen.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/componentes.dart';
import 'package:mente_saudavel/widgets/medir_tela.dart';

/// Pacientes que já têm (ou tiveram) sessão com o profissional. A busca filtra a lista já carregada
/// ([pacientesFiltradosProvider]); a tela só desenha o resultado.
class PacientesTab extends ConsumerStatefulWidget {
  const PacientesTab({super.key});

  @override
  ConsumerState<PacientesTab> createState() => _PacientesTabState();
}

class _PacientesTabState extends ConsumerState<PacientesTab> {
  // O campo de texto é estado de widget (controller); o TEXTO é do provider, que zera ao trocar de conta.
  final TextEditingController _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _abrir(PacienteResumo paciente) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => PacienteDetalheScreen(paciente: paciente)),
    );
    if (mounted) ref.invalidate(pacientesProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Se o texto do provider foi zerado (troca de conta), limpa também o campo.
    ref.listen<String>(buscaPacientesProvider, (_, novo) {
      if (novo != _busca.text) _busca.text = novo;
    });
    final texto = ref.watch(buscaPacientesProvider);
    final todos = ref.watch(pacientesProvider);
    final filtrados = ref.watch(pacientesFiltradosProvider);

    return MedirTela(
      nome: 'pacientes',
      child: Scaffold(
        appBar: AppBar(title: const Text('Pacientes')),
        body: todos.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Erro ao carregar os pacientes.'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => ref.invalidate(pacientesProvider), child: const Text('Tentar novamente')),
                ],
              ),
            ),
          ),
          data: (todosOsPacientes) {
            final lista = filtrados.valueOrNull ?? const <PacienteResumo>[];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _busca,
                    onChanged: (v) => ref.read(buscaPacientesProvider.notifier).state = v,
                    decoration: campo(
                      'Buscar paciente',
                      icone: Icons.search,
                      sufixo: texto.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Limpar busca',
                              onPressed: () {
                                _busca.clear();
                                ref.read(buscaPacientesProvider.notifier).state = '';
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
                              todosOsPacientes.isEmpty
                                  ? 'Você ainda não tem pacientes.\nEles aparecem aqui quando agendarem uma sessão com você.'
                                  : 'Nenhum paciente encontrado.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => ref.read(pacientesProvider.notifier).recarregar(),
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: lista.length,
                            itemBuilder: (context, i) {
                              final p = lista[i];
                              final proxima = p.proxima == null ? 'Sem sessão futura' : 'Próxima: ${formatarDataHora(p.proxima!)}';
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.green.shade100,
                                    child: Text(p.nome.isNotEmpty ? p.nome[0].toUpperCase() : '?', style: const TextStyle(color: verdeMarca)),
                                  ),
                                  title: Text(p.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text('${p.concluidas} concluída(s) de ${p.totalSessoes}\n$proxima'),
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
            );
          },
        ),
      ),
    );
  }
}
