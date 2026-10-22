import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/domain/repositories/sessao_repository.dart';
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
