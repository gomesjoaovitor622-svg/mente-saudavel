import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mente_saudavel/models/prontuario.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/prontuario_providers.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Prontuário de um paciente: registros clínicos que só o psicólogo vê. O servidor guarda tudo cifrado,
/// não permite apagar e mantém o histórico de cada edição.
class ProntuarioScreen extends ConsumerWidget {
  const ProntuarioScreen({super.key, required this.paciente});

  final PacienteResumo paciente;

  Future<void> _abrirEditor(BuildContext context, WidgetRef ref, {EntradaProntuario? entrada}) async {
    final salvou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditorProntuario(pacienteId: paciente.id, entrada: entrada),
    );
    if (salvou == true && context.mounted) {
      mostrarMensagem(context, entrada == null ? 'Registro salvo.' : 'Registro atualizado.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registros = ref.watch(prontuarioProvider(paciente.id));
    return Scaffold(
      appBar: AppBar(title: Text('Prontuário · ${paciente.nome}')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.green.shade50,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(
              'Só você vê estes registros. Eles ficam cifrados no servidor, não podem ser apagados e cada edição guarda a versão anterior.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
            ),
          ),
          Expanded(
            child: registros.when(
              skipLoadingOnReload: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e is AppException ? e.mensagem : 'Erro ao carregar o prontuário.', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => ref.invalidate(prontuarioProvider(paciente.id)),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (lista) => lista.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhum registro ainda.\nToque em "Novo registro" para começar.', textAlign: TextAlign.center),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => ref.read(prontuarioProvider(paciente.id).notifier).recarregar(),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        itemCount: lista.length,
                        itemBuilder: (context, i) {
                          final e = lista[i];
                          return Card(
                            child: ListTile(
                              title: Text(
                                '${TipoProntuario.rotulo(e.tipo)} · ${formatarDataHora(e.criadoEm)}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(e.conteudo, maxLines: 3, overflow: TextOverflow.ellipsis),
                              ),
                              trailing: e.editado ? Chip(label: Text('v${e.versao}'), visualDensity: VisualDensity.compact) : null,
                              onTap: () => _abrirEditor(context, ref, entrada: e),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo registro'),
      ),
    );
  }
}

class _EditorProntuario extends ConsumerStatefulWidget {
  const _EditorProntuario({required this.pacienteId, this.entrada});

  final int pacienteId;
  final EntradaProntuario? entrada;

  @override
  ConsumerState<_EditorProntuario> createState() => _EditorProntuarioState();
}

class _EditorProntuarioState extends ConsumerState<_EditorProntuario> {
  late final TextEditingController _texto = TextEditingController(text: widget.entrada?.conteudo ?? '');
  late String _tipo = widget.entrada?.tipo ?? TipoProntuario.evolucao;
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final conteudo = _texto.text.trim();
    if (conteudo.isEmpty) {
      setState(() => _erro = 'Escreva o registro antes de salvar.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final notificador = ref.read(prontuarioProvider(widget.pacienteId).notifier);
    try {
      final existente = widget.entrada;
      if (existente == null) {
        await notificador.criar(tipo: _tipo, conteudo: conteudo);
      } else if (conteudo != existente.conteudo) {
        await notificador.editar(existente, conteudo);
      }
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = e.mensagem;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Não foi possível salvar. Tente novamente.';
        });
      }
    }
  }

  Future<void> _verHistorico(int entradaId) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _HistoricoDialog(entradaId: entradaId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existente = widget.entrada;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(existente == null ? 'Novo registro' : 'Editar registro', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (existente == null)
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: campo('Tipo'),
                items: [for (final t in TipoProntuario.todos) DropdownMenuItem(value: t, child: Text(TipoProntuario.rotulo(t)))],
                onChanged: _salvando ? null : (v) => setState(() => _tipo = v ?? _tipo),
              )
            else
              Text('${TipoProntuario.rotulo(existente.tipo)} · versão ${existente.versao}', style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            TextField(
              controller: _texto,
              minLines: 6,
              maxLines: 14,
              maxLength: 20000,
              enabled: !_salvando,
              decoration: campo('Registro clínico'),
            ),
            if (_erro != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_erro!, style: TextStyle(color: Colors.red.shade700))),
            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: const Icon(Icons.save_outlined),
              label: Text(_salvando ? 'Salvando...' : 'Salvar'),
            ),
            if (existente != null && existente.editado)
              TextButton.icon(
                onPressed: _salvando ? null : () => _verHistorico(existente.id),
                icon: const Icon(Icons.history),
                label: const Text('Ver versões anteriores'),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoricoDialog extends ConsumerWidget {
  const _HistoricoDialog({required this.entradaId});

  final int entradaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revisoes = ref.watch(revisoesProvider(entradaId));
    return AlertDialog(
      title: const Text('Versões anteriores'),
      content: SizedBox(
        width: double.maxFinite,
        child: revisoes.when(
          loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const Text('Não foi possível carregar o histórico.'),
          data: (lista) => lista.isEmpty
              ? const Text('Este registro ainda não foi editado.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in lista)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Versão ${r.versao} · substituída em ${formatarDataHora(r.substituidaEm)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(r.conteudo),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
