#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

MODULES=(
  extensions/dual-cdn/00-env-utils.sh
  extensions/dual-cdn/01-read-existing.sh
  extensions/dual-cdn/02-cert-nginx.sh
  extensions/dual-cdn/03-client-config.sh
  extensions/dual-cdn/04-subscription-output.sh
)

append_with_includes() {
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == @@include\ * ]]; then
      append_with_includes "$ROOT_DIR/${line#@@include }"
    else
      printf '%s\n' "$line"
    fi
  done < "$1"
}

build_one() {
  local output="$1"
  local tmp module

  tmp="$(mktemp)"
  cat > "$tmp" <<'SCRIPTHEADER'
#!/bin/bash
set -e
SCRIPTHEADER

  for module in "${MODULES[@]}"; do
    append_with_includes "$ROOT_DIR/$module" >> "$tmp"
    printf '\n' >> "$tmp"
  done

  mv "$tmp" "$output"
  chmod +x "$output"
}

OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"
mkdir -p "$OUT_DIR"

build_one "$OUT_DIR/add-dual-cdn.sh"

echo "Generated $OUT_DIR/add-dual-cdn.sh"
