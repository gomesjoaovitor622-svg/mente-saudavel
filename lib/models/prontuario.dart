/// Tipos de registro do prontuário (o servidor aceita exatamente estes).
class TipoProntuario {
  static const String evolucao = 'evolucao';
  static const String anamnese = 'anamnese';
  static const String plano = 'plano';
  static const String observacao = 'observacao';

  static const List<String> todos = [evolucao, anamnese, plano, observacao];

  static String rotulo(String tipo) => switch (tipo) {
        evolucao => 'Evolução',
        anamnese => 'Anamnese',
        plano => 'Plano terapêutico',
        observacao => 'Observação',
        _ => tipo,
      };
}

/// Um registro do prontuário. Só o psicólogo autor vê; o servidor guarda cifrado.
class EntradaProntuario {
  const EntradaProntuario({
    required this.id,
    required this.pacienteId,
    required this.tipo,
    required this.conteudo,
    required this.versao,
    required this.criadoEm,
    required this.atualizadoEm,
    this.sessaoId,
  });

  final int id;
  final int pacienteId;
  final int? sessaoId;
  final String tipo;
  final String conteudo;

  /// Sobe a cada edição; vai de volta ao servidor para impedir sobrescrever uma edição feita em outro aparelho.
  final int versao;
  final DateTime criadoEm;
  final DateTime atualizadoEm;

  bool get editado => versao > 1;

  factory EntradaProntuario.fromMap(Map<String, Object?> m) => EntradaProntuario(
        id: (m['id']! as num).toInt(),
        pacienteId: (m['paciente_id']! as num).toInt(),
        sessaoId: (m['sessao_id'] as num?)?.toInt(),
        tipo: m['tipo']! as String,
        conteudo: m['conteudo']! as String,
        versao: (m['versao']! as num).toInt(),
        criadoEm: DateTime.parse(m['criado_em']! as String),
        atualizadoEm: DateTime.parse(m['atualizado_em']! as String),
      );
}

/// Versão anterior de um registro (o histórico nunca é apagado).
class RevisaoProntuario {
  const RevisaoProntuario({required this.versao, required this.conteudo, required this.substituidaEm});

  final int versao;
  final String conteudo;
  final DateTime substituidaEm;

  factory RevisaoProntuario.fromMap(Map<String, Object?> m) => RevisaoProntuario(
        versao: (m['versao']! as num).toInt(),
        conteudo: m['conteudo']! as String,
        substituidaEm: DateTime.parse(m['substituida_em']! as String),
      );
}
