import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/models/avaliacao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/utils/formatters.dart';

void main() {
  group('formatarReais', () {
    test('formata centavos em reais', () {
      expect(formatarReais(0), 'R\$ 0,00');
      expect(formatarReais(5), 'R\$ 0,05');
      expect(formatarReais(15000), 'R\$ 150,00');
      expect(formatarReais(123456), 'R\$ 1.234,56');
      expect(formatarReais(100000000), 'R\$ 1.000.000,00');
    });
  });

  group('centavosDeTexto', () {
    test('aceita vírgula, ponto e inteiros', () {
      expect(centavosDeTexto('150'), 15000);
      expect(centavosDeTexto('150,5'), 15050);
      expect(centavosDeTexto('150.50'), 15050);
      expect(centavosDeTexto('  99,99 '), 9999);
      expect(centavosDeTexto('0'), 0);
    });

    test('recusa vazio, texto, negativo e acima de R\$ 10.000', () {
      expect(centavosDeTexto(''), isNull);
      expect(centavosDeTexto('abc'), isNull);
      expect(centavosDeTexto('-1'), isNull);
      expect(centavosDeTexto('10000,01'), isNull);
      expect(centavosDeTexto('10000'), 1000000);
    });
  });

  group('modelos lendo o JSON da API', () {
    test('Usuario traz o preço da sessão', () {
      final u = Usuario.fromMap({
        'id': 1,
        'nome': 'Dra. Helena',
        'email': 'h@x.com',
        'perfil': 'profissional',
        'valor_sessao_centavos': 15000,
      });
      expect(u.valorSessaoCentavos, 15000);
      expect(u.copyWith(valorSessaoCentavos: 20000).valorSessaoCentavos, 20000);
    });

    test('Sessao sem preço (modo local) vale 0', () {
      final s = Sessao.fromMap({
        'id': 1,
        'paciente_id': 1,
        'profissional_id': 2,
        'data_hora': '2026-10-14T10:00:00',
        'modalidade': 'Online',
        'status': 'agendada',
      });
      expect(s.valorCentavos, 0);
    });

    test('ProfissionalResumo traz preço e nota média', () {
      final p = ProfissionalResumo.fromMap({
        'id': 2,
        'nome': 'Dr. Rafael',
        'valor_sessao_centavos': 12000,
        'media': 4.5,
        'total': 2,
      });
      expect(p.valorSessaoCentavos, 12000);
      expect(p.media, 4.5);
      expect(p.totalAvaliacoes, 2);
    });
  });
}
