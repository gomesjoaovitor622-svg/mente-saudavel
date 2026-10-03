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
  final String criadoEm;

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
    required this.criadoEm,
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
      'criado_em': criadoEm,
    };
  }

  factory Usuario.fromMap(Map<String, Object?> map) {
    return Usuario(
      id: map['id'] as int?,
      nome: map['nome'] as String,
      email: map['email'] as String,
      senhaHash: map['senha_hash'] as String,
      salt: map['salt'] as String,
      perfil: map['perfil'] as String,
      registro: map['registro'] as String?,
      especialidade: map['especialidade'] as String?,
      endereco: map['endereco'] as String?,
      criadoEm: map['criado_em'] as String,
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
      criadoEm: criadoEm,
    );
  }
}
