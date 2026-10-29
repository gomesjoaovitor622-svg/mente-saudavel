/// Versão dos Termos e da Política. MUDE ao alterar os textos: todo mundo precisará aceitar de novo.
const String kVersaoTermos = '2026-10';

/// Quem é o controlador dos dados e como falar com o encarregado (DPO). Defina no build:
/// `--dart-define=CONTROLADOR="Razão Social, CNPJ ..." --dart-define=CONTATO_LGPD=privacidade@seudominio.com.br`
const String kControlador = String.fromEnvironment('CONTROLADOR', defaultValue: 'Mente Saudável (versão de demonstração)');
const String kContatoLgpd = String.fromEnvironment('CONTATO_LGPD', defaultValue: 'defina CONTATO_LGPD no build');

class SecaoLegal {
  const SecaoLegal(this.titulo, this.texto);
  final String titulo;
  final String texto;
}

// ATENÇÃO: textos-modelo escritos para este projeto. Antes de usar com pacientes reais, o texto
// precisa ser revisado por advogado(a) e pelo(a) responsável técnico(a) (CRP).

const List<SecaoLegal> termosDeUso = [
  SecaoLegal('1. O que é o app',
      'O Mente Saudável conecta pacientes e psicólogos para agendar sessões, registrar o humor e acompanhar o histórico. O app NÃO presta atendimento de emergência.'),
  SecaoLegal('2. Em caso de crise',
      'Se você está em risco ou pensa em se machucar, procure ajuda imediata: no Brasil, ligue 188 (CVV, 24 h) ou 192 (SAMU), ou vá ao pronto-socorro mais próximo.'),
  SecaoLegal('3. Sua conta',
      'Você é responsável por manter sua senha em segredo e por informar dados verdadeiros. Profissionais declaram possuir registro ativo no Conselho Regional de Psicologia; essa declaração ainda não é verificada automaticamente pelo app.'),
  SecaoLegal('4. Uso adequado',
      'É proibido usar o app para fraude, assédio, para se passar por outra pessoa ou para tentar acessar dados de terceiros.'),
  SecaoLegal('5. Sessões e cancelamentos',
      'O agendamento reserva o horário com o profissional. Cancelamentos liberam o horário. Valores e condições de pagamento são combinados com o profissional.'),
  SecaoLegal('6. Encerramento',
      'Você pode encerrar sua conta a qualquer momento no Perfil. Podemos suspender contas que violem estes Termos.'),
];

const List<SecaoLegal> politicaDePrivacidade = [
  SecaoLegal('1. Quem trata seus dados', 'O controlador é: $kControlador. Contato do encarregado (LGPD): $kContatoLgpd.'),
  SecaoLegal('2. Quais dados',
      'Cadastro (nome, e-mail, senha protegida por hash), agendamentos, registros de humor e anotações que você escolher fazer, avaliações das sessões e, para profissionais, registro profissional, especialidade, endereço e valor da sessão. Dados de saúde mental são dados pessoais SENSÍVEIS (LGPD, art. 5º, II).'),
  SecaoLegal('3. Para que usamos',
      'Somente para prestar o serviço: agendar, mostrar seu histórico, permitir que o profissional acompanhe o atendimento e manter a segurança da conta (base legal: execução de contrato e consentimento, art. 7º, V e I; art. 11, I).'),
  SecaoLegal('4. Com quem compartilhamos',
      'Seu profissional vê seus agendamentos e as informações que você compartilha com ele. Não vendemos dados nem usamos para publicidade. O app consulta serviços públicos (BrasilAPI e ViaCEP) apenas com CEP e datas, sem identificar você.'),
  SecaoLegal('5. Medições técnicas',
      'Para corrigir falhas, o app envia erros e tempos de resposta SEM seu nome, e-mail ou dados de saúde (e-mails são removidos do texto dos erros).'),
  SecaoLegal('6. Por quanto tempo',
      'Mantemos seus dados enquanto a conta existir. Ao encerrar a conta, os dados que identificam você são anonimizados. O histórico das sessões fica sem identificação porque o profissional precisa guardar prontuário e registros financeiros por obrigação legal (art. 16, I).'),
  SecaoLegal('7. Seus direitos',
      'Você pode: confirmar e acessar seus dados; exportá-los (Perfil > Exportar meus dados); corrigir dados; eliminar a conta (Perfil > Excluir minha conta, que anonimiza seus dados); revogar o consentimento; e reclamar à ANPD (LGPD, art. 18).'),
  SecaoLegal('8. Segurança',
      'Conexão HTTPS, senhas com hash forte, sessão por cookie protegido (web) ou armazenamento seguro do aparelho (celular), limites contra tentativas em massa e registros técnicos sem dados pessoais.'),
  SecaoLegal('9. Alterações',
      'Se estes textos mudarem, pediremos seu aceite novamente. A versão aceita e a data ficam registradas na sua conta.'),
];
