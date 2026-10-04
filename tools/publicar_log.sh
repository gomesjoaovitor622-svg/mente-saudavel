#!/bin/sh
# Publica um log numa branch "ci-logs-<nome>" do repositório, para ser lido depois.
# Uso: sh tools/publicar_log.sh <arquivo> <nome>      (precisa de GH_TOKEN no ambiente)
set -e
ARQ="$1"
DEST="$2"
TMP=$(mktemp -d)
cd "$TMP"
git init -q
git config user.name "github-actions"
git config user.email "actions@users.noreply.github.com"
git checkout -q -b "ci-logs-$DEST"
{
  echo "commit: ${GITHUB_SHA}"
  echo "branch: ${GITHUB_REF_NAME}"
  echo "data:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  tail -n 500 "$ARQ"
} > log.txt
git add log.txt
git commit -q -m "log $DEST $GITHUB_SHA"
git push -q -f "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:refs/heads/ci-logs-$DEST"
echo "log publicado em ci-logs-$DEST"
