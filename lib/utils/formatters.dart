const List<String> _diasSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
const List<String> _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

String doisDigitos(int n) => n.toString().padLeft(2, '0');

String formatarHora(DateTime d) => '${doisDigitos(d.hour)}:${doisDigitos(d.minute)}';

/// Ex.: "Sex, 7 de agosto"
String formatarDataExtenso(DateTime d) =>
    '${_diasSemana[d.weekday - 1]}, ${d.day} de ${_meses[d.month - 1]}';

/// Ex.: "Sex, 7 de agosto · 15:00"
String formatarDataHora(DateTime d) => '${formatarDataExtenso(d)} · ${formatarHora(d)}';

/// Ex.: "07/08/2026"
String formatarDataCurta(DateTime d) =>
    '${doisDigitos(d.day)}/${doisDigitos(d.month)}/${d.year}';

/// Ex.: "2026-08-07" (mesmo formato usado pela BrasilAPI).
String chaveData(DateTime d) => '${d.year}-${doisDigitos(d.month)}-${doisDigitos(d.day)}';

DateTime somenteData(DateTime d) => DateTime(d.year, d.month, d.day);

bool mesmoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Quantidade de dias de calendário entre duas datas.
int diasEntre(DateTime de, DateTime ate) => DateTime.utc(ate.year, ate.month, ate.day)
    .difference(DateTime.utc(de.year, de.month, de.day))
    .inDays;

String primeiroNome(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+'));
  if (partes.isEmpty || partes.first.isEmpty) return nome;
  return partes.first;
}

/// Ex.: 15000 -> "R$ 150,00"; 123456 -> "R$ 1.234,56"
String formatarReais(int centavos) {
  final reais = centavos ~/ 100;
  final milhar = reais.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return 'R\$ $milhar,${doisDigitos(centavos % 100)}';
}

/// "150", "150,5" ou "150.50" -> centavos. Vazio, inválido, negativo ou acima de R$ 10.000 -> null.
int? centavosDeTexto(String texto) {
  final limpo = texto.trim().replaceAll(',', '.');
  if (limpo.isEmpty) return null;
  final valor = double.tryParse(limpo);
  if (valor == null || valor < 0 || valor > 10000) return null;
  return (valor * 100).round();
}
