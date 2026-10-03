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
