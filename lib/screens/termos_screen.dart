import 'package:flutter/material.dart';
import 'package:mente_saudavel/legal/textos_legais.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Mostra um documento legal (Termos de Uso ou Política de Privacidade) em seções.
class DocumentoLegalScreen extends StatelessWidget {
  const DocumentoLegalScreen({super.key, required this.titulo, required this.secoes});

  final String titulo;
  final List<SecaoLegal> secoes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Versão $kVersaoTermos', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          for (final s in secoes) ...[
            Text(s.titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(s.texto),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

void abrirTermosDeUso(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DocumentoLegalScreen(titulo: 'Termos de Uso', secoes: termosDeUso)),
    );

void abrirPoliticaDePrivacidade(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DocumentoLegalScreen(titulo: 'Política de Privacidade', secoes: politicaDePrivacidade),
      ),
    );

/// Tela de aceite OBRIGATÓRIO: não há como seguir sem marcar a caixa e aceitar.
/// Aparece no primeiro acesso e sempre que a versão dos textos muda.
class TermosScreen extends StatefulWidget {
  const TermosScreen({super.key, required this.aoAceitar});

  /// Chamado ao aceitar (grava o aceite no aparelho e/ou na conta).
  final Future<void> Function() aoAceitar;

  @override
  State<TermosScreen> createState() => _TermosScreenState();
}

class _TermosScreenState extends State<TermosScreen> {
  bool _marcado = false;
  bool _salvando = false;

  Future<void> _aceitar() async {
    setState(() => _salvando = true);
    try {
      await widget.aoAceitar();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      mostrarMensagem(context, e.mensagem, erro: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _salvando = false);
      mostrarMensagem(context, 'Não foi possível registrar o aceite. Tente novamente.', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.verified_user_outlined, size: 56, color: verdeMarca),
                const SizedBox(height: 12),
                Text('Sua privacidade importa', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text(
                  'O Mente Saudável trata dados de saúde mental, que são dados sensíveis. Para continuar, leia e aceite '
                  'os Termos de Uso e a Política de Privacidade. Você pode excluir sua conta a qualquer momento.',
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Ler os Termos de Uso'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => abrirTermosDeUso(context),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Ler a Política de Privacidade'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => abrirPoliticaDePrivacidade(context),
                ),
                CheckboxListTile(
                  key: const Key('aceite-termos'),
                  value: _marcado,
                  onChanged: _salvando ? null : (v) => setState(() => _marcado = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Li e aceito os Termos de Uso e a Política de Privacidade'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('botao-aceitar'),
                  onPressed: _marcado && !_salvando ? _aceitar : null,
                  child: _salvando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Aceitar e continuar'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sem o aceite não é possível usar o app.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
