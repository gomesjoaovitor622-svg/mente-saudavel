import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Banco local DESCARTÁVEL (em memória) para o app inteiro: o mesmo `DatabaseHelper` que o app usa,
/// com o esquema real (migrações incluídas), sem celular. Chame no `setUp`.
Future<void> prepararBancoLocal() async {
  SharedPreferences.setMockInitialValues({});
  DatabaseHelper.caminhoParaTestes = inMemoryDatabasePath;
  await DatabaseHelper.instance.reiniciar();
  AuthService.atual.value = null;
}
