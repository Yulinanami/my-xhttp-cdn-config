#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

MODULES=(
  extensions/common-nodes/00-env-utils.sh
  extensions/common-nodes/01-read-existing.sh
  extensions/common-nodes/02-server-config.sh
  extensions/common-nodes/03-client-config.sh
  extensions/common-nodes/04-subscription-output.sh
)

build_one() {
  local output="$1"
  local tmp module

  tmp="$(mktemp)"
  cat > "$tmp" <<'SCRIPTHEADER'
#!/bin/bash
set -e
SCRIPTHEADER

  for module in "${MODULES[@]}"; do
    cat "$ROOT_DIR/$module" >> "$tmp"
    printf '\n' >> "$tmp"
  done

  mv "$tmp" "$output"
  chmod +x "$output"
}

OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"
mkdir -p "$OUT_DIR"

build_one "$OUT_DIR/add-common-nodes.sh"

echo "Generated $OUT_DIR/add-common-nodes.sh"
