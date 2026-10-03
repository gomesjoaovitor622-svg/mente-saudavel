import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mente_saudavel/database/database_factory_setup.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/screens/login_screen.dart';
import 'package:mente_saudavel/screens/paciente/paciente_home_screen.dart';
import 'package:mente_saudavel/screens/profissional/profissional_home_screen.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

Future<void> main() async {
  // Necessário antes de usar plugins nativos (como o sqflite).
  WidgetsFlutterBinding.ensureInitialized();
  // Celular: não faz nada. Web: ativa o SQLite do navegador.
  await configurarBanco();
  runApp(const MenteSaudavelApp());
}

class MenteSaudavelApp extends StatelessWidget {
  const MenteSaudavelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mente Saudável',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: verdeMarca),
        scaffoldBackgroundColor: const Color(0xFFF6F8F5),
      ),
      // Calendário e relógio em português.
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}

/// Decide qual tela mostrar: login, painel do paciente ou do profissional.
/// Abre o banco, restaura o login salvo e "escuta" mudanças (login/logout).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<void> _inicio;

  @override
  void initState() {
    super.initState();
    _inicio = AuthService.carregarSessao();
  }

  void _tentarNovamente() {
    setState(() {
      _inicio = AuthService.carregarSessao();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _inicio,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 56, color: Colors.red),
                    const SizedBox(height: 12),
                    const Text('Não foi possível abrir o banco de dados.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _tentarNovamente,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return ValueListenableBuilder<Usuario?>(
          valueListenable: AuthService.atual,
          builder: (context, usuario, _) {
            if (usuario == null) return const LoginScreen();
            if (usuario.isProfissional) {
              return ProfissionalHomeScreen(key: ValueKey('pro${usuario.id}'));
            }
            return PacienteHomeScreen(key: ValueKey('pac${usuario.id}'));
          },
        );
      },
    );
  }
}
