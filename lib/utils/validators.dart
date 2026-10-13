import 'package:mente_saudavel/utils/build_flags.dart';

/// O servidor exige 8+ caracteres; no modo local bastam 6.
const int tamanhoMinimoSenha = usaServidor ? 8 : 6;

String? validarNome(String? valor) {
  final texto = valor?.trim() ?? '';
  if (texto.isEmpty) return 'Informe seu nome.';
  if (texto.length < 2) return 'O nome deve ter pelo menos 2 caracteres.';
  return null;
}

String? validarEmail(String? valor) {
  final texto = valor?.trim() ?? '';
  if (texto.isEmpty) return 'Informe o e-mail.';
  final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  if (!regex.hasMatch(texto)) return 'Informe um e-mail válido.';
  return null;
}

String? validarSenha(String? valor) {
  final texto = valor ?? '';
  if (texto.isEmpty) return 'Informe a senha.';
  if (texto.length < tamanhoMinimoSenha) {
    return 'A senha deve ter pelo menos $tamanhoMinimoSenha caracteres.';
  }
  return null;
}
