import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mente_saudavel/app/dependencias.dart';
import 'package:mente_saudavel/domain/repositories/sessao_repository.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/services/seguranca.dart';
import 'package:mente_saudavel/services/video_service.dart';
import 'package:mente_saudavel/utils/build_flags.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/avaliacao_widgets.dart';
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
  final SessaoRepository _dao = Dependencias.instancia.sessoes;
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

    // Conferir o horário e gravar acontecem juntos (transação); conflito vira mensagem na tela.
    await _executar(
      () => _dao.remarcar(_sessao.id!, nova),
      'Sessão remarcada para ${formatarDataHora(nova)}.',
    );
  }

  /// Modo servidor: pede a sala ao servidor (só os dois participantes, numa janela de horário, com link
  /// imprevisível) e abre no navegador. Se o navegador não abrir, copia o link.
  Future<void> _entrarNaVideo() async {
    setState(() => _ocupado = true);
    try {
      final sala = await VideoService.obterSala(_sessao.id!);
      if (!mounted) return;
      final abriu = await VideoService.abrir(sala.url);
      if (!mounted) return;
      if (!abriu) await _copiar(sala.url.toString(), 'Não consegui abrir o navegador. Link copiado: cole no navegador.');
    } on AppException catch (e) {
      if (mounted) mostrarMensagem(context, e.mensagem, erro: true);
    } catch (_) {
      if (mounted) mostrarMensagem(context, 'Não foi possível abrir a videochamada.', erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// SÓ no modo local (sem servidor): link derivado do id da sessão. NÃO é seguro (qualquer pessoa que conheça
  /// o esquema consegue calcular a sala); por isso o modo servidor usa [_entrarNaVideo].
  String get _linkVideo {
    final sala = Seguranca.hashSenha('sessao-${_sessao.id}', 'mente-saudavel').substring(0, 16);
    return 'https://meet.jit.si/MenteSaudavel-$sala';
  }

  String get _linkMapa =>
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeQueryComponent(_sessao.profissionalEndereco ?? '')}';

  Future<void> _copiar(String texto, String aviso) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    mostrarMensagem(context, aviso);
  }

  Future<void> _avaliar() async {
    final salvou = await mostrarAvaliarDialog(context, _sessao);
    if (!mounted) return;
    if (salvou) {
      mostrarMensagem(context, 'Avaliação enviada. Obrigado!');
      Navigator.pop(context, true);
    }
  }

  Widget _botaoLink(IconData icone, String rotulo, String link, String aviso) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: OutlinedButton.icon(
        onPressed: () => _copiar(link, aviso),
        icon: Icon(icone),
        label: Text(rotulo),
      ),
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
            if (s.valorCentavos > 0) _linha(Icons.payments_outlined, formatarReais(s.valorCentavos)),
            if (s.agendada && s.modalidade == Modalidade.online && usaServidor && !s.pendente && s.id != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FilledButton.icon(
                  onPressed: _ocupado ? null : _entrarNaVideo,
                  icon: const Icon(Icons.videocam),
                  label: const Text('Entrar na videochamada'),
                ),
              ),
            if (s.agendada && s.modalidade == Modalidade.online && !usaServidor)
              _botaoLink(Icons.videocam, 'Copiar link da videochamada', _linkVideo,
                  'Link copiado. Cole no navegador na hora da sessão.'),
            if (!profissional &&
                s.agendada &&
                s.modalidade == Modalidade.presencial &&
                endereco != null &&
                endereco.isNotEmpty)
              _botaoLink(Icons.map, 'Copiar link do mapa', _linkMapa, 'Link do mapa copiado.'),
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
              ] else ...[
                if (s.status == StatusSessao.concluida) ...[
                  FilledButton.icon(
                    onPressed: _ocupado ? null : _avaliar,
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Avaliar atendimento'),
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : _excluir,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Excluir do histórico'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
