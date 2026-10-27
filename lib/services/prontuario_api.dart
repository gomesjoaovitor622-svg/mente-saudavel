import 'package:mente_saudavel/models/prontuario.dart';
import 'package:mente_saudavel/services/api_client.dart';

/// Chamadas do prontuário ao servidor. Não há exclusão de propósito: o registro clínico deve ser mantido
/// (as edições ficam no histórico). O prontuário só existe no modo servidor.
class ProntuarioApi {
  Future<List<EntradaProntuario>> listar(int pacienteId) async {
    final r = await ApiClient.get('/profissional/pacientes/$pacienteId/prontuario');
    return ApiClient.comoLista(r).map(EntradaProntuario.fromMap).toList();
  }

  Future<EntradaProntuario> criar(int pacienteId, {required String tipo, required String conteudo, int? sessaoId}) async {
    final r = await ApiClient.post(
      '/profissional/pacientes/$pacienteId/prontuario',
      corpo: {'tipo': tipo, 'conteudo': conteudo, if (sessaoId != null) 'sessao_id': sessaoId},
    );
    return EntradaProntuario.fromMap(Map<String, Object?>.from(r as Map));
  }

  Future<EntradaProntuario> editar(int entradaId, {required String conteudo, required int versaoEsperada}) async {
    final r = await ApiClient.patch(
      '/profissional/prontuario/$entradaId',
      corpo: {'conteudo': conteudo, 'versao_esperada': versaoEsperada},
    );
    return EntradaProntuario.fromMap(Map<String, Object?>.from(r as Map));
  }

  Future<List<RevisaoProntuario>> revisoes(int entradaId) async {
    final r = await ApiClient.get('/profissional/prontuario/$entradaId/revisoes');
    return ApiClient.comoLista(r).map(RevisaoProntuario.fromMap).toList();
  }
}
