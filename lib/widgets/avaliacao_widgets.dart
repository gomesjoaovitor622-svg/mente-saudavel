import 'package:flutter/material.dart';
import 'package:mente_saudavel/database/avaliacao_dao.dart';
import 'package:mente_saudavel/models/avaliacao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Mostra 5 estrelas preenchidas conforme a nota (aceita decimais, ex.: 4.3).
class Estrelas extends StatelessWidget {
  final double nota;
  final double tamanho;

  const Estrelas({super.key, required this.nota, this.tamanho = 18});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final IconData icone;
        if (nota >= i + 0.75) {
          icone = Icons.star;
        } else if (nota >= i + 0.25) {
          icone = Icons.star_half;
        } else {
          icone = Icons.star_border;
        }
        return Icon(icone, size: tamanho, color: Colors.amber.shade700);
      }),
    );
  }
}

/// Abre a janela para o paciente avaliar uma sessão concluída.
/// Retorna true se a avaliação foi salva.
Future<bool> mostrarAvaliarDialog(BuildContext context, Sessao sessao) async {
  final dao = AvaliacaoDao();
  final existente = await dao.daSessao(sessao.id!);
  if (!context.mounted) return false;

  final salvou = await showDialog<bool>(
    context: context,
    builder: (_) => _AvaliarDialog(sessao: sessao, existente: existente, dao: dao),
  );
  return salvou == true;
}

class _AvaliarDialog extends StatefulWidget {
  final Sessao sessao;
  final Avaliacao? existente;
  final AvaliacaoDao dao;

  const _AvaliarDialog({required this.sessao, required this.existente, required this.dao});

  @override
  State<_AvaliarDialog> createState() => _AvaliarDialogState();
}

class _AvaliarDialogState extends State<_AvaliarDialog> {
  late int _nota = widget.existente?.nota ?? 0;
  late final TextEditingController _comentario =
      TextEditingController(text: widget.existente?.comentario ?? '');
  bool _salvando = false;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_nota == 0) {
      mostrarMensagem(context, 'Escolha uma nota de 1 a 5 estrelas.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      final s = widget.sessao;
      await widget.dao.salvar(
        Avaliacao(
          id: widget.existente?.id,
          sessaoId: s.id!,
          pacienteId: s.pacienteId,
          profissionalId: s.profissionalId,
          nota: _nota,
          comentario: _comentario.text.trim(),
          criadoEm: DateTime.now(),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _salvando = false);
      mostrarMensagem(context, 'Não foi possível salvar a avaliação.', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Avaliar ${widget.sessao.profissionalNome ?? 'profissional'}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final n = i + 1;
                return IconButton(
                  tooltip: '$n estrela${n > 1 ? 's' : ''}',
                  onPressed: () => setState(() => _nota = n),
                  icon: Icon(
                    n <= _nota ? Icons.star : Icons.star_border,
                    color: Colors.amber.shade700,
                    size: 32,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _comentario,
              maxLines: 3,
              maxLength: 300,
              decoration: campo('Comentário (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          child: Text(_salvando ? 'Salvando...' : 'Enviar'),
        ),
      ],
    );
  }
}
