import 'package:flutter/material.dart';
import 'package:mente_saudavel/services/telemetria.dart';

/// Mede quanto a tela demora para aparecer (do `initState` até o primeiro quadro desenhado)
/// e registra como métrica de desempenho. Envolva só as telas críticas.
class MedirTela extends StatefulWidget {
  const MedirTela({super.key, required this.nome, required this.child});

  final String nome;
  final Widget child;

  @override
  State<MedirTela> createState() => _MedirTelaState();
}

class _MedirTelaState extends State<MedirTela> {
  final Stopwatch _relogio = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Telemetria.registrarTela('${widget.nome}:primeiro_quadro', _relogio.elapsedMilliseconds);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
