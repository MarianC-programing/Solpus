#!/usr/bin/env sh
# Instala solana-test-validator (Agave) en .tools/agave con versión y suma
# SHA-256 fijadas. Se usa igual en local y en CI. Es idempotente.
#
# Origen de la suma: coincide con el digest que publica GitHub para el asset
# (API de releases de anza-xyz/agave) y con la descarga verificada en local.
#
# Para actualizar la versión: cambiar versión y suma, revisar el changelog y
# ejecutar la integración (`SOLANA_INTEGRATION=1 cabal test
# solpus-client:test:integration`).
set -eu

AGAVE_VERSION="4.4.1"
AGAVE_SHA256="5b0f0fc7e4eedace05f6455de00aa1f2f3d1642068f1e8d50760ba49112c3941"
AGAVE_URL="https://github.com/anza-xyz/agave/releases/download/v${AGAVE_VERSION}/solana-release-x86_64-unknown-linux-gnu.tar.bz2"

root=$(cd "$(dirname "$0")/.." && pwd)
dest="$root/.tools/agave"
validator="$dest/bin/solana-test-validator"

if [ -x "$validator" ] && [ "$(cat "$dest/VERSION" 2>/dev/null)" = "$AGAVE_VERSION" ]; then
  echo "agave $AGAVE_VERSION ya instalado"
else
  echo "Instalando agave $AGAVE_VERSION"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl --proto '=https' --tlsv1.2 -fsSL -o "$tmp/agave.tar.bz2" "$AGAVE_URL"
  echo "$AGAVE_SHA256  $tmp/agave.tar.bz2" | sha256sum -c - >/dev/null || {
    echo "Suma SHA-256 inválida para $AGAVE_URL" >&2
    exit 1
  }
  rm -rf "$dest"
  mkdir -p "$dest"
  tar -xjf "$tmp/agave.tar.bz2" -C "$dest" --strip-components=1
  echo "$AGAVE_VERSION" >"$dest/VERSION"
fi

"$validator" --version | head -1
echo "SOLANA_TEST_VALIDATOR=$validator"
