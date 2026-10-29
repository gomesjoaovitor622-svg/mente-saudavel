# Checklist de lançamento — o que só você pode fazer

O código dos itens 1, 2 e 4 está pronto (aprovação de profissional, e-mail, fuso). Os demais dependem de decisão, contrato ou acesso seu.

## 1. Aprovar profissionais (feito no código)
Profissional novo fica "em análise": não aparece na busca nem recebe agendamentos.
Confira o CRP no site do conselho (cadastro.cfp.org.br) e aprove no servidor:
```
docker compose -f docker-compose.prod.yml exec api python -m app.admin pendentes
docker compose -f docker-compose.prod.yml exec api python -m app.admin aprovar EMAIL
docker compose -f docker-compose.prod.yml exec api python -m app.admin revogar EMAIL
```

## 2. E-mail (feito no código; falta a conta SMTP)
Contrate um serviço SMTP (Amazon SES, Brevo, Mailgun, Google Workspace) e verifique o domínio (SPF, DKIM, DMARC).
Preencha no `deploy/.env`: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`, `SMTP_SECURITY`.
Sem `SMTP_HOST`/`SMTP_FROM` o recurso fica desligado (recuperar senha responde 503 e o paciente não é obrigado a confirmar e-mail).
Teste: cadastre-se, receba o código, use "Esqueci minha senha".

## 3. Textos legais
Os Termos e a Política em `lib/legal/textos_legais.dart` são modelos. Peça a um advogado com experiência em LGPD/saúde para revisar
(dado sensível, base legal, encarregado/DPO, prazos de guarda do prontuário — Resolução CFP 01/2009 e 001/2009, retenção de 5 anos —,
transferência internacional se o servidor for fora do Brasil). Depois de revisar, aumente `kVersaoTermos` para todos aceitarem de novo.

## 4. Fuso horário (decidido: fixo, horário de Brasília)
Todos os horários são "horário de parede" de `APP_TZ=America/Sao_Paulo`; o app avisa isso na tela de agendamento.
Para atender em outro fuso (ex.: Manaus), seria preciso migrar para UTC — não é necessário no lançamento só no Brasil.

## 5. Infraestrutura real
- VPS (2 vCPU / 2 GB bastam para começar), domínio apontando (registro A) para o IP.
- `cp deploy/.env.example deploy/.env` e preencher tudo (DOMAIN, POSTGRES_PASSWORD, JWT_SECRET `openssl rand -hex 32`, PRONTUARIO_KEYS, SMTP_*).
- `docker compose -f docker-compose.prod.yml up -d` — o Caddy emite o HTTPS sozinho.
- Rode o ensaio de restauração uma vez (`deploy/backup/ensaio-dr.sh`) e copie os backups para FORA do servidor (bucket S3/B2 ou outro servidor).
- Firewall: só 80 e 443 (e SSH por chave).
Guia completo: `docs/GUIA-PRODUCAO.md` e `docs/GUIA-DR-E-APK.md`.

## 6. Chave dos prontuários
Gere: `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`.
Guarde cópia em gerenciador de senhas + um segundo lugar físico/offline. Sem ela, nem o backup abre os prontuários.
Para trocar: `PRONTUARIO_KEYS=NOVA,ANTIGA`.

## 7. Vídeo (Jitsi)
Com `VIDEO_DOMAIN` vazio o app lança sem vídeo (sessão online sem botão de entrar). Para ligar: `docs/VIDEO.md`
(Jitsi próprio com JWT; teste ao vivo com 2 aparelhos antes de ligar).

## 8. GitHub
Settings → Code security: ative Dependency graph, Dependabot alerts, Code scanning (CodeQL) e Secret scanning + push protection.
Settings → Branches: proteger `main` (PR obrigatório, checks obrigatórios, sem force-push).
Revogue o token antigo colado no chat: github.com/settings/tokens.
Para o APK falar com o servidor: Settings → Variables → `API_URL=https://seu-dominio/api`.
