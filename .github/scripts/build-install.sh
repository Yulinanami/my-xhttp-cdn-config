#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

MODULES=(
  01-env.sh
  02-os-service.sh
  03-xray-install.sh
  04-input.sh
  05-base-env.sh
  06-acme-cert.sh
  07-nginx-install.sh
  08-server-config.sh
  09-service-check.sh
  10-client-config.sh
  11-subscription.sh
  12-final-output.sh
)

append_module() {
  local file="$1"
  local line include_path

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == @@include\ * ]]; then
      include_path="${line#@@include }"
      cat "$ROOT_DIR/$include_path"
    else
      printf '%s\n' "$line"
    fi
  done < "$file"
}

append_profile() {
  local variant="$1"

  case "$variant" in
    normal)
      cat <<'PROFILE'
# ==================================================
# 功能开关：普通版
# ==================================================

FEATURE_XPADDING=false
FEATURE_CDN_ECH=false
CDN_ECH_ENABLED=false
CDN_ECH_QUERY=""
PROFILE
      ;;
    xpadding)
      cat <<'PROFILE'
# ==================================================
# 功能开关：xpadding + ECH 版
# ==================================================

FEATURE_XPADDING=true
FEATURE_CDN_ECH=true
PROFILE
      ;;
    *)
      echo "Unknown variant: $variant" >&2
      return 1
      ;;
  esac
}

build_one() {
  local variant="$1"
  local output="$2"
  local tmp module

  tmp="$(mktemp)"
  cat > "$tmp" <<'SCRIPTHEADER'
#!/bin/bash
set -e
SCRIPTHEADER

  for module in "${MODULES[@]}"; do
    append_module "$ROOT_DIR/src/$module" >> "$tmp"
    if [[ "$module" == "01-env.sh" ]]; then
      append_profile "$variant" >> "$tmp"
    fi
  done

  mv "$tmp" "$output"
  chmod +x "$output"
}

OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"
mkdir -p "$OUT_DIR"

build_one normal "$OUT_DIR/install.sh"
build_one xpadding "$OUT_DIR/install-xpadding.sh"

echo "Generated $OUT_DIR/install.sh and $OUT_DIR/install-xpadding.sh"
