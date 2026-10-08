# Operação (runbook)

## Rotinas agendadas
| Quando (UTC) | Workflow | Objetivo |
|---|---|---|
| Diário 06:17 | API Validation | Detectar mudança de contrato/CORS/User-Agent em APIs de terceiros (suíte `live`) |
| Segunda 05:23 | Security | CVEs novas em dependências já fixadas; SBOM atualizado |
| Terça 04:41 | CodeQL | Reanálise com consultas atualizadas |
Falha em agendamento notifica quem editou o `cron` por último. Defina um responsável de plantão.

## Releases do app
1. Merge em `main` com todos os checks verdes.
2. `git tag v1.2.3 && git push origin v1.2.3` → o workflow **Build APK** compila em modo **produção**
   (sem contas/dados de demonstração), assina com a keystore (se configurada), atesta a procedência e publica em *Releases*.
3. Verifique: `gh attestation verify MenteSaudavel.apk --repo <dono>/<repo>` e `sha256sum -c MenteSaudavel.apk.sha256`.
4. Build de demonstração: *Actions → Build APK → Run workflow* com `demo = true` (e `release = true` se quiser publicar).

**Rollback:** publique novamente a tag anterior (re-execute o workflow dela) ou crie uma nova tag corretiva. O site: reverta o commit e o `deploy-web.yml` republica.

## Evidências para auditoria
| Evidência | Onde | Retenção |
|---|---|---|
| Relatório executivo (MD/HTML) + `manifest.json` (SHA-256) | Artefato `executive-report` | 90 dias |
| Atestado de procedência (SLSA) do relatório e do APK | *Actions → Attestations* / `gh attestation verify` | permanente |
| SBOM CycloneDX | Artefato `sbom` | 90 dias |
| JUnit, diagnóstico, cobertura | Artefatos `reports-*` | 7 dias |
| Logs brutos de falha | Artefatos `failure-dumps-*` | 14 dias |
| APK + SHA-256 | Artefato `MenteSaudavel-APK` / Release | 30 dias / permanente |
| Alertas de código | *Security → Code scanning* | permanente |
Retenção maior exige exportar os artefatos para o repositório de evidências do cliente.

### Verificar a integridade do relatório
```bash
unzip executive-report.zip -d er && cd er
python3 - <<'PY'
import hashlib, json
m = json.load(open("manifest.json"))
for nome, esperado in m["files"].items():
    atual = hashlib.sha256(open(nome, "rb").read()).hexdigest()
    print(nome, "OK" if atual == esperado else "ADULTERADO")
PY
gh attestation verify executive-report.md --repo <dono>/<repo>
```

## Resposta a incidente: segredo exposto
1. **Revogue** a credencial no provedor (não espere investigar).
2. Rode *Security → Secret scanning* e `leakscan` para achar a origem.
3. Rotacione todo segredo que compartilhava o escopo; invalide sessões se aplicável.
4. Reescrever o histórico git **não** invalida o segredo; faça apenas após a revogação.
5. Registre causa-raiz e ajuste: se foi o pipeline, adicione o padrão em `apival/redaction.py` com teste.

## Indicadores sugeridos (SLOs do pipeline)
| Indicador | Meta |
|---|---|
| Taxa de sucesso do `Gate` em `main` | ≥ 98% |
| Tempo do `Gate` (PR) | ≤ 5 min (p90) |
| Tempo para corrigir `Security Gate` vermelho | ≤ 2 dias úteis |
| Suíte `live`: dias consecutivos verdes | acompanhar tendência; alerta se 3 falhas seguidas |
