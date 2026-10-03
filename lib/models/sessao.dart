class StatusSessao {
  static const String agendada = 'agendada';
  static const String concluida = 'concluida';
  static const String cancelada = 'cancelada';
}

class Modalidade {
  static const String online = 'Online';
  static const String presencial = 'Presencial';
}

class Sessao {
  final int? id;
  final int pacienteId;
  final int profissionalId;
  final DateTime dataHora;
  final String modalidade;
  final String status;
  final String? anotacoes;

  // Campos vindos de JOIN com a tabela usuarios (somente leitura).
  final String? pacienteNome;
  final String? profissionalNome;
  final String? profissionalRegistro;
  final String? profissionalEspecialidade;
  final String? profissionalEndereco;

  const Sessao({
    this.id,
    required this.pacienteId,
    required this.profissionalId,
    required this.dataHora,
    required this.modalidade,
    required this.status,
    this.anotacoes,
    this.pacienteNome,
    this.profissionalNome,
    this.profissionalRegistro,
    this.profissionalEspecialidade,
    this.profissionalEndereco,
  });

  bool get agendada => status == StatusSessao.agendada;
  bool get passou => dataHora.isBefore(DateTime.now());

  String get statusTexto {
    switch (status) {
      case StatusSessao.concluida:
        return 'Concluída';
      case StatusSessao.cancelada:
        return 'Cancelada';
      default:
        return passou ? 'Aguardando conclusão' : 'Agendada';
    }
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'paciente_id': pacienteId,
      'profissional_id': profissionalId,
      'data_hora': dataHora.toIso8601String(),
      'modalidade': modalidade,
      'status': status,
      'anotacoes': anotacoes,
      'criado_em': DateTime.now().toIso8601String(),
    };
  }

  factory Sessao.fromMap(Map<String, Object?> m) {
    return Sessao(
      id: m['id'] as int?,
      pacienteId: m['paciente_id'] as int,
      profissionalId: m['profissional_id'] as int,
      dataHora: DateTime.parse(m['data_hora'] as String),
      modalidade: m['modalidade'] as String,
      status: m['status'] as String,
      anotacoes: m['anotacoes'] as String?,
      pacienteNome: m['paciente_nome'] as String?,
      profissionalNome: m['profissional_nome'] as String?,
      profissionalRegistro: m['profissional_registro'] as String?,
      profissionalEspecialidade: m['profissional_especialidade'] as String?,
      profissionalEndereco: m['profissional_endereco'] as String?,
    );
  }
}

/// Resumo de um paciente para a lista do profissional.
class PacienteResumo {
  final int id;
  final String nome;
  final String email;
  final int totalSessoes;
  final int concluidas;
  final DateTime? proxima;

  const PacienteResumo({
    required this.id,
    required this.nome,
    required this.email,
    required this.totalSessoes,
    required this.concluidas,
    this.proxima,
  });

  factory PacienteResumo.fromMap(Map<String, Object?> m) {
    final proxima = m['proxima'] as String?;
    return PacienteResumo(
      id: m['id'] as int,
      nome: m['nome'] as String,
      email: m['email'] as String,
      totalSessoes: (m['total'] as num).toInt(),
      concluidas: (m['concluidas'] as num).toInt(),
      proxima: proxima == null ? null : DateTime.parse(proxima),
    );
  }
}
