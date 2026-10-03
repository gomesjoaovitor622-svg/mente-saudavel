class HumorRegistro {
  static const List<String> emojis = ['😞', '🙁', '😐', '🙂', '😄'];
  static const List<String> rotulos = ['Muito mal', 'Mal', 'Neutro', 'Bem', 'Muito bem'];

  final int? id;
  final int usuarioId;
  final int nivel; // 1 a 5
  final String nota;
  final DateTime dataHora;

  const HumorRegistro({
    this.id,
    required this.usuarioId,
    required this.nivel,
    required this.nota,
    required this.dataHora,
  });

  String get emoji => emojis[nivel - 1];
  String get rotulo => rotulos[nivel - 1];

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'usuario_id': usuarioId,
      'nivel': nivel,
      'nota': nota,
      'data_hora': dataHora.toIso8601String(),
    };
  }

  factory HumorRegistro.fromMap(Map<String, Object?> m) {
    return HumorRegistro(
      id: m['id'] as int?,
      usuarioId: m['usuario_id'] as int,
      nivel: m['nivel'] as int,
      nota: (m['nota'] as String?) ?? '',
      dataHora: DateTime.parse(m['data_hora'] as String),
    );
  }
}
