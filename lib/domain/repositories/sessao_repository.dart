import 'package:mente_saudavel/models/sessao.dart';

/// Contrato de acesso às sessões (agendamentos). As telas conhecem SÓ esta interface;
/// quem decide se os dados vêm do SQLite do aparelho ou da API é o composition root
/// (`Dependencias.producao()`), uma única vez, na inicialização do app.
///
/// Erros "esperados" saem como [AppException]; horário já ocupado sai como [ConflitoException].
abstract interface class SessaoRepository {
  /// Agenda uma sessão. Atômico: conferir o horário e gravar acontecem juntos.
  /// Lança `ConflitoException` se o profissional (ou o paciente) já tem sessão ativa nesse horário.
  Future<int> agendar({
    required int pacienteId,
    required int profissionalId,
    required DateTime dataHora,
    required String modalidade,
  });

  Future<List<Sessao>> doPaciente(int pacienteId, {String? status});
  Future<Sessao?> proximaDoPaciente(int pacienteId);
  Future<int> concluidasDoPaciente(int pacienteId);

  Future<List<Sessao>> doProfissionalNoDia(int profissionalId, DateTime dia, {bool incluirCanceladas = true});
  Future<int> atendimentosHoje(int profissionalId);
  Future<int> pacientesAtivos(int profissionalId);
  Future<List<PacienteResumo>> pacientesDoProfissional(int profissionalId);
  Future<List<Sessao>> doProfissionalComPaciente(int profissionalId, int pacienteId);

  /// Horas (0-23) já ocupadas pelo profissional em um dia (para desabilitar botões na tela).
  Future<Set<int>> horasOcupadas(int profissionalId, DateTime dia);

  Future<void> atualizarStatus(int id, String status);
  Future<void> atualizarAnotacoes(int id, String anotacoes);

  /// Remarca para [novaDataHora] (atômico, como [agendar]). Lança `ConflitoException` se ocupado.
  Future<void> remarcar(int id, DateTime novaDataHora);

  Future<void> excluir(int id);
}
