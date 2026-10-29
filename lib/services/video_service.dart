import 'package:mente_saudavel/services/api_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sala de videochamada liberada pelo servidor para UMA sessão.
class SalaVideo {
  const SalaVideo({required this.url, required this.moderador, required this.expiraEm});

  /// Link com token de curta duração (não registre nem compartilhe: quem tem o link entra).
  final Uri url;
  final bool moderador;
  final DateTime expiraEm;

  factory SalaVideo.fromMap(Map<String, Object?> m) => SalaVideo(
        url: Uri.parse(m['url']! as String),
        moderador: m['moderador'] == true,
        expiraEm: DateTime.parse(m['expira_em']! as String),
      );
}

/// Videochamada das sessões online. O servidor decide QUEM entra e QUANDO (só os dois participantes,
/// numa janela ao redor do horário) e devolve um link imprevisível; o vídeo em si roda no servidor Jitsi.
/// A chamada abre no navegador do aparelho, que cuida das permissões de câmera e microfone.
class VideoService {
  /// Troque nos testes para não abrir navegador de verdade.
  static Future<bool> Function(Uri url) abrir = (url) => launchUrl(url, mode: LaunchMode.externalApplication);

  /// Pede a sala ao servidor. Erros (sala ainda fechada, sessão cancelada, vídeo desligado) chegam como
  /// `AppException` com a mensagem do servidor, pronta para mostrar na tela.
  static Future<SalaVideo> obterSala(int sessaoId) async {
    final r = await ApiClient.get('/sessoes/$sessaoId/video');
    return SalaVideo.fromMap(Map<String, Object?>.from(r as Map));
  }
}
