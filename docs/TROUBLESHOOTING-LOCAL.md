# Troubleshooting rápido — testes locais e APK

Rode `tools/run_local_tests.sh all` (ou uma etapa: `deps`, `dr`, `lan`, `android`). Os logs ficam em `logs-locais/`. No Windows use **Git Bash** ou **WSL** (Docker Desktop precisa estar aberto).

| Sintoma | Causa provável | Correção (um comando) |
|---|---|---|
| `Docker não está rodando` | daemon parado | Windows/macOS: abrir o Docker Desktop · Linux: `sudo systemctl start docker` |
| `/health` funciona em `localhost:8000` mas não em `IP:8000` / no celular | Firewall do Windows bloqueando a porta | PowerShell **como administrador**: `New-NetFirewallRule -DisplayName "MenteSaudavel 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Private` · Linux: `sudo ufw allow from 192.168.0.0/16 to any port 8000 proto tcp` |
| Idem, e a rede do Windows está como "Pública" | regra só vale no perfil Privado | PowerShell admin: `Set-NetConnectionProfile -NetworkCategory Private` (ou troque a rede para "Privada" nas configurações) |
| Celular não alcança o computador mesmo com firewall liberado | **isolamento de clientes / AP isolation** no roteador, ou rede de convidados | Desative "Isolamento de AP" no roteador; use a rede principal. Teste: `adb shell ping -c 2 IP_DO_PC` (100% de perda = isolamento) |
| IP muda toda hora | DHCP | Reserve o IP do computador no roteador, ou rode `tools/run_local_tests.sh lan` e edite `env/local.json` |
| `permission denied` em `deploy/backups` (ensaio DR) | contêiner do PostgreSQL grava com outro usuário | `chmod -R a+rwX deploy/backups` (a etapa `dr` já faz isso sozinha) |
| `network ... not found` / contêiner antigo atrapalhando | resquício de execução anterior | `cd deploy && docker compose -f docker-compose.prod.yml down` (sem `-v`, para manter os dados) |
| `JWT_SECRET ausente` / `defina POSTGRES_PASSWORD` | `deploy/.env` incompleto | `tools/run_local_tests.sh dr` cria um `.env` de teste · ou `cp deploy/.env.example deploy/.env` |
| API reinicia sem parar com "Banco na versão None" | banco sem migração | `cd deploy && docker compose -f docker-compose.prod.yml run --rm migrate` e veja o log do `migrate` |
| `no devices/emulators found` ou `unauthorized` no `adb devices` | Depuração USB desligada/não autorizada | `adb kill-server && adb start-server && adb devices`, aceite o aviso no celular; cabo de **dados**, modo "Transferência de arquivos" |
| `adb: command not found` | platform-tools fora do PATH | Instale o Android SDK platform-tools e adicione ao PATH (`export PATH=$PATH:$HOME/Android/Sdk/platform-tools`) |
| `minSdkVersion 21 cannot be smaller than version 23` (Gradle/manifest merger) | `android/` gerado sem o ajuste | `rm -rf android && tools/preparar_android.sh` |
| `Gradle ... Could not resolve` / `Unsupported class file major version` / JDK errado | JDK incompatível ou cache quebrado | `flutter doctor -v` (use o JDK que ele indica) e `cd android && ./gradlew --stop && cd .. && flutter clean && flutter pub get` |
| `Android license status unknown` / SDK não aceito | licenças pendentes | `flutter doctor --android-licenses` |
| App mostra "Sem conexão com o servidor" | IP errado em `env/local.json`, firewall, ou APK sem cleartext | Confira `cat env/local.json`; abra `http://IP:8000/health` no navegador do celular; recompile com `flutter build apk --debug --dart-define-from-file=env/local.json` |
| `CLEARTEXT communication to IP not permitted` | HTTP bloqueado no release | `tools/preparar_android.sh --cleartext` (só teste) ou use build **debug** |
| App abre em "modo local" (sem servidor) | build sem `API_URL` | Rebuild com `--dart-define-from-file=env/local.json` e confirme que o arquivo tem `API_URL` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` / `INSTALL_FAILED_USER_RESTRICTED` | assinatura diferente / instalação via USB bloqueada | `adb uninstall br.edu.ifro.mentesaudavel.mente_saudavel` e instale de novo · Xiaomi/Oppo: ativar "Instalar via USB" nas opções de desenvolvedor |
| Porta 8000 já em uso | outro serviço | Linux/macOS `lsof -i :8000` · Windows `netstat -ano \| findstr :8000` |
| Windows: `bash\r: No such file` / `$'\r'` | finais de linha CRLF | `git config core.autocrlf input` e `git checkout -- tools deploy` (ou `dos2unix tools/*.sh deploy/backup/*.sh`) |

**Ao pedir ajuda:** cole o final do log (`tail -40 logs-locais/<etapa>-*.log`), a saída de `docker compose -f deploy/docker-compose.prod.yml ps` e, para rede, `adb devices` e `curl -v http://IP:8000/health`.
