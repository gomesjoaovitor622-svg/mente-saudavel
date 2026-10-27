# Videochamada das sessões online

## Como funciona
O servidor **não transmite vídeo**. Ele decide *quem* pode entrar e *quando*, e entrega um link com token de curta duração para um servidor **Jitsi Meet** (vídeo ponta a ponta entre os participantes, pelo navegador).

`GET /sessoes/{id}/video` (autenticado) devolve `{ url, sala, moderador, expira_em }` quando **todas** as condições valem:
- quem pede é o paciente ou o profissional **daquela** sessão (senão, 404 — não revela sessões alheias);
- a sessão é **Online** (presencial → 409) e está **agendada** (cancelada/concluída → 409);
- estamos na janela do horário: `VIDEO_ANTES_MIN` (padrão 15) antes até `VIDEO_DEPOIS_MIN` (padrão 120) depois (fora dela → 409 com a hora de abertura);
- o recurso está configurado (`VIDEO_DOMAIN`; senão 503).

Segurança:
- O nome da sala é `ms-` + HMAC-SHA256 (derivado de `JWT_SECRET`, id da sessão, participantes e data de criação): **imprevisível** e estável para a mesma sessão.
- O token JWT (HS256, `aud=jitsi`, `iss=VIDEO_APP_ID`, `sub=VIDEO_DOMAIN`, `room`) vale só para aquela sala e expira ao fim da janela. O profissional entra como **moderador**; o paciente aparece só pelo **primeiro nome**.
- O log registra apenas `sessao_id` e `usuario_id` — **nunca** a URL nem o token.
- No app, o botão "Entrar na videochamada" pede o link ao servidor e o abre no navegador do aparelho (que pede câmera/microfone). Se o navegador não abrir, o link é copiado.

> **Modo local (sem servidor)**: o app ainda mostra "Copiar link da videochamada" com uma sala pública derivada do id da sessão. Isso **não é seguro** (a sala é calculável e o Jitsi público não tem senha). Serve só para demonstração; para atendimento real use o modo servidor.

## Onde o recurso aparece (site x APK)
| Versão | Vídeo e prontuário | Condição |
|---|---|---|
| **Site (Flutter web)** | Sim | O site é compilado com `API_URL=/api` (modo servidor). Testado no CI por navegador (botão abre nova aba com o link do servidor; tela de prontuário cria e lista registros) |
| **APK** | Sim, **se compilado com `API_URL`** | Sem `API_URL` o APK roda em modo LOCAL (SQLite no aparelho): não há prontuário nem link seguro de vídeo. Defina a variável do repositório `API_URL` (Settings → Secrets and variables → Actions → Variables) ou compile com `--dart-define-from-file=env/producao.json` |

No site, o navegador pode bloquear a nova aba (bloqueador de pop-up, principalmente no Safari): nesse caso o link é copiado para a área de transferência.

| Variável | Para que serve |
|---|---|
| `VIDEO_DOMAIN` | Domínio do SEU servidor Jitsi, ex.: `video.seudominio.com.br` (vazio = recurso desligado) |
| `VIDEO_APP_ID` | Deve ser igual a `JWT_APP_ID` do Jitsi (padrão `mente-saudavel`) |
| `VIDEO_APP_SECRET` | Deve ser igual a `JWT_APP_SECRET` do Jitsi. `openssl rand -hex 32` |
| `VIDEO_ANTES_MIN` / `VIDEO_DEPOIS_MIN` | Janela em que a sala abre |

## Jitsi próprio (recomendado)
Não use `meet.jit.si` para atendimentos: é um serviço público, sem autenticação por sala e fora do seu controle (dados de saúde).
1. VPS **separada** (ou subdomínio dedicado), com 4 GB+ de RAM, portas **443/TCP** e **10000/UDP** liberadas e DNS `video.seudominio.com.br`.
2. Siga a instalação oficial por Docker do Jitsi (`jitsi/docker-jitsi-meet`) e, no `.env` dele, ative a autenticação por JWT:
   ```
   ENABLE_AUTH=1
   AUTH_TYPE=jwt
   JWT_APP_ID=mente-saudavel
   JWT_APP_SECRET=<o mesmo VIDEO_APP_SECRET>
   JWT_ACCEPTED_ISSUERS=mente-saudavel
   JWT_ACCEPTED_AUDIENCES=jitsi
   ENABLE_GUESTS=0
   ```
   Desative gravação e transmissão (Jibri) e a página inicial pública.
3. No `deploy/.env` do app preencha `VIDEO_DOMAIN`, `VIDEO_APP_ID`, `VIDEO_APP_SECRET` e rode `docker compose -f docker-compose.prod.yml up -d`.
4. Teste: agende uma sessão Online para daqui a 5 minutos nas duas contas e entre pelos dois aparelhos.

Alternativa gerenciada (paga): serviços como o JaaS (8x8) usam outro formato de token (com `kid` e o app id no caminho da URL) e **não** são compatíveis sem ajuste em `app/video.py`.

## LGPD / ética (validar com responsável jurídico e conselho profissional)
- Não grave as sessões; avise o paciente de que o atendimento é por vídeo e registre o consentimento nos termos.
- Oriente o paciente a usar ambiente privado e rede confiável.
- O servidor Jitsi trata áudio e vídeo em trânsito: inclua-o no inventário de tratamentos e na política de privacidade.

## O que NÃO foi verificado
O código gera o token no formato do Jitsi com autenticação JWT e há testes automatizados do contrato (`server/tests/test_video.py`), mas **nenhum servidor Jitsi real, câmera ou celular foi usado nos testes**. Faça o teste do passo 4 antes de usar com pacientes.
