# Release mobile: APK conectado ao servidor de produção

O APK só fala com o servidor se for compilado com `API_URL`. Sem ela, vira **modo local** (SQLite no aparelho): sem vídeo,
sem prontuário, sem aprovação de profissional e sem e-mail. Por isso o passo abaixo é obrigatório no lançamento.

## Pré-requisitos (uma vez)
1. O servidor está no ar em HTTPS (`docs/LANCAMENTO-CHECKLIST.md`, item 5) e `https://SEU-DOMINIO/api/health` responde `{"status":"ok"}`.
2. **Obrigatório para release:** chave de assinatura própria. O workflow **falha** (`release=true` ou tag `v*.*.*`) se qualquer um dos 4 segredos `ANDROID_KEYSTORE_*`/`ANDROID_KEY_*` faltar; só builds de teste (sem release) saem com assinatura de teste, que o Android recusa atualizar por cima:
   ```bash
   keytool -genkeypair -v -keystore mente.jks -alias mente -keyalg RSA -keysize 4096 -validity 10000
   base64 -w0 mente.jks > mente.jks.b64      # macOS: base64 -i mente.jks | tr -d '\n'
   gh secret set ANDROID_KEYSTORE_B64      < mente.jks.b64
   gh secret set ANDROID_KEYSTORE_PASSWORD            # digita a senha do keystore
   gh secret set ANDROID_KEY_ALIAS --body mente
   gh secret set ANDROID_KEY_PASSWORD                 # digita a senha da chave
   ```
   Guarde `mente.jks` e as senhas num cofre. Perder a chave = não conseguir atualizar o app já instalado.

## Gerar o APK de produção
Parâmetros do workflow "Build APK" (`.github/workflows/build-apk.yml`):

| Parâmetro | Valor de produção | Efeito |
|---|---|---|
| `--ref` | `main` (ou `dev` para teste) | branch compilada |
| `api_url` | `https://SEU-DOMINIO/api` | embute o endereço da API (HTTPS obrigatório; `/api` é acrescentado se faltar) |
| `release` | `true` | publica o APK em Releases (link direto de download) |
| `demo` | `false` | sem contas/dados de demonstração |

```bash
gh workflow run build-apk.yml --ref main -f api_url=https://SEU-DOMINIO/api -f release=true -f demo=false
sleep 10
gh run watch "$(gh run list --workflow build-apk.yml --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
gh release list --limit 1                                   # tag apk-NNN
gh release view apk-NNN --json assets -q '.assets[0].url'   # link do APK
```

Alternativa permanente: `gh variable set API_URL --body https://SEU-DOMINIO/api` (o campo `api_url` do disparo tem prioridade).
O APK gerado é só `arm64-v8a` (~20 MB): cobre os celulares atuais; aparelhos de 32 bits não instalam.

## Conferir no celular
1. Desinstale versões anteriores (assinaturas diferentes conflitam) e instale o APK.
2. Cadastro → chega o código por e-mail (SMTP ligado) → confirmar.
3. Profissional novo aparece como "Cadastro em análise" até `python -m app.admin aprovar EMAIL` no servidor.
4. Agendar sessão **Online** → na hora (15 min antes) o botão "Entrar na videochamada" abre o Jitsi.
5. No profissional: paciente → ícone **Prontuário**.

## Site (PWA) com a mesma API
O site é compilado pelo CI com `API_URL=/api` (mesmo domínio, via Caddy) e servido pela pilha Docker (`deploy/`). Não precisa de parâmetro.

## iPhone (iOS)
O workflow **Build iOS** (`.github/workflows/build-ios.yml`) compila o app num runner macOS; a pasta `ios/` é gerada por `tools/preparar_ios.sh` (como a `android/`). Não há como compilar para iPhone fora de um macOS com Xcode.

**Sem conta paga da Apple** — o artefato `MenteSaudavel-iOS` traz `MenteSaudavel-unsigned.ipa`. Instale pelo Mac/Windows com [Sideloadly](https://sideloadly.io) ou AltStore usando um Apple ID comum (o app expira em 7 dias e precisa ser reinstalado; o modo desenvolvedor do iPhone deve estar ligado).

**Com Apple Developer Program (US$ 99/ano)** — crie em Settings > Secrets and variables > Actions:
| Segredo | Conteúdo |
|---|---|
| `IOS_CERT_P12_B64` | certificado de distribuição/desenvolvimento exportado como .p12, em base64 (`base64 -i cert.p12`) |
| `IOS_CERT_PASSWORD` | senha do .p12 |
| `IOS_PROVISION_PROFILE_B64` | perfil `.mobileprovision` em base64 do ID do app (o log mostra o Bundle ID esperado) |
| `IOS_TEAM_ID` | Team ID da conta (10 caracteres) |

Variável opcional `IOS_EXPORT_METHOD`: `development`, `ad-hoc` (padrão) ou `app-store-connect` (TestFlight/App Store). Com os segredos o artefato inclui também `MenteSaudavel-signed.ipa`. Ad hoc só instala nos aparelhos (UDID) listados no perfil.

**Sem build nativo (alternativa)** — com o site no ar em HTTPS, abra no Safari > Compartilhar > "Adicionar à Tela de Início" (PWA).

Observação: o app usa Keychain (`flutter_secure_storage`) para o token e SQLite local; `API_URL` e `DEMO_MODE` funcionam como no Android.
