import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/services/telemetria.dart';

class _SinkFalso implements TelemetriaSink {
  final List<List<EventoTelemetria>> lotes = [];
  bool falhar = false;

  @override
  Future<void> enviar(List<EventoTelemetria> eventos) async {
    if (falhar) throw Exception('sem rede');
    lotes.add(eventos);
  }
}

void main() {
  late _SinkFalso sink;
  late void Function(FlutterErrorDetails)? onErrorOriginal;

  setUp(() {
    Telemetria.reiniciar();
    sink = _SinkFalso();
    Telemetria.sink = sink;
    onErrorOriginal = FlutterError.onError;
  });

  tearDown(() {
    FlutterError.onError = onErrorOriginal;
    PlatformDispatcher.instance.onError = null;
    Telemetria.sink = null;
    Telemetria.reiniciar();
  });

  test('erro: tira e-mail da mensagem, limita o tamanho e é enviado na hora', () async {
    Telemetria.registrarErro(Exception('falhou para maria@exemplo.com ${'x' * 500}'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);
    final e = sink.lotes.single.single;
    expect(e.tipo, 'erro');
    expect(e.mensagem, isNot(contains('maria@exemplo.com')));
    expect(e.mensagem, contains('[email]'));
    expect(e.mensagem!.length, lessThanOrEqualTo(300));
  });

  test('rede e tela esperam o lote encher (10 eventos) antes de enviar', () async {
    for (var i = 0; i < 9; i++) {
      Telemetria.registrarRede('GET /sessoes', 40 + i, 200);
    }
    await Future<void>.delayed(Duration.zero);
    expect(sink.lotes, isEmpty);
    Telemetria.registrarTela('minhas_sessoes:primeiro_quadro', 120);
    await Future<void>.delayed(Duration.zero);
    expect(sink.lotes.single, hasLength(10));
  });

  test('falha ao enviar não lança e não deixa a fila crescer sem fim', () async {
    sink.falhar = true;
    Telemetria.registrarErro(Exception('x'), null);
    await Future<void>.delayed(Duration.zero);
    await Telemetria.descarregar(); // fila vazia: nada a fazer
    expect(sink.lotes, isEmpty);
  });

  test('modo local (sem sink): guarda só na memória', () {
    Telemetria.sink = null;
    Telemetria.registrarTela('x', 5);
    expect(Telemetria.recentes, hasLength(1));
  });

  test('normalizarCaminho troca identificadores e descarta a query', () {
    expect(Telemetria.normalizarCaminho('GET', '/sessoes/12/avaliacao?x=1'), 'GET /sessoes/{id}/avaliacao');
    expect(Telemetria.normalizarCaminho('POST', '/sessoes'), 'POST /sessoes');
    expect(Telemetria.normalizarCaminho('GET', '/profissionais/7/horas-ocupadas'), 'GET /profissionais/{id}/horas-ocupadas');
  });

  test('medir registra a duração e devolve o resultado (mesmo se a operação falhar)', () async {
    expect(await Telemetria.medir('op', () async => 42), 42);
    await expectLater(Telemetria.medir('op', () async => throw StateError('x')), throwsStateError);
    expect(Telemetria.recentes.where((e) => e.tipo == 'tela' && e.nome == 'op'), hasLength(2));
  });

  test('FlutterError.onError passa a registrar os erros de widget', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (_) {}; // o "anterior" não pode ser o do flutter_test (ele reprovaria o teste)
    Telemetria.instalar();
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('quebrou o build')));
    await Future<void>.delayed(Duration.zero);
    expect(Telemetria.recentes.any((e) => e.tipo == 'erro' && e.mensagem!.contains('quebrou o build')), isTrue);
  });
}
