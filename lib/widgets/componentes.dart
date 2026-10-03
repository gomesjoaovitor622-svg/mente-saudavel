import 'package:flutter/material.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/utils/formatters.dart';

const Color verdeMarca = Color(0xFF3F8F5A);

/// Estilo padrão dos campos de texto do app.
InputDecoration campo(String rotulo, {IconData? icone, String? dica, Widget? sufixo}) {
  return InputDecoration(
    labelText: rotulo,
    hintText: dica,
    prefixIcon: icone == null ? null : Icon(icone),
    suffixIcon: sufixo,
    border: const OutlineInputBorder(),
    filled: true,
    fillColor: Colors.white,
  );
}

void mostrarMensagem(BuildContext context, String texto, {bool erro = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
}

Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensagem,
  String textoConfirmar = 'Confirmar',
}) async {
  final resultado = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensagem),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(textoConfirmar),
        ),
      ],
    ),
  );
  return resultado == true;
}

class LogoMente extends StatelessWidget {
  final double tamanho;
  final bool mostrarNome;

  const LogoMente({super.key, this.tamanho = 56, this.mostrarNome = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.psychology, size: tamanho, color: verdeMarca),
        if (mostrarNome)
          const Text(
            'mente saudável',
            style: TextStyle(color: verdeMarca, fontWeight: FontWeight.w600, fontSize: 16),
          ),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  final String valor;
  final String rotulo;

  const StatCard({super.key, required this.valor, required this.rotulo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Text(valor, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            rotulo,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final Sessao sessao;

  const StatusChip({super.key, required this.sessao});

  @override
  Widget build(BuildContext context) {
    Color fundo;
    Color texto;
    switch (sessao.status) {
      case StatusSessao.concluida:
        fundo = Colors.green.shade100;
        texto = Colors.green.shade900;
        break;
      case StatusSessao.cancelada:
        fundo = Colors.red.shade100;
        texto = Colors.red.shade900;
        break;
      default:
        if (sessao.passou) {
          fundo = Colors.orange.shade100;
          texto = Colors.orange.shade900;
        } else {
          fundo = Colors.blue.shade100;
          texto = Colors.blue.shade900;
        }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(20)),
      child: Text(
        sessao.statusTexto,
        style: TextStyle(fontSize: 12, color: texto, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Cartão de sessão usado nas listas (paciente e profissional).
class SessaoCard extends StatelessWidget {
  final Sessao sessao;
  final bool comoProfissional;
  final bool mostrarData;
  final VoidCallback onTap;

  const SessaoCard({
    super.key,
    required this.sessao,
    required this.comoProfissional,
    required this.onTap,
    this.mostrarData = true,
  });

  @override
  Widget build(BuildContext context) {
    final nome = comoProfissional
        ? (sessao.pacienteNome ?? 'Paciente')
        : (sessao.profissionalNome ?? 'Profissional');
    final quando = mostrarData
        ? '${formatarDataHora(sessao.dataHora)} · ${sessao.modalidade}'
        : '${formatarHora(sessao.dataHora)} - ${sessao.modalidade}';
    final futura = sessao.agendada && !sessao.passou;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: const Icon(Icons.person, color: verdeMarca),
        ),
        title: Text(nome, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(quando),
        trailing: futura ? const Icon(Icons.chevron_right) : StatusChip(sessao: sessao),
        onTap: onTap,
      ),
    );
  }
}
