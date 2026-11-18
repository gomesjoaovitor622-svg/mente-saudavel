import 'package:mente_saudavel/services/api_client.dart';

/// Chamadas da API para o diário de humor. A `Idempotency-Key` faz o servidor devolver o MESMO registro se o
/// reenvio da fila offline chegar de novo (resposta perdida, timeout): nunca duplica.
class HumorRemoto {
  Future<int> registrar({
    required int nivel,
    required String nota,
    required DateTime dataHora,
    String? chaveIdempotencia,
  }) async {
    final r = await ApiClient.post(
      '/humor',
      chaveIdempotencia: chaveIdempotencia,
      corpo: {'nivel': nivel, 'nota': nota, 'data_hora': dataHora.toIso8601String()},
    ) as Map<String, dynamic>;
    return r['id'] as int;
  }
}

/// Atualização cadastral (PATCH /auth/eu). É naturalmente idempotente: repetir grava os mesmos valores.
class PerfilRemoto {
  Future<dynamic> atualizar(Map<String, Object?> campos) => ApiClient.patch('/auth/eu', corpo: campos);
}
