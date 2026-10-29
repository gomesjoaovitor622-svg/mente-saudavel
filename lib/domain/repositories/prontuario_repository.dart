import 'package:mente_saudavel/models/prontuario.dart';

/// Prontuário do psicólogo. Só existe no modo servidor (o servidor cifra e audita os acessos).
abstract class ProntuarioRepository {
  Future<List<EntradaProntuario>> listar(int pacienteId);

  Future<EntradaProntuario> criar(int pacienteId, {required String tipo, required String conteudo, int? sessaoId});

  /// [versaoEsperada] é a versão que a tela estava mostrando; se outro aparelho editou antes, o servidor
  /// responde 409 (ConflitoException) em vez de sobrescrever.
  Future<EntradaProntuario> editar(int entradaId, {required String conteudo, required int versaoEsperada});

  Future<List<RevisaoProntuario>> revisoes(int entradaId);
}
