import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mente_saudavel/utils/build_flags.dart';

/// Um evento de observabilidade. NUNCA carrega identificador de pessoa nem dados de saúde:
/// só o tipo, um nome técnico, tempos e (para erros) a mensagem/pilha já sem e-mails.
class EventoTelemetria {
  const EventoTelemetria({
    required this.tipo,
    required this.nome,
    this.duracaoMs,
    this.status,
    this.mensagem,
    this.pilha,
  });

  /// 'erro', 'rede' ou 'tela' (mesmos valores aceitos pelo servidor).
  final String tipo;
  final String nome;
  final int? duracaoMs;
  final int? status;
  final String? mensagem;
  final String? pilha;

  Map<String, Object?> toJson() => {
        'tipo': tipo,
        'nome': nome,
        if (duracaoMs != null) 'duracao_ms': duracaoMs,
        if (status != null) 'status': status,
        if (mensagem != null) 'mensagem': mensagem,
        if (pilha != null) 'pilha': pilha,
      };
}

/// Para onde os eventos vão. Trocável: o servidor próprio (padrão), o Sentry, um arquivo, etc.
abstract interface class TelemetriaSink {
  Future<void> enviar(List<EventoTelemetria> eventos);
}

/// Envia para `POST /telemetria` da API (vira log JSON no servidor).
class TelemetriaSinkHttp implements TelemetriaSink {
  @override
  Future<void> enviar(List<EventoTelemetria> eventos) async {
    final base = kApiUrl.endsWith('/') ? kApiUrl.substring(0, kApiUrl.length - 1) : kApiUrl;
    final corpo = jsonEncode({
      'versao_app': kAppVersao,
      'plataforma': Telemetria.plataforma,
      'eventos': eventos.map((e) => e.toJson()).toList(),
    });
    await http
        .post(Uri.parse('$base/telemetria'), headers: {'Content-Type': 'application/json'}, body: corpo)
        .timeout(const Duration(seconds: 10));
  }
}

/// Captura de erros globais + métricas de rede e de tela.
///
/// Erros: `FlutterError.onError` (erros de widget), `PlatformDispatcher.onError` (erros assíncronos
/// que ninguém tratou) e a `runZonedGuarded` do `main()`.
/// Envio: em lote (até 20 por vez), nunca derruba o app e nunca repete em laço se a rede falhar.
class Telemetria {
  static TelemetriaSink? sink = usaServidor ? TelemetriaSinkHttp() : null;
  static String plataforma = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

  static const int _lote = 10;
  static const int _maxBuffer = 50;
  static final List<EventoTelemetria> _fila = [];
  static Timer? _timer;

  /// Últimos eventos (para a tela de diagnóstico e para os testes).
  static final List<EventoTelemetria> recentes = [];

  static final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');

  /// Tira e-mails e limita o tamanho (o servidor também faz isso; aqui é a 1ª barreira).
  static String limpar(String texto, int limite) {
    final semEmail = texto.replaceAll(_email, '[email]');
    return semEmail.length <= limite ? semEmail : semEmail.substring(0, limite);
  }

  /// `GET /sessoes/12/avaliacao` -> `GET /sessoes/{id}/avaliacao` (sem identificadores nas métricas).
  static String normalizarCaminho(String metodo, String caminho) {
    final semConsulta = caminho.split('?').first;
    final modelo = semConsulta.replaceAllMapped(RegExp(r'/\d+(?=/|$)'), (_) => '/{id}');
    return '$metodo $modelo';
  }

  /// Liga a captura global. Chame uma vez no `main()`, depois do `ensureInitialized()`.
  static void instalar() {
    final anterior = FlutterError.onError;
    FlutterError.onError = (detalhes) {
      registrarErro(detalhes.exception, detalhes.stack, origem: 'FlutterError');
      (anterior ?? FlutterError.presentError)(detalhes); // continua aparecendo no console
    };
    PlatformDispatcher.instance.onError = (erro, pilha) {
      registrarErro(erro, pilha, origem: 'PlatformDispatcher');
      return true; // tratado: não derruba o app
    };
  }

  /// Envia o que estiver na fila a cada [intervalo]. Chame no `main()` (não nos testes).
  static void iniciarEnvioPeriodico({Duration intervalo = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _timer = Timer.periodic(intervalo, (_) => descarregar());
  }

  static void registrarErro(Object erro, StackTrace? pilha, {String origem = 'zona'}) {
    _adicionar(
      EventoTelemetria(
        tipo: 'erro',
        nome: limpar(origem, 80),
        mensagem: limpar(erro.toString(), 300),
        pilha: pilha == null ? null : limpar(pilha.toString(), 4000),
      ),
      urgente: true,
    );
  }

  static void registrarRede(String nome, int duracaoMs, int? status) {
    _adicionar(EventoTelemetria(tipo: 'rede', nome: limpar(nome, 80), duracaoMs: duracaoMs, status: status));
  }

  static void registrarTela(String nome, int duracaoMs) {
    _adicionar(EventoTelemetria(tipo: 'tela', nome: limpar(nome, 80), duracaoMs: duracaoMs));
  }

  /// Mede o tempo de uma operação assíncrona e registra como evento de tela
  /// (ex.: "quanto demorou até a lista de sessões ter dados").
  static Future<T> medir<T>(String nome, Future<T> Function() operacao) async {
    final relogio = Stopwatch()..start();
    try {
      return await operacao();
    } finally {
      registrarTela(nome, relogio.elapsedMilliseconds);
    }
  }

  static void _adicionar(EventoTelemetria e, {bool urgente = false}) {
    if (kDebugMode) debugPrint('[telemetria] ${jsonEncode(e.toJson())}');
    recentes.add(e);
    if (recentes.length > 100) recentes.removeAt(0);
    if (sink == null) return; // modo local: só fica na memória do aparelho
    if (_fila.length >= _maxBuffer) _fila.removeAt(0); // descarta o mais antigo, nunca cresce sem limite
    _fila.add(e);
    if (urgente || _fila.length >= _lote) unawaited(descarregar());
  }

  /// Envia a fila agora. Se falhar, descarta o lote (telemetria é "melhor esforço": não pode
  /// virar fila infinita nem consumir bateria tentando de novo).
  static Future<void> descarregar() async {
    final destino = sink;
    if (destino == null || _fila.isEmpty) return;
    final lote = _fila.take(20).toList();
    _fila.removeRange(0, lote.length);
    try {
      await destino.enviar(lote);
    } catch (_) {
      // ignorado de propósito
    }
  }

  @visibleForTesting
  static void reiniciar() {
    _timer?.cancel();
    _timer = null;
    _fila.clear();
    recentes.clear();
  }
}
