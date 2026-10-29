#!/usr/bin/env bash
# Personaliza a pasta web/ gerada pelo `flutter create` para o Mente Saudável (PWA instalável + SEO).
# Uso: tools/personalizar_web.sh <pasta_web>
# A pasta web/ não é versionada (nasce de `flutter create` em cada build); o que é nosso fica em web_overrides/.
set -euo pipefail

web="${1:?uso: personalizar_web.sh <pasta_web>}"
aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
index="$web/index.html"
[[ -f "$index" ]] || { echo "::error::$index não existe (rode flutter create antes)"; exit 1; }
grep -q '</head>' "$index" || { echo "::error::index.html sem </head>: template do Flutter mudou"; exit 1; }

# Arquivos próprios: manifest e ícones (os do template "Flutter" são substituídos).
cp "$aqui/web_overrides/manifest.json" "$web/manifest.json"
mkdir -p "$web/icons"
cp "$aqui"/web_overrides/icons/*.png "$web/icons/"
cp "$aqui/web_overrides/favicon.png" "$web/favicon.png"

# Idioma, título e descrição (o template traz "A new Flutter project").
sed -i -E 's#<html[^>]*>#<html lang="pt-BR">#' "$index"
sed -i -E 's#<title>[^<]*</title>#<title>Mente Saudável: psicoterapia online</title>#' "$index"
sed -i -E '/<meta name="description"/d' "$index"

# Metadados novos (uma vez só, antes de </head>). O <link rel="manifest"> já vem no template.
if ! grep -q 'ms-pwa' "$index"; then
  extras="$(mktemp)"
  cat > "$extras" <<'HTML'
  <!-- ms-pwa -->
  <meta name="description" content="Agende sessões de psicoterapia, acompanhe seu humor e converse com profissionais, com privacidade e em conformidade com a LGPD.">
  <meta name="theme-color" content="#3F8F5A">
  <meta name="color-scheme" content="light">
  <meta name="application-name" content="Mente Saudável">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-title" content="Mente Saudável">
  <meta name="apple-mobile-web-app-status-bar-style" content="default">
  <meta property="og:type" content="website">
  <meta property="og:locale" content="pt_BR">
  <meta property="og:title" content="Mente Saudável: psicoterapia online">
  <meta property="og:description" content="Agende sessões, acompanhe seu humor e cuide da sua saúde mental com privacidade.">
  <meta property="og:image" content="icons/Icon-512.png">
  <meta name="twitter:card" content="summary">
HTML
  awk -v f="$extras" '/<\/head>/ { while ((getline linha < f) > 0) print linha } { print }' "$index" > "$index.tmp" && mv "$index.tmp" "$index"
  rm -f "$extras"
fi

# O template deve conservar o link do manifest e o apple-touch-icon; acrescenta se faltarem.
grep -q 'rel="manifest"' "$index" || sed -i 's#</head>#  <link rel="manifest" href="manifest.json">\n</head>#' "$index"
grep -q 'rel="apple-touch-icon"' "$index" || sed -i 's#</head>#  <link rel="apple-touch-icon" href="icons/Icon-192.png">\n</head>#' "$index"
echo "web personalizada: $(grep -c 'theme-color' "$index") theme-color, manifest e ícones copiados"
