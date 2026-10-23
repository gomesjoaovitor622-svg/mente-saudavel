import 'package:mente_saudavel/domain/repositories/sessao_repository.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/utils/formatters.dart';

/// Sessões pela API (FastAPI + PostgreSQL). Erros HTTP viram `AppException`
/// (409 vira `ConflitoException`) dentro do [ApiClient].
class SessaoRepositoryRemoto implements SessaoRepository {
  Future<List<Sessao>> _lista(Map<String, String> consulta) async {
    final r = await ApiClient.get('/sessoes', consulta: consulta);
    return ApiClient.comoLista(r).map(Sessao.fromMap).toList();
  }

  @override
  Future<int> agendar({
    required int pacienteId,
    required int profissionalId,
    required DateTime dataHora,
    required String modalidade,
    String? chaveIdempotencia,
  }) async {
    // O paciente é o usuário do token: o servidor ignora qualquer outro id.
    final r = await ApiClient.post('/sessoes',
        chaveIdempotencia: chaveIdempotencia,
        corpo: {
          'profissional_id': profissionalId,
          'data_hora': dataHora.toIso8601String(),
          'modalidade': modalidade,
        }) as Map<String, dynamic>;
    return r['id'] as int;
  }

  @override
  Future<List<Sessao>> doPaciente(int pacienteId, {String? status}) =>
      _lista({if (status != null) 'status': status});

  @override
  Future<Sessao?> proximaDoPaciente(int pacienteId) async {
    final lista = await _lista({
      'status': StatusSessao.agendada,
      'de': DateTime.now().toIso8601String(),
    });
    return lista.isEmpty ? null : lista.first; // o servidor ordena do mais próximo
  }

  @override
  Future<int> concluidasDoPaciente(int pacienteId) async =>
      (await _lista({'status': StatusSessao.concluida})).length;

  @override
  Future<List<Sessao>> doProfissionalNoDia(
    int profissionalId,
    DateTime dia, {
    bool incluirCanceladas = true,
  }) {
    final inicio = somenteData(dia);
    final fim = DateTime(dia.year, dia.month, dia.day + 1);
    return _lista({
      'de': inicio.toIso8601String(),
      'ate': fim.toIso8601String(),
      if (!incluirCanceladas) 'nao_canceladas': 'true',
    });
  }

  @override
  Future<int> atendimentosHoje(int profissionalId) async =>
      (await doProfissionalNoDia(profissionalId, DateTime.now(), incluirCanceladas: false)).length;

  @override
  Future<int> pacientesAtivos(int profissionalId) async =>
      (await pacientesDoProfissional(profissionalId)).length;

  @override
  Future<List<PacienteResumo>> pacientesDoProfissional(int profissionalId) async {
    final r = await ApiClient.get('/profissional/pacientes');
    return ApiClient.comoLista(r).map(PacienteResumo.fromMap).toList();
  }

  @override
  Future<List<Sessao>> doProfissionalComPaciente(int profissionalId, int pacienteId) =>
      _lista({'paciente_id': '$pacienteId'});

  @override
  Future<Set<int>> horasOcupadas(int profissionalId, DateTime dia) async {
    final r = await ApiClient.get('/profissionais/$profissionalId/horas-ocupadas',
        consulta: {'dia': somenteData(dia).toIso8601String()});
    return (r as List<dynamic>).map((e) => e as int).toSet();
  }

  @override
  Future<void> atualizarStatus(int id, String status) async {
    await ApiClient.patch('/sessoes/$id', corpo: {'status': status});
  }

  @override
  Future<void> atualizarAnotacoes(int id, String anotacoes) async {
    await ApiClient.patch('/sessoes/$id', corpo: {'anotacoes': anotacoes});
  }

  @override
  Future<void> remarcar(int id, DateTime novaDataHora) async {
    await ApiClient.patch('/sessoes/$id', corpo: {'data_hora': novaDataHora.toIso8601String()});
  }

  @override
  Future<void> excluir(int id) async {
    await ApiClient.delete('/sessoes/$id');
  }
}
