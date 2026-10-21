import 'package:mente_saudavel/data/local/sessao_repository_local.dart';
import 'package:mente_saudavel/data/remote/sessao_repository_remoto.dart';
import 'package:mente_saudavel/domain/repositories/sessao_repository.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Composition root: o ÚNICO lugar que sabe qual implementação usar (SQLite local ou API).
/// O resto do app só enxerga as interfaces de `domain/repositories`.
///
/// Uso: `Dependencias.configurar(Dependencias.producao())` no `main()`.
/// Em testes: `Dependencias.configurar(Dependencias(sessoes: FakeSessaoRepository()))`.
class Dependencias {
  const Dependencias({required this.sessoes});

  final SessaoRepository sessoes;

  /// Escolha feita uma vez só, na inicialização (flag `API_URL` do build).
  factory Dependencias.producao() => Dependencias(
        sessoes: usaServidor ? SessaoRepositoryRemoto() : SessaoRepositoryLocal(),
      );

  static Dependencias? _instancia;

  static Dependencias get instancia {
    final atual = _instancia;
    if (atual == null) {
      throw StateError('Dependencias.configurar() não foi chamado no main().');
    }
    return atual;
  }

  static void configurar(Dependencias dependencias) => _instancia = dependencias;
}
