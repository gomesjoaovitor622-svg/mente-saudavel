import 'package:flutter/material.dart';
import 'package:mente_saudavel/screens/paciente/humor_tab.dart';
import 'package:mente_saudavel/screens/paciente/minhas_sessoes_tab.dart';
import 'package:mente_saudavel/screens/paciente/paciente_inicio_tab.dart';
import 'package:mente_saudavel/screens/perfil_tab.dart';

/// Estrutura do paciente: barra de navegação com 4 abas.
class PacienteHomeScreen extends StatefulWidget {
  const PacienteHomeScreen({super.key});

  @override
  State<PacienteHomeScreen> createState() => _PacienteHomeScreenState();
}

class _PacienteHomeScreenState extends State<PacienteHomeScreen> {
  int _indice = 0;

  void _irPara(int indice) => setState(() => _indice = indice);

  // A aba é recriada ao trocar, então sempre recarrega os dados do banco.
  Widget _aba() {
    switch (_indice) {
      case 0:
        return PacienteInicioTab(onVerSessoes: () => _irPara(1));
      case 1:
        return const MinhasSessoesTab();
      case 2:
        return const HumorTab();
      default:
        return const PerfilTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _aba(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: _irPara,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Sessões',
          ),
          NavigationDestination(
            icon: Icon(Icons.mood_outlined),
            selectedIcon: Icon(Icons.mood),
            label: 'Humor',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
