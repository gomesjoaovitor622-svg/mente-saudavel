import 'package:flutter/material.dart';
import 'package:mente_saudavel/models/humor.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Gráfico de linha simples (sem dependências) com a média diária de humor
/// dos últimos [dias] dias. Dias sem registro ficam sem ponto.
class GraficoHumor extends StatelessWidget {
  final List<HumorRegistro> registros;
  final int dias;

  const GraficoHumor({super.key, required this.registros, this.dias = 14});

  /// Média por dia (índice 0 = mais antigo, último = hoje); null = sem registro.
  List<double?> _medias() {
    final hoje = DateTime.now();
    final inicio = DateTime(hoje.year, hoje.month, hoje.day).subtract(Duration(days: dias - 1));
    final soma = List<double>.filled(dias, 0);
    final qtd = List<int>.filled(dias, 0);
    for (final r in registros) {
      final dia = DateTime(r.dataHora.year, r.dataHora.month, r.dataHora.day);
      final i = dia.difference(inicio).inDays;
      if (i < 0 || i >= dias) continue;
      soma[i] += r.nivel;
      qtd[i] += 1;
    }
    return List.generate(dias, (i) => qtd[i] == 0 ? null : soma[i] / qtd[i]);
  }

  @override
  Widget build(BuildContext context) {
    final medias = _medias();
    final temDados = medias.any((m) => m != null);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Últimos $dias dias', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: temDados
                  ? CustomPaint(
                      size: Size.infinite,
                      painter: _PintorHumor(medias, Theme.of(context).dividerColor),
                    )
                  : Center(
                      child: Text(
                        'Registre seu humor para ver a evolução.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
            ),
            if (temDados)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${dias - 1} dias atrás', style: const TextStyle(fontSize: 11)),
                  const Text('Hoje', style: TextStyle(fontSize: 11)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PintorHumor extends CustomPainter {
  final List<double?> medias;
  final Color corGrade;

  _PintorHumor(this.medias, this.corGrade);

  @override
  void paint(Canvas canvas, Size size) {
    const margemEsq = 22.0;
    final largura = size.width - margemEsq;
    final altura = size.height;

    final grade = Paint()
      ..color = corGrade
      ..strokeWidth = 1;
    for (var nivel = 1; nivel <= 5; nivel++) {
      final y = altura - (nivel - 1) / 4 * altura;
      canvas.drawLine(Offset(margemEsq, y), Offset(size.width, y), grade);
      final tp = TextPainter(
        text: TextSpan(text: '$nivel', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    final n = medias.length;
    double x(int i) => margemEsq + (n == 1 ? 0 : i / (n - 1) * largura);
    double y(double m) => altura - (m - 1) / 4 * altura;

    final linha = Paint()
      ..color = verdeMarca
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final caminho = Path();
    var comecou = false;
    for (var i = 0; i < n; i++) {
      final m = medias[i];
      if (m == null) continue;
      if (!comecou) {
        caminho.moveTo(x(i), y(m));
        comecou = true;
      } else {
        caminho.lineTo(x(i), y(m));
      }
    }
    canvas.drawPath(caminho, linha);

    final ponto = Paint()..color = verdeMarca;
    for (var i = 0; i < n; i++) {
      final m = medias[i];
      if (m != null) canvas.drawCircle(Offset(x(i), y(m)), 4, ponto);
    }
  }

  @override
  bool shouldRepaint(covariant _PintorHumor antigo) =>
      antigo.medias != medias || antigo.corGrade != corGrade;
}
