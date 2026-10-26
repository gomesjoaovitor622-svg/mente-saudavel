import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/database/avaliacao_dao.dart';
import 'package:mente_saudavel/domain/repositories/sessao_repository.dart';
import 'package:mente_saudavel/models/avaliacao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/models/usuario.dart';

/// Repositório falso em memória: só o que as telas testadas usam (o resto lança ao ser chamado).
class FakeSessaoRepository extends Fake implements SessaoRepository {
  FakeSessaoRepository(this.sessoes);

  final List<Sessao> sessoes;
  int consultas = 0;
  Object? falhar; // se preenchido, a próxima consulta lança isso

  @override
  Future<List<Sessao>> doPaciente(int pacienteId, {String? status}) async {
    consultas++;
    final erro = falhar;
    if (erro != null) {
      falhar = null;
      throw erro;
    }
    return sessoes.where((s) => s.pacienteId == pacienteId && (status == null || s.status == status)).toList();
  }

  // Painel do profissional.
  @override
  Future<int> atendimentosHoje(int profissionalId) async => sessoes.length;

  @override
  Future<int> pacientesAtivos(int profissionalId) async => sessoes.map((s) => s.pacienteId).toSet().length;

  final List<DateTime> diasConsultados = [];
  final List<PacienteResumo> pacientes = [];

  @override
  Future<List<Sessao>> doProfissionalNoDia(int profissionalId, DateTime dia, {bool incluirCanceladas = true}) async {
    consultas++;
    diasConsultados.add(dia);
    final erro = falhar;
    if (erro != null) {
      falhar = null;
      throw erro;
    }
    return sessoes
        .where((s) => s.profissionalId == profissionalId && s.dataHora.year == dia.year && s.dataHora.month == dia.month && s.dataHora.day == dia.day)
        .toList();
  }

  @override
  Future<List<PacienteResumo>> pacientesDoProfissional(int profissionalId) async {
    consultas++;
    final erro = falhar;
    if (erro != null) {
      falhar = null;
      throw erro;
    }
    return List.of(pacientes);
  }
}

/// Avaliações falsas: o painel só usa `doProfissional`.
class FakeAvaliacaoDao extends Fake implements AvaliacaoDao {
  FakeAvaliacaoDao(this.notas);
  final List<int> notas;

  @override
  Future<List<Avaliacao>> doProfissional(int profissionalId, {int limite = 30}) async => [
        for (final n in notas)
          Avaliacao(
            sessaoId: n,
            pacienteId: 1,
            profissionalId: profissionalId,
            nota: n,
            comentario: '',
            criadoEm: DateTime(2031),
          ),
      ];
}

Usuario pacienteDeTeste({int id = 1}) => Usuario(
      id: id,
      nome: 'Ana',
      email: 'ana@teste.com',
      senhaHash: 'x',
      salt: 'y',
      perfil: Perfil.paciente,
      criadoEm: DateTime(2030).toIso8601String(),
    );

Sessao sessaoDeTeste(String profissional, String status, {int pacienteId = 1, int dia = 10}) => Sessao(
      id: profissional.hashCode,
      pacienteId: pacienteId,
      profissionalId: 99,
      dataHora: DateTime(2031, 1, dia, 10),
      modalidade: 'Online',
      status: status,
      profissionalNome: profissional,
    );

Usuario profissionalDeTeste({int id = 99}) => Usuario(
      id: id,
      nome: 'Dra. Marta',
      email: 'marta@teste.com',
      senhaHash: 'x',
      salt: 'y',
      perfil: Perfil.profissional,
      registro: '06/12345',
      criadoEm: DateTime(2030).toIso8601String(),
    );

PacienteResumo pacienteResumoDeTeste(String nome, {int id = 1, String? email, int total = 3, int concluidas = 1}) => PacienteResumo(
      id: id,
      nome: nome,
      email: email ?? '${nome.toLowerCase().replaceAll(' ', '.')}@teste.com',
      totalSessoes: total,
      concluidas: concluidas,
    );
