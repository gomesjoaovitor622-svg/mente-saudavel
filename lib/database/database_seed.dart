import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/seguranca.dart';

/// Dados de demonstração, gravados UMA vez, quando o banco é criado.
///
/// Contas de teste:
///   Profissional: helena@mentesaudavel.app / mente123
///   Paciente:     carlos@email.com        / 123456
class DatabaseSeed {
  static Future<int> _criarUsuario(
    DatabaseExecutor db, {
    required String nome,
    required String email,
    required String senha,
    required String perfil,
    String? registro,
    String? especialidade,
    String? endereco,
  }) {
    final salt = Seguranca.gerarSalt();
    return db.insert('usuarios', {
      'nome': nome,
      'email': email,
      'senha_hash': Seguranca.hashSenha(senha, salt),
      'salt': salt,
      'perfil': perfil,
      'registro': registro,
      'especialidade': especialidade,
      'endereco': endereco,
      'criado_em': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> _criarSessao(
    DatabaseExecutor db, {
    required int pacienteId,
    required int profissionalId,
    required DateTime dataHora,
    required String modalidade,
    required String status,
    String? anotacoes,
  }) {
    return db.insert('sessoes', {
      'paciente_id': pacienteId,
      'profissional_id': profissionalId,
      'data_hora': dataHora.toIso8601String(),
      'modalidade': modalidade,
      'status': status,
      'anotacoes': anotacoes,
      'criado_em': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> executar(DatabaseExecutor db) async {
    final helena = await _criarUsuario(
      db,
      nome: 'Dra. Helena Marques',
      email: 'helena@mentesaudavel.app',
      senha: 'mente123',
      perfil: Perfil.profissional,
      registro: '06/12345',
      especialidade: 'Psicologia clínica',
      endereco: 'Av. Paulista, 1000, Bela Vista, São Paulo - SP',
    );
    await _criarUsuario(
      db,
      nome: 'Dr. Rafael Andrade',
      email: 'rafael@mentesaudavel.app',
      senha: 'mente123',
      perfil: Perfil.profissional,
      registro: '06/54321',
      especialidade: 'Terapia cognitivo-comportamental',
    );
    await _criarUsuario(
      db,
      nome: 'Dra. Beatriz Souza',
      email: 'beatriz@mentesaudavel.app',
      senha: 'mente123',
      perfil: Perfil.profissional,
      registro: '06/11223',
      especialidade: 'Psicologia infantil',
    );

    final carlos = await _criarUsuario(
      db,
      nome: 'Carlos Silva',
      email: 'carlos@email.com',
      senha: '123456',
      perfil: Perfil.paciente,
    );

    final agora = DateTime.now();
    final hoje = agora.year;
    final mes = agora.month;
    final dia = agora.day;

    await _criarSessao(
      db,
      pacienteId: carlos,
      profissionalId: helena,
      dataHora: DateTime(hoje, mes, dia - 9, 10),
      modalidade: Modalidade.online,
      status: StatusSessao.concluida,
      anotacoes: 'Primeira sessão: queixa principal de ansiedade no trabalho.',
    );
    await _criarSessao(
      db,
      pacienteId: carlos,
      profissionalId: helena,
      dataHora: DateTime(hoje, mes, dia - 2, 10),
      modalidade: Modalidade.online,
      status: StatusSessao.concluida,
      anotacoes: 'Trabalhadas técnicas de respiração e rotina de sono.',
    );
    await _criarSessao(
      db,
      pacienteId: carlos,
      profissionalId: helena,
      dataHora: DateTime(hoje, mes, dia, 14),
      modalidade: Modalidade.online,
      status: StatusSessao.agendada,
    );
    await _criarSessao(
      db,
      pacienteId: carlos,
      profissionalId: helena,
      dataHora: DateTime(hoje, mes, dia + 3, 15),
      modalidade: Modalidade.presencial,
      status: StatusSessao.agendada,
    );
  }
}
