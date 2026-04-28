#!/usr/bin/env bash
# Quita del índice de Git rutas alineadas con .gitignore (caches, pptx pesados, claves, etc.).
# No borra archivos locales; después conviene: git status && git add -A && git commit
# NO toca documents/presentacion_proyecto/ (presentación versión en repo).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Ejecutar desde dentro del repositorio git."; exit 1; }
cd "$ROOT"

echo "Repo: $ROOT"
echo

PATHS=(
  "bibliografia/Speech and Language Processing"
  "documents/tesis_book/_freeze"
  "documents/tesis_book/.quarto"
  "revision"
  "backups"
  "scripts/scrapping/claves_Api"
)

for p in "${PATHS[@]}"; do
  git rm -r --cached --ignore-unmatch "$p" 2>/dev/null || true
done

# PDF suelto en la raíz (si alguna vez se trackeó)
git rm --cached --ignore-unmatch -- Rplots.pdf 2>/dev/null || true
git rm --cached --ignore-unmatch -- tesis_book.pdf 2>/dev/null || true

echo
echo "Hecho. Revisa con: git status"
echo "Ejemplo commit: git add .gitignore && git commit -m \"chore: dejar de versionar caches y artefactos ignorados\""
