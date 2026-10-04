import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mente_saudavel/database/db_inspector.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Tela para olhar o banco SQLite do app: tabelas, estrutura, dados,
/// consultas SELECT e exportação do script SQL. Somente leitura.
class BancoScreen extends StatefulWidget {
  const BancoScreen({super.key});

  @override
  State<BancoScreen> createState() => _BancoScreenState();
}

class _BancoScreenState extends State<BancoScreen> {
  final DbInspector _inspector = DbInspector();
  final TextEditingController _sql = TextEditingController(text: 'SELECT * FROM usuarios');

  List<String> _tabelas = [];
  final Map<String, int> _contagens = {};
  String? _tabela;
  ResultadoConsulta? _estrutura;
  ResultadoConsulta? _dados;
  ResultadoConsulta? _resultadoSql;
  String? _erroSql;
  bool _carregando = true;
  bool _executando = false;

  @override
  void initState() {
    super.initState();
    _carregarTabelas();
  }

  @override
  void dispose() {
    _sql.dispose();
    super.dispose();
  }

  Future<void> _carregarTabelas() async {
    try {
      final tabelas = await _inspector.listarTabelas();
      for (final t in tabelas) {
        _contagens[t] = await _inspector.contar(t);
      }
      if (!mounted) return;
      setState(() {
        _tabelas = tabelas;
        _carregando = false;
      });
      if (tabelas.isNotEmpty) {
        await _selecionar(tabelas.contains('usuarios') ? 'usuarios' : tabelas.first);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, 'Erro ao ler o banco de dados.', erro: true);
    }
  }

  Future<void> _selecionar(String tabela) async {
    try {
      final estrutura = await _inspector.estrutura(tabela);
      final dados = await _inspector.dados(tabela);
      if (!mounted) return;
      setState(() {
        _tabela = tabela;
        _estrutura = estrutura;
        _dados = dados;
      });
    } catch (_) {
      if (!mounted) return;
      mostrarMensagem(context, 'Erro ao ler a tabela $tabela.', erro: true);
    }
  }

  Future<void> _executarSql() async {
    setState(() {
      _executando = true;
      _erroSql = null;
    });
    try {
      final resultado = await _inspector.consultar(_sql.text);
      if (!mounted) return;
      setState(() {
        _resultadoSql = resultado;
        _executando = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _resultadoSql = null;
        _erroSql = e.mensagem;
        _executando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultadoSql = null;
        _erroSql = 'Erro na consulta: $e';
        _executando = false;
      });
    }
  }

  Future<void> _exportar() async {
    try {
      final texto = await _inspector.gerarDump();
      await Clipboard.setData(ClipboardData(text: texto));
      if (!mounted) return;
      mostrarMensagem(context, 'Script SQL copiado para a área de transferência.');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Script SQL do banco'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(texto, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: texto));
                if (ctx.mounted) {
                  mostrarMensagem(ctx, 'Copiado!');
                }
              },
              child: const Text('Copiar de novo'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      mostrarMensagem(context, 'Erro ao gerar o script SQL.', erro: true);
    }
  }

  Widget _titulo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }

  Widget _tabelaDados(ResultadoConsulta resultado) {
    if (resultado.colunas.isEmpty) {
      return Text('Nenhum resultado.', style: TextStyle(color: Colors.grey.shade700));
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          columns: resultado.colunas
              .map(
                (c) => DataColumn(
                  label: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              )
              .toList(),
          rows: resultado.linhas
              .map(
                (linha) => DataRow(
                  cells: linha
                      .map(
                        (valor) => DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              valor == null ? 'NULL' : valor.toString(),
                              overflow: TextOverflow.ellipsis,
                              style: valor == null
                                  ? TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic)
                                  : null,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dados = _dados;
    final estrutura = _estrutura;
    final resultadoSql = _resultadoSql;

    return Scaffold(
      appBar: AppBar(title: const Text('Banco de dados (SQLite)')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Banco: mente_saudavel.db (SQLite).\n'
                      'Fica guardado neste aparelho/navegador. Esta tela é somente leitura, '
                      'e as senhas (senha_hash e salt) ficam ocultas.',
                      style: TextStyle(color: Colors.grey.shade800),
                    ),
                  ),
                ),
                _titulo('Tabelas'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tabelas
                      .map(
                        (t) => ChoiceChip(
                          label: Text('$t (${_contagens[t] ?? 0})'),
                          selected: _tabela == t,
                          onSelected: (_) => _selecionar(t),
                        ),
                      )
                      .toList(),
                ),
                if (_tabela != null && estrutura != null) ...[
                  _titulo('Estrutura de $_tabela'),
                  _tabelaDados(estrutura),
                ],
                if (_tabela != null && dados != null) ...[
                  _titulo('Dados de $_tabela (até 200 linhas)'),
                  _tabelaDados(dados),
                ],
                _titulo('Consulta SQL (somente leitura)'),
                TextField(
                  controller: _sql,
                  maxLines: 4,
                  minLines: 2,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: campo('SELECT ...', dica: 'Ex.: SELECT * FROM sessoes'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _executando ? null : _executarSql,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_executando ? 'Executando...' : 'Executar consulta'),
                ),
                if (_erroSql != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_erroSql!, style: TextStyle(color: Colors.red.shade700)),
                  ),
                if (resultadoSql != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${resultadoSql.linhas.length} linha(s)',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 4),
                  _tabelaDados(resultadoSql),
                ],
                _titulo('Exportar'),
                OutlinedButton.icon(
                  onPressed: _exportar,
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Copiar script SQL completo'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
