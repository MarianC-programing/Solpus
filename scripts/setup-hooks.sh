#!/usr/bin/env sh
# Activa los hooks versionados de .githooks/ en este clon.
# Es configuración local (.git/config); no afecta a otros clones ni a CI.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

git config core.hooksPath .githooks
echo "Hooks activados (core.hooksPath = .githooks)."
echo "Si faltan fourmolu o hlint: sh scripts/install-tools.sh"
