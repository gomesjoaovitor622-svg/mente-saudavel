import 'package:flutter/material.dart';
import 'package:mente_saudavel/database/sessao_dao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Abre os detalhes da sessão. Retorna true se algo foi alterado.
Future<bool> mostrarSessaoSheet(
  BuildContext context, {
  required Sessao sessao,
  required bool comoProfissional,
}) async {
  final resultado = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SessaoSheet(sessao: sessao, comoProfissional: comoProfissional),
  );
  return resultado == true;
}

class _SessaoSheet extends StatefulWidget {
  final Sessao sessao;
  final bool comoProfissional;

  const _SessaoSheet({required this.sessao, required this.comoProfissional});

  @override
  State<_SessaoSheet> createState() => _SessaoSheetState();
}

class _SessaoSheetState extends State<_SessaoSheet> {
  final SessaoDao _dao = SessaoDao();
  late final TextEditingController _anotacoes;
  bool _ocupado = false;

  Sessao get _sessao => widget.sessao;

  @override
  void initState() {
    super.initState();
    _anotacoes = TextEditingController(text: _sessao.anotacoes ?? '');
  }

  @override
  void dispose() {
    _anotacoes.dispose();
    super.dispose();
  }

  /// Executa uma ação no banco, mostra o resultado e fecha o painel.
  Future<void> _executar(Future<void> Function() acao, String sucesso) async {
    setState(() => _ocupado = true);
    try {
      await acao();
      if (!mounted) return;
      mostrarMensagem(context, sucesso);
      Navigator.pop(context, true);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      mostrarMensagem(context, e.mensagem, erro: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      mostrarMensagem(context, 'Não foi possível concluir a operação.', erro: true);
    }
  }

  Future<void> _cancelar() async {
    final ok = await confirmar(
      context,
      titulo: 'Cancelar sessão',
      mensagem: 'Deseja realmente cancelar esta sessão?',
      textoConfirmar: 'Cancelar sessão',
    );
    if (!ok || !mounted) return;
    await _executar(
      () async {
        await _dao.atualizarStatus(_sessao.id!, StatusSessao.cancelada);
      },
      'Sessão cancelada.',
    );
  }

  Future<void> _concluir() async {
    await _executar(
      () async {
        await _dao.atualizarStatus(_sessao.id!, StatusSessao.concluida);
      },
      'Sessão marcada como concluída.',
    );
  }

  Future<void> _salvarAnotacoes() async {
    await _executar(
      () async {
        await _dao.atualizarAnotacoes(_sessao.id!, _anotacoes.text.trim());
      },
      'Anotações salvas.',
    );
  }

  Future<void> _excluir() async {
    final ok = await confirmar(
      context,
      titulo: 'Excluir do histórico',
      mensagem: 'Deseja excluir esta sessão do seu histórico?',
      textoConfirmar: 'Excluir',
    );
    if (!ok || !mounted) return;
    await _executar(
      () async {
        await _dao.excluir(_sessao.id!);
      },
      'Sessão excluída do histórico.',
    );
  }

  Future<void> _remarcar() async {
    final agora = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: _sessao.dataHora.isAfter(agora) ? _sessao.dataHora : agora,
      firstDate: somenteData(agora),
      lastDate: agora.add(const Duration(days: 365)),
    );
    if (data == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _sessao.dataHora.hour, minute: 0),
    );
    if (hora == null || !mounted) return;

    final nova = DateTime(data.year, data.month, data.day, hora.hour, hora.minute);
    if (!nova.isAfter(agora)) {
      mostrarMensagem(context, 'Escolha um horário no futuro.', erro: true);
      return;
    }

    await _executar(
      () async {
        final conflito = await _dao.verificarConflito(
          profissionalId: _sessao.profissionalId,
          pacienteId: _sessao.pacienteId,
          dataHora: nova,
          ignorarId: _sessao.id,
        );
        if (conflito != null) throw AppException(conflito);
        await _dao.remarcar(_sessao.id!, nova);
      },
      'Sessão remarcada para ${formatarDataHora(nova)}.',
    );
  }

  Widget _linha(IconData icone, String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: Colors.grey.shade700),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _sessao;
    final profissional = widget.comoProfissional;
    final nome = profissional ? (s.pacienteNome ?? 'Paciente') : (s.profissionalNome ?? 'Profissional');
    final registro = s.profissionalRegistro;
    final endereco = s.profissionalEndereco;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(nome, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                StatusChip(sessao: s),
              ],
            ),
            if (!profissional && registro != null && registro.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Psicólogo(a) CRP $registro',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            const SizedBox(height: 12),
            _linha(Icons.schedule, formatarDataHora(s.dataHora)),
            _linha(
              s.modalidade == Modalidade.online ? Icons.videocam_outlined : Icons.place_outlined,
              s.modalidade,
            ),
            if (!profissional &&
                s.modalidade == Modalidade.presencial &&
                endereco != null &&
                endereco.isNotEmpty)
              _linha(Icons.map_outlined, endereco),
            const SizedBox(height: 12),
            if (profissional) ...[
              TextField(
                controller: _anotacoes,
                maxLines: 4,
                decoration: campo('Anotações da sessão (privadas)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _ocupado ? null : _salvarAnotacoes,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar anotações'),
              ),
              if (s.agendada) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _ocupado ? null : _concluir,
                  icon: const Icon(Icons.check),
                  label: const Text('Marcar como concluída'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : _cancelar,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar sessão'),
                ),
              ],
            ] else ...[
              if (s.agendada) ...[
                FilledButton.icon(
                  onPressed: _ocupado ? null : _remarcar,
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text('Remarcar'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : _cancelar,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar sessão'),
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : _excluir,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Excluir do histórico'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
