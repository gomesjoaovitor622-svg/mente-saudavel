import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

void main() {
  test('o inspetor do banco só existe em build de demonstração sem servidor', () {
    expect(kMostrarInspetorDeBanco, kDemoMode && !usaServidor);
  });

  test('build padrão (produção, sem --dart-define) não expõe o inspetor do banco', () {
    // Os testes rodam sem DEMO_MODE: se alguém trocar o padrão para true, este teste avisa.
    expect(kDemoMode, isFalse);
    expect(kMostrarInspetorDeBanco, isFalse);
  });
}
