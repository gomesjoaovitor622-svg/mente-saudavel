import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/services/video_service.dart';
import 'package:mente_saudavel/utils/app_exception.dart';

http.Response _json(int status, Object corpo) =>
    http.Response.bytes(utf8.encode(jsonEncode(corpo)), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late List<http.Request> recebidas;

  tearDown(() => ApiClient.cliente = http.Client());

  void servidor(http.Response Function(http.Request) resposta) {
    recebidas = [];
    ApiClient.cliente = MockClient((req) async {
      recebidas.add(req);
      return resposta(req);
    });
  }

  test('pede a sala da sessão ao servidor e entende a resposta', () async {
    servidor((_) => _json(200, {
          'url': 'https://video.exemplo.com/ms-abc?jwt=token',
          'sala': 'ms-abc',
          'moderador': true,
          'expira_em': '2031-01-12T11:00:00',
        }));
    final sala = await VideoService.obterSala(42);
    expect(recebidas.single.method, 'GET');
    expect(recebidas.single.url.path, endsWith('/sessoes/42/video'));
    expect(sala.url.host, 'video.exemplo.com');
    expect(sala.moderador, isTrue);
    expect(sala.expiraEm, DateTime(2031, 1, 12, 11));
  });

  test('sala ainda fechada: a mensagem do servidor chega pronta para a tela', () async {
    servidor((_) => _json(409, {'detail': 'A sala abre às 09:45 de 12/01.'}));
    await expectLater(
      VideoService.obterSala(42),
      throwsA(isA<AppException>().having((e) => e.mensagem, 'mensagem', contains('A sala abre às 09:45'))),
    );
  });

  test('vídeo desligado no servidor (503) vira erro com mensagem', () async {
    servidor((_) => _json(503, {'detail': 'A videochamada não está configurada neste servidor.'}));
    await expectLater(VideoService.obterSala(1), throwsA(isA<AppException>().having((e) => e.statusHttp, 'status', 503)));
  });

  test('sem rede: erro de conexão, sem travar', () async {
    ApiClient.cliente = MockClient((_) async => throw http.ClientException('sem rede'));
    await expectLater(VideoService.obterSala(1), throwsA(isA<AppException>()));
  });

  test('o abridor de link pode ser trocado (testes não abrem navegador)', () async {
    final abertos = <Uri>[];
    final original = VideoService.abrir;
    VideoService.abrir = (u) async {
      abertos.add(u);
      return true;
    };
    addTearDown(() => VideoService.abrir = original);
    expect(await VideoService.abrir(Uri.parse('https://video.exemplo.com/ms-abc')), isTrue);
    expect(abertos, hasLength(1));
  });
}
