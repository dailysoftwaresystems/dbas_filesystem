#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC="$PROJECT_ROOT/web/libs/src/dbas_filesystem_worker.js"
OUT="$PROJECT_ROOT/web/libs/dbas_filesystem_worker.js"

if [ ! -f "$SRC" ]; then
  echo "Error: Source file not found: $SRC" >&2
  exit 1
fi

# Install esbuild if not available
if ! command -v esbuild &>/dev/null; then
  echo "esbuild not found, installing via npm..."
  npm install -g esbuild
fi

echo "Minifying worker..."
esbuild "$SRC" --minify --outfile="$OUT" --target=es2020

ORIG_SIZE=$(wc -c < "$SRC")
MIN_SIZE=$(wc -c < "$OUT")
echo "Done: $ORIG_SIZE bytes -> $MIN_SIZE bytes ($(( (ORIG_SIZE - MIN_SIZE) * 100 / ORIG_SIZE ))% reduction)"
