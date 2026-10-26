# Guia: ensaio de restauração e APK no celular

Todos os comandos de Docker rodam em `deploy/`. Pré-requisitos: Docker Compose, `.env` preenchido (`cp .env.example .env`; use `DOMAIN=localhost` e `DEMO_SEED=true` para teste local).

## 1. Ensaio de Disaster Recovery

### 1.1 Automático (recomendado)
```bash
cd deploy
docker compose -f docker-compose.prod.yml up -d --build   # sobe tudo (1ª vez ~10 min)
CONFIRMO=sim ./backup/ensaio-dr.sh                        # APAGA o banco: só em teste
```
O script termina com `ENSAIO OK` se o registro voltou e o Alembic continua em `0001`.

### 1.2 Manual, passo a passo
```bash
alias dc='docker compose -f docker-compose.prod.yml'
# 1) registro de teste
dc exec -T db psql -U mente -d mente_saudavel -c \
 "INSERT INTO usuarios (nome,email,senha_hash,perfil,criado_em) VALUES ('Teste DR','dr@exemplo.com','x','paciente',now());"
dc exec -T db psql -U mente -d mente_saudavel -tAc "SELECT version_num FROM alembic_version"   # 0001

# 2) backup + checksum
dc exec -T backup sh /usr/local/bin/backup-postgres.sh
ls backups/diario/ ; (cd backups/diario && sha256sum -c *.sha256)

# 3) desastre
dc stop api caddy backup
dc exec -T db psql -U mente -d postgres -c "DROP DATABASE mente_saudavel WITH (FORCE)"
dc exec -T db psql -U mente -d postgres -c "CREATE DATABASE mente_saudavel"

# 4) restaurar (o script confere o SHA256 e lista o dump antes de aplicar)
ARQ=$(ls -1 backups/diario/*.dump | sort | tail -1)
dc run --rm --no-deps --entrypoint sh backup /usr/local/bin/restore-postgres.sh /backups/diario/$(basename $ARQ)

# 5) verificar
dc exec -T db psql -U mente -d mente_saudavel -tAc "SELECT email FROM usuarios WHERE email='dr@exemplo.com'"
dc exec -T db psql -U mente -d mente_saudavel -tAc "SELECT version_num FROM alembic_version"   # 0001
dc up -d                                    # o serviço migrate roda e não encontra nada a fazer
dc exec -T db psql -U mente -d mente_saudavel -c "DELETE FROM usuarios WHERE email='dr@exemplo.com'"
```
Nota: o script de restauração se chama `restore-postgres.sh` (em `deploy/backup/`). Para um desastre real, copie o `.dump` mais recente de fora do servidor para `deploy/backups/diario/` e siga a partir do passo 4. Se o `.sha256` não bater, **não restaure**: use o dump anterior.

## 2. `API_URL` no Flutter (local x produção)
O app lê `API_URL` em tempo de compilação (`--dart-define`). Vazio = modo local (só SQLite, sem servidor).
```bash
cp env/local.json.example env/local.json          # edite o IP do seu computador
cp env/producao.json.example env/producao.json    # edite o domínio
# (env/*.json não vai para o Git)
flutter run   --dart-define-from-file=env/local.json
flutter build apk --release --dart-define-from-file=env/producao.json
# ou direto: --dart-define=API_URL=http://192.168.0.10:8000 --dart-define=DEMO_MODE=true
```
Descobrir o IP: Linux `hostname -I`, macOS `ipconfig getifaddr en0`, Windows `ipconfig` (IPv4 do Wi-Fi). Celular e computador na **mesma rede Wi-Fi** (sem "isolamento de clientes" no roteador).

## 3. Build e instalação do APK
A pasta `android/` não fica no repositório; gere-a (mesmos ajustes do CI: minSdk 23, INTERNET, nome do app):
```bash
tools/preparar_android.sh               # HTTP liberado só no APK debug
tools/preparar_android.sh --cleartext   # HTTP também no release (somente para teste local; nunca publique esse APK)
flutter pub get
```
**Teste na rede local (HTTP):** o Caddy usa certificado interno para `localhost`, que o Android não aceita; por isso publique a API direto em HTTP, só na LAN:
```bash
cd deploy && docker compose -f docker-compose.prod.yml -f docker-compose.lan.yml up -d --build
curl http://SEU-IP:8000/health              # do computador; depois abra no navegador do celular
# libere a porta 8000 no firewall do computador (ex.: sudo ufw allow from 192.168.0.0/24 to any port 8000)
cd .. && flutter build apk --debug --dart-define-from-file=env/local.json
adb install -r build/app/outputs/flutter-apk/app-debug.apk    # celular com depuração USB; ou envie o APK por cabo/Drive
```
**Produção (HTTPS):** sem ajuste de cleartext; use `tools/preparar_android.sh` (sem flag) e `flutter build apk --release --dart-define-from-file=env/producao.json`. Assinatura com sua keystore: veja `build-apk.yml` (segredos `ANDROID_KEYSTORE_*`). Defina também a variável do repositório `API_URL` para o APK do CI deixar o modo local.

## 4. Checklist no celular
Comunicação:
- [ ] Navegador do celular abre `http://IP:8000/health` → `{"status":"ok"}`.
- [ ] Abrir o app, aceitar os termos, entrar (contas demo se `DEMO_SEED=true`) ou cadastrar.
- [ ] Agendar uma sessão online; conferir no computador: `dc exec -T db psql -U mente -d mente_saudavel -c "SELECT id,data_hora,status,chave_idempotencia FROM sessoes ORDER BY id DESC LIMIT 3"`.
- [ ] Outro paciente tentando o mesmo horário recebe a mensagem de conflito (409).

Offline / Outbox:
- [ ] Ative o **modo avião** (ou desligue o Wi-Fi) com o app aberto.
- [ ] Crie 2 agendamentos em horários diferentes: o app deve mostrá-los como pendentes e não dar erro.
- [ ] No computador, confirme que **não** chegaram: a consulta acima não mostra as novas linhas.
- [ ] Religue a rede. Em até alguns segundos (ou ao reabrir o app) os agendamentos devem sincronizar e perder a marca de pendente.
- [ ] Confirme no PostgreSQL: 2 linhas novas, cada uma com `chave_idempotencia` preenchida.
- [ ] Repita o teste forçando duplicidade: crie offline, religue a rede, e force reenvio (feche/abra o app logo após reconectar). A contagem de sessões não pode passar de 2.
- [ ] Offline com o mesmo horário já ocupado por outro paciente: ao sincronizar o item vira conflito e o app avisa, sem apagar silenciosamente.
- [ ] `docker compose -f docker-compose.prod.yml logs api | tail` mostra requisições `POST /sessoes` 201 (e 200 em reenvios).

Solução de problemas: "Sem conexão com o servidor" → IP errado, firewall, ou APK release sem `--cleartext` falando HTTP. `CLEARTEXT communication not permitted` → faltou `usesCleartextTraffic` (rode `tools/preparar_android.sh`). App abre mas "modo local" → o build ficou sem `API_URL`.
