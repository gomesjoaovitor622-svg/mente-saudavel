import 'package:flutter/material.dart';
import 'package:mente_saudavel/screens/perfil_tab.dart';
import 'package:mente_saudavel/screens/profissional/agenda_tab.dart';
import 'package:mente_saudavel/screens/profissional/pacientes_tab.dart';
import 'package:mente_saudavel/screens/profissional/painel_tab.dart';

/// Estrutura do profissional: barra de navegação com 4 abas.
class ProfissionalHomeScreen extends StatefulWidget {
  const ProfissionalHomeScreen({super.key});

  @override
  State<ProfissionalHomeScreen> createState() => _ProfissionalHomeScreenState();
}

class _ProfissionalHomeScreenState extends State<ProfissionalHomeScreen> {
  int _indice = 0;

  void _irPara(int indice) => setState(() => _indice = indice);

  Widget _aba() {
    switch (_indice) {
      case 0:
        return PainelTab(onVerAgenda: () => _irPara(1));
      case 1:
        return const AgendaTab();
      case 2:
        return const PacientesTab();
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
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Painel',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Pacientes',
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
