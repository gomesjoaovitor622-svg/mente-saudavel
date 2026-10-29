import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onde o token de login fica guardado entre aberturas do app.
///
/// * Celular: [TokenStoreSeguro] (Android Keystore / iOS Keychain, criptografado).
/// * Web: NÃO se guarda token no navegador. O servidor entrega um cookie `HttpOnly`, que o
///   JavaScript da página não consegue ler (nem um script injetado por XSS). Ver [TokenStoreWeb].
abstract interface class TokenStore {
  Future<String?> ler();
  Future<void> gravar(String token);
  Future<void> apagar();
}

class TokenStoreSeguro implements TokenStore {
  TokenStoreSeguro({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  static const String _chave = 'ms_token';
  static const String _chaveLegada = 'ms_token'; // nome usado quando o token ficava no SharedPreferences

  final FlutterSecureStorage _storage;

  @override
  Future<String?> ler() async {
    final atual = await _storage.read(key: _chave);
    if (atual != null) return atual;
    return _migrarDoSharedPreferences();
  }

  @override
  Future<void> gravar(String token) => _storage.write(key: _chave, value: token);

  @override
  Future<void> apagar() async {
    await _storage.delete(key: _chave);
    await removerLegado();
  }

  /// Versões antigas guardavam o token em texto puro no SharedPreferences. Move para o
  /// armazenamento seguro e apaga a cópia antiga (uma vez só).
  Future<String?> _migrarDoSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final legado = prefs.getString(_chaveLegada);
    if (legado == null) return null;
    await _storage.write(key: _chave, value: legado);
    await prefs.remove(_chaveLegada);
    return legado;
  }

  /// Apaga o token antigo em texto puro, se existir.
  static Future<void> removerLegado() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_chaveLegada);
    } catch (_) {
      // Sem SharedPreferences: nada a limpar.
    }
  }
}

/// Web: o navegador guarda e envia o cookie `HttpOnly`; o app não toca no token.
/// Só limpa um token antigo que versões anteriores gravaram no localStorage.
class TokenStoreWeb implements TokenStore {
  @override
  Future<String?> ler() async {
    await TokenStoreSeguro.removerLegado();
    return null;
  }

  @override
  Future<void> gravar(String token) async {}

  @override
  Future<void> apagar() => TokenStoreSeguro.removerLegado();
}
