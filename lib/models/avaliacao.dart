class Avaliacao {
  final int? id;
  final int sessaoId;
  final int pacienteId;
  final int profissionalId;
  final int nota; // 1 a 5
  final String comentario;
  final DateTime criadoEm;
  final String? pacienteNome; // vem de JOIN

  const Avaliacao({
    this.id,
    required this.sessaoId,
    required this.pacienteId,
    required this.profissionalId,
    required this.nota,
    required this.comentario,
    required this.criadoEm,
    this.pacienteNome,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'sessao_id': sessaoId,
        'paciente_id': pacienteId,
        'profissional_id': profissionalId,
        'nota': nota,
        'comentario': comentario,
        'criado_em': criadoEm.toIso8601String(),
      };

  factory Avaliacao.fromMap(Map<String, Object?> m) => Avaliacao(
        id: m['id'] as int?,
        sessaoId: m['sessao_id'] as int,
        pacienteId: m['paciente_id'] as int,
        profissionalId: m['profissional_id'] as int,
        nota: m['nota'] as int,
        comentario: (m['comentario'] as String?) ?? '',
        criadoEm: DateTime.parse(m['criado_em'] as String),
        pacienteNome: m['paciente_nome'] as String?,
      );
}

/// Profissional + resumo das avaliações (usado na busca).
class ProfissionalResumo {
  final int id;
  final String nome;
  final String? registro;
  final String? especialidade;
  final String? endereco;
  final int? valorSessaoCentavos;
  final double? media; // null = ainda sem avaliações
  final int totalAvaliacoes;

  const ProfissionalResumo({
    required this.id,
    required this.nome,
    this.registro,
    this.especialidade,
    this.endereco,
    this.valorSessaoCentavos,
    this.media,
    this.totalAvaliacoes = 0,
  });

  factory ProfissionalResumo.fromMap(Map<String, Object?> m) => ProfissionalResumo(
        id: m['id'] as int,
        nome: m['nome'] as String,
        registro: m['registro'] as String?,
        especialidade: m['especialidade'] as String?,
        endereco: m['endereco'] as String?,
        valorSessaoCentavos: (m['valor_sessao_centavos'] as num?)?.toInt(),
        media: (m['media'] as num?)?.toDouble(),
        totalAvaliacoes: (m['total'] as num?)?.toInt() ?? 0,
      );
}
