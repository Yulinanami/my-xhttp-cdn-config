#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请使用 root 用户运行此脚本"
[[ -f "${1:-}" ]] || error "配置文件不存在或未指定: ${1:-config.env}"
CONFIG_FILE=$(readlink -f "$1")
# shellcheck disable=SC1090
. "$CONFIG_FILE"
RELEASE_URL="${RELEASE_URL:-https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download}"
trap 'rm -f /tmp/install.sh /tmp/install-xpadding.sh /tmp/add-dual-cdn.sh /tmp/add-dual-ip.sh /tmp/add-quic.sh /tmp/add-hysteria2.sh' EXIT

required() {
  [[ -n "${!1:-}" ]] || error "配置项未填写: $1"
}

boolean() {
  required "$1"
  [[ "${!1}" == "true" || "${!1}" == "false" ]] || error "配置项 $1 只能填写 true 或 false"
}

run_script() {
  info "下载并运行 $1"
  if ! curl -fsSL "$RELEASE_URL/$1" -o "/tmp/$1"; then
    rm -f "/tmp/$1"
    error "$1 下载失败"
  fi
  if ! printf '%s\n' "${@:2}" | bash "/tmp/$1"; then
    rm -f "/tmp/$1"
    error "$1 运行失败"
  fi
  rm -f "/tmp/$1"
}

boolean XPADDING_ENABLED
required REALITY_DOMAIN
required CDN_DOMAIN
required IP_CHOICE
required FALLBACK_CHOICE
boolean CDN_ECH_ENABLED
boolean DUAL_CDN_ENABLED
boolean DUAL_IP_ENABLED
boolean QUIC_ENABLED
boolean HYSTERIA2_ENABLED

[[ "$IP_CHOICE" == "1" || "$IP_CHOICE" == "2" ]] || error "IP_CHOICE 只能填写 1 或 2"
[[ "$FALLBACK_CHOICE" == "1" || "$FALLBACK_CHOICE" == "2" ]] || error "FALLBACK_CHOICE 只能填写 1 或 2"
[[ "$XPADDING_ENABLED" == "true" || "$CDN_ECH_ENABLED" == "false" ]] || error "启用 CDN ECH 前必须启用 XPADDING_ENABLED"

if [[ "$FALLBACK_CHOICE" == "2" ]]; then
  required REALITY_FALLBACK_ORIGIN
  required CDN_FALLBACK_ORIGIN
fi
if [[ "$XPADDING_ENABLED" == "true" ]]; then
  required XHTTP_PADDING_HEADER
  required XHTTP_PADDING_KEY
fi
if [[ "$DUAL_CDN_ENABLED" == "true" ]]; then
  boolean DUAL_CDN_REUSE_ECH
  required CDN_A
  required CDN_B
  if [[ "$FALLBACK_CHOICE" == "2" && "$CDN_A" != "$CDN_DOMAIN" ]]; then
    required CDN_A_FALLBACK_ORIGIN
  fi
  if [[ "$FALLBACK_CHOICE" == "2" && "$CDN_B" != "$CDN_A" && "$CDN_B" != "$CDN_DOMAIN" ]]; then
    required CDN_B_FALLBACK_ORIGIN
  fi
fi
if [[ "$DUAL_IP_ENABLED" == "true" ]]; then
  required REALITY_DOMAIN_V4
  required REALITY_DOMAIN_V6
  if [[ "$FALLBACK_CHOICE" == "2" && "$REALITY_DOMAIN_V4" != "$REALITY_DOMAIN" ]]; then
    required FALLBACK_ORIGIN_V4
  fi
  if [[ "$FALLBACK_CHOICE" == "2" && "$REALITY_DOMAIN_V6" != "$REALITY_DOMAIN" ]]; then
    required FALLBACK_ORIGIN_V6
  fi
fi
if [[ "$QUIC_ENABLED" == "true" ]]; then
  boolean QUIC_REUSE_ECH
  required XHTTP_H3_PORT
  [[ "$XHTTP_H3_PORT" =~ ^[0-9]+$ ]] && (( XHTTP_H3_PORT >= 1 && XHTTP_H3_PORT <= 65535 )) ||
    error "XHTTP_H3_PORT 必须是 1-65535 的整数"
fi
if [[ "$HYSTERIA2_ENABLED" == "true" ]]; then
  required HY2_PORT
  required HY2_PASSWORD
  [[ "$HY2_PORT" =~ ^[0-9]+$ ]] && (( HY2_PORT >= 1 && HY2_PORT <= 65535 )) ||
    error "HY2_PORT 必须是 1-65535 的整数"
  [[ "$HY2_PASSWORD" =~ ^[A-Za-z0-9._~-]+$ ]] || error "HY2_PASSWORD 仅支持字母、数字与 . _ ~ -"
fi
if [[ "$QUIC_ENABLED" == "true" && "$HYSTERIA2_ENABLED" == "true" && "$XHTTP_H3_PORT" == "$HY2_PORT" ]]; then
  error "XHTTP_H3_PORT 与 HY2_PORT 不能相同"
fi

MAIN_INPUT=("$REALITY_DOMAIN" "$CDN_DOMAIN" "$IP_CHOICE" "$FALLBACK_CHOICE")
if [[ "$FALLBACK_CHOICE" == "1" ]]; then
  MAIN_INPUT+=("")
else
  MAIN_INPUT+=("$REALITY_FALLBACK_ORIGIN" "$CDN_FALLBACK_ORIGIN")
fi

if [[ "$XPADDING_ENABLED" == "true" ]]; then
  MAIN_INPUT+=("$XHTTP_PADDING_HEADER" "$XHTTP_PADDING_KEY")
  [[ "$CDN_ECH_ENABLED" == "true" ]] && MAIN_INPUT+=("y") || MAIN_INPUT+=("n")
  run_script install-xpadding.sh "${MAIN_INPUT[@]}"
else
  run_script install.sh "${MAIN_INPUT[@]}"
fi

if [[ "$DUAL_CDN_ENABLED" == "true" ]]; then
  DUAL_CDN_INPUT=()
  if [[ "$CDN_ECH_ENABLED" == "true" ]]; then
    [[ "$DUAL_CDN_REUSE_ECH" == "true" ]] && DUAL_CDN_INPUT+=("y") || DUAL_CDN_INPUT+=("n")
  fi
  DUAL_CDN_INPUT+=("$CDN_A" "$CDN_B")
  if [[ "$FALLBACK_CHOICE" == "1" ]]; then
    DUAL_CDN_INPUT+=("")
  else
    if [[ "$CDN_A" != "$CDN_DOMAIN" ]]; then
      DUAL_CDN_INPUT+=("$CDN_A_FALLBACK_ORIGIN")
    fi
    if [[ "$CDN_B" != "$CDN_A" && "$CDN_B" != "$CDN_DOMAIN" ]]; then
      DUAL_CDN_INPUT+=("$CDN_B_FALLBACK_ORIGIN")
    fi
  fi
  run_script add-dual-cdn.sh "${DUAL_CDN_INPUT[@]}"
fi

if [[ "$DUAL_IP_ENABLED" == "true" ]]; then
  DUAL_IP_INPUT=("$REALITY_DOMAIN_V4" "$REALITY_DOMAIN_V6")
  if [[ "$FALLBACK_CHOICE" == "1" ]]; then
    DUAL_IP_INPUT+=("")
  else
    if [[ "$REALITY_DOMAIN_V4" != "$REALITY_DOMAIN" ]]; then
      DUAL_IP_INPUT+=("$FALLBACK_ORIGIN_V4")
    fi
    if [[ "$REALITY_DOMAIN_V6" != "$REALITY_DOMAIN" ]]; then
      DUAL_IP_INPUT+=("$FALLBACK_ORIGIN_V6")
    fi
  fi
  run_script add-dual-ip.sh "${DUAL_IP_INPUT[@]}"
fi

if [[ "$QUIC_ENABLED" == "true" ]]; then
  QUIC_INPUT=()
  if [[ "$CDN_ECH_ENABLED" == "true" ]]; then
    [[ "$QUIC_REUSE_ECH" == "true" ]] && QUIC_INPUT+=("y") || QUIC_INPUT+=("n")
  fi
  QUIC_INPUT+=("$XHTTP_H3_PORT")
  run_script add-quic.sh "${QUIC_INPUT[@]}"
fi

if [[ "$HYSTERIA2_ENABLED" == "true" ]]; then
  run_script add-hysteria2.sh "$HY2_PORT" "$HY2_PASSWORD"
fi

info "全部配置已执行完成"
