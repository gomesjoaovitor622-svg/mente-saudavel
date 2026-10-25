import 'package:flutter/foundation.dart';
import 'package:mente_saudavel/legal/textos_legais.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aceite dos Termos de Uso e da Política de Privacidade neste aparelho/navegador.
///
/// O aceite é pedido ANTES do login/cadastro (primeiro acesso). Na conta (servidor ou banco local)
/// a versão aceita e a data também ficam gravadas: essa é a prova do consentimento.
class Consentimento {
  static const String _chaveVersao = 'ms_aceite_versao';
  static const String _chaveData = 'ms_aceite_em';

  /// `true` = este aparelho já aceitou a versão ATUAL dos textos.
  static final ValueNotifier<bool> aceitoNoAparelho = ValueNotifier<bool>(false);

  static Future<void> carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      aceitoNoAparelho.value = prefs.getString(_chaveVersao) == kVersaoTermos;
    } catch (_) {
      // Sem armazenamento (ex.: navegador privativo): pede o aceite a cada abertura.
      aceitoNoAparelho.value = false;
    }
  }

  static Future<void> aceitarNoAparelho() async {
    aceitoNoAparelho.value = true; // libera a tela mesmo se não conseguir gravar
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_chaveVersao, kVersaoTermos);
      await prefs.setString(_chaveData, DateTime.now().toIso8601String());
    } catch (_) {}
  }
}
