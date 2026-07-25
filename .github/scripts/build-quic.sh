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

OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"
OUTPUT="$OUT_DIR/add-quic.sh"
mkdir -p "$OUT_DIR"

cat > "$OUTPUT" <<'SCRIPTHEADER'
#!/bin/bash
set -e
SCRIPTHEADER

for module in "${MODULES[@]}"; do
  cat "$ROOT_DIR/$module" >> "$OUTPUT"
  printf '\n' >> "$OUTPUT"
done
chmod +x "$OUTPUT"

echo "Generated $OUTPUT"
