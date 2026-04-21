#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${TARGET_DIR:-/etc/sing-box}"
TARGET_CONFIG="${TARGET_CONFIG:-$TARGET_DIR/config.json}"
RULE_SET_DIR="${RULE_SET_DIR:-$TARGET_DIR/rule-set}"
ARTIFACT_DIR="${ARTIFACT_DIR:-/var/lib/sing-box-script}"
STATE_FILE="${STATE_FILE:-$ARTIFACT_DIR/install-state.json}"
SSL_DIR="${SSL_DIR:-$TARGET_DIR/ssl}"
CERT_FULLCHAIN="${CERT_FULLCHAIN:-$SSL_DIR/fullchain.pem}"
CERT_KEY="${CERT_KEY:-$SSL_DIR/key.pem}"
SHARE_LINKS_FILE="${SHARE_LINKS_FILE:-$ARTIFACT_DIR/share-links.txt}"
CLIENT_SNIPPET_FILE="${CLIENT_SNIPPET_FILE:-$ARTIFACT_DIR/client-config.json}"
CLIENT_FULL_CONFIG_FILE="${CLIENT_FULL_CONFIG_FILE:-$ARTIFACT_DIR/client-full.json}"
CLIENT_TUN_CONFIG_FILE="${CLIENT_TUN_CONFIG_FILE:-$ARTIFACT_DIR/client-tun.json}"
SUMMARY_FILE="${SUMMARY_FILE:-$ARTIFACT_DIR/deployment-summary.txt}"
ACME_LOG_FILE="${ACME_LOG_FILE:-$ARTIFACT_DIR/acme-issue.log}"
ACME_HOME="${ACME_HOME:-/root/.acme.sh}"
ACME_SH="$ACME_HOME/acme.sh"
SERVICE_NAME="${SERVICE_NAME:-sing-box}"

COMMAND="install"
ARG_SEEN=0
ASSUME_YES=0

INTERACTIVE_MODE="${SB_INTERACTIVE:-auto}"
PROTOCOLS_SET=0
ROTATE_SECRETS=0

PROTOCOLS_CSV="${SB_PROTOCOLS:-}"
VLESS_MODE="${SB_VLESS_MODE:-}"
DOMAIN="${SB_DOMAIN:-}"
EMAIL="${SB_EMAIL:-}"
SHARE_HOST="${SB_SHARE_HOST:-}"
CERT_MODE="${SB_CERT_MODE:-}"
ACME_MODE="${SB_ACME_MODE:-auto}"
CLIENT_FINGERPRINT="${SB_CLIENT_FINGERPRINT:-chrome}"
REALITY_SERVER_NAME="${SB_REALITY_SERVER_NAME:-}"
REALITY_HANDSHAKE_SERVER="${SB_REALITY_HANDSHAKE_SERVER:-}"
REALITY_HANDSHAKE_PORT="${SB_REALITY_HANDSHAKE_PORT:-}"
NAIVE_NETWORK="${SB_NAIVE_NETWORK:-}"
SS2022_METHOD="${SB_SS2022_METHOD:-}"
TUIC_CONGESTION_CONTROL="${SB_TUIC_CC:-}"
MANAGE_PROTOCOL="${SB_MANAGE_PROTOCOL:-}"
MANAGE_USER_NAME="${SB_USER_NAME:-}"
MANAGE_USER_UUID="${SB_USER_UUID:-}"
MANAGE_USER_PASSWORD="${SB_USER_PASSWORD:-}"
ROUTE_ACTION="${SB_ROUTE_ACTION:-}"

VLESS_PORT="${SB_VLESS_PORT:-}"
VMESS_PORT="${SB_VMESS_PORT:-}"
TROJAN_PORT="${SB_TROJAN_PORT:-}"
HYSTERIA2_PORT="${SB_HYSTERIA2_PORT:-}"
TUIC_PORT="${SB_TUIC_PORT:-}"
NAIVE_PORT="${SB_NAIVE_PORT:-}"
SOCKS5_PORT="${SB_SOCKS5_PORT:-}"
SS2022_PORT="${SB_SS2022_PORT:-}"

STATE_LOADED=0
APT_UPDATED=0
TLS_REQUIRED=0
TLS_STATUS="not-requested"
TLS_REASON=""
ACME_CHALLENGE_USED="none"
SING_BOX_VERSION="not-installed"
SING_BOX_VERSION_NUMBER=""
BACKUP_PATH=""

VLESS_UUID=""
VMESS_UUID=""
TROJAN_PASSWORD=""
HYSTERIA2_PASSWORD=""
HYSTERIA2_OBFS_PASSWORD=""
TUIC_UUID=""
TUIC_PASSWORD=""
NAIVE_USERNAME=""
NAIVE_PASSWORD=""
SOCKS5_USERNAME=""
SOCKS5_PASSWORD=""
SS2022_SERVER_PASSWORD=""
SS2022_USER_PASSWORD=""
REALITY_PRIVATE_KEY=""
REALITY_PUBLIC_KEY=""
REALITY_SHORT_ID=""
ROUTE_BLOCK_BITTORRENT="${SB_ROUTE_BLOCK_BITTORRENT:-}"
ROUTE_BLOCK_CN="${SB_ROUTE_BLOCK_CN:-}"
ROUTE_BLOCK_ADS="${SB_ROUTE_BLOCK_ADS:-}"

VLESS_USERS_JSON='[]'
VMESS_USERS_JSON='[]'
TROJAN_USERS_JSON='[]'
HYSTERIA2_USERS_JSON='[]'
TUIC_USERS_JSON='[]'
NAIVE_USERS_JSON='[]'
SOCKS5_USERS_JSON='[]'
SS2022_USERS_JSON='[]'

declare -a ENABLED_PROTOCOLS=()
declare -A PROTOCOL_SELECTED=()

SUPPORTED_PROTOCOL_ORDER=(
  vless
  vmess
  trojan
  hysteria2
  tuic
  naive
  socks5
  ss2022
)

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: install-sing-box.sh [command] [options]

Commands:
  install        Install or reconfigure sing-box all-in-one service (default)
  list-users     List saved users for one or all protocols
  add-user       Add one user to a protocol and reload sing-box
  remove-user    Remove one user from a protocol and reload sing-box
  regenerate     Re-render config/share artifacts from saved state and reload sing-box
  routing-menu   Interactive routing policy menu
  client-menu    Interactive sing-box client config menu
  show-info      Print saved share links and client snippets
  validate       Run sing-box format/check on the deployed config
  status         Show service status
  restart        Restart sing-box
  stop           Stop sing-box
  uninstall      Remove deployed files and optionally uninstall sing-box

Options:
  --protocols LIST            Comma-separated protocols:
                              vless,vmess,trojan,hysteria2,tuic,naive,socks5,ss2022
  --vless-mode reality|tls
  --domain DOMAIN
  --email EMAIL
  --cert-mode acme|self-signed
  --share-host HOST
  --acme-mode auto|standalone|alpn
  --naive-network tcp|udp
  --ss2022-method METHOD
  --tuic-cc cubic|new_reno|bbr
  --reality-server-name HOST
  --reality-handshake-server HOST
  --reality-handshake-port PORT
  --protocol NAME              For add-user/remove-user/list-users:
                               vless,vmess,trojan,hysteria2,tuic,naive,socks5,ss2022
  --user-name NAME
  --user-uuid UUID
  --user-password VALUE
  --vless-port PORT
  --vmess-port PORT
  --trojan-port PORT
  --hysteria2-port PORT
  --tuic-port PORT
  --naive-port PORT
  --socks5-port PORT
  --ss2022-port PORT
  --rotate-secrets
  --interactive
  --non-interactive
  --yes
  --target-config PATH
  --help

Examples:
  ./install-sing-box.sh
  ./install-sing-box.sh install --protocols vless,vmess,trojan,hysteria2,tuic,naive,socks5,ss2022 --domain example.com --email admin@example.com
  ./install-sing-box.sh install --protocols vless,socks5,ss2022 --vless-mode reality
  ./install-sing-box.sh list-users
  ./install-sing-box.sh add-user --protocol vmess --user-name alice
  ./install-sing-box.sh remove-user --protocol socks5 --user-name socks-123abc
  ./install-sing-box.sh show-info
  ./install-sing-box.sh validate
  ./install-sing-box.sh restart
EOF
}

refresh_paths_from_target_config() {
  TARGET_DIR="$(dirname -- "$TARGET_CONFIG")"
  RULE_SET_DIR="$TARGET_DIR/rule-set"
  SSL_DIR="$TARGET_DIR/ssl"
  CERT_FULLCHAIN="$SSL_DIR/fullchain.pem"
  CERT_KEY="$SSL_DIR/key.pem"
  STATE_FILE="$ARTIFACT_DIR/install-state.json"
  SHARE_LINKS_FILE="$ARTIFACT_DIR/share-links.txt"
  CLIENT_SNIPPET_FILE="$ARTIFACT_DIR/client-config.json"
  CLIENT_FULL_CONFIG_FILE="$ARTIFACT_DIR/client-full.json"
  CLIENT_TUN_CONFIG_FILE="$ARTIFACT_DIR/client-tun.json"
  SUMMARY_FILE="$ARTIFACT_DIR/deployment-summary.txt"
  ACME_LOG_FILE="$ARTIFACT_DIR/acme-issue.log"
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      install|list-users|add-user|remove-user|regenerate|show-info|validate|status|restart|stop|routing-menu|client-menu|uninstall)
        COMMAND="$1"
        ARG_SEEN=1
        shift
        ;;
      --protocols)
        (($# >= 2)) || die "--protocols requires a value"
        PROTOCOLS_CSV="$2"
        PROTOCOLS_SET=1
        ARG_SEEN=1
        shift 2
        ;;
      --vless-mode)
        (($# >= 2)) || die "--vless-mode requires a value"
        VLESS_MODE="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --domain)
        (($# >= 2)) || die "--domain requires a value"
        DOMAIN="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --email)
        (($# >= 2)) || die "--email requires a value"
        EMAIL="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --cert-mode)
        (($# >= 2)) || die "--cert-mode requires a value"
        CERT_MODE="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --share-host)
        (($# >= 2)) || die "--share-host requires a value"
        SHARE_HOST="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --acme-mode)
        (($# >= 2)) || die "--acme-mode requires a value"
        ACME_MODE="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --naive-network)
        (($# >= 2)) || die "--naive-network requires a value"
        NAIVE_NETWORK="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --ss2022-method)
        (($# >= 2)) || die "--ss2022-method requires a value"
        SS2022_METHOD="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --tuic-cc)
        (($# >= 2)) || die "--tuic-cc requires a value"
        TUIC_CONGESTION_CONTROL="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --reality-server-name)
        (($# >= 2)) || die "--reality-server-name requires a value"
        REALITY_SERVER_NAME="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --reality-handshake-server)
        (($# >= 2)) || die "--reality-handshake-server requires a value"
        REALITY_HANDSHAKE_SERVER="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --reality-handshake-port)
        (($# >= 2)) || die "--reality-handshake-port requires a value"
        REALITY_HANDSHAKE_PORT="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --protocol)
        (($# >= 2)) || die "--protocol requires a value"
        MANAGE_PROTOCOL="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --user-name)
        (($# >= 2)) || die "--user-name requires a value"
        MANAGE_USER_NAME="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --user-uuid)
        (($# >= 2)) || die "--user-uuid requires a value"
        MANAGE_USER_UUID="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --user-password)
        (($# >= 2)) || die "--user-password requires a value"
        MANAGE_USER_PASSWORD="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --vless-port)
        (($# >= 2)) || die "--vless-port requires a value"
        VLESS_PORT="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --vmess-port)
        (($# >= 2)) || die "--vmess-port requires a value"
        VMESS_PORT="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --trojan-port)
        (($# >= 2)) || die "--trojan-port requires a value"
        TROJAN_PORT="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --hysteria2-port)
        (($# >= 2)) || die "--hysteria2-port requires a value"
        HYSTERIA2_PORT="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --tuic-port)
        (($# >= 2)) || die "--tuic-port requires a value"
        TUIC_PORT="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --naive-port)
        (($# >= 2)) || die "--naive-port requires a value"
        NAIVE_PORT="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --socks5-port)
        (($# >= 2)) || die "--socks5-port requires a value"
        SOCKS5_PORT="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --ss2022-port)
        (($# >= 2)) || die "--ss2022-port requires a value"
        SS2022_PORT="$2"
        ARG_SEEN=1
        shift 2
        ;;
      --rotate-secrets)
        ROTATE_SECRETS=1
        ARG_SEEN=1
        shift
        ;;
      --interactive)
        INTERACTIVE_MODE="1"
        ARG_SEEN=1
        shift
        ;;
      --non-interactive)
        INTERACTIVE_MODE="0"
        ARG_SEEN=1
        shift
        ;;
      --yes)
        ASSUME_YES=1
        ARG_SEEN=1
        shift
        ;;
      --target-config)
        (($# >= 2)) || die "--target-config requires a value"
        TARGET_CONFIG="$2"
        refresh_paths_from_target_config
        ARG_SEEN=1
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown option or command: $1"
        ;;
    esac
  done
}

should_prompt_interactively() {
  case "$INTERACTIVE_MODE" in
    1|true|yes|on)
      return 0
      ;;
    0|false|no|off)
      return 1
      ;;
    auto)
      [[ -t 0 && -t 1 ]]
      return $?
      ;;
    *)
      die "Unsupported interactive mode: $INTERACTIVE_MODE"
      ;;
  esac
}

normalize_protocol_name() {
  case "${1,,}" in
    vless)
      printf 'vless\n'
      ;;
    vmess)
      printf 'vmess\n'
      ;;
    trojan)
      printf 'trojan\n'
      ;;
    hysteria2|hy2)
      printf 'hysteria2\n'
      ;;
    tuic)
      printf 'tuic\n'
      ;;
    naive|naiveproxy)
      printf 'naive\n'
      ;;
    socks|socks5)
      printf 'socks5\n'
      ;;
    ss|ss2022|shadowsocks|shadowsocks-2022)
      printf 'ss2022\n'
      ;;
    *)
      return 1
      ;;
  esac
}

protocol_label() {
  case "$1" in
    vless) printf 'VLESS\n' ;;
    vmess) printf 'VMess\n' ;;
    trojan) printf 'Trojan\n' ;;
    hysteria2) printf 'Hysteria2\n' ;;
    tuic) printf 'TUIC\n' ;;
    naive) printf 'NaiveProxy\n' ;;
    socks5) printf 'SOCKS5\n' ;;
    ss2022) printf 'SS2022\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

clear_protocol_selection() {
  ENABLED_PROTOCOLS=()
  PROTOCOL_SELECTED=()
}

add_protocol() {
  local normalized=""

  normalized="$(normalize_protocol_name "$1")" || die "Unsupported protocol: $1"
  if [[ -n "${PROTOCOL_SELECTED[$normalized]+x}" ]]; then
    return 0
  fi

  ENABLED_PROTOCOLS+=("$normalized")
  PROTOCOL_SELECTED["$normalized"]=1
}

load_protocols_from_csv() {
  local raw="$1"
  local item=""
  local cleaned=""
  local had_any=0

  clear_protocol_selection
  cleaned="${raw// /}"
  IFS=',' read -r -a items <<< "$cleaned"
  for item in "${items[@]}"; do
    [[ -n "$item" ]] || continue
    add_protocol "$item"
    had_any=1
  done

  [[ "$had_any" -eq 1 ]] || die "No valid protocols were selected"
}

set_default_protocols() {
  clear_protocol_selection
  local item=""
  for item in "${SUPPORTED_PROTOCOL_ORDER[@]}"; do
    add_protocol "$item"
  done
}

protocol_enabled() {
  local normalized=""
  normalized="$(normalize_protocol_name "$1")" || return 1
  [[ -n "${PROTOCOL_SELECTED[$normalized]+x}" ]]
}

protocols_csv() {
  local item=""
  local first=1

  for item in "${ENABLED_PROTOCOLS[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      printf '%s' "$item"
      first=0
    else
      printf ',%s' "$item"
    fi
  done
  printf '\n'
}

protocols_pretty() {
  local item=""
  local first=1

  for item in "${ENABLED_PROTOCOLS[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      printf '%s' "$(protocol_label "$item")"
      first=0
    else
      printf ', %s' "$(protocol_label "$item")"
    fi
  done
  printf '\n'
}

protocols_json() {
  printf '%s\n' "${ENABLED_PROTOCOLS[@]}" | jq -R . | jq -s .
}

state_value() {
  local query="$1"

  if [[ "$STATE_LOADED" -eq 0 ]]; then
    printf '\n'
    return 0
  fi

  jq -r "$query // empty" "$STATE_FILE"
}

state_json() {
  local query="$1"

  if [[ "$STATE_LOADED" -eq 0 ]]; then
    printf 'null\n'
    return 0
  fi

  jq -c "$query" "$STATE_FILE"
}

get_users_json_var() {
  case "$1" in
    vless) printf '%s\n' "$VLESS_USERS_JSON" ;;
    vmess) printf '%s\n' "$VMESS_USERS_JSON" ;;
    trojan) printf '%s\n' "$TROJAN_USERS_JSON" ;;
    hysteria2) printf '%s\n' "$HYSTERIA2_USERS_JSON" ;;
    tuic) printf '%s\n' "$TUIC_USERS_JSON" ;;
    naive) printf '%s\n' "$NAIVE_USERS_JSON" ;;
    socks5) printf '%s\n' "$SOCKS5_USERS_JSON" ;;
    ss2022) printf '%s\n' "$SS2022_USERS_JSON" ;;
    *)
      die "Unknown protocol in get_users_json_var: $1"
      ;;
  esac
}

set_users_json_var() {
  local protocol="$1"
  local value="$2"

  case "$protocol" in
    vless) VLESS_USERS_JSON="$value" ;;
    vmess) VMESS_USERS_JSON="$value" ;;
    trojan) TROJAN_USERS_JSON="$value" ;;
    hysteria2) HYSTERIA2_USERS_JSON="$value" ;;
    tuic) TUIC_USERS_JSON="$value" ;;
    naive) NAIVE_USERS_JSON="$value" ;;
    socks5) SOCKS5_USERS_JSON="$value" ;;
    ss2022) SS2022_USERS_JSON="$value" ;;
    *)
      die "Unknown protocol in set_users_json_var: $protocol"
      ;;
  esac
}

protocol_user_key() {
  case "$1" in
    vless|vmess|trojan|hysteria2|tuic|ss2022)
      printf 'name\n'
      ;;
    naive|socks5)
      printf 'username\n'
      ;;
    *)
      die "Unknown protocol in protocol_user_key: $1"
      ;;
  esac
}

user_exists_in_json() {
  local protocol="$1"
  local users_json="$2"
  local user_key=""

  user_key="$(protocol_user_key "$protocol")"
  jq -e --arg key "$user_key" --arg value "$MANAGE_USER_NAME" 'map(select(.[$key] == $value)) | length > 0' <<< "$users_json" >/dev/null
}

build_default_user_json_for_protocol() {
  case "$1" in
    vless)
      jq -nc --arg name "vless" --arg uuid "$VLESS_UUID" --arg flow "xtls-rprx-vision" '[{name: $name, uuid: $uuid, flow: $flow}]'
      ;;
    vmess)
      jq -nc --arg name "vmess" --arg uuid "$VMESS_UUID" '[{name: $name, uuid: $uuid, alterId: 0}]'
      ;;
    trojan)
      jq -nc --arg name "trojan" --arg password "$TROJAN_PASSWORD" '[{name: $name, password: $password}]'
      ;;
    hysteria2)
      jq -nc --arg name "hy2" --arg password "$HYSTERIA2_PASSWORD" '[{name: $name, password: $password}]'
      ;;
    tuic)
      jq -nc --arg name "tuic" --arg uuid "$TUIC_UUID" --arg password "$TUIC_PASSWORD" '[{name: $name, uuid: $uuid, password: $password}]'
      ;;
    naive)
      jq -nc --arg username "$NAIVE_USERNAME" --arg password "$NAIVE_PASSWORD" '[{username: $username, password: $password}]'
      ;;
    socks5)
      jq -nc --arg username "$SOCKS5_USERNAME" --arg password "$SOCKS5_PASSWORD" '[{username: $username, password: $password}]'
      ;;
    ss2022)
      jq -nc --arg name "ss2022" --arg password "$SS2022_USER_PASSWORD" '[{name: $name, password: $password}]'
      ;;
    *)
      die "Unknown protocol in build_default_user_json_for_protocol: $1"
      ;;
  esac
}

normalize_protocol_or_die() {
  local normalized=""
  normalized="$(normalize_protocol_name "$1")" || die "Unsupported protocol: $1"
  printf '%s\n' "$normalized"
}

load_state() {
  if [[ -f "$STATE_FILE" ]] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    STATE_LOADED=1
  else
    STATE_LOADED=0
  fi
}

load_defaults_from_state() {
  if [[ "$STATE_LOADED" -eq 0 ]]; then
    return 0
  fi

  if [[ "$PROTOCOLS_SET" -eq 0 && -z "$PROTOCOLS_CSV" ]]; then
    PROTOCOLS_CSV="$(state_value '.enabled_protocols | join(",")')"
  fi

  [[ -n "$VLESS_MODE" ]] || VLESS_MODE="$(state_value '.settings.vless_mode')"
  [[ -n "$DOMAIN" ]] || DOMAIN="$(state_value '.domain')"
  [[ -n "$EMAIL" ]] || EMAIL="$(state_value '.email')"
  [[ -n "$SHARE_HOST" ]] || SHARE_HOST="$(state_value '.share_host')"
  [[ -n "$CERT_MODE" ]] || CERT_MODE="$(state_value '.cert_mode')"
  [[ -n "$ACME_MODE" && "$ACME_MODE" != "auto" ]] || ACME_MODE="$(state_value '.acme_mode')"
  [[ -n "$REALITY_SERVER_NAME" ]] || REALITY_SERVER_NAME="$(state_value '.settings.reality.server_name')"
  [[ -n "$REALITY_HANDSHAKE_SERVER" ]] || REALITY_HANDSHAKE_SERVER="$(state_value '.settings.reality.handshake_server')"
  [[ -n "$REALITY_HANDSHAKE_PORT" ]] || REALITY_HANDSHAKE_PORT="$(state_value '.settings.reality.handshake_port')"
  [[ -n "$NAIVE_NETWORK" ]] || NAIVE_NETWORK="$(state_value '.settings.naive_network')"
  [[ -n "$SS2022_METHOD" ]] || SS2022_METHOD="$(state_value '.settings.ss2022_method')"
  [[ -n "$TUIC_CONGESTION_CONTROL" ]] || TUIC_CONGESTION_CONTROL="$(state_value '.settings.tuic_congestion_control')"
  [[ -n "$ROUTE_BLOCK_BITTORRENT" ]] || ROUTE_BLOCK_BITTORRENT="$(state_value '.routing.block_bittorrent')"
  [[ -n "$ROUTE_BLOCK_CN" ]] || ROUTE_BLOCK_CN="$(state_value '.routing.block_cn')"
  [[ -n "$ROUTE_BLOCK_ADS" ]] || ROUTE_BLOCK_ADS="$(state_value '.routing.block_ads')"

  [[ -n "$VLESS_PORT" ]] || VLESS_PORT="$(state_value '.ports.vless')"
  [[ -n "$VMESS_PORT" ]] || VMESS_PORT="$(state_value '.ports.vmess')"
  [[ -n "$TROJAN_PORT" ]] || TROJAN_PORT="$(state_value '.ports.trojan')"
  [[ -n "$HYSTERIA2_PORT" ]] || HYSTERIA2_PORT="$(state_value '.ports.hysteria2')"
  [[ -n "$TUIC_PORT" ]] || TUIC_PORT="$(state_value '.ports.tuic')"
  [[ -n "$NAIVE_PORT" ]] || NAIVE_PORT="$(state_value '.ports.naive')"
  [[ -n "$SOCKS5_PORT" ]] || SOCKS5_PORT="$(state_value '.ports.socks5')"
  [[ -n "$SS2022_PORT" ]] || SS2022_PORT="$(state_value '.ports.ss2022')"

  if [[ "$ROTATE_SECRETS" -eq 0 ]]; then
    [[ -n "$VLESS_UUID" ]] || VLESS_UUID="$(state_value '.credentials.vless.uuid')"
    [[ -n "$VMESS_UUID" ]] || VMESS_UUID="$(state_value '.credentials.vmess.uuid')"
    [[ -n "$TROJAN_PASSWORD" ]] || TROJAN_PASSWORD="$(state_value '.credentials.trojan.password')"
    [[ -n "$HYSTERIA2_PASSWORD" ]] || HYSTERIA2_PASSWORD="$(state_value '.credentials.hysteria2.password')"
    [[ -n "$HYSTERIA2_OBFS_PASSWORD" ]] || HYSTERIA2_OBFS_PASSWORD="$(state_value '.credentials.hysteria2.obfs_password')"
    [[ -n "$TUIC_UUID" ]] || TUIC_UUID="$(state_value '.credentials.tuic.uuid')"
    [[ -n "$TUIC_PASSWORD" ]] || TUIC_PASSWORD="$(state_value '.credentials.tuic.password')"
    [[ -n "$NAIVE_USERNAME" ]] || NAIVE_USERNAME="$(state_value '.credentials.naive.username')"
    [[ -n "$NAIVE_PASSWORD" ]] || NAIVE_PASSWORD="$(state_value '.credentials.naive.password')"
    [[ -n "$SOCKS5_USERNAME" ]] || SOCKS5_USERNAME="$(state_value '.credentials.socks5.username')"
    [[ -n "$SOCKS5_PASSWORD" ]] || SOCKS5_PASSWORD="$(state_value '.credentials.socks5.password')"
    [[ -n "$SS2022_SERVER_PASSWORD" ]] || SS2022_SERVER_PASSWORD="$(state_value '.credentials.ss2022.server_password')"
    [[ -n "$SS2022_USER_PASSWORD" ]] || SS2022_USER_PASSWORD="$(state_value '.credentials.ss2022.user_password')"
    [[ -n "$REALITY_PRIVATE_KEY" ]] || REALITY_PRIVATE_KEY="$(state_value '.credentials.vless.reality_private_key')"
    [[ -n "$REALITY_PUBLIC_KEY" ]] || REALITY_PUBLIC_KEY="$(state_value '.credentials.vless.reality_public_key')"
    [[ -n "$REALITY_SHORT_ID" ]] || REALITY_SHORT_ID="$(state_value '.credentials.vless.reality_short_id')"
  fi

  VLESS_USERS_JSON="$(state_json '.users.vless // []')"
  VMESS_USERS_JSON="$(state_json '.users.vmess // []')"
  TROJAN_USERS_JSON="$(state_json '.users.trojan // []')"
  HYSTERIA2_USERS_JSON="$(state_json '.users.hysteria2 // []')"
  TUIC_USERS_JSON="$(state_json '.users.tuic // []')"
  NAIVE_USERS_JSON="$(state_json '.users.naive // []')"
  SOCKS5_USERS_JSON="$(state_json '.users.socks5 // []')"
  SS2022_USERS_JSON="$(state_json '.users.ss2022 // []')"
}

apply_runtime_defaults() {
  if [[ "$PROTOCOLS_SET" -eq 1 || -n "$PROTOCOLS_CSV" ]]; then
    load_protocols_from_csv "$PROTOCOLS_CSV"
  else
    set_default_protocols
  fi

  [[ -n "$ACME_MODE" ]] || ACME_MODE="auto"
  [[ -n "$CERT_MODE" ]] || CERT_MODE="acme"
  [[ -n "$VLESS_MODE" ]] || VLESS_MODE="reality"
  [[ -n "$REALITY_SERVER_NAME" ]] || REALITY_SERVER_NAME="icloud.com"
  [[ -n "$REALITY_HANDSHAKE_SERVER" ]] || REALITY_HANDSHAKE_SERVER="$REALITY_SERVER_NAME"
  [[ -n "$REALITY_HANDSHAKE_PORT" ]] || REALITY_HANDSHAKE_PORT="443"
  [[ -n "$NAIVE_NETWORK" ]] || NAIVE_NETWORK="tcp"
  [[ -n "$SS2022_METHOD" ]] || SS2022_METHOD="2022-blake3-aes-128-gcm"
  [[ -n "$TUIC_CONGESTION_CONTROL" ]] || TUIC_CONGESTION_CONTROL="cubic"
  [[ -n "$ROUTE_BLOCK_BITTORRENT" ]] || ROUTE_BLOCK_BITTORRENT="0"
  [[ -n "$ROUTE_BLOCK_CN" ]] || ROUTE_BLOCK_CN="0"
  [[ -n "$ROUTE_BLOCK_ADS" ]] || ROUTE_BLOCK_ADS="0"
}

update_tls_requirement() {
  TLS_REQUIRED=0

  if protocol_enabled vless && [[ "$VLESS_MODE" == "tls" ]]; then
    TLS_REQUIRED=1
  fi
  if protocol_enabled vmess || protocol_enabled trojan || protocol_enabled hysteria2 || protocol_enabled tuic || protocol_enabled naive; then
    TLS_REQUIRED=1
  fi
}

validate_selection() {
  [[ "${#ENABLED_PROTOCOLS[@]}" -gt 0 ]] || die "At least one protocol must be enabled"

  case "$VLESS_MODE" in
    reality|tls)
      ;;
    *)
      die "Unsupported VLESS mode: $VLESS_MODE"
      ;;
  esac

  case "$ACME_MODE" in
    auto|standalone|alpn)
      ;;
    *)
      die "Unsupported ACME mode: $ACME_MODE"
      ;;
  esac

  case "$CERT_MODE" in
    acme|self-signed)
      ;;
    *)
      die "Unsupported certificate mode: $CERT_MODE"
      ;;
  esac

  case "$NAIVE_NETWORK" in
    tcp|udp)
      ;;
    *)
      die "Unsupported Naive network: $NAIVE_NETWORK"
      ;;
  esac

  case "$SS2022_METHOD" in
    2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305)
      ;;
    *)
      die "Unsupported SS2022 method: $SS2022_METHOD"
      ;;
  esac

  case "$TUIC_CONGESTION_CONTROL" in
    cubic|new_reno|bbr)
      ;;
    *)
      die "Unsupported TUIC congestion control: $TUIC_CONGESTION_CONTROL"
      ;;
  esac

  case "$ROUTE_BLOCK_BITTORRENT" in
    0|1) ;;
    *) die "Unsupported routing flag ROUTE_BLOCK_BITTORRENT: $ROUTE_BLOCK_BITTORRENT" ;;
  esac

  case "$ROUTE_BLOCK_CN" in
    0|1) ;;
    *) die "Unsupported routing flag ROUTE_BLOCK_CN: $ROUTE_BLOCK_CN" ;;
  esac

  case "$ROUTE_BLOCK_ADS" in
    0|1) ;;
    *) die "Unsupported routing flag ROUTE_BLOCK_ADS: $ROUTE_BLOCK_ADS" ;;
  esac

  update_tls_requirement
}

prompt_text_value() {
  local label="$1"
  local current_value="$2"
  local description="${3:-}"
  local required="${4:-0}"
  local input=""

  PROMPT_RESULT="$current_value"

  if ! should_prompt_interactively; then
    return 0
  fi

  while true; do
    [[ -n "$description" ]] && printf '%s\n' "$description" >&2
    if [[ -n "$current_value" ]]; then
      printf '请输入 %s [%s]: ' "$label" "$current_value" >&2
    else
      printf '请输入 %s: ' "$label" >&2
    fi
    read -r input

    if [[ -z "$input" ]]; then
      if [[ "$required" == "1" && -z "$current_value" ]]; then
        warn "${label} 不能为空，请重新输入。"
        continue
      fi
      PROMPT_RESULT="$current_value"
      return 0
    fi

    PROMPT_RESULT="$input"
    return 0
  done
}

prompt_main_menu() {
  local input=""

  if ! should_prompt_interactively; then
    return 0
  fi

  if [[ "$ARG_SEEN" -eq 1 ]]; then
    return 0
  fi

  while true; do
    printf '\n' >&2
    printf '%s\n' "================ sing-box all-in-one 菜单 ================" >&2
    print_menu_status_summary
    printf '%s\n' "  1) 安装 / 重配多协议服务" >&2
    printf '%s\n' "  2) 查看用户列表" >&2
    printf '%s\n' "  3) 新增用户" >&2
    printf '%s\n' "  4) 删除用户" >&2
    printf '%s\n' "  5) 重建配置与分享信息" >&2
    printf '%s\n' "  6) 查看分享链接与客户端片段" >&2
    printf '%s\n' "  7) 校验当前配置" >&2
    printf '%s\n' "  8) 查看服务状态" >&2
    printf '%s\n' "  9) 重启服务" >&2
    printf '%s\n' " 10) 停止服务" >&2
    printf '%s\n' " 11) 分流管理" >&2
    printf '%s\n' " 12) 客户端配置管理" >&2
    printf '%s\n' " 13) 卸载" >&2
    printf '%s\n' "  0) 退出" >&2
    printf '%s' "请选择操作 [0-13]，直接回车默认安装: " >&2
    read -r input

    case "$input" in
      ""|1)
        COMMAND="install"
        return 0
        ;;
      2)
        COMMAND="list-users"
        return 0
        ;;
      3)
        COMMAND="add-user"
        return 0
        ;;
      4)
        COMMAND="remove-user"
        return 0
        ;;
      5)
        COMMAND="regenerate"
        return 0
        ;;
      6)
        COMMAND="show-info"
        return 0
        ;;
      7)
        COMMAND="validate"
        return 0
        ;;
      8)
        COMMAND="status"
        return 0
        ;;
      9)
        COMMAND="restart"
        return 0
        ;;
      10)
        COMMAND="stop"
        return 0
        ;;
      11)
        COMMAND="routing-menu"
        return 0
        ;;
      12)
        COMMAND="client-menu"
        return 0
        ;;
      13)
        COMMAND="uninstall"
        return 0
        ;;
      0)
        exit 0
        ;;
      *)
        warn "无效选项，请重新输入。"
        ;;
    esac
  done
}

interactive_menu_mode() {
  if [[ "$ARG_SEEN" -ne 0 ]]; then
    return 1
  fi

  should_prompt_interactively
}

menu_status_value() {
  local service_state="not-installed"
  local enabled_state="not-installed"
  local version="not-installed"
  local protocols="not-configured"
  local routing="BT/PT:off, 回国限制:off, 广告拦截:off"

  if command -v sing-box >/dev/null 2>&1; then
    version="$(sing-box version 2>/dev/null | head -n 1 || true)"
    [[ -n "$version" ]] || version="installed"
    service_state="$(systemctl is-active sing-box 2>/dev/null || true)"
    enabled_state="$(systemctl is-enabled sing-box 2>/dev/null || true)"
    [[ -n "$service_state" ]] || service_state="unknown"
    [[ -n "$enabled_state" ]] || enabled_state="unknown"
  fi

  if [[ -f "$STATE_FILE" ]] && jq -e '.enabled_protocols | length > 0' "$STATE_FILE" >/dev/null 2>&1; then
    protocols="$(jq -r '.enabled_protocols | join(", ")' "$STATE_FILE")"
  fi

  if [[ -f "$STATE_FILE" ]] && jq -e '.routing' "$STATE_FILE" >/dev/null 2>&1; then
    routing="$(jq -r '"BT/PT:" + (if .routing.block_bittorrent then "on" else "off" end) + ", 回国限制:" + (if .routing.block_cn then "on" else "off" end) + ", 广告拦截:" + (if .routing.block_ads then "on" else "off" end)' "$STATE_FILE")"
  fi

  printf '%s|%s|%s|%s|%s\n' "$service_state" "$enabled_state" "$version" "$protocols" "$routing"
}

print_menu_status_summary() {
  local status_line=""
  local service_state=""
  local enabled_state=""
  local version=""
  local protocols=""
  local routing=""

  status_line="$(menu_status_value)"
  IFS='|' read -r service_state enabled_state version protocols routing <<< "$status_line"

  printf '%s\n' "---------------- 当前状态 ----------------" >&2
  printf '  服务状态: %s\n' "$service_state" >&2
  printf '  开机自启: %s\n' "$enabled_state" >&2
  printf '  版本信息: %s\n' "$version" >&2
  printf '  当前协议: %s\n' "$protocols" >&2
  printf '  分流策略: %s\n' "$routing" >&2
  printf '%s\n' "------------------------------------------" >&2
}

menu_command_label() {
  case "$1" in
    install) printf '安装 / 重配多协议服务\n' ;;
    list-users) printf '查看用户列表\n' ;;
    add-user) printf '新增用户\n' ;;
    remove-user) printf '删除用户\n' ;;
    regenerate) printf '重建配置与分享信息\n' ;;
    show-info) printf '查看分享链接与客户端片段\n' ;;
    validate) printf '校验当前配置\n' ;;
    status) printf '查看服务状态\n' ;;
    restart) printf '重启服务\n' ;;
    stop) printf '停止服务\n' ;;
    routing-menu) printf '分流管理\n' ;;
    client-menu) printf '客户端配置管理\n' ;;
    uninstall) printf '卸载\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

print_menu_action_banner() {
  printf '\n================ 执行：%s ================\n\n' "$(menu_command_label "$1")"
}

print_menu_return_banner() {
  printf '\n================ 返回主菜单 ================\n'
}

reset_menu_iteration_state() {
  COMMAND="install"
  MANAGE_PROTOCOL=""
  MANAGE_USER_NAME=""
  MANAGE_USER_UUID=""
  MANAGE_USER_PASSWORD=""
}

prompt_protocol_selection() {
  local input=""
  local current=""
  local token=""
  local normalized=""

  if ! should_prompt_interactively; then
    return 0
  fi

  current="$(protocols_csv)"
  printf '%s\n' "请选择要启用的协议，可输入编号组合（如 1,3,8）或协议名列表。" >&2
  printf '%s\n' "  1) VLESS" >&2
  printf '%s\n' "  2) VMess" >&2
  printf '%s\n' "  3) Trojan" >&2
  printf '%s\n' "  4) Hysteria2" >&2
  printf '%s\n' "  5) TUIC" >&2
  printf '%s\n' "  6) NaiveProxy" >&2
  printf '%s\n' "  7) SOCKS5" >&2
  printf '%s\n' "  8) SS2022" >&2

  while true; do
    printf '当前选择 [%s]，直接回车保留: ' "$current" >&2
    read -r input
    [[ -z "$input" ]] && return 0

    clear_protocol_selection
    input="${input// /}"
    IFS=',' read -r -a tokens <<< "$input"
    local valid=1
    for token in "${tokens[@]}"; do
      normalized=""
      case "$token" in
        1) normalized="vless" ;;
        2) normalized="vmess" ;;
        3) normalized="trojan" ;;
        4) normalized="hysteria2" ;;
        5) normalized="tuic" ;;
        6) normalized="naive" ;;
        7) normalized="socks5" ;;
        8) normalized="ss2022" ;;
        *)
          normalized="$(normalize_protocol_name "$token" 2>/dev/null || true)"
          ;;
      esac

      if [[ -z "$normalized" ]]; then
        valid=0
        break
      fi
      add_protocol "$normalized"
    done

    if [[ "$valid" -eq 1 && "${#ENABLED_PROTOCOLS[@]}" -gt 0 ]]; then
      return 0
    fi

    warn "协议输入无效，请重新输入。"
    load_protocols_from_csv "$current"
  done
}

prompt_vless_mode() {
  local input=""

  if ! protocol_enabled vless || ! should_prompt_interactively; then
    return 0
  fi

  while true; do
    printf '%s\n' "请选择 VLESS 模式：" >&2
    printf '%s\n' "  1) reality（默认，推荐，不依赖证书）" >&2
    printf '%s\n' "  2) tls（需要域名与证书）" >&2
    printf '当前为 [%s]，请输入 [1-2]，直接回车保留: ' "$VLESS_MODE" >&2
    read -r input

    case "$input" in
      "")
        return 0
        ;;
      1)
        VLESS_MODE="reality"
        return 0
        ;;
      2)
        VLESS_MODE="tls"
        return 0
        ;;
      *)
        warn "VLESS 模式输入无效，请重新输入。"
        ;;
    esac
  done
}

prompt_acme_mode() {
  local input=""

  if [[ "$TLS_REQUIRED" -ne 1 || ! should_prompt_interactively ]]; then
    return 0
  fi

  while true; do
    printf '%s\n' "请选择 ACME 方式：" >&2
    printf '%s\n' "  1) auto（默认，优先 80，再尝试 443）" >&2
    printf '%s\n' "  2) standalone（使用 80/tcp）" >&2
    printf '%s\n' "  3) alpn（使用 443/tcp）" >&2
    printf '当前为 [%s]，请输入 [1-3]，直接回车保留: ' "$ACME_MODE" >&2
    read -r input

    case "$input" in
      "")
        return 0
        ;;
      1)
        ACME_MODE="auto"
        return 0
        ;;
      2)
        ACME_MODE="standalone"
        return 0
        ;;
      3)
        ACME_MODE="alpn"
        return 0
        ;;
      *)
        warn "ACME 方式输入无效，请重新输入。"
        ;;
    esac
  done
}

prompt_cert_mode() {
  local input=""

  if [[ "$TLS_REQUIRED" -ne 1 || ! should_prompt_interactively ]]; then
    return 0
  fi

  while true; do
    printf '%s\n' "请选择证书模式：" >&2
    printf '%s\n' "  1) acme（默认，公开证书）" >&2
    printf '%s\n' "  2) self-signed（OpenSSL 自签名证书）" >&2
    printf '当前为 [%s]，请输入 [1-2]，直接回车保留: ' "$CERT_MODE" >&2
    read -r input

    case "$input" in
      "")
        return 0
        ;;
      1)
        CERT_MODE="acme"
        return 0
        ;;
      2)
        CERT_MODE="self-signed"
        return 0
        ;;
      *)
        warn "证书模式输入无效，请重新输入。"
        ;;
    esac
  done
}

prompt_optional_settings() {
  local input=""

  if should_prompt_interactively && protocol_enabled naive; then
    while true; do
      printf '%s\n' "请选择 NaiveProxy 网络模式：" >&2
      printf '%s\n' "  1) tcp（默认，HTTP/2）" >&2
      printf '%s\n' "  2) udp（QUIC）" >&2
      printf '当前为 [%s]，请输入 [1-2]，直接回车保留: ' "$NAIVE_NETWORK" >&2
      read -r input
      case "$input" in
        "")
          break
          ;;
        1)
          NAIVE_NETWORK="tcp"
          break
          ;;
        2)
          NAIVE_NETWORK="udp"
          break
          ;;
        *)
          warn "NaiveProxy 网络模式无效，请重新输入。"
          ;;
      esac
    done
  fi

  if should_prompt_interactively && protocol_enabled ss2022; then
    while true; do
      printf '%s\n' "请选择 SS2022 加密方式：" >&2
      printf '%s\n' "  1) 2022-blake3-aes-128-gcm（默认）" >&2
      printf '%s\n' "  2) 2022-blake3-aes-256-gcm" >&2
      printf '%s\n' "  3) 2022-blake3-chacha20-poly1305" >&2
      printf '当前为 [%s]，请输入 [1-3]，直接回车保留: ' "$SS2022_METHOD" >&2
      read -r input
      case "$input" in
        "")
          break
          ;;
        1)
          SS2022_METHOD="2022-blake3-aes-128-gcm"
          break
          ;;
        2)
          SS2022_METHOD="2022-blake3-aes-256-gcm"
          break
          ;;
        3)
          SS2022_METHOD="2022-blake3-chacha20-poly1305"
          break
          ;;
        *)
          warn "SS2022 加密方式无效，请重新输入。"
          ;;
      esac
    done
  fi

  if should_prompt_interactively && protocol_enabled tuic; then
    while true; do
      printf '%s\n' "请选择 TUIC 拥塞控制：" >&2
      printf '%s\n' "  1) cubic（默认）" >&2
      printf '%s\n' "  2) new_reno" >&2
      printf '%s\n' "  3) bbr" >&2
      printf '当前为 [%s]，请输入 [1-3]，直接回车保留: ' "$TUIC_CONGESTION_CONTROL" >&2
      read -r input
      case "$input" in
        "")
          break
          ;;
        1)
          TUIC_CONGESTION_CONTROL="cubic"
          break
          ;;
        2)
          TUIC_CONGESTION_CONTROL="new_reno"
          break
          ;;
        3)
          TUIC_CONGESTION_CONTROL="bbr"
          break
          ;;
        *)
          warn "TUIC 拥塞控制输入无效，请重新输入。"
          ;;
      esac
    done
  fi
}

validate_port_number() {
  local port="$1"

  [[ "$port" =~ ^[0-9]+$ ]] || die "Port must be numeric: $port"
  ((port >= 1 && port <= 65535)) || die "Port out of range: $port"
}

port_is_free() {
  local port="$1"

  if ss -ltnH "( sport = :$port )" 2>/dev/null | grep -q .; then
    return 1
  fi
  if ss -lunH "( sport = :$port )" 2>/dev/null | grep -q .; then
    return 1
  fi
  return 0
}

port_owned_by_sing_box() {
  local port="$1"

  if ss -ltnp "( sport = :$port )" 2>/dev/null | grep -q 'sing-box'; then
    return 0
  fi
  if ss -lunp "( sport = :$port )" 2>/dev/null | grep -q 'sing-box'; then
    return 0
  fi
  return 1
}

port_in_reserved_set() {
  local candidate="$1"
  shift || true

  local item=""
  for item in "$@"; do
    [[ "$item" == "$candidate" ]] && return 0
  done
  return 1
}

pick_port() {
  local requested="${1:-}"
  shift || true
  local reserved=("$@")
  local candidate=""
  local attempt=0

  if [[ -n "$requested" && "$requested" != "0" ]]; then
    validate_port_number "$requested"
    port_in_reserved_set "$requested" "${reserved[@]}" && die "Port duplicated in requested inputs: $requested"
    if ! port_is_free "$requested" && ! port_owned_by_sing_box "$requested"; then
      die "Requested port is already in use: $requested"
    fi
    printf '%s\n' "$requested"
    return 0
  fi

  for attempt in $(seq 1 200); do
    candidate=$((RANDOM % 40000 + 20000))
    port_in_reserved_set "$candidate" "${reserved[@]}" && continue
    if port_is_free "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  die "Failed to allocate a free random port after 200 attempts"
}

get_protocol_port() {
  case "$1" in
    vless) printf '%s\n' "${VLESS_PORT:-}" ;;
    vmess) printf '%s\n' "${VMESS_PORT:-}" ;;
    trojan) printf '%s\n' "${TROJAN_PORT:-}" ;;
    hysteria2) printf '%s\n' "${HYSTERIA2_PORT:-}" ;;
    tuic) printf '%s\n' "${TUIC_PORT:-}" ;;
    naive) printf '%s\n' "${NAIVE_PORT:-}" ;;
    socks5) printf '%s\n' "${SOCKS5_PORT:-}" ;;
    ss2022) printf '%s\n' "${SS2022_PORT:-}" ;;
    *)
      die "Unknown protocol in get_protocol_port: $1"
      ;;
  esac
}

set_protocol_port() {
  local protocol="$1"
  local value="$2"

  case "$protocol" in
    vless) VLESS_PORT="$value" ;;
    vmess) VMESS_PORT="$value" ;;
    trojan) TROJAN_PORT="$value" ;;
    hysteria2) HYSTERIA2_PORT="$value" ;;
    tuic) TUIC_PORT="$value" ;;
    naive) NAIVE_PORT="$value" ;;
    socks5) SOCKS5_PORT="$value" ;;
    ss2022) SS2022_PORT="$value" ;;
    *)
      die "Unknown protocol in set_protocol_port: $protocol"
      ;;
  esac
}

prompt_port_value() {
  local label="$1"
  local current="$2"
  shift 2 || true
  local reserved=("$@")
  local input=""

  PROMPT_RESULT="$current"

  if ! should_prompt_interactively; then
    return 0
  fi

  while true; do
    if [[ -n "$current" && "$current" != "0" ]]; then
      printf '请输入 %s 端口 [%s]，直接回车保留，输入 0 则自动分配: ' "$label" "$current" >&2
    else
      printf '请输入 %s 端口，直接回车自动分配: ' "$label" >&2
    fi
    read -r input

    if [[ -z "$input" ]]; then
      PROMPT_RESULT="$current"
      return 0
    fi

    if [[ "$input" == "0" ]]; then
      PROMPT_RESULT=""
      return 0
    fi

    if [[ ! "$input" =~ ^[0-9]+$ ]]; then
      warn "${label} 端口必须是数字，请重新输入。"
      continue
    fi

    if ((input < 1 || input > 65535)); then
      warn "${label} 端口必须在 1-65535 之间，请重新输入。"
      continue
    fi

    if port_in_reserved_set "$input" "${reserved[@]}"; then
      warn "${label} 端口和本次其它选择重复，请重新输入。"
      continue
    fi

    PROMPT_RESULT="$input"
    return 0
  done
}

prompt_ports() {
  local reserved=()
  local protocol=""
  local current=""
  local label=""

  if ! should_prompt_interactively; then
    return 0
  fi

  printf '%s\n' "下面设置各协议监听端口。直接回车时，脚本会随机分配可用端口。" >&2

  for protocol in "${SUPPORTED_PROTOCOL_ORDER[@]}"; do
    protocol_enabled "$protocol" || continue
    current="$(get_protocol_port "$protocol")"
    label="$(protocol_label "$protocol")"
    prompt_port_value "$label" "$current" "${reserved[@]}"
    set_protocol_port "$protocol" "$PROMPT_RESULT"
    if [[ -n "$PROMPT_RESULT" && "$PROMPT_RESULT" != "0" ]]; then
      reserved+=("$PROMPT_RESULT")
    fi
  done
}

prompt_install_settings() {
  prompt_protocol_selection
  prompt_vless_mode
  validate_selection

  if [[ "$TLS_REQUIRED" -eq 1 ]]; then
    prompt_cert_mode
    if [[ "$CERT_MODE" == "acme" ]]; then
      prompt_text_value "域名" "$DOMAIN" "说明：所选协议包含 TLS/QUIC 协议，ACME 公开证书必须使用可访问的域名。" "1"
      DOMAIN="$PROMPT_RESULT"
      prompt_text_value "邮箱" "$EMAIL" "说明：acme.sh 会使用该邮箱注册证书账户。" "1"
      EMAIL="$PROMPT_RESULT"
      prompt_acme_mode
    else
      prompt_text_value "证书主机名（域名或IP）" "$DOMAIN" "说明：自签名证书会把这里作为证书主题名/SAN。可留空，脚本会回退到分享地址或公网 IPv4。" "0"
      DOMAIN="$PROMPT_RESULT"
      EMAIL=""
    fi
  fi

  prompt_optional_settings

  prompt_text_value "客户端使用的服务器地址" "$SHARE_HOST" "说明：建议填写域名；如留空，脚本会优先用域名，否则尝试探测公网 IPv4。" "0"
  SHARE_HOST="$PROMPT_RESULT"

  prompt_ports
  validate_selection
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Please run this script as root."
}

check_os() {
  [[ -f /etc/os-release ]] || die "Unable to detect operating system."
  # shellcheck disable=SC1091
  . /etc/os-release

  [[ "${ID:-}" == "debian" ]] || die "This script supports Debian 12 only."
  [[ "${VERSION_ID:-}" == "12" ]] || die "Detected Debian ${VERSION_ID:-unknown}; Debian 12 is required."
}

ensure_apt_updated() {
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    APT_UPDATED=1
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fq 'install ok installed'
}

install_packages() {
  local packages=("$@")
  local missing=()
  local package=""

  ((${#packages[@]} > 0)) || return 0
  for package in "${packages[@]}"; do
    if ! package_installed "$package"; then
      missing+=("$package")
    fi
  done

  ((${#missing[@]} > 0)) || return 0
  ensure_apt_updated
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y "${missing[@]}"
}

install_dependencies() {
  install_packages ca-certificates curl gpg jq iproute2 openssl socat
}

ensure_sagernet_repo() {
  if [[ -f /etc/apt/sources.list.d/sagernet.sources && -f /etc/apt/keyrings/sagernet.asc ]]; then
    return 0
  fi

  install_packages ca-certificates curl gpg
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
  chmod a+r /etc/apt/keyrings/sagernet.asc

  cat > /etc/apt/sources.list.d/sagernet.sources <<'EOF'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF

  APT_UPDATED=0
  ensure_apt_updated
}

install_sing_box() {
  if command -v sing-box >/dev/null 2>&1 && package_installed sing-box; then
    SING_BOX_VERSION="$(sing-box version 2>/dev/null | head -n 1 || true)"
    SING_BOX_VERSION_NUMBER="$(printf '%s\n' "$SING_BOX_VERSION" | awk 'NR==1{print $NF}' | sed 's/^v//')"
    return 0
  fi

  ensure_sagernet_repo
  install_packages sing-box
  SING_BOX_VERSION="$(sing-box version 2>/dev/null | head -n 1 || true)"
  SING_BOX_VERSION_NUMBER="$(printf '%s\n' "$SING_BOX_VERSION" | awk 'NR==1{print $NF}' | sed 's/^v//')"
}

require_min_sing_box_version() {
  local minimum="$1"
  local current="${SING_BOX_VERSION_NUMBER:-}"

  [[ -n "$current" ]] || die "Unable to determine installed sing-box version."
  if ! dpkg --compare-versions "$current" ge "$minimum"; then
    die "Current sing-box version $current is too old; at least $minimum is required."
  fi
}

validate_protocol_version_support() {
  if protocol_enabled naive; then
    require_min_sing_box_version "1.13.0"
  fi
}

prepare_dirs() {
  mkdir -p -- "$TARGET_DIR" "$RULE_SET_DIR" "$SSL_DIR" "$ARTIFACT_DIR"
  chmod 0755 "$TARGET_DIR" "$RULE_SET_DIR"
  chmod 0700 "$SSL_DIR" "$ARTIFACT_DIR"
}

backup_existing_files() {
  local timestamp=""
  timestamp="$(date +%Y%m%d%H%M%S)"

  if [[ -f "$TARGET_CONFIG" || -f "$STATE_FILE" || -f "$SHARE_LINKS_FILE" || -f "$CLIENT_SNIPPET_FILE" || -f "$CLIENT_FULL_CONFIG_FILE" || -f "$CLIENT_TUN_CONFIG_FILE" || -f "$SUMMARY_FILE" || -f "$ACME_LOG_FILE" ]]; then
    BACKUP_PATH="$ARTIFACT_DIR/backup-$timestamp"
    mkdir -p -- "$BACKUP_PATH"
    chmod 0700 "$BACKUP_PATH"
    [[ -f "$TARGET_CONFIG" ]] && cp -a -- "$TARGET_CONFIG" "$BACKUP_PATH/"
    [[ -f "$STATE_FILE" ]] && cp -a -- "$STATE_FILE" "$BACKUP_PATH/"
    [[ -f "$SHARE_LINKS_FILE" ]] && cp -a -- "$SHARE_LINKS_FILE" "$BACKUP_PATH/"
    [[ -f "$CLIENT_SNIPPET_FILE" ]] && cp -a -- "$CLIENT_SNIPPET_FILE" "$BACKUP_PATH/"
    [[ -f "$CLIENT_FULL_CONFIG_FILE" ]] && cp -a -- "$CLIENT_FULL_CONFIG_FILE" "$BACKUP_PATH/"
    [[ -f "$CLIENT_TUN_CONFIG_FILE" ]] && cp -a -- "$CLIENT_TUN_CONFIG_FILE" "$BACKUP_PATH/"
    [[ -f "$SUMMARY_FILE" ]] && cp -a -- "$SUMMARY_FILE" "$BACKUP_PATH/"
    [[ -f "$ACME_LOG_FILE" ]] && cp -a -- "$ACME_LOG_FILE" "$BACKUP_PATH/"
  fi
}

domain_resolves() {
  local host="$1"
  getent ahostsv4 "$host" >/dev/null 2>&1
}

get_public_ipv4() {
  local ip=""
  ip="$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -4fsS --max-time 5 https://ipv4.icanhazip.com 2>/dev/null | tr -d '\n' || true)"
  fi
  printf '%s\n' "$ip"
}

domain_matches_public_ip() {
  local host="$1"
  local public_ip="$2"

  [[ -n "$public_ip" ]] || return 1
  getent ahostsv4 "$host" | awk '{print $1}' | sort -u | grep -Fxq "$public_ip"
}

is_ipv4_address() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

resolve_tls_identity() {
  local identity=""

  if [[ -n "$DOMAIN" ]]; then
    printf '%s\n' "$DOMAIN"
    return 0
  fi

  if [[ -n "$SHARE_HOST" ]]; then
    printf '%s\n' "$SHARE_HOST"
    return 0
  fi

  identity="$(get_public_ipv4)"
  [[ -n "$identity" ]] || return 1
  printf '%s\n' "$identity"
}

choose_share_host() {
  if [[ -n "$SHARE_HOST" ]]; then
    printf '%s\n' "$SHARE_HOST"
    return 0
  fi
  if [[ -n "$DOMAIN" ]]; then
    printf '%s\n' "$DOMAIN"
    return 0
  fi

  SHARE_HOST="$(get_public_ipv4)"
  if [[ -n "$SHARE_HOST" ]]; then
    printf '%s\n' "$SHARE_HOST"
    return 0
  fi

  printf 'SERVER_IP\n'
}

install_acme_sh() {
  if [[ -x "$ACME_SH" ]]; then
    return 0
  fi

  local installer=""
  installer="$(mktemp)"
  curl -fsSL https://get.acme.sh -o "$installer"
  if [[ -n "$EMAIL" ]]; then
    sh "$installer" "email=$EMAIL"
  else
    sh "$installer"
  fi
  rm -f -- "$installer"

  [[ -x "$ACME_SH" ]] || die "acme.sh installation completed but $ACME_SH was not found"
}

acme_challenge_candidates() {
  case "$ACME_MODE" in
    standalone)
      if port_is_free 80; then
        printf 'standalone\n'
      fi
      ;;
    alpn)
      if port_is_free 443; then
        printf 'alpn\n'
      fi
      ;;
    auto)
      if port_is_free 80; then
        printf 'standalone\n'
      fi
      if port_is_free 443; then
        printf 'alpn\n'
      fi
      ;;
  esac
}

acme_issue_with_mode() {
  local mode="$1"

  : > "$ACME_LOG_FILE"

  if [[ "$mode" == "standalone" ]]; then
    "$ACME_SH" --issue --standalone -d "$DOMAIN" >"$ACME_LOG_FILE" 2>&1
    return $?
  fi

  "$ACME_SH" --issue --alpn -d "$DOMAIN" >"$ACME_LOG_FILE" 2>&1
}

generate_self_signed_certificate() {
  local identity="$1"
  local san=""
  local openssl_conf=""
  local days="825"

  : > "$ACME_LOG_FILE"
  if is_ipv4_address "$identity"; then
    san="IP:$identity"
  else
    san="DNS:$identity"
  fi

  openssl_conf="$(mktemp)"
  cat > "$openssl_conf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = $identity

[v3_req]
subjectAltName = $san
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

  if ! openssl req -x509 -nodes -newkey rsa:2048 \
    -days "$days" \
    -keyout "$CERT_KEY" \
    -out "$CERT_FULLCHAIN" \
    -config "$openssl_conf" >"$ACME_LOG_FILE" 2>&1; then
    rm -f -- "$openssl_conf"
    return 1
  fi

  rm -f -- "$openssl_conf"
  chmod 0600 "$CERT_KEY"
  chmod 0644 "$CERT_FULLCHAIN"
}

certificate_matches_domain() {
  [[ -s "$CERT_FULLCHAIN" ]] || return 1
  if is_ipv4_address "$DOMAIN"; then
    openssl x509 -in "$CERT_FULLCHAIN" -noout -ext subjectAltName 2>/dev/null | tr -d ' ' | grep -Fq "IPAddress:$DOMAIN"
    return $?
  fi
  openssl x509 -in "$CERT_FULLCHAIN" -noout -ext subjectAltName 2>/dev/null | tr -d ' ' | grep -Fq "DNS:$DOMAIN"
}

certificate_is_fresh() {
  [[ -s "$CERT_FULLCHAIN" ]] || return 1
  openssl x509 -checkend 2592000 -noout -in "$CERT_FULLCHAIN" >/dev/null 2>&1
}

issue_certificate() {
  local public_ip=""
  local challenges=()
  local challenge=""
  local matched_public_ipv4="unknown"
  local issued=0

  if domain_resolves "$DOMAIN"; then
    public_ip="$(get_public_ipv4)"
    if [[ -n "$public_ip" ]] && domain_matches_public_ip "$DOMAIN" "$public_ip"; then
      matched_public_ipv4="yes"
    elif [[ -n "$public_ip" ]]; then
      matched_public_ipv4="no"
      warn "域名 $DOMAIN 当前未解析到本机公网 IPv4 ($public_ip)。脚本将继续尝试 ACME；如果最终失败，请检查域名解析或改用 DNS-01。"
    fi
  else
    warn "域名 $DOMAIN 当前无法通过本机解析器解析。脚本将继续尝试 ACME；如果最终失败，请检查 DNS 解析或改用 DNS-01。"
  fi

  while IFS= read -r challenge; do
    [[ -n "$challenge" ]] && challenges+=("$challenge")
  done < <(acme_challenge_candidates)

  if ((${#challenges[@]} == 0)); then
    TLS_REASON="Neither TCP/80 nor TCP/443 is free for ACME mode $ACME_MODE"
    return 1
  fi

  touch "$CERT_FULLCHAIN" "$CERT_KEY"
  chmod 0644 "$CERT_FULLCHAIN"
  chmod 0600 "$CERT_KEY"

  "$ACME_SH" --set-default-ca --server letsencrypt >/dev/null
  "$ACME_SH" --register-account -m "$EMAIL" --server letsencrypt >/dev/null 2>&1 || true

  for challenge in "${challenges[@]}"; do
    ACME_CHALLENGE_USED="$challenge"
    if acme_issue_with_mode "$challenge"; then
      issued=1
      break
    fi
  done

  if [[ "$issued" -ne 1 ]]; then
    TLS_REASON="acme.sh issue failed for $DOMAIN (matched_public_ipv4=$matched_public_ipv4, tried=$(printf '%s,' "${challenges[@]}" | sed 's/,$//')). See $ACME_LOG_FILE"
    return 1
  fi

  "$ACME_SH" --install-cert \
    -d "$DOMAIN" \
    --key-file "$CERT_KEY" \
    --fullchain-file "$CERT_FULLCHAIN" \
    --reloadcmd "systemctl restart $SERVICE_NAME" || {
      TLS_REASON="acme.sh install-cert failed"
      return 1
    }

  [[ -s "$CERT_FULLCHAIN" ]] || {
    TLS_REASON="Installed certificate file is empty: $CERT_FULLCHAIN"
    return 1
  }
  [[ -s "$CERT_KEY" ]] || {
    TLS_REASON="Installed private key file is empty: $CERT_KEY"
    return 1
  }

  TLS_STATUS="installed"
  TLS_REASON="certificate issued with acme.sh"
  return 0
}

ensure_certificate() {
  local tls_identity=""

  if [[ "$TLS_REQUIRED" -ne 1 ]]; then
    TLS_STATUS="skipped"
    TLS_REASON="No TLS certificate required by current protocol set"
    return 0
  fi

  tls_identity="$(resolve_tls_identity || true)"

  if [[ "$CERT_MODE" == "acme" ]]; then
    [[ -n "$DOMAIN" ]] || die "ACME certificate mode requires --domain"
    [[ -n "$EMAIL" ]] || die "ACME certificate mode requires --email"
  else
    [[ -n "$tls_identity" ]] || die "Self-signed certificate mode requires a domain, share host, or detectable public IPv4"
    DOMAIN="$tls_identity"
    EMAIL=""
  fi

  if certificate_matches_domain && certificate_is_fresh; then
    TLS_STATUS="existing"
    TLS_REASON="Existing certificate is still valid"
    return 0
  fi

  if [[ "$CERT_MODE" == "self-signed" ]]; then
    if ! generate_self_signed_certificate "$DOMAIN"; then
      TLS_REASON="OpenSSL self-signed certificate generation failed. See $ACME_LOG_FILE"
      die "$TLS_REASON"
    fi
    TLS_STATUS="installed"
    TLS_REASON="self-signed certificate generated with openssl"
    ACME_CHALLENGE_USED="none"
    return 0
  fi

  install_acme_sh
  issue_certificate || die "${TLS_REASON:-Certificate issuance failed}"
}

generate_uuid() {
  cat /proc/sys/kernel/random/uuid
}

generate_hex_secret() {
  local bytes="${1:-16}"
  openssl rand -hex "$bytes"
}

generate_username() {
  local prefix="$1"
  printf '%s-%s\n' "$prefix" "$(generate_hex_secret 3)"
}

base64url_to_base64() {
  local value="$1"
  local mod=""

  value="${value//-/+}"
  value="${value//_/\/}"
  mod=$(( ${#value} % 4 ))

  case "$mod" in
    0) ;;
    2) value="${value}==" ;;
    3) value="${value}=" ;;
    *) return 1 ;;
  esac

  printf '%s\n' "$value"
}

derive_reality_public_key() {
  local private_key="$1"
  local std_b64=""
  local tmp_raw=""
  local tmp_der=""
  local tmp_pub=""
  local raw_len=""
  local public_key=""

  std_b64="$(base64url_to_base64 "$private_key")" || return 1
  tmp_raw="$(mktemp)"
  tmp_der="$(mktemp)"
  tmp_pub="$(mktemp)"

  cleanup() {
    rm -f -- "$tmp_raw" "$tmp_der" "$tmp_pub"
  }

  printf '%s' "$std_b64" | openssl enc -d -base64 -A -out "$tmp_raw" >/dev/null 2>&1 || {
    cleanup
    return 1
  }

  raw_len="$(wc -c < "$tmp_raw" | tr -d '[:space:]')"
  [[ "$raw_len" == "32" ]] || {
    cleanup
    return 1
  }

  {
    printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20'
    cat "$tmp_raw"
  } > "$tmp_der"

  openssl pkey -inform DER -in "$tmp_der" -pubout -outform DER -out "$tmp_pub" >/dev/null 2>&1 || {
    cleanup
    return 1
  }

  public_key="$(tail -c 32 "$tmp_pub" | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  cleanup
  printf '%s\n' "$public_key"
}

generate_reality_keypair() {
  local pair_output=""
  local private_key=""
  local public_key=""

  pair_output="$(sing-box generate reality-keypair)"
  private_key="$(printf '%s\n' "$pair_output" | awk -F': ' '/PrivateKey/ {print $2; exit}')"
  public_key="$(printf '%s\n' "$pair_output" | awk -F': ' '/PublicKey/ {print $2; exit}')"

  [[ -n "$private_key" ]] || die "Failed to generate Reality private key"
  [[ -n "$public_key" ]] || die "Failed to generate Reality public key"

  REALITY_PRIVATE_KEY="$private_key"
  REALITY_PUBLIC_KEY="$public_key"
}

ss2022_key_length() {
  case "$1" in
    2022-blake3-aes-128-gcm)
      printf '16\n'
      ;;
    2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305)
      printf '32\n'
      ;;
    *)
      die "Unsupported SS2022 method in ss2022_key_length: $1"
      ;;
  esac
}

is_valid_base64_of_length() {
  local value="$1"
  local expected_length="$2"
  local actual_length=""

  actual_length="$(printf '%s' "$value" | openssl enc -d -base64 -A 2>/dev/null | wc -c | tr -d '[:space:]' || true)"
  [[ "$actual_length" == "$expected_length" ]]
}

generate_ss2022_secret() {
  local length=""
  length="$(ss2022_key_length "$1")"
  sing-box generate rand "$length" --base64
}

prepare_credentials() {
  local expected_length=""

  if protocol_enabled vless; then
    [[ -n "$VLESS_UUID" ]] || VLESS_UUID="$(generate_uuid)"
    if [[ "$VLESS_MODE" == "reality" ]]; then
      if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_SHORT_ID" || "$ROTATE_SECRETS" -eq 1 ]]; then
        generate_reality_keypair
        REALITY_SHORT_ID="$(generate_hex_secret 4)"
      fi
      if [[ -z "$REALITY_PUBLIC_KEY" ]]; then
        REALITY_PUBLIC_KEY="$(derive_reality_public_key "$REALITY_PRIVATE_KEY" || true)"
      fi
      [[ -n "$REALITY_PUBLIC_KEY" ]] || die "Failed to derive Reality public key"
    fi
  fi

  if protocol_enabled vmess; then
    [[ -n "$VMESS_UUID" ]] || VMESS_UUID="$(generate_uuid)"
  fi

  if protocol_enabled trojan; then
    [[ -n "$TROJAN_PASSWORD" ]] || TROJAN_PASSWORD="$(generate_hex_secret 16)"
  fi

  if protocol_enabled hysteria2; then
    [[ -n "$HYSTERIA2_PASSWORD" ]] || HYSTERIA2_PASSWORD="$(generate_hex_secret 16)"
    [[ -n "$HYSTERIA2_OBFS_PASSWORD" ]] || HYSTERIA2_OBFS_PASSWORD="$(generate_hex_secret 16)"
  fi

  if protocol_enabled tuic; then
    [[ -n "$TUIC_UUID" ]] || TUIC_UUID="$(generate_uuid)"
    [[ -n "$TUIC_PASSWORD" ]] || TUIC_PASSWORD="$(generate_hex_secret 16)"
  fi

  if protocol_enabled naive; then
    [[ -n "$NAIVE_USERNAME" ]] || NAIVE_USERNAME="$(generate_username naive)"
    [[ -n "$NAIVE_PASSWORD" ]] || NAIVE_PASSWORD="$(generate_hex_secret 16)"
  fi

  if protocol_enabled socks5; then
    [[ -n "$SOCKS5_USERNAME" ]] || SOCKS5_USERNAME="$(generate_username socks)"
    [[ -n "$SOCKS5_PASSWORD" ]] || SOCKS5_PASSWORD="$(generate_hex_secret 16)"
  fi

  if protocol_enabled ss2022; then
    expected_length="$(ss2022_key_length "$SS2022_METHOD")"
    if ! is_valid_base64_of_length "$SS2022_SERVER_PASSWORD" "$expected_length"; then
      SS2022_SERVER_PASSWORD="$(generate_ss2022_secret "$SS2022_METHOD")"
    fi
    if ! is_valid_base64_of_length "$SS2022_USER_PASSWORD" "$expected_length"; then
      SS2022_USER_PASSWORD="$(generate_ss2022_secret "$SS2022_METHOD")"
    fi
  fi
}

ensure_user_arrays() {
  local protocol=""
  local users_json=""

  for protocol in "${SUPPORTED_PROTOCOL_ORDER[@]}"; do
    protocol_enabled "$protocol" || continue
    users_json="$(get_users_json_var "$protocol")"
    if ! jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<< "$users_json"; then
      users_json="$(build_default_user_json_for_protocol "$protocol")"
      set_users_json_var "$protocol" "$users_json"
    fi
  done
}

sync_primary_credentials_from_users() {
  if protocol_enabled vless; then
    VLESS_UUID="$(jq -r '.[0].uuid // empty' <<< "$VLESS_USERS_JSON")"
  fi
  if protocol_enabled vmess; then
    VMESS_UUID="$(jq -r '.[0].uuid // empty' <<< "$VMESS_USERS_JSON")"
  fi
  if protocol_enabled trojan; then
    TROJAN_PASSWORD="$(jq -r '.[0].password // empty' <<< "$TROJAN_USERS_JSON")"
  fi
  if protocol_enabled hysteria2; then
    HYSTERIA2_PASSWORD="$(jq -r '.[0].password // empty' <<< "$HYSTERIA2_USERS_JSON")"
  fi
  if protocol_enabled tuic; then
    TUIC_UUID="$(jq -r '.[0].uuid // empty' <<< "$TUIC_USERS_JSON")"
    TUIC_PASSWORD="$(jq -r '.[0].password // empty' <<< "$TUIC_USERS_JSON")"
  fi
  if protocol_enabled naive; then
    NAIVE_USERNAME="$(jq -r '.[0].username // empty' <<< "$NAIVE_USERS_JSON")"
    NAIVE_PASSWORD="$(jq -r '.[0].password // empty' <<< "$NAIVE_USERS_JSON")"
  fi
  if protocol_enabled socks5; then
    SOCKS5_USERNAME="$(jq -r '.[0].username // empty' <<< "$SOCKS5_USERS_JSON")"
    SOCKS5_PASSWORD="$(jq -r '.[0].password // empty' <<< "$SOCKS5_USERS_JSON")"
  fi
  if protocol_enabled ss2022; then
    SS2022_USER_PASSWORD="$(jq -r '.[0].password // empty' <<< "$SS2022_USERS_JSON")"
  fi
}

resolve_ports() {
  local reserved=()
  local protocol=""
  local value=""

  for protocol in "${SUPPORTED_PROTOCOL_ORDER[@]}"; do
    if ! protocol_enabled "$protocol"; then
      set_protocol_port "$protocol" "0"
      continue
    fi

    value="$(get_protocol_port "$protocol")"
    value="$(pick_port "$value" "${reserved[@]}")"
    set_protocol_port "$protocol" "$value"
    reserved+=("$value")
  done
}

uri_encode() {
  jq -rn --arg s "$1" '$s|@uri'
}

base64_url_nopad() {
  printf '%s' "$1" | openssl base64 -A | tr '+/' '-_' | tr -d '='
}

build_vless_inbound() {
  if [[ "$VLESS_MODE" == "reality" ]]; then
    jq -nc \
      --argjson port "$VLESS_PORT" \
      --argjson users "$VLESS_USERS_JSON" \
      --arg server_name "$REALITY_SERVER_NAME" \
      --arg handshake_server "$REALITY_HANDSHAKE_SERVER" \
      --argjson handshake_port "$REALITY_HANDSHAKE_PORT" \
      --arg private_key "$REALITY_PRIVATE_KEY" \
      --arg short_id "$REALITY_SHORT_ID" \
      '{
        type: "vless",
        tag: "vless-reality",
        listen: "::",
        listen_port: $port,
        users: $users,
        tls: {
          enabled: true,
          server_name: $server_name,
          reality: {
            enabled: true,
            handshake: {
              server: $handshake_server,
              server_port: $handshake_port
            },
            private_key: $private_key,
            short_id: [$short_id]
          }
        }
      }'
    return 0
  fi

  jq -nc \
    --argjson port "$VLESS_PORT" \
    --argjson users "$VLESS_USERS_JSON" \
    --arg domain "$DOMAIN" \
    --arg cert "$CERT_FULLCHAIN" \
    --arg key "$CERT_KEY" \
    '{
      type: "vless",
      tag: "vless-tls",
      listen: "::",
      listen_port: $port,
      users: $users,
      tls: {
        enabled: true,
        server_name: $domain,
        certificate_path: $cert,
        key_path: $key
      }
    }'
}

build_vmess_inbound() {
  jq -nc \
    --argjson port "$VMESS_PORT" \
    --argjson users "$VMESS_USERS_JSON" \
    --arg domain "$DOMAIN" \
    --arg cert "$CERT_FULLCHAIN" \
    --arg key "$CERT_KEY" \
    '{
      type: "vmess",
      tag: "vmess-in",
      listen: "::",
      listen_port: $port,
      users: $users,
      tls: {
        enabled: true,
        server_name: $domain,
        certificate_path: $cert,
        key_path: $key
      }
    }'
}

build_trojan_inbound() {
  jq -nc \
    --argjson port "$TROJAN_PORT" \
    --argjson users "$TROJAN_USERS_JSON" \
    --arg domain "$DOMAIN" \
    --arg cert "$CERT_FULLCHAIN" \
    --arg key "$CERT_KEY" \
    '{
      type: "trojan",
      tag: "trojan-in",
      listen: "::",
      listen_port: $port,
      users: $users,
      tls: {
        enabled: true,
        server_name: $domain,
        certificate_path: $cert,
        key_path: $key
      }
    }'
}

build_hysteria2_inbound() {
  jq -nc \
    --argjson port "$HYSTERIA2_PORT" \
    --argjson users "$HYSTERIA2_USERS_JSON" \
    --arg obfs_password "$HYSTERIA2_OBFS_PASSWORD" \
    --arg domain "$DOMAIN" \
    --arg cert "$CERT_FULLCHAIN" \
    --arg key "$CERT_KEY" \
    '{
      type: "hysteria2",
      tag: "hysteria2-in",
        listen: "::",
        listen_port: $port,
        obfs: {
          type: "salamander",
          password: $obfs_password
        },
      users: $users,
      ignore_client_bandwidth: true,
      tls: {
        enabled: true,
        server_name: $domain,
        alpn: ["h3"],
        certificate_path: $cert,
        key_path: $key
      }
    }'
}

build_tuic_inbound() {
  jq -nc \
    --argjson port "$TUIC_PORT" \
    --argjson users "$TUIC_USERS_JSON" \
    --arg cc "$TUIC_CONGESTION_CONTROL" \
    --arg domain "$DOMAIN" \
    --arg cert "$CERT_FULLCHAIN" \
    --arg key "$CERT_KEY" \
    '{
      type: "tuic",
      tag: "tuic-in",
      listen: "::",
      listen_port: $port,
      users: $users,
      congestion_control: $cc,
      auth_timeout: "3s",
      zero_rtt_handshake: false,
      heartbeat: "10s",
      tls: {
        enabled: true,
        server_name: $domain,
        alpn: ["h3"],
        certificate_path: $cert,
        key_path: $key
      }
    }'
}

build_naive_inbound() {
  if [[ "$NAIVE_NETWORK" == "udp" ]]; then
    jq -nc \
      --argjson port "$NAIVE_PORT" \
      --argjson users "$NAIVE_USERS_JSON" \
      --arg domain "$DOMAIN" \
      --arg cert "$CERT_FULLCHAIN" \
      --arg key "$CERT_KEY" \
      '{
        type: "naive",
        tag: "naive-in",
        network: "udp",
        listen: "::",
        listen_port: $port,
        users: $users,
        quic_congestion_control: "bbr",
        tls: {
          enabled: true,
          server_name: $domain,
          alpn: ["h3"],
          certificate_path: $cert,
          key_path: $key
        }
      }'
    return 0
  fi

  jq -nc \
    --argjson port "$NAIVE_PORT" \
    --argjson users "$NAIVE_USERS_JSON" \
    --arg domain "$DOMAIN" \
    --arg cert "$CERT_FULLCHAIN" \
    --arg key "$CERT_KEY" \
    '{
      type: "naive",
      tag: "naive-in",
      network: "tcp",
      listen: "::",
      listen_port: $port,
      users: $users,
      tls: {
        enabled: true,
        server_name: $domain,
        alpn: ["h2", "http/1.1"],
        certificate_path: $cert,
        key_path: $key
      }
    }'
}

build_socks5_inbound() {
  jq -nc \
    --argjson port "$SOCKS5_PORT" \
    --argjson users "$SOCKS5_USERS_JSON" \
    '{
      type: "socks",
      tag: "socks5-in",
      listen: "::",
      listen_port: $port,
      users: $users
    }'
}

build_ss2022_inbound() {
  jq -nc \
    --argjson port "$SS2022_PORT" \
    --arg method "$SS2022_METHOD" \
    --arg server_password "$SS2022_SERVER_PASSWORD" \
    --argjson users "$SS2022_USERS_JSON" \
    '{
      type: "shadowsocks",
      tag: "ss2022-in",
      listen: "::",
      listen_port: $port,
      method: $method,
      password: $server_password,
      users: $users
    }'
}

routing_status_brief() {
  printf 'BT/PT:%s, 回国限制:%s, 广告拦截:%s\n' \
    "$(if [[ "$ROUTE_BLOCK_BITTORRENT" == "1" ]]; then printf 'on'; else printf 'off'; fi)" \
    "$(if [[ "$ROUTE_BLOCK_CN" == "1" ]]; then printf 'on'; else printf 'off'; fi)" \
    "$(if [[ "$ROUTE_BLOCK_ADS" == "1" ]]; then printf 'on'; else printf 'off'; fi)"
}

download_rule_set_file() {
  local tag="$1"
  local url="$2"
  local target="$RULE_SET_DIR/$tag.srs"

  if [[ -s "$target" ]]; then
    return 0
  fi

  curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$target"
  [[ -s "$target" ]] || die "Downloaded rule-set file is empty: $target"
  chmod 0644 "$target"
}

download_required_rule_sets() {
  if [[ "$ROUTE_BLOCK_CN" == "1" ]]; then
    download_rule_set_file "geosite-cn" "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs"
    download_rule_set_file "geoip-cn" "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
  fi

  if [[ "$ROUTE_BLOCK_ADS" == "1" ]]; then
    download_rule_set_file "geosite-category-ads-all" "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs"
  fi
}

build_route_rules_json() {
  local tmp_rules=()
  local tmp_dir=""

  tmp_dir="$(mktemp -d)"

  if [[ "$ROUTE_BLOCK_BITTORRENT" == "1" ]]; then
    jq -nc '{protocol: "bittorrent", action: "reject"}' > "$tmp_dir/bt.json"
    tmp_rules+=("$tmp_dir/bt.json")
  fi

  if [[ "$ROUTE_BLOCK_CN" == "1" ]]; then
    jq -nc '{ip_is_private: true, action: "reject"}' > "$tmp_dir/private.json"
    jq -nc '{rule_set: ["geosite-cn", "geoip-cn"], action: "reject"}' > "$tmp_dir/cn.json"
    tmp_rules+=("$tmp_dir/private.json" "$tmp_dir/cn.json")
  fi

  if [[ "$ROUTE_BLOCK_ADS" == "1" ]]; then
    jq -nc '{rule_set: "geosite-category-ads-all", action: "reject"}' > "$tmp_dir/ads.json"
    tmp_rules+=("$tmp_dir/ads.json")
  fi

  if ((${#tmp_rules[@]} > 0)); then
    jq -s '.' "${tmp_rules[@]}"
  else
    jq -n '[]'
  fi

  rm -rf -- "$tmp_dir"
}

build_route_rule_sets_json() {
  local tmp_files=()
  local tmp_dir=""

  tmp_dir="$(mktemp -d)"

  if [[ "$ROUTE_BLOCK_CN" == "1" ]]; then
    jq -nc --arg path "$RULE_SET_DIR/geosite-cn.srs" '{type: "local", tag: "geosite-cn", path: $path}' > "$tmp_dir/geosite-cn.json"
    jq -nc --arg path "$RULE_SET_DIR/geoip-cn.srs" '{type: "local", tag: "geoip-cn", path: $path}' > "$tmp_dir/geoip-cn.json"
    tmp_files+=("$tmp_dir/geosite-cn.json" "$tmp_dir/geoip-cn.json")
  fi

  if [[ "$ROUTE_BLOCK_ADS" == "1" ]]; then
    jq -nc --arg path "$RULE_SET_DIR/geosite-category-ads-all.srs" '{type: "local", tag: "geosite-category-ads-all", path: $path}' > "$tmp_dir/ads.json"
    tmp_files+=("$tmp_dir/ads.json")
  fi

  if ((${#tmp_files[@]} > 0)); then
    jq -s '.' "${tmp_files[@]}"
  else
    jq -n '[]'
  fi

  rm -rf -- "$tmp_dir"
}

render_config() {
  local tmp_dir=""
  local files=()
  local route_rules_json=""
  local route_rule_sets_json=""

  tmp_dir="$(mktemp -d)"

  if protocol_enabled vless; then
    build_vless_inbound > "$tmp_dir/vless.json"
    files+=("$tmp_dir/vless.json")
  fi
  if protocol_enabled vmess; then
    build_vmess_inbound > "$tmp_dir/vmess.json"
    files+=("$tmp_dir/vmess.json")
  fi
  if protocol_enabled trojan; then
    build_trojan_inbound > "$tmp_dir/trojan.json"
    files+=("$tmp_dir/trojan.json")
  fi
  if protocol_enabled hysteria2; then
    build_hysteria2_inbound > "$tmp_dir/hysteria2.json"
    files+=("$tmp_dir/hysteria2.json")
  fi
  if protocol_enabled tuic; then
    build_tuic_inbound > "$tmp_dir/tuic.json"
    files+=("$tmp_dir/tuic.json")
  fi
  if protocol_enabled naive; then
    build_naive_inbound > "$tmp_dir/naive.json"
    files+=("$tmp_dir/naive.json")
  fi
  if protocol_enabled socks5; then
    build_socks5_inbound > "$tmp_dir/socks5.json"
    files+=("$tmp_dir/socks5.json")
  fi
  if protocol_enabled ss2022; then
    build_ss2022_inbound > "$tmp_dir/ss2022.json"
    files+=("$tmp_dir/ss2022.json")
  fi

  ((${#files[@]} > 0)) || die "No protocol inbounds were rendered"

  route_rules_json="$(build_route_rules_json)"
  route_rule_sets_json="$(build_route_rule_sets_json)"

  jq -s \
    --argjson route_rules "$route_rules_json" \
    --argjson route_rule_set "$route_rule_sets_json" \
    '
    {
      log: {
        level: "warn",
        timestamp: true
      },
      inbounds: .,
      outbounds: [
        {type: "direct", tag: "direct"},
        {type: "block", tag: "block"}
      ],
      route: {
        rules: $route_rules,
        rule_set: $route_rule_set,
        final: "direct"
      }
    }
  ' "${files[@]}" > "$TARGET_CONFIG"

  rm -rf -- "$tmp_dir"
}

validate_rendered_config() {
  sing-box format -w -c "$TARGET_CONFIG"
  sing-box check -c "$TARGET_CONFIG"
}

restart_service() {
  systemctl enable "$SERVICE_NAME" >/dev/null
  systemctl restart "$SERVICE_NAME"
  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" --no-pager -n 100 || true
    die "$SERVICE_NAME failed to start"
  fi
}

show_service_status() {
  systemctl status "$SERVICE_NAME" --no-pager --lines=20 || true
}

uri_fragment() {
  uri_encode "$1"
}

sanitize_tag_value() {
  local value="$1"
  value="${value// /-}"
  value="$(printf '%s' "$value" | tr '/:@' '---' | tr -cd '[:alnum:]_.-')"
  [[ -n "$value" ]] || value="user"
  printf '%s\n' "$value"
}

write_client_snippet() {
  local share_host="$1"
  local tmp_dir=""
  local files=()
  local user_json=""
  local user_name=""
  local tag_suffix=""
  local file=""
  local quic=false
  local tls_insecure=false

  tmp_dir="$(mktemp -d)"
  [[ "$NAIVE_NETWORK" == "udp" ]] && quic=true
  [[ "$CERT_MODE" == "self-signed" ]] && tls_insecure=true

  if protocol_enabled vless; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      tag_suffix="$(sanitize_tag_value "$user_name")"
      file="$tmp_dir/vless-$tag_suffix.json"
      if [[ "$VLESS_MODE" == "reality" ]]; then
        jq -nc \
          --argjson user "$user_json" \
          --arg host "$share_host" \
          --argjson port "$VLESS_PORT" \
          --arg server_name "$REALITY_SERVER_NAME" \
          --arg fingerprint "$CLIENT_FINGERPRINT" \
          --arg public_key "$REALITY_PUBLIC_KEY" \
          --arg short_id "$REALITY_SHORT_ID" \
          --arg tag_suffix "$tag_suffix" \
          '{
            type: "vless",
            tag: ("vless-reality-" + $tag_suffix),
            server: $host,
            server_port: $port,
            uuid: $user.uuid,
            flow: ($user.flow // "xtls-rprx-vision"),
            tls: {
              enabled: true,
              server_name: $server_name,
              utls: {
                enabled: true,
                fingerprint: $fingerprint
              },
              reality: {
                enabled: true,
                public_key: $public_key,
                short_id: $short_id
              }
            }
          }' > "$file"
      else
        jq -nc \
          --argjson user "$user_json" \
          --arg host "$share_host" \
          --argjson port "$VLESS_PORT" \
          --arg domain "$DOMAIN" \
          --argjson tls_insecure "$tls_insecure" \
          --arg tag_suffix "$tag_suffix" \
          '{
            type: "vless",
            tag: ("vless-tls-" + $tag_suffix),
            server: $host,
            server_port: $port,
            uuid: $user.uuid,
            flow: ($user.flow // "xtls-rprx-vision"),
            tls: {
              enabled: true,
              server_name: $domain,
              insecure: $tls_insecure
            }
          }' > "$file"
      fi
      files+=("$file")
    done < <(jq -c '.[]' <<< "$VLESS_USERS_JSON")
  fi

  if protocol_enabled vmess; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      tag_suffix="$(sanitize_tag_value "$user_name")"
      file="$tmp_dir/vmess-$tag_suffix.json"
      jq -nc \
        --argjson user "$user_json" \
        --arg host "$share_host" \
        --argjson port "$VMESS_PORT" \
        --arg domain "$DOMAIN" \
        --arg fingerprint "$CLIENT_FINGERPRINT" \
        --argjson tls_insecure "$tls_insecure" \
        --arg tag_suffix "$tag_suffix" \
        '{
          type: "vmess",
          tag: ("vmess-" + $tag_suffix),
          server: $host,
          server_port: $port,
          uuid: $user.uuid,
          security: "auto",
          alter_id: ($user.alterId // 0),
          tls: {
            enabled: true,
            server_name: $domain,
            insecure: $tls_insecure,
            utls: {
              enabled: true,
              fingerprint: $fingerprint
            }
          }
        }' > "$file"
      files+=("$file")
    done < <(jq -c '.[]' <<< "$VMESS_USERS_JSON")
  fi

  if protocol_enabled trojan; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      tag_suffix="$(sanitize_tag_value "$user_name")"
      file="$tmp_dir/trojan-$tag_suffix.json"
      jq -nc \
        --argjson user "$user_json" \
        --arg host "$share_host" \
        --argjson port "$TROJAN_PORT" \
        --arg domain "$DOMAIN" \
        --argjson tls_insecure "$tls_insecure" \
        --arg tag_suffix "$tag_suffix" \
        '{
          type: "trojan",
          tag: ("trojan-" + $tag_suffix),
          server: $host,
          server_port: $port,
          password: $user.password,
          tls: {
            enabled: true,
            server_name: $domain,
            insecure: $tls_insecure
          }
        }' > "$file"
      files+=("$file")
    done < <(jq -c '.[]' <<< "$TROJAN_USERS_JSON")
  fi

  if protocol_enabled hysteria2; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      tag_suffix="$(sanitize_tag_value "$user_name")"
      file="$tmp_dir/hysteria2-$tag_suffix.json"
      jq -nc \
        --argjson user "$user_json" \
        --arg host "$share_host" \
        --argjson port "$HYSTERIA2_PORT" \
        --arg obfs_password "$HYSTERIA2_OBFS_PASSWORD" \
        --arg domain "$DOMAIN" \
        --argjson tls_insecure "$tls_insecure" \
        --arg tag_suffix "$tag_suffix" \
        '{
          type: "hysteria2",
          tag: ("hysteria2-" + $tag_suffix),
          server: $host,
          server_port: $port,
          password: $user.password,
          obfs: {
            type: "salamander",
            password: $obfs_password
          },
          tls: {
            enabled: true,
            server_name: $domain,
            insecure: $tls_insecure
          }
        }' > "$file"
      files+=("$file")
    done < <(jq -c '.[]' <<< "$HYSTERIA2_USERS_JSON")
  fi

  if protocol_enabled tuic; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      tag_suffix="$(sanitize_tag_value "$user_name")"
      file="$tmp_dir/tuic-$tag_suffix.json"
      jq -nc \
        --argjson user "$user_json" \
        --arg host "$share_host" \
        --argjson port "$TUIC_PORT" \
        --arg cc "$TUIC_CONGESTION_CONTROL" \
        --arg domain "$DOMAIN" \
        --argjson tls_insecure "$tls_insecure" \
        --arg tag_suffix "$tag_suffix" \
        '{
          type: "tuic",
          tag: ("tuic-" + $tag_suffix),
          server: $host,
          server_port: $port,
          uuid: $user.uuid,
          password: $user.password,
          congestion_control: $cc,
          zero_rtt_handshake: false,
          heartbeat: "10s",
          tls: {
            enabled: true,
            server_name: $domain,
            insecure: $tls_insecure
          }
        }' > "$file"
      files+=("$file")
    done < <(jq -c '.[]' <<< "$TUIC_USERS_JSON")
  fi

  if protocol_enabled naive; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.username // "user"' <<< "$user_json")"
      tag_suffix="$(sanitize_tag_value "$user_name")"
      file="$tmp_dir/naive-$tag_suffix.json"
      jq -nc \
        --argjson user "$user_json" \
        --arg host "$share_host" \
        --argjson port "$NAIVE_PORT" \
        --arg domain "$DOMAIN" \
        --argjson quic "$quic" \
        --argjson tls_insecure "$tls_insecure" \
        --arg tag_suffix "$tag_suffix" \
        '{
          type: "naive",
          tag: ("naive-" + $tag_suffix),
          server: $host,
          server_port: $port,
          username: $user.username,
          password: $user.password,
          quic: $quic,
          tls: {
            enabled: true,
            server_name: $domain,
            insecure: $tls_insecure
          }
        }' > "$file"
      files+=("$file")
    done < <(jq -c '.[]' <<< "$NAIVE_USERS_JSON")
  fi

  if protocol_enabled socks5; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.username // "user"' <<< "$user_json")"
      tag_suffix="$(sanitize_tag_value "$user_name")"
      file="$tmp_dir/socks5-$tag_suffix.json"
      jq -nc \
        --argjson user "$user_json" \
        --arg host "$share_host" \
        --argjson port "$SOCKS5_PORT" \
        --arg tag_suffix "$tag_suffix" \
        '{
          type: "socks",
          tag: ("socks5-" + $tag_suffix),
          server: $host,
          server_port: $port,
          version: "5",
          username: $user.username,
          password: $user.password
        }' > "$file"
      files+=("$file")
    done < <(jq -c '.[]' <<< "$SOCKS5_USERS_JSON")
  fi

  if protocol_enabled ss2022; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      tag_suffix="$(sanitize_tag_value "$user_name")"
      file="$tmp_dir/ss2022-$tag_suffix.json"
      jq -nc \
        --argjson user "$user_json" \
        --arg host "$share_host" \
        --argjson port "$SS2022_PORT" \
        --arg method "$SS2022_METHOD" \
        --arg server_password "$SS2022_SERVER_PASSWORD" \
        --arg tag_suffix "$tag_suffix" \
        '{
          type: "shadowsocks",
          tag: ("ss2022-" + $tag_suffix),
          server: $host,
          server_port: $port,
          method: $method,
          password: ($server_password + ":" + $user.password)
        }' > "$file"
      files+=("$file")
    done < <(jq -c '.[]' <<< "$SS2022_USERS_JSON")
  fi

  if ((${#files[@]} > 0)); then
    jq -s '{outbounds: .}' "${files[@]}" > "$CLIENT_SNIPPET_FILE"
  else
    jq -n '{outbounds: []}' > "$CLIENT_SNIPPET_FILE"
  fi
  rm -rf -- "$tmp_dir"
}

write_client_full_config() {
  local outbounds_json=""
  local proxy_tags_json=""
  local strategy_outbounds_json=""
  local route_rule_set_json=""
  local route_rules_json=""
  local final_tag="direct"

  if [[ ! -f "$CLIENT_SNIPPET_FILE" ]]; then
    jq -n '{outbounds: []}' > "$CLIENT_SNIPPET_FILE"
  fi

  outbounds_json="$(jq -c '.outbounds' "$CLIENT_SNIPPET_FILE")"
  proxy_tags_json="$(jq -c '[.outbounds[].tag]' "$CLIENT_SNIPPET_FILE")"
  route_rule_set_json="$(
    jq -n '[
      {
        type: "remote",
        tag: "geosite-geolocation-cn",
        format: "binary",
        url: "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs"
      },
      {
        type: "remote",
        tag: "geoip-cn",
        format: "binary",
        url: "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
      }
    ]'
  )"
  route_rules_json="$(
    jq -n '[
      {
        ip_is_private: true,
        outbound: "direct"
      },
      {
        rule_set: ["geosite-geolocation-cn", "geoip-cn"],
        outbound: "direct"
      }
    ]'
  )"

  if [[ "$(jq -r 'length' <<< "$proxy_tags_json")" -gt 0 ]]; then
    strategy_outbounds_json="$(
      jq -n \
        --argjson tags "$proxy_tags_json" \
        '[
          {
            type: "urltest",
            tag: "auto",
            outbounds: $tags,
            url: "https://cp.cloudflare.com/generate_204",
            interval: "10m",
            tolerance: 50,
            idle_timeout: "30m",
            interrupt_exist_connections: false
          },
          {
            type: "selector",
            tag: "select",
            outbounds: (["auto"] + $tags + ["direct"]),
            interrupt_exist_connections: false
          }
        ]'
    )"
    final_tag="select"
  else
    strategy_outbounds_json='[]'
  fi

  jq -n \
    --argjson outbounds "$outbounds_json" \
    --argjson strategy_outbounds "$strategy_outbounds_json" \
    --argjson rule_set "$route_rule_set_json" \
    --argjson rules "$route_rules_json" \
    --arg final_tag "$final_tag" \
    '{
      log: {
        level: "warn",
        timestamp: true
      },
      inbounds: [
        {
          type: "mixed",
          tag: "mixed-in",
          listen: "127.0.0.1",
          listen_port: 2080
        }
      ],
      dns: {
        servers: [
          {
            type: "udp",
            tag: "dns-local",
            server: "223.5.5.5"
          },
          {
            type: "tls",
            tag: "dns-remote",
            server: "8.8.8.8"
          }
        ],
        rules: [
          {
            rule_set: "geosite-geolocation-cn",
            server: "dns-local"
          },
          {
            rule_set: "geoip-cn",
            server: "dns-local"
          }
        ],
        final: "dns-remote",
        strategy: "ipv4_only"
      },
      outbounds: ($outbounds + $strategy_outbounds + [
        {type: "direct", tag: "direct"},
        {type: "block", tag: "block"}
      ]),
      route: {
        auto_detect_interface: true,
        default_domain_resolver: "dns-remote",
        rule_set: $rule_set,
        rules: $rules,
        final: $final_tag
      }
    }' > "$CLIENT_FULL_CONFIG_FILE"
}

write_client_tun_config() {
  local outbounds_json=""
  local proxy_tags_json=""
  local strategy_outbounds_json=""
  local route_rule_set_json=""
  local route_rules_json=""
  local final_tag="direct"

  if [[ ! -f "$CLIENT_SNIPPET_FILE" ]]; then
    jq -n '{outbounds: []}' > "$CLIENT_SNIPPET_FILE"
  fi

  outbounds_json="$(jq -c '.outbounds' "$CLIENT_SNIPPET_FILE")"
  proxy_tags_json="$(jq -c '[.outbounds[].tag]' "$CLIENT_SNIPPET_FILE")"
  route_rule_set_json="$(
    jq -n '[
      {
        type: "remote",
        tag: "geosite-geolocation-cn",
        format: "binary",
        url: "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs"
      },
      {
        type: "remote",
        tag: "geoip-cn",
        format: "binary",
        url: "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
      }
    ]'
  )"
  route_rules_json="$(
    jq -n '[
      {
        action: "sniff"
      },
      {
        protocol: "dns",
        action: "hijack-dns"
      },
      {
        ip_is_private: true,
        outbound: "direct"
      },
      {
        rule_set: ["geosite-geolocation-cn", "geoip-cn"],
        outbound: "direct"
      }
    ]'
  )"

  if [[ "$(jq -r 'length' <<< "$proxy_tags_json")" -gt 0 ]]; then
    strategy_outbounds_json="$(
      jq -n \
        --argjson tags "$proxy_tags_json" \
        '[
          {
            type: "urltest",
            tag: "auto",
            outbounds: $tags,
            url: "https://cp.cloudflare.com/generate_204",
            interval: "10m",
            tolerance: 50,
            idle_timeout: "30m",
            interrupt_exist_connections: false
          },
          {
            type: "selector",
            tag: "select",
            outbounds: (["auto"] + $tags + ["direct"]),
            interrupt_exist_connections: false
          }
        ]'
    )"
    final_tag="select"
  else
    strategy_outbounds_json='[]'
  fi

  jq -n \
    --argjson outbounds "$outbounds_json" \
    --argjson strategy_outbounds "$strategy_outbounds_json" \
    --argjson rule_set "$route_rule_set_json" \
    --argjson rules "$route_rules_json" \
    --arg final_tag "$final_tag" \
    '{
      log: {
        level: "warn",
        timestamp: true
      },
      dns: {
        servers: [
          {
            type: "udp",
            tag: "dns-local",
            server: "223.5.5.5"
          },
          {
            type: "tls",
            tag: "dns-remote",
            server: "8.8.8.8"
          }
        ],
        rules: [
          {
            rule_set: "geosite-geolocation-cn",
            server: "dns-local"
          },
          {
            rule_set: "geoip-cn",
            server: "dns-local"
          }
        ],
        final: "dns-remote",
        strategy: "ipv4_only"
      },
      inbounds: [
        {
          type: "tun",
          tag: "tun-in",
          address: ["172.19.0.1/30"],
          auto_route: true,
          strict_route: true,
          stack: "mixed"
        },
        {
          type: "mixed",
          tag: "mixed-in",
          listen: "127.0.0.1",
          listen_port: 2080
        }
      ],
      outbounds: ($outbounds + $strategy_outbounds + [
        {type: "direct", tag: "direct"},
        {type: "block", tag: "block"}
      ]),
      route: {
        auto_detect_interface: true,
        default_domain_resolver: "dns-remote",
        rule_set: $rule_set,
        rules: $rules,
        final: $final_tag
      }
    }' > "$CLIENT_TUN_CONFIG_FILE"
}

write_share_links() {
  local share_host="$1"
  local links=()
  local encoded=""
  local fragment=""
  local vmess_json=""
  local vmess_link=""
  local ss_info=""
  local user_json=""
  local user_name=""

  if protocol_enabled vless; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      fragment="$(uri_fragment "vless-${VLESS_MODE}-${user_name}-${VLESS_PORT}")"
      if [[ "$VLESS_MODE" == "reality" ]]; then
        links+=("vless://$(jq -r '.uuid' <<< "$user_json")@${share_host}:${VLESS_PORT}?encryption=none&flow=$(jq -r '.flow // "xtls-rprx-vision"' <<< "$user_json")&security=reality&sni=${REALITY_SERVER_NAME}&fp=${CLIENT_FINGERPRINT}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#${fragment}")
      else
        links+=("vless://$(jq -r '.uuid' <<< "$user_json")@${share_host}:${VLESS_PORT}?encryption=none&flow=$(jq -r '.flow // "xtls-rprx-vision"' <<< "$user_json")&security=tls&sni=${DOMAIN}&type=tcp&headerType=none#${fragment}")
      fi
    done < <(jq -c '.[]' <<< "$VLESS_USERS_JSON")
  fi

  if protocol_enabled vmess; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      vmess_json="$(
        jq -cn \
          --arg add "$share_host" \
          --arg port "$VMESS_PORT" \
          --arg id "$(jq -r '.uuid' <<< "$user_json")" \
          --arg ps "vmess-${user_name}-${VMESS_PORT}" \
          --arg sni "$DOMAIN" \
          '{
            v: "2",
            ps: $ps,
            add: $add,
            port: $port,
            id: $id,
            aid: "0",
            scy: "auto",
            net: "tcp",
            type: "none",
            host: "",
            path: "",
            tls: "tls",
            sni: $sni
          }'
      )"
      vmess_link="vmess://$(printf '%s' "$vmess_json" | openssl base64 -A)"
      links+=("$vmess_link")
    done < <(jq -c '.[]' <<< "$VMESS_USERS_JSON")
  fi

  if protocol_enabled trojan; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      encoded="$(uri_encode "$(jq -r '.password' <<< "$user_json")")"
      fragment="$(uri_fragment "trojan-${user_name}-${TROJAN_PORT}")"
      links+=("trojan://${encoded}@${share_host}:${TROJAN_PORT}?security=tls&sni=${DOMAIN}&type=tcp#${fragment}")
    done < <(jq -c '.[]' <<< "$TROJAN_USERS_JSON")
  fi

  if protocol_enabled hysteria2; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      encoded="$(uri_encode "$(jq -r '.password' <<< "$user_json")")"
      fragment="$(uri_fragment "hysteria2-${user_name}-${HYSTERIA2_PORT}")"
      links+=("hysteria2://${encoded}@${share_host}:${HYSTERIA2_PORT}/?sni=${DOMAIN}&obfs=salamander&obfs-password=${HYSTERIA2_OBFS_PASSWORD}#${fragment}")
    done < <(jq -c '.[]' <<< "$HYSTERIA2_USERS_JSON")
  fi

  if protocol_enabled tuic; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      fragment="$(uri_fragment "tuic-${user_name}-${TUIC_PORT}")"
      links+=("tuic://$(jq -r '.uuid' <<< "$user_json"):$(uri_encode "$(jq -r '.password' <<< "$user_json")")@${share_host}:${TUIC_PORT}?sni=${DOMAIN}&congestion_control=${TUIC_CONGESTION_CONTROL}&alpn=h3#${fragment}")
    done < <(jq -c '.[]' <<< "$TUIC_USERS_JSON")
  fi

  if protocol_enabled naive; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.username // "user"' <<< "$user_json")"
      fragment="$(uri_fragment "naive-${user_name}-${NAIVE_PORT}")"
      if [[ "$NAIVE_NETWORK" == "udp" ]]; then
        links+=("naive+quic://$(uri_encode "$user_name"):$(uri_encode "$(jq -r '.password' <<< "$user_json")")@${share_host}:${NAIVE_PORT}#${fragment}")
      else
        links+=("naive+https://$(uri_encode "$user_name"):$(uri_encode "$(jq -r '.password' <<< "$user_json")")@${share_host}:${NAIVE_PORT}#${fragment}")
      fi
    done < <(jq -c '.[]' <<< "$NAIVE_USERS_JSON")
  fi

  if protocol_enabled socks5; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.username // "user"' <<< "$user_json")"
      fragment="$(uri_fragment "socks5-${user_name}-${SOCKS5_PORT}")"
      links+=("socks5://$(uri_encode "$user_name"):$(uri_encode "$(jq -r '.password' <<< "$user_json")")@${share_host}:${SOCKS5_PORT}#${fragment}")
    done < <(jq -c '.[]' <<< "$SOCKS5_USERS_JSON")
  fi

  if protocol_enabled ss2022; then
    while IFS= read -r user_json; do
      user_name="$(jq -r '.name // "user"' <<< "$user_json")"
      ss_info="${SS2022_METHOD}:${SS2022_SERVER_PASSWORD}:$(jq -r '.password' <<< "$user_json")"
      fragment="$(uri_fragment "ss2022-${user_name}-${SS2022_PORT}")"
      links+=("ss://$(base64_url_nopad "$ss_info")@${share_host}:${SS2022_PORT}#${fragment}")
    done < <(jq -c '.[]' <<< "$SS2022_USERS_JSON")
  fi

  printf '%s\n' "${links[@]}" > "$SHARE_LINKS_FILE"
}

write_state() {
  local share_host="$1"
  local protocols=""

  protocols="$(protocols_json)"
  sync_primary_credentials_from_users

  jq -n \
    --arg updated_at "$(date --iso-8601=seconds)" \
    --argjson protocols "$protocols" \
    --arg domain "$DOMAIN" \
    --arg email "$EMAIL" \
    --arg share_host "$share_host" \
    --arg cert_mode "$CERT_MODE" \
    --arg acme_mode "$ACME_MODE" \
    --arg tls_status "$TLS_STATUS" \
    --arg tls_reason "$TLS_REASON" \
    --arg acme_challenge "$ACME_CHALLENGE_USED" \
    --arg vless_mode "$VLESS_MODE" \
    --arg reality_server_name "$REALITY_SERVER_NAME" \
    --arg reality_handshake_server "$REALITY_HANDSHAKE_SERVER" \
    --argjson reality_handshake_port "$REALITY_HANDSHAKE_PORT" \
    --arg naive_network "$NAIVE_NETWORK" \
    --arg ss2022_method "$SS2022_METHOD" \
    --arg tuic_cc "$TUIC_CONGESTION_CONTROL" \
    --argjson route_block_bittorrent "$ROUTE_BLOCK_BITTORRENT" \
    --argjson route_block_cn "$ROUTE_BLOCK_CN" \
    --argjson route_block_ads "$ROUTE_BLOCK_ADS" \
    --argjson tls_required "$TLS_REQUIRED" \
    --arg sing_box_version "$SING_BOX_VERSION_NUMBER" \
    --argjson vless_port "${VLESS_PORT:-0}" \
    --argjson vmess_port "${VMESS_PORT:-0}" \
    --argjson trojan_port "${TROJAN_PORT:-0}" \
    --argjson hysteria2_port "${HYSTERIA2_PORT:-0}" \
    --argjson tuic_port "${TUIC_PORT:-0}" \
    --argjson naive_port "${NAIVE_PORT:-0}" \
    --argjson socks5_port "${SOCKS5_PORT:-0}" \
    --argjson ss2022_port "${SS2022_PORT:-0}" \
    --arg vless_uuid "$VLESS_UUID" \
    --arg reality_private_key "$REALITY_PRIVATE_KEY" \
    --arg reality_public_key "$REALITY_PUBLIC_KEY" \
    --arg reality_short_id "$REALITY_SHORT_ID" \
    --arg vmess_uuid "$VMESS_UUID" \
    --arg trojan_password "$TROJAN_PASSWORD" \
    --arg hysteria2_password "$HYSTERIA2_PASSWORD" \
    --arg hysteria2_obfs_password "$HYSTERIA2_OBFS_PASSWORD" \
    --arg tuic_uuid "$TUIC_UUID" \
    --arg tuic_password "$TUIC_PASSWORD" \
    --arg naive_username "$NAIVE_USERNAME" \
    --arg naive_password "$NAIVE_PASSWORD" \
    --arg socks5_username "$SOCKS5_USERNAME" \
    --arg socks5_password "$SOCKS5_PASSWORD" \
    --arg ss2022_server_password "$SS2022_SERVER_PASSWORD" \
    --arg ss2022_user_password "$SS2022_USER_PASSWORD" \
    --argjson vless_users "$VLESS_USERS_JSON" \
    --argjson vmess_users "$VMESS_USERS_JSON" \
    --argjson trojan_users "$TROJAN_USERS_JSON" \
    --argjson hysteria2_users "$HYSTERIA2_USERS_JSON" \
    --argjson tuic_users "$TUIC_USERS_JSON" \
    --argjson naive_users "$NAIVE_USERS_JSON" \
    --argjson socks5_users "$SOCKS5_USERS_JSON" \
    --argjson ss2022_users "$SS2022_USERS_JSON" \
    '{
      version: 2,
      updated_at: $updated_at,
      sing_box_version: $sing_box_version,
      enabled_protocols: $protocols,
      domain: $domain,
      email: $email,
      share_host: $share_host,
      cert_mode: $cert_mode,
      acme_mode: $acme_mode,
      tls: {
        required: $tls_required,
        status: $tls_status,
        reason: $tls_reason,
        acme_challenge: $acme_challenge
      },
      settings: {
        vless_mode: $vless_mode,
        reality: {
          server_name: $reality_server_name,
          handshake_server: $reality_handshake_server,
          handshake_port: $reality_handshake_port
        },
        naive_network: $naive_network,
        ss2022_method: $ss2022_method,
        tuic_congestion_control: $tuic_cc
      },
      routing: {
        block_bittorrent: $route_block_bittorrent,
        block_cn: $route_block_cn,
        block_ads: $route_block_ads
      },
      ports: {
        vless: $vless_port,
        vmess: $vmess_port,
        trojan: $trojan_port,
        hysteria2: $hysteria2_port,
        tuic: $tuic_port,
        naive: $naive_port,
        socks5: $socks5_port,
        ss2022: $ss2022_port
      },
      credentials: {
        vless: {
          uuid: $vless_uuid,
          reality_private_key: $reality_private_key,
          reality_public_key: $reality_public_key,
          reality_short_id: $reality_short_id
        },
        vmess: {
          uuid: $vmess_uuid
        },
        trojan: {
          password: $trojan_password
        },
        hysteria2: {
          password: $hysteria2_password,
          obfs_password: $hysteria2_obfs_password
        },
        tuic: {
          uuid: $tuic_uuid,
          password: $tuic_password
        },
        naive: {
          username: $naive_username,
          password: $naive_password
        },
        socks5: {
          username: $socks5_username,
          password: $socks5_password
        },
        ss2022: {
          server_password: $ss2022_server_password,
          user_password: $ss2022_user_password
        }
      },
      users: {
        vless: $vless_users,
        vmess: $vmess_users,
        trojan: $trojan_users,
        hysteria2: $hysteria2_users,
        tuic: $tuic_users,
        naive: $naive_users,
        socks5: $socks5_users,
        ss2022: $ss2022_users
      }
    }' > "$STATE_FILE"
}

write_summary() {
  local share_host="$1"
  local service_state=""
  local protocols=""

  service_state="$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)"
  protocols="$(protocols_pretty)"

  cat > "$SUMMARY_FILE" <<EOF
sing-box all-in-one deployment summary

Service
  Name: $SERVICE_NAME
  State: ${service_state:-unknown}
  sing-box: ${SING_BOX_VERSION:-unknown}

Protocols
  Enabled: $protocols
  VLESS mode: $VLESS_MODE
  Naive network: $NAIVE_NETWORK
  SS2022 method: $SS2022_METHOD
  TUIC congestion control: $TUIC_CONGESTION_CONTROL

Routing
  Policy: $(routing_status_brief)

Addressing
  Share host: $share_host
  Domain: ${DOMAIN:-not-set}
  Email: ${EMAIL:-not-set}

TLS
  Required: $TLS_REQUIRED
  Certificate mode: $CERT_MODE
  Status: $TLS_STATUS
  Detail: ${TLS_REASON:-none}
  ACME challenge: $ACME_CHALLENGE_USED
  ACME/OpenSSL log: $ACME_LOG_FILE

Ports
  VLESS: ${VLESS_PORT:-disabled}
  VMess: ${VMESS_PORT:-disabled}
  Trojan: ${TROJAN_PORT:-disabled}
  Hysteria2: ${HYSTERIA2_PORT:-disabled}
  TUIC: ${TUIC_PORT:-disabled}
  NaiveProxy: ${NAIVE_PORT:-disabled}
  SOCKS5: ${SOCKS5_PORT:-disabled}
  SS2022: ${SS2022_PORT:-disabled}

Artifacts
  Config: $TARGET_CONFIG
  State: $STATE_FILE
  Share links: $SHARE_LINKS_FILE
  Client snippet: $CLIENT_SNIPPET_FILE
  Client full config: $CLIENT_FULL_CONFIG_FILE
  Client tun config: $CLIENT_TUN_CONFIG_FILE
  Summary: $SUMMARY_FILE
  Backup: ${BACKUP_PATH:-none}

Notes
  Naive outbound/client support in sing-box starts from 1.13.0 and depends on platform/runtime support.
  VLESS defaults to Reality unless you explicitly switch to TLS mode.
  The deployed config uses one listen port per protocol to keep the layout predictable and easy to manage.
EOF
}

print_install_result() {
  local share_host="$1"

  cat <<EOF

Deployment summary
$(cat "$SUMMARY_FILE")

Share links
$(cat "$SHARE_LINKS_FILE")

Client snippet
$(cat "$CLIENT_SNIPPET_FILE")

Client full config
$(if [[ -f "$CLIENT_FULL_CONFIG_FILE" ]]; then cat "$CLIENT_FULL_CONFIG_FILE"; else printf '(not generated)'; fi)
EOF
}

show_saved_artifacts() {
  if [[ ! -f "$SUMMARY_FILE" || ! -f "$SHARE_LINKS_FILE" || ! -f "$CLIENT_SNIPPET_FILE" ]]; then
    if [[ -f "$STATE_FILE" ]]; then
      die "$(cat <<EOF
当前检测到部署状态文件，但分享信息文件还不存在或不完整。
建议操作：
1. 先执行“5) 重建配置与分享信息”或运行：
   ./install-sing-box.sh regenerate
2. 然后再执行“6) 查看分享链接与客户端片段”
当前状态文件：
  $STATE_FILE
EOF
)"
    fi

    die "$(cat <<EOF
当前还没有可查看的部署信息。
建议操作：
1. 先执行“1) 安装 / 重配多协议服务”
2. 部署完成后，再执行“6) 查看分享链接与客户端片段”
预期生成文件：
  $SUMMARY_FILE
  $SHARE_LINKS_FILE
  $CLIENT_SNIPPET_FILE
EOF
)"
  fi

  cat <<EOF
$(cat "$SUMMARY_FILE")

Share links
$(cat "$SHARE_LINKS_FILE")

Client snippet
$(cat "$CLIENT_SNIPPET_FILE")

Client full config
$(if [[ -f "$CLIENT_FULL_CONFIG_FILE" ]]; then cat "$CLIENT_FULL_CONFIG_FILE"; else printf '(not generated)'; fi)

Client tun config
$(if [[ -f "$CLIENT_TUN_CONFIG_FILE" ]]; then cat "$CLIENT_TUN_CONFIG_FILE"; else printf '(not generated)'; fi)
EOF
}

ensure_state_exists() {
  load_state
  [[ "$STATE_LOADED" -eq 1 ]] || die "$(cat <<EOF
当前还没有可用的部署状态，或者状态文件已损坏。
建议操作：
1. 先执行“1) 安装 / 重配多协议服务”
2. 完成至少一次成功部署后，再使用当前菜单功能
状态文件路径：
  $STATE_FILE
EOF
)"
}

load_runtime_from_state() {
  ensure_state_exists
  load_defaults_from_state
  apply_runtime_defaults
  validate_selection
  [[ "${#ENABLED_PROTOCOLS[@]}" -gt 0 ]] || die "$(cat <<EOF
当前状态文件里没有任何已启用协议。
建议操作：
1. 执行“1) 安装 / 重配多协议服务”
2. 在安装向导里至少选择一个协议后再继续
EOF
)"
  prepare_credentials
  ensure_user_arrays
  sync_primary_credentials_from_users

  if command -v sing-box >/dev/null 2>&1; then
    SING_BOX_VERSION="$(sing-box version 2>/dev/null | head -n 1 || true)"
    SING_BOX_VERSION_NUMBER="$(printf '%s\n' "$SING_BOX_VERSION" | awk 'NR==1{print $NF}' | sed 's/^v//')"
    validate_protocol_version_support
  fi
}

check_tls_files_if_required() {
  update_tls_requirement
  if [[ "$TLS_REQUIRED" -eq 1 ]]; then
    [[ -s "$CERT_FULLCHAIN" ]] || die "TLS certificate file is missing: $CERT_FULLCHAIN"
    [[ -s "$CERT_KEY" ]] || die "TLS private key file is missing: $CERT_KEY"
  fi
}

render_from_current_state() {
  local share_host=""

  command -v sing-box >/dev/null 2>&1 || die "sing-box is not installed"
  prepare_dirs
  backup_existing_files
  check_tls_files_if_required
  download_required_rule_sets
  render_config
  validate_rendered_config
  restart_service
  share_host="$(choose_share_host)"
  write_share_links "$share_host"
  write_client_snippet "$share_host"
  write_client_full_config
  write_client_tun_config
  write_state "$share_host"
  write_summary "$share_host"
}

refresh_client_artifacts_from_state() {
  local share_host=""

  share_host="$(choose_share_host)"
  write_share_links "$share_host"
  write_client_snippet "$share_host"
  write_client_full_config
  write_client_tun_config
  write_state "$share_host"
  write_summary "$share_host"
}

default_managed_user_name() {
  case "$1" in
    vless) generate_username vless ;;
    vmess) generate_username vmess ;;
    trojan) generate_username trojan ;;
    hysteria2) generate_username hy2 ;;
    tuic) generate_username tuic ;;
    naive) generate_username naive ;;
    socks5) generate_username socks ;;
    ss2022) generate_username ss2022 ;;
    *)
      die "Unknown protocol in default_managed_user_name: $1"
      ;;
  esac
}

ensure_manage_protocol_enabled() {
  MANAGE_PROTOCOL="$(normalize_protocol_or_die "$MANAGE_PROTOCOL")"
  protocol_enabled "$MANAGE_PROTOCOL" || die "Protocol is not enabled in current state: $MANAGE_PROTOCOL"
}

prompt_manage_protocol_if_needed() {
  local input=""
  local protocol=""
  local index=0
  local -a choices=()

  if [[ -n "$MANAGE_PROTOCOL" ]]; then
    MANAGE_PROTOCOL="$(normalize_protocol_or_die "$MANAGE_PROTOCOL")"
    return 0
  fi

  if ! should_prompt_interactively; then
    die "--protocol is required"
  fi

  for protocol in "${SUPPORTED_PROTOCOL_ORDER[@]}"; do
    protocol_enabled "$protocol" || continue
    choices+=("$protocol")
  done

  ((${#choices[@]} > 0)) || die "$(cat <<EOF
当前没有任何可操作的 inbound 协议。
建议操作：
1. 先执行“1) 安装 / 重配多协议服务”
2. 至少启用一个协议后，再执行新增或删除用户
EOF
)"

  while true; do
    printf '%s\n' "请选择要操作的 inbound 协议：" >&2
    for index in "${!choices[@]}"; do
      printf '  %d) %s\n' "$((index + 1))" "$(protocol_label "${choices[$index]}")" >&2
    done
    printf '请输入编号 [1-%d]: ' "${#choices[@]}" >&2
    read -r input

    if [[ ! "$input" =~ ^[0-9]+$ ]]; then
      warn "输入无效，请输入上面列表中的数字。"
      continue
    fi

    if ((input < 1 || input > ${#choices[@]})); then
      warn "编号超出范围，请重新输入。"
      continue
    fi

    MANAGE_PROTOCOL="${choices[$((input - 1))]}"
    return 0
  done
}

prompt_manage_user_name_if_needed() {
  local prompt_label="用户名"
  local users_json=""
  local key=""
  local count=0
  local input=""
  local index=0
  local -a choices=()

  case "$MANAGE_PROTOCOL" in
    vless|vmess|trojan|hysteria2|tuic|ss2022)
      prompt_label="用户标识"
      ;;
    naive|socks5)
      prompt_label="用户名"
      ;;
  esac

  if [[ -n "$MANAGE_USER_NAME" ]]; then
    return 0
  fi

  if [[ "$COMMAND" == "add-user" ]]; then
    MANAGE_USER_NAME="$(default_managed_user_name "$MANAGE_PROTOCOL")"
    if should_prompt_interactively; then
      prompt_text_value "$prompt_label" "$MANAGE_USER_NAME" "" "1"
      MANAGE_USER_NAME="$PROMPT_RESULT"
    fi
    return 0
  fi

  if should_prompt_interactively; then
    if [[ "$COMMAND" == "remove-user" ]]; then
      users_json="$(get_users_json_var "$MANAGE_PROTOCOL")"
      key="$(protocol_user_key "$MANAGE_PROTOCOL")"
      count="$(jq -r 'length' <<< "$users_json")"

      if ((count == 0)); then
        die "$(cat <<EOF
当前协议下没有可删除的用户。
建议操作：
1. 先执行“3) 新增用户”
2. 或返回主菜单选择其它已配置协议
当前协议：
  $(protocol_label "$MANAGE_PROTOCOL")
EOF
)"
      fi

      if ((count == 1)); then
        die "$(cat <<EOF
当前协议只剩最后一个用户，脚本不允许直接删空。
建议操作：
1. 先执行“3) 新增用户”
2. 再回来删除旧用户
当前协议：
  $(protocol_label "$MANAGE_PROTOCOL")
当前唯一用户：
  $(jq -r --arg key "$key" '.[0][$key]' <<< "$users_json")
EOF
)"
      fi

      while IFS= read -r input; do
        choices+=("$input")
      done < <(jq -r --arg key "$key" '.[][$key]' <<< "$users_json")

      while true; do
        printf '%s\n' "请选择要删除的用户：" >&2
        for index in "${!choices[@]}"; do
          printf '  %d) %s\n' "$((index + 1))" "${choices[$index]}" >&2
        done
        printf '请输入编号 [1-%d]: ' "${#choices[@]}" >&2
        read -r input

        if [[ ! "$input" =~ ^[0-9]+$ ]]; then
          warn "输入无效，请输入上面列表中的数字。"
          continue
        fi

        if ((input < 1 || input > ${#choices[@]})); then
          warn "编号超出范围，请重新输入。"
          continue
        fi

        MANAGE_USER_NAME="${choices[$((input - 1))]}"
        return 0
      done
    fi

    prompt_text_value "$prompt_label" "" "" "1"
    MANAGE_USER_NAME="$PROMPT_RESULT"
    return 0
  fi

  die "--user-name is required"
}

build_managed_user_json() {
  local protocol="$1"
  local uuid=""
  local password=""

  case "$protocol" in
    vless)
      uuid="${MANAGE_USER_UUID:-$(generate_uuid)}"
      jq -nc --arg name "$MANAGE_USER_NAME" --arg uuid "$uuid" --arg flow "xtls-rprx-vision" '{name: $name, uuid: $uuid, flow: $flow}'
      ;;
    vmess)
      uuid="${MANAGE_USER_UUID:-$(generate_uuid)}"
      jq -nc --arg name "$MANAGE_USER_NAME" --arg uuid "$uuid" '{name: $name, uuid: $uuid, alterId: 0}'
      ;;
    trojan)
      password="${MANAGE_USER_PASSWORD:-$(generate_hex_secret 16)}"
      jq -nc --arg name "$MANAGE_USER_NAME" --arg password "$password" '{name: $name, password: $password}'
      ;;
    hysteria2)
      password="${MANAGE_USER_PASSWORD:-$(generate_hex_secret 16)}"
      jq -nc --arg name "$MANAGE_USER_NAME" --arg password "$password" '{name: $name, password: $password}'
      ;;
    tuic)
      uuid="${MANAGE_USER_UUID:-$(generate_uuid)}"
      password="${MANAGE_USER_PASSWORD:-$(generate_hex_secret 16)}"
      jq -nc --arg name "$MANAGE_USER_NAME" --arg uuid "$uuid" --arg password "$password" '{name: $name, uuid: $uuid, password: $password}'
      ;;
    naive)
      password="${MANAGE_USER_PASSWORD:-$(generate_hex_secret 16)}"
      jq -nc --arg username "$MANAGE_USER_NAME" --arg password "$password" '{username: $username, password: $password}'
      ;;
    socks5)
      password="${MANAGE_USER_PASSWORD:-$(generate_hex_secret 16)}"
      jq -nc --arg username "$MANAGE_USER_NAME" --arg password "$password" '{username: $username, password: $password}'
      ;;
    ss2022)
      password="${MANAGE_USER_PASSWORD:-}"
      if [[ -z "$password" ]]; then
        password="$(generate_ss2022_secret "$SS2022_METHOD")"
      else
        is_valid_base64_of_length "$password" "$(ss2022_key_length "$SS2022_METHOD")" || die "SS2022 user password must be valid base64 with method-matching length"
      fi
      jq -nc --arg name "$MANAGE_USER_NAME" --arg password "$password" '{name: $name, password: $password}'
      ;;
    *)
      die "Unknown protocol in build_managed_user_json: $protocol"
      ;;
  esac
}

list_users_for_protocol() {
  local protocol="$1"
  local users_json=""
  local key=""

  users_json="$(get_users_json_var "$protocol")"
  key="$(protocol_user_key "$protocol")"

  printf '%s\n' "$(protocol_label "$protocol")"
  jq -r --arg key "$key" '
    if length == 0 then
      "  (no users)"
    else
      .[] | "  - " + .[$key]
    end
  ' <<< "$users_json"
}

list_users_command() {
  local protocol=""

  load_runtime_from_state
  if [[ -n "$MANAGE_PROTOCOL" ]]; then
    MANAGE_PROTOCOL="$(normalize_protocol_or_die "$MANAGE_PROTOCOL")"
    list_users_for_protocol "$MANAGE_PROTOCOL"
    return 0
  fi

  for protocol in "${SUPPORTED_PROTOCOL_ORDER[@]}"; do
    protocol_enabled "$protocol" || continue
    list_users_for_protocol "$protocol"
  done
}

add_user_command() {
  local users_json=""
  local new_user_json=""

  require_root
  load_runtime_from_state
  prompt_manage_protocol_if_needed
  ensure_manage_protocol_enabled
  prompt_manage_user_name_if_needed
  users_json="$(get_users_json_var "$MANAGE_PROTOCOL")"

  if user_exists_in_json "$MANAGE_PROTOCOL" "$users_json"; then
    die "User already exists in $MANAGE_PROTOCOL: $MANAGE_USER_NAME"
  fi

  new_user_json="$(build_managed_user_json "$MANAGE_PROTOCOL")"
  users_json="$(jq -c --argjson item "$new_user_json" '. + [$item]' <<< "$users_json")"
  set_users_json_var "$MANAGE_PROTOCOL" "$users_json"
  render_from_current_state
  printf 'Added user %s to %s\n' "$MANAGE_USER_NAME" "$MANAGE_PROTOCOL"
}

remove_user_command() {
  local users_json=""
  local key=""
  local remaining_count=""

  require_root
  load_runtime_from_state
  prompt_manage_protocol_if_needed
  ensure_manage_protocol_enabled
  prompt_manage_user_name_if_needed
  users_json="$(get_users_json_var "$MANAGE_PROTOCOL")"
  key="$(protocol_user_key "$MANAGE_PROTOCOL")"

  user_exists_in_json "$MANAGE_PROTOCOL" "$users_json" || die "User not found in $MANAGE_PROTOCOL: $MANAGE_USER_NAME"
  remaining_count="$(jq -r --arg key "$key" --arg value "$MANAGE_USER_NAME" 'map(select(.[$key] != $value)) | length' <<< "$users_json")"
  ((remaining_count > 0)) || die "Cannot remove the last user from $MANAGE_PROTOCOL"

  users_json="$(jq -c --arg key "$key" --arg value "$MANAGE_USER_NAME" 'map(select(.[$key] != $value))' <<< "$users_json")"
  set_users_json_var "$MANAGE_PROTOCOL" "$users_json"
  render_from_current_state
  printf 'Removed user %s from %s\n' "$MANAGE_USER_NAME" "$MANAGE_PROTOCOL"
}

regenerate_command() {
  require_root
  load_runtime_from_state
  render_from_current_state
  show_saved_artifacts
}

routing_menu_command() {
  local input=""

  require_root
  load_runtime_from_state

  if ! should_prompt_interactively; then
    printf 'Routing: %s\n' "$(routing_status_brief)"
    return 0
  fi

  while true; do
    printf '\n分流管理\n'
    printf '  当前状态: %s\n' "$(routing_status_brief)"
    printf '  1) 切换 BT/PT 限制\n'
    printf '  2) 切换 回国限制\n'
    printf '  3) 切换 广告拦截\n'
    printf '  4) 重建当前服务配置\n'
    printf '  0) 返回主菜单\n'
    printf '请选择操作 [0-4]: '
    read -r input

    case "$input" in
      1)
        if [[ "$ROUTE_BLOCK_BITTORRENT" == "1" ]]; then ROUTE_BLOCK_BITTORRENT="0"; else ROUTE_BLOCK_BITTORRENT="1"; fi
        render_from_current_state
        printf '已更新 BT/PT 限制：%s\n' "$(routing_status_brief)"
        ;;
      2)
        if [[ "$ROUTE_BLOCK_CN" == "1" ]]; then ROUTE_BLOCK_CN="0"; else ROUTE_BLOCK_CN="1"; fi
        render_from_current_state
        printf '已更新 回国限制：%s\n' "$(routing_status_brief)"
        ;;
      3)
        if [[ "$ROUTE_BLOCK_ADS" == "1" ]]; then ROUTE_BLOCK_ADS="0"; else ROUTE_BLOCK_ADS="1"; fi
        render_from_current_state
        printf '已更新 广告拦截：%s\n' "$(routing_status_brief)"
        ;;
      4)
        render_from_current_state
        printf '已按当前分流策略重建服务配置。\n'
        ;;
      0)
        return 0
        ;;
      *)
        warn "无效选项，请重新输入。"
        ;;
    esac
  done
}

client_menu_command() {
  local input=""

  load_runtime_from_state

  if ! should_prompt_interactively; then
    show_saved_artifacts
    return 0
  fi

  while true; do
    printf '\n客户端配置管理\n'
    printf '  1) 查看当前客户端信息\n'
    printf '  2) 重建全部客户端文件\n'
    printf '  3) 查看客户端 outbounds 片段\n'
    printf '  4) 查看完整客户端模板（mixed）\n'
    printf '  5) 查看 TUN 客户端模板\n'
    printf '  0) 返回主菜单\n'
    printf '请选择操作 [0-5]: '
    read -r input

    case "$input" in
      1)
        show_saved_artifacts
        ;;
      2)
        refresh_client_artifacts_from_state
        printf '已重建客户端文件：\n'
        printf '  %s\n' "$CLIENT_SNIPPET_FILE"
        printf '  %s\n' "$CLIENT_FULL_CONFIG_FILE"
        printf '  %s\n' "$CLIENT_TUN_CONFIG_FILE"
        ;;
      3)
        if [[ -f "$CLIENT_SNIPPET_FILE" ]]; then
          cat "$CLIENT_SNIPPET_FILE"
        else
          die "$(cat <<EOF
当前还没有客户端 outbounds 片段。
建议操作：
1. 先执行“2) 重建全部客户端文件”
2. 再回来查看客户端 outbounds 片段
EOF
)"
        fi
        ;;
      4)
        if [[ -f "$CLIENT_FULL_CONFIG_FILE" ]]; then
          cat "$CLIENT_FULL_CONFIG_FILE"
        else
          die "$(cat <<EOF
当前还没有完整客户端模板。
建议操作：
1. 先执行“2) 重建全部客户端文件”
2. 再回来查看完整客户端模板
EOF
)"
        fi
        ;;
      5)
        if [[ -f "$CLIENT_TUN_CONFIG_FILE" ]]; then
          cat "$CLIENT_TUN_CONFIG_FILE"
        else
          die "$(cat <<EOF
当前还没有 TUN 客户端模板。
建议操作：
1. 先执行“2) 重建全部客户端文件”
2. 再回来查看 TUN 客户端模板
EOF
)"
        fi
        ;;
      0)
        return 0
        ;;
      *)
        warn "无效选项，请重新输入。"
        ;;
    esac
  done
}

handle_interactive_command_failure() {
  warn "当前操作未完成，已返回主菜单。"
  print_menu_return_banner
}

validate_existing_config() {
  [[ -f "$TARGET_CONFIG" ]] || die "Config not found: $TARGET_CONFIG"
  command -v sing-box >/dev/null 2>&1 || die "sing-box is not installed"
  sing-box check -c "$TARGET_CONFIG"
}

confirm_uninstall() {
  local input=""

  if [[ "$ASSUME_YES" -eq 1 || ! -t 0 ]]; then
    return 0
  fi

  printf '这会停止服务并删除 %s 下的部署文件，是否继续？[y/N]: ' "$TARGET_DIR" >&2
  read -r input
  case "${input,,}" in
    y|yes)
      return 0
      ;;
    *)
      die "Uninstall cancelled"
      ;;
  esac
}

uninstall_all() {
  require_root
  confirm_uninstall

  systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
  apt-get remove -y sing-box >/dev/null 2>&1 || true
  rm -rf -- "$TARGET_DIR"
  rm -f /etc/apt/sources.list.d/sagernet.sources
  rm -f /etc/apt/keyrings/sagernet.asc
  printf 'Removed sing-box deployment from %s\n' "$TARGET_DIR"
}

handle_non_install_command() {
  case "$COMMAND" in
    list-users)
      list_users_command
      ;;
    add-user)
      add_user_command
      ;;
    remove-user)
      remove_user_command
      ;;
    regenerate)
      regenerate_command
      ;;
    show-info)
      show_saved_artifacts
      ;;
    validate)
      validate_existing_config
      ;;
    status)
      show_service_status
      ;;
    restart)
      require_root
      systemctl restart "$SERVICE_NAME"
      show_service_status
      ;;
    stop)
      require_root
      systemctl stop "$SERVICE_NAME"
      show_service_status
      ;;
    routing-menu)
      routing_menu_command
      ;;
    client-menu)
      client_menu_command
      ;;
    uninstall)
      uninstall_all
      ;;
    *)
      die "Unsupported command handler: $COMMAND"
      ;;
  esac
}

run_install_command() {
  local share_host=""

  require_root
  check_os
  install_dependencies
  load_state
  load_defaults_from_state
  apply_runtime_defaults
  prompt_install_settings
  validate_selection
  install_sing_box
  validate_protocol_version_support
  prepare_dirs
  backup_existing_files
  ensure_certificate
  resolve_ports
  prepare_credentials
  ensure_user_arrays
  sync_primary_credentials_from_users
  download_required_rule_sets
  render_config
  validate_rendered_config
  restart_service

  share_host="$(choose_share_host)"
  write_share_links "$share_host"
  write_client_snippet "$share_host"
  write_client_full_config
  write_state "$share_host"
  write_summary "$share_host"
  print_install_result "$share_host"
}

main() {
  refresh_paths_from_target_config
  parse_args "$@"

  if interactive_menu_mode; then
    while true; do
      reset_menu_iteration_state
      prompt_main_menu
      print_menu_action_banner "$COMMAND"

      if [[ "$COMMAND" == "install" ]]; then
        if ! ( run_install_command ); then
          handle_interactive_command_failure
        else
          print_menu_return_banner
        fi
      else
        if ! ( handle_non_install_command ); then
          handle_interactive_command_failure
        else
          print_menu_return_banner
        fi
      fi
    done
  fi

  prompt_main_menu

  if [[ "$COMMAND" != "install" ]]; then
    handle_non_install_command
    exit 0
  fi

  run_install_command
}

main "$@"
