import 'package:flutter/foundation.dart';

/// "Agora" da interface. Existe só para os testes fixarem a data (ex.: calendário e horários
/// que dependem de a hora ter passado). Em produção é sempre `DateTime.now()`.
class Relogio {
  Relogio._();

  static DateTime _real() => DateTime.now();

  @visibleForTesting
  static DateTime Function() fonte = _real;

  static DateTime agora() => fonte();

  @visibleForTesting
  static void restaurar() => fonte = _real;
}
