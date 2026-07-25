#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

MODULES=(
  extensions/dual-ip/00-env-utils.sh
  extensions/dual-ip/01-read-existing.sh
  extensions/dual-ip/02-server-config.sh
  extensions/dual-ip/03-client-config.sh
  extensions/dual-ip/04-subscription-output.sh
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

OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"
OUTPUT="$OUT_DIR/add-dual-ip.sh"
mkdir -p "$OUT_DIR"

cat > "$OUTPUT" <<'SCRIPTHEADER'
#!/bin/bash
set -e
SCRIPTHEADER

for module in "${MODULES[@]}"; do
  append_with_includes "$ROOT_DIR/$module" >> "$OUTPUT"
  printf '\n' >> "$OUTPUT"
done
chmod +x "$OUTPUT"

echo "Generated $OUTPUT"
