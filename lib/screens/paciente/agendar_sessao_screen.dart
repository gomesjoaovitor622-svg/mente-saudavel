import 'package:flutter/material.dart';
import 'package:mente_saudavel/database/sessao_dao.dart';
import 'package:mente_saudavel/database/usuario_dao.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/api_service.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/formatters.dart';
import 'package:mente_saudavel/widgets/componentes.dart';

/// Agendamento: escolhe profissional, data, horário e modalidade.
/// Os horários já ocupados vêm do banco; os feriados vêm da BrasilAPI.
class AgendarSessaoScreen extends StatefulWidget {
  const AgendarSessaoScreen({super.key});

  @override
  State<AgendarSessaoScreen> createState() => _AgendarSessaoScreenState();
}

class _AgendarSessaoScreenState extends State<AgendarSessaoScreen> {
  static const List<int> _horarios = [8, 9, 10, 11, 13, 14, 15, 16, 17, 18];

  final UsuarioDao _usuarioDao = UsuarioDao();
  final SessaoDao _sessaoDao = SessaoDao();

  List<Usuario> _profissionais = [];
  Usuario? _profissional;
  DateTime? _data;
  int? _hora;
  String _modalidade = Modalidade.online;
  Set<int> _ocupadas = {};
  String? _feriado;

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarProfissionais();
  }

  Future<void> _carregarProfissionais() async {
    try {
      final lista = await _usuarioDao.listarProfissionais();
      if (!mounted) return;
      setState(() {
        _profissionais = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, 'Erro ao carregar os profissionais.', erro: true);
    }
  }

  Future<void> _atualizarDisponibilidade() async {
    final profissional = _profissional;
    final data = _data;
    if (profissional == null || data == null) return;
    try {
      final ocupadas = await _sessaoDao.horasOcupadas(profissional.id!, data);
      if (!mounted) return;
      setState(() {
        _ocupadas = ocupadas;
        if (_hora != null && ocupadas.contains(_hora)) _hora = null;
      });
    } catch (_) {
      if (!mounted) return;
      mostrarMensagem(context, 'Erro ao consultar os horários.', erro: true);
    }
  }

  Future<void> _escolherProfissional(Usuario profissional) async {
    setState(() {
      _profissional = profissional;
      _hora = null;
    });
    await _atualizarDisponibilidade();
  }

  Future<void> _escolherData() async {
    final agora = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _data ?? agora,
      firstDate: somenteData(agora),
      lastDate: agora.add(const Duration(days: 365)),
    );
    if (escolhida == null || !mounted) return;

    setState(() {
      _data = escolhida;
      _hora = null;
      _feriado = null;
    });
    await _atualizarDisponibilidade();

    // API BrasilAPI: avisa se a data é feriado nacional (opcional, online).
    final feriados = await ApiService.feriados(escolhida.year);
    if (!mounted) return;
    final atual = _data;
    if (atual != null && mesmoDia(atual, escolhida)) {
      setState(() => _feriado = feriados[chaveData(escolhida)]);
    }
  }

  Future<void> _confirmar() async {
    final profissional = _profissional;
    final data = _data;
    final hora = _hora;
    if (profissional == null || data == null || hora == null) {
      mostrarMensagem(context, 'Escolha o profissional, a data e o horário.', erro: true);
      return;
    }

    final dataHora = DateTime(data.year, data.month, data.day, hora);
    final pacienteId = AuthService.atual.value!.id!;
    setState(() => _salvando = true);

    try {
      // Confere de novo no banco, para evitar horário duplicado.
      final conflito = await _sessaoDao.verificarConflito(
        profissionalId: profissional.id!,
        pacienteId: pacienteId,
        dataHora: dataHora,
      );
      if (conflito != null) {
        if (!mounted) return;
        setState(() => _salvando = false);
        mostrarMensagem(context, conflito, erro: true);
        await _atualizarDisponibilidade();
        return;
      }

      await _sessaoDao.inserir(
        Sessao(
          pacienteId: pacienteId,
          profissionalId: profissional.id!,
          dataHora: dataHora,
          modalidade: _modalidade,
          status: StatusSessao.agendada,
        ),
      );
      if (!mounted) return;
      mostrarMensagem(context, 'Sessão agendada com sucesso!');
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _salvando = false);
      mostrarMensagem(context, 'Erro ao agendar a sessão.', erro: true);
    }
  }

  Widget _titulo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }

  Widget _cartaoProfissional(Usuario p) {
    final selecionado = _profissional?.id == p.id;
    final registro = p.registro ?? '';
    final especialidade = p.especialidade ?? '';
    final detalhes = [
      if (registro.isNotEmpty) 'CRP $registro',
      if (especialidade.isNotEmpty) especialidade,
    ].join(' · ');

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selecionado ? verdeMarca : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: const Icon(Icons.person, color: verdeMarca),
        ),
        title: Text(p.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: detalhes.isEmpty ? null : Text(detalhes),
        trailing: selecionado ? const Icon(Icons.check_circle, color: verdeMarca) : null,
        onTap: () => _escolherProfissional(p),
      ),
    );
  }

  Widget _horariosWidget() {
    if (_profissional == null || _data == null) {
      return Text(
        'Escolha o profissional e a data para ver os horários.',
        style: TextStyle(color: Colors.grey.shade700),
      );
    }
    final agora = DateTime.now();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _horarios.map((h) {
        final ocupado = _ocupadas.contains(h);
        final passou = mesmoDia(_data!, agora) && h <= agora.hour;
        final indisponivel = ocupado || passou;
        return ChoiceChip(
          label: Text('${doisDigitos(h)}:00'),
          selected: _hora == h,
          onSelected: indisponivel ? null : (_) => setState(() => _hora = h),
        );
      }).toList(),
    );
  }

  Widget _enderecoPresencial() {
    final endereco = _profissional?.endereco ?? '';
    if (_modalidade != Modalidade.presencial || _profissional == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        endereco.isEmpty
            ? 'Este profissional ainda não informou o endereço do consultório.'
            : 'Local: $endereco',
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agendar sessão')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _titulo('1. Profissional'),
                if (_profissionais.isEmpty)
                  const Text('Nenhum profissional cadastrado.')
                else
                  ..._profissionais.map(_cartaoProfissional),
                _titulo('2. Data'),
                OutlinedButton.icon(
                  onPressed: _escolherData,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(_data == null ? 'Escolher data' : formatarDataExtenso(_data!)),
                ),
                if (_feriado != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Feriado nacional: $_feriado. Confirme a disponibilidade.'),
                        ),
                      ],
                    ),
                  ),
                _titulo('3. Horário'),
                _horariosWidget(),
                _titulo('4. Modalidade'),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: Modalidade.online,
                      label: Text('Online'),
                      icon: Icon(Icons.videocam_outlined),
                    ),
                    ButtonSegment(
                      value: Modalidade.presencial,
                      label: Text('Presencial'),
                      icon: Icon(Icons.place_outlined),
                    ),
                  ],
                  selected: {_modalidade},
                  onSelectionChanged: (selecao) => setState(() => _modalidade = selecao.first),
                ),
                _enderecoPresencial(),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _salvando ? null : _confirmar,
                    icon: const Icon(Icons.check),
                    label: Text(_salvando ? 'Agendando...' : 'Confirmar agendamento'),
                  ),
                ),
              ],
            ),
    );
  }
}
