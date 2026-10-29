class Perfil {
  static const String paciente = 'paciente';
  static const String profissional = 'profissional';
}

class Usuario {
  final int? id;
  final String nome;
  final String email;
  final String senhaHash;
  final String salt;
  final String perfil; // 'paciente' ou 'profissional'
  final String? registro; // CRP (somente profissional)
  final String? especialidade; // somente profissional
  final String? endereco; // consultório (somente profissional)
  final int? valorSessaoCentavos; // preço da sessão em centavos (somente profissional, modo servidor)
  final String criadoEm;
  final String? aceiteTermosVersao; // LGPD: versão dos Termos/Política que a pessoa aceitou
  // Só vêm do servidor. Profissional novo fica "em análise" até um administrador conferir o CRP.
  final bool verificado;
  // true quando o servidor envia e-mails e a pessoa ainda não confirmou o dela.
  final bool precisaVerificarEmail;

  const Usuario({
    this.id,
    required this.nome,
    required this.email,
    required this.senhaHash,
    required this.salt,
    required this.perfil,
    this.registro,
    this.especialidade,
    this.endereco,
    this.valorSessaoCentavos,
    required this.criadoEm,
    this.aceiteTermosVersao,
    this.verificado = true,
    this.precisaVerificarEmail = false,
  });

  bool get isProfissional => perfil == Perfil.profissional;

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'nome': nome,
      'email': email,
      'senha_hash': senhaHash,
      'salt': salt,
      'perfil': perfil,
      'registro': registro,
      'especialidade': especialidade,
      'endereco': endereco,
      'valor_sessao_centavos': valorSessaoCentavos,
      'criado_em': criadoEm,
      'aceite_termos_versao': aceiteTermosVersao,
    };
  }

  factory Usuario.fromMap(Map<String, Object?> map) {
    return Usuario(
      id: map['id'] as int?,
      nome: map['nome'] as String,
      email: (map['email'] as String?) ?? '',
      senhaHash: (map['senha_hash'] as String?) ?? '',
      salt: (map['salt'] as String?) ?? '',
      perfil: map['perfil'] as String,
      registro: map['registro'] as String?,
      especialidade: map['especialidade'] as String?,
      endereco: map['endereco'] as String?,
      valorSessaoCentavos: (map['valor_sessao_centavos'] as num?)?.toInt(),
      criadoEm: (map['criado_em'] as String?) ?? '',
      aceiteTermosVersao: map['aceite_termos_versao'] as String?,
      verificado: (map['verificado'] as bool?) ?? true,
      precisaVerificarEmail: (map['precisa_verificar_email'] as bool?) ?? false,
    );
  }

  Usuario copyWith({
    int? id,
    String? nome,
    String? senhaHash,
    String? salt,
    String? registro,
    String? especialidade,
    String? endereco,
    int? valorSessaoCentavos,
    String? aceiteTermosVersao,
  }) {
    return Usuario(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      email: email,
      senhaHash: senhaHash ?? this.senhaHash,
      salt: salt ?? this.salt,
      perfil: perfil,
      registro: registro ?? this.registro,
      especialidade: especialidade ?? this.especialidade,
      endereco: endereco ?? this.endereco,
      valorSessaoCentavos: valorSessaoCentavos ?? this.valorSessaoCentavos,
      criadoEm: criadoEm,
      aceiteTermosVersao: aceiteTermosVersao ?? this.aceiteTermosVersao,
      verificado: verificado,
      precisaVerificarEmail: precisaVerificarEmail,
    );
  }
}
