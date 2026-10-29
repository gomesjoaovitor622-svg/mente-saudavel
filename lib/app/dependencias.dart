import 'dart:async';

import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mente_saudavel/data/local/sessao_repository_local.dart';
import 'package:mente_saudavel/data/remote/sessao_repository_offline.dart';
import 'package:mente_saudavel/data/remote/sessao_repository_remoto.dart';
import 'package:mente_saudavel/domain/repositories/sessao_repository.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/services/sincronizador_outbox.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Composition root: o ÚNICO lugar que sabe qual implementação usar (SQLite local ou API).
/// O resto do app só enxerga as interfaces de `domain/repositories`.
///
/// Uso: `Dependencias.configurar(Dependencias.producao())` no `main()`.
/// Em testes: `Dependencias.configurar(Dependencias(sessoes: FakeSessaoRepository()))`.
class Dependencias {
  const Dependencias({required this.sessoes, this.outbox, this.cache, this.sincronizador});

  final SessaoRepository sessoes;

  /// Fila offline e sincronizador: só existem no modo servidor (o modo local já é todo offline).
  final OutboxRepository? outbox;
  final CacheKv? cache;
  final SincronizadorOutbox? sincronizador;

  /// Escolha feita uma vez só, na inicialização (flag `API_URL` do build).
  factory Dependencias.producao() {
    if (!usaServidor) return Dependencias(sessoes: SessaoRepositoryLocal());
    final remoto = SessaoRepositoryRemoto();
    // No NAVEGADOR não há banco local durável neste modo (o SQLite web exige arquivos extras de
    // WebAssembly): o site funciona só online, direto na API. A fila offline é do Android/iOS.
    if (kIsWeb) return Dependencias(sessoes: remoto);
    final outbox = OutboxRepository();
    final cache = CacheKv();
    int? usuario() => AuthService.atual.value?.id;
    final sincronizador = SincronizadorOutbox(outbox: outbox, remoto: remoto, usuarioId: usuario);
    return Dependencias(
      sessoes: SessaoRepositoryOffline(
        remoto: remoto,
        outbox: outbox,
        cache: cache,
        usuarioId: usuario,
        aoMudarFila: () {
          sincronizador.notificar();
          unawaited(sincronizador.sincronizar()); // se a internet já voltou, envia na hora
        },
      ),
      outbox: outbox,
      cache: cache,
      sincronizador: sincronizador,
    );
  }

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
