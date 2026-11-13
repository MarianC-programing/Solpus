#!/usr/bin/env sh
# Instala fourmolu y hlint en .tools/bin con versiones y sumas SHA-256 fijadas.
# Se usa igual en local y en CI. Es idempotente: no vuelve a descargar si la
# versión instalada coincide.
#
# Origen de las sumas:
#   - fourmolu: coincide con el digest que publica GitHub para el asset.
#   - hlint:    GitHub no publica digest; la suma se fijó en la primera descarga.
#
# Para actualizar una versión: cambiar versión y suma, revisar el changelog y
# pasar `fourmolu --mode check` y `hlint` sobre todo el repositorio.
set -eu

FOURMOLU_VERSION="0.21.0.0"
FOURMOLU_SHA256="aadf6931653df7b96f52014cf8eb4285a3e8778cd0b531499fc3ee013e1e00c7"
FOURMOLU_URL="https://github.com/fourmolu/fourmolu/releases/download/v${FOURMOLU_VERSION}/fourmolu-${FOURMOLU_VERSION}-linux-x86_64.zip"

HLINT_VERSION="3.10"
HLINT_SHA256="ccabc8802a58154699a3583b8dddc5ea2e6d65753a62c45c0e80088ebb16b42b"
HLINT_URL="https://github.com/ndmitchell/hlint/releases/download/v${HLINT_VERSION}/hlint-${HLINT_VERSION}-x86_64-linux.tar.gz"

root=$(cd "$(dirname "$0")/.." && pwd)
bin="$root/.tools/bin"
mkdir -p "$bin"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

download() { # url destino suma
  curl --proto '=https' --tlsv1.2 -fsSL -o "$2" "$1"
  echo "$3  $2" | sha256sum -c - >/dev/null || {
    echo "Suma SHA-256 inválida para $1" >&2
    exit 1
  }
}

if [ -x "$bin/fourmolu" ] && "$bin/fourmolu" --version 2>/dev/null | grep -q "$FOURMOLU_VERSION"; then
  echo "fourmolu $FOURMOLU_VERSION ya instalado"
else
  echo "Instalando fourmolu $FOURMOLU_VERSION"
  download "$FOURMOLU_URL" "$tmp/fourmolu.zip" "$FOURMOLU_SHA256"
  unzip -q -j -o "$tmp/fourmolu.zip" "*/fourmolu" -d "$bin"
  chmod +x "$bin/fourmolu"
fi

if [ -x "$bin/hlint" ] && "$bin/hlint" --version 2>/dev/null | grep -q "v${HLINT_VERSION}"; then
  echo "hlint $HLINT_VERSION ya instalado"
else
  echo "Instalando hlint $HLINT_VERSION"
  download "$HLINT_URL" "$tmp/hlint.tar.gz" "$HLINT_SHA256"
  tar -xzf "$tmp/hlint.tar.gz" -C "$tmp"
  cp "$tmp/hlint-${HLINT_VERSION}/hlint" "$bin/hlint"
  chmod +x "$bin/hlint"
fi

"$bin/fourmolu" --version | head -1
"$bin/hlint" --version | head -1
