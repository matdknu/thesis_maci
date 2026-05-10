#!/usr/bin/env bash
# Exporta la presentación Reveal.js a PDF capturando cada slide como en el navegador.
# Requisitos: quarto, Node/npx (decktape descarga Chromium la primera vez).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

PORT="${PORT:-}"
if [[ -z "${PORT}" ]]; then
  PORT="$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")"
fi
OUT="${1:-presentation.pdf}"

quarto render presentation.qmd

python3 -m http.server "$PORT" --bind 127.0.0.1 &
PID=$!
cleanup() { kill "$PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1

npx --yes decktape reveal "http://127.0.0.1:${PORT}/presentation.html" "$OUT"
echo "Escrito: $DIR/$OUT"
