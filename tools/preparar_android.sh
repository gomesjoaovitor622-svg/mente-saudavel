#!/usr/bin/env bash
# Gera a pasta android/ (o repositório não a guarda) e aplica os mesmos ajustes do CI:
# minSdk 23, permissão de INTERNET e nome do app. Rode na raiz do projeto.
#   tools/preparar_android.sh               # só debug aceita HTTP (cleartext) — release continua só HTTPS
#   tools/preparar_android.sh --cleartext   # libera HTTP também no release (APK de teste na rede local; NUNCA publique)
set -euo pipefail
cd "$(dirname "$0")/.."
cleartext=0; [[ "${1:-}" == "--cleartext" ]] && cleartext=1
if [[ ! -d android ]]; then
  tmp="$(mktemp -d)"
  flutter create --platforms=android --project-name mente_saudavel --org br.edu.ifro.mentesaudavel "$tmp/gerado"
  cp -r "$tmp/gerado/android" ./android
fi
gradle=$(find android/app -maxdepth 1 -name 'build.gradle*' | head -1)
sed -i -E 's/minSdk(Version)?([ =]+)flutter\.minSdkVersion/minSdk\1\2 23/' "$gradle"
grep -qE "minSdk(Version)?[ =]+ ?23" "$gradle" || { echo "não consegui ajustar o minSdk em $gradle" >&2; exit 1; }
main=android/app/src/main/AndroidManifest.xml
grep -q "android.permission.INTERNET" "$main" || sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$main"
sed -i 's#android:label="[^"]*"#android:label="Mente Saudável"#' "$main"
# Dados de saúde no aparelho: sem backup do Android (adb backup / nuvem do Google).
grep -q "android:allowBackup" "$main" || sed -i 's#<application#<application android:allowBackup="false" android:fullBackupContent="false"#' "$main"
# HTTP em texto puro: no manifesto de DEBUG (não vai para o release) ou, com --cleartext, no principal.
alvo=android/app/src/debug/AndroidManifest.xml
[[ $cleartext == 1 ]] && alvo="$main"
if ! grep -q usesCleartextTraffic "$alvo"; then
  sed -i 's#<application#<application android:usesCleartextTraffic="true"#' "$alvo"
fi
echo "android pronto. cleartext em: $alvo"
