#!/usr/bin/env sh
# Comprueba las fronteras de dependencia del plan (docs/PLAN.md §4):
#
#   solpus-cli -> solpus-app -> solpus-client -> solpus-core
#                                   |
#                         solana-haskell-sdk   (solo Rpc.hs, Tx.hs y Wallet.hs)
#
# Reglas:
#   1. El SDK (Network.Solana, Network.Web3, Network.JsonRpc) solo puede
#      importarse en solpus-client/src/Solpus/Client/{Rpc,Tx,Wallet}.hs y en las
#      pruebas de solpus-client (test/ y test-integration/), para fabricar
#      excepciones, contrastar parsers y hablar con un validador real.
#   2. Una capa no importa a otra superior.
#   3. solpus-app solo puede importar de Solpus.Client los módulos de la lista
#      PERMITIDOS_APP (la interfaz). Ninguna implementación. Sus pruebas pueden
#      además usar el intérprete en memoria (PERMITIDOS_APP_TEST).
#
# Es una comprobación por texto sobre las líneas `import`: barata y sin
# dependencias. Los módulos nuevos de solpus-client que solpus-app deba usar se
# añaden a la lista, de forma explícita y revisable.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

# Módulos de Solpus.Client que solpus-app puede importar en su código.
PERMITIDOS_APP="Solpus.Client.Class Solpus.Client.Info"
# En sus pruebas, además, el intérprete en memoria.
PERMITIDOS_APP_TEST="$PERMITIDOS_APP Solpus.Client.InMemory"

fallos=0
fallo() {
  echo "FRONTERA VIOLADA: $1" >&2
  fallos=$((fallos + 1))
}

# Líneas `import` de .hs bajo un directorio. Admite `import qualified X` y
# `import X qualified`.
imports_en() {
  grep -rEn --include='*.hs' --exclude-dir=dist-newstyle --exclude-dir=.git \
    --exclude-dir=.tools '^import[[:space:]]+' "$1" 2>/dev/null || true
}

# 1. El SDK solo entra por Rpc.hs, Tx.hs y Wallet.hs.
sdk=$(imports_en . \
  | grep -E '^[^:]+:[0-9]+:import[[:space:]]+(qualified[[:space:]]+)?Network\.(Solana|Web3|JsonRpc)' \
  | grep -vE '^\./solpus-client/(src/Solpus/Client/(Rpc|Tx|Wallet)\.hs|test/[^:]*\.hs|test-integration/[^:]*\.hs):' || true)
[ -z "$sdk" ] || fallo "el SDK se importa fuera de Rpc.hs/Tx.hs/Wallet.hs:
$sdk"

# 2. Una capa no importa a otra superior.
cap() { # directorio patrón descripción
  hit=$(imports_en "$1" | grep -E "import[[:space:]]+(qualified[[:space:]]+)?($2)" || true)
  [ -z "$hit" ] || fallo "$3:
$hit"
}
cap solpus-core 'Solpus\.(Client|App)' "solpus-core importa una capa superior"
cap solpus-client 'Solpus\.App' "solpus-client importa a solpus-app"
cap solpus-app 'Main' "solpus-app importa a la CLI"

# 3. solpus-app solo conoce la interfaz de solpus-client.
comprobar_app() { # directorio lista-permitidos
  modulos=$(imports_en "$1" \
    | grep -oE 'Solpus\.Client\.[A-Za-z0-9_.]+' | sort -u || true)
  for m in $modulos; do
    permitido=no
    for p in $2; do
      [ "$m" = "$p" ] && permitido=si
    done
    [ "$permitido" = si ] || fallo "$1 importa $m (permitidos: $2)"
  done
}
comprobar_app solpus-app/src "$PERMITIDOS_APP"
comprobar_app solpus-app/test "$PERMITIDOS_APP_TEST"

if [ "$fallos" -gt 0 ]; then
  echo "$fallos regla(s) de frontera incumplida(s). Ver docs/PLAN.md §4." >&2
  exit 1
fi
echo "Fronteras OK"
