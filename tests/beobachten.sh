#!/bin/sh
# Tests bei jeder gespeicherten Änderung neu laufen lassen (Strg+C beendet).
# Aufruf: tests/beobachten.sh [Filter], z. B. tests/beobachten.sh Gildenchat
cd "$(dirname "$0")/.." || exit 1
mark="${TMPDIR:-/tmp}/elternabend-tests.$$"
trap 'rm -f "$mark"' EXIT
run() { clear; luajit tests/run.lua "$@"; touch "$mark"; }
run "$@"
while sleep 1; do
    if find . -maxdepth 2 \( -name '*.lua' -o -name '*.toc' \) -newer "$mark" | grep -q .; then run "$@"; fi
done
