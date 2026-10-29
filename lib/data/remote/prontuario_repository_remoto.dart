import 'package:mente_saudavel/domain/repositories/prontuario_repository.dart';
import 'package:mente_saudavel/models/prontuario.dart';
import 'package:mente_saudavel/services/api_client.dart';

/// Prontuário via API (`/profissional/...`).
class ProntuarioRepositoryRemoto implements ProntuarioRepository {
  @override
  Future<List<EntradaProntuario>> listar(int pacienteId) async {
    final r = await ApiClient.get('/profissional/pacientes/$pacienteId/prontuario');
    return ApiClient.comoLista(r).map(EntradaProntuario.fromMap).toList();
  }

  @override
  Future<EntradaProntuario> criar(int pacienteId, {required String tipo, required String conteudo, int? sessaoId}) async {
    final r = await ApiClient.post('/profissional/pacientes/$pacienteId/prontuario', corpo: {
      'tipo': tipo,
      'conteudo': conteudo,
      if (sessaoId != null) 'sessao_id': sessaoId,
    });
    return EntradaProntuario.fromMap((r as Map).cast<String, Object?>());
  }

  @override
  Future<EntradaProntuario> editar(int entradaId, {required String conteudo, required int versaoEsperada}) async {
    final r = await ApiClient.patch('/profissional/prontuario/$entradaId', corpo: {
      'conteudo': conteudo,
      'versao_esperada': versaoEsperada,
    });
    return EntradaProntuario.fromMap((r as Map).cast<String, Object?>());
  }

  @override
  Future<List<RevisaoProntuario>> revisoes(int entradaId) async {
    final r = await ApiClient.get('/profissional/prontuario/$entradaId/revisoes');
    return ApiClient.comoLista(r).map(RevisaoProntuario.fromMap).toList();
  }
}
