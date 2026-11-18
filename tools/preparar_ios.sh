#!/usr/bin/env bash
# Gera a pasta ios/ (não versionada) e aplica os ajustes do app. Roda em macOS (CI ou Mac local).
# Uso: tools/preparar_ios.sh
set -euo pipefail

[[ "$(uname)" == "Darwin" ]] || { echo "Este script precisa de macOS (PlistBuddy/Xcode)." >&2; exit 1; }
raiz="$(cd "$(dirname "$0")/.." && pwd)"
cd "$raiz"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
flutter create --platforms=ios --project-name mente_saudavel --org br.edu.ifro.mentesaudavel "$tmp/gerado"
rm -rf ios && cp -R "$tmp/gerado/ios" ./ios

plist=ios/Runner/Info.plist
pb() { /usr/libexec/PlistBuddy -c "$1" "$plist"; }
setkey() { pb "Set :$1 $2" 2>/dev/null || pb "Add :$1 ${3:-string} $2"; }

setkey CFBundleDisplayName "Mente Saudável"
setkey CFBundleName "MenteSaudavel"
# Sem pergunta de criptografia a cada envio ao TestFlight (o app só usa HTTPS/SHA-256 padrão).
setkey ITSAppUsesNonExemptEncryption false bool
# Só retrato: telas de conversa/diário foram pensadas assim.
pb "Delete :UISupportedInterfaceOrientations" 2>/dev/null || true
pb "Add :UISupportedInterfaceOrientations array"
pb "Add :UISupportedInterfaceOrientations:0 string UIInterfaceOrientationPortrait"
# App Transport Security permanece no padrão (somente HTTPS): garante que ninguém deixou exceção.
pb "Delete :NSAppTransportSecurity" 2>/dev/null || true

# iOS 13+ (exigido pelo flutter_secure_storage / sqflite atuais).
sed -i '' -E 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 13.0;/' ios/Runner.xcodeproj/project.pbxproj
grep -q "IPHONEOS_DEPLOYMENT_TARGET = 13.0" ios/Runner.xcodeproj/project.pbxproj || { echo "falha ao ajustar iOS 13"; exit 1; }
[[ -f ios/Podfile ]] && sed -i '' -E "s/^# *platform :ios, '[0-9.]+'/platform :ios, '13.0'/" ios/Podfile || true

plutil -lint "$plist"
echo "ios/ pronto."
