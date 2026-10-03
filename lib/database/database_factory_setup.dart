/// Prepara o SQLite para a plataforma.
///
/// No Android/iOS o sqflite já usa o SQLite nativo, então não há nada a fazer.
/// Na versão WEB, o workflow "Publicar versão Web" troca este arquivo por
/// web_overrides/database_factory_setup.web.txt, que ativa o SQLite do navegador.
Future<void> configurarBanco() async {}
