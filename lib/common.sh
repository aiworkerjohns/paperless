#!/bin/bash
# common.sh — UI wrappers (gum + fallback), secrets, templates, API helpers, state management

set -euo pipefail

# ── Directories ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$SCRIPT_DIR}"
PAPERLESS_STATE_DIR="$HOME/.paperless-install"
mkdir -p "$PAPERLESS_STATE_DIR"
CONFIG_FILE="$PAPERLESS_STATE_DIR/.install-config"
STATE_FILE="$PAPERLESS_STATE_DIR/.install-state"

# ── Detect gum ──
HAS_GUM=false
if command -v gum &>/dev/null; then
  HAS_GUM=true
fi

# ── Detect docker compose command ──
# Sets DC as the compose command array to use everywhere
if docker compose version &>/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose &>/dev/null; then
  DC="docker-compose"
else
  DC=""
fi

# ── Colors (fallback when no gum) ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── UI Wrappers ──

ui_header() {
  local text="$1"
  if $HAS_GUM; then
    gum style --border double --padding "0 2" --border-foreground 212 "$text"
  else
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║  $text${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}"
    echo ""
  fi
}

ui_phase() {
  local num="$1"
  local title="$2"
  if $HAS_GUM; then
    gum style --foreground 212 --bold "Phase $num: $title"
  else
    echo ""
    echo -e "${BOLD}${BLUE}━━━ Phase $num: $title ━━━${RESET}"
  fi
}

ui_pass() {
  local msg="$1"
  if $HAS_GUM; then
    gum style --foreground 46 "  ✓ $msg"
  else
    echo -e "  ${GREEN}✓${RESET} $msg"
  fi
}

ui_fail() {
  local msg="$1"
  if $HAS_GUM; then
    gum style --foreground 196 "  ✗ $msg"
  else
    echo -e "  ${RED}✗${RESET} $msg"
  fi
}

ui_warn() {
  local msg="$1"
  if $HAS_GUM; then
    gum style --foreground 214 "  ⚠ $msg"
  else
    echo -e "  ${YELLOW}⚠${RESET} $msg"
  fi
}

ui_info() {
  local msg="$1"
  if $HAS_GUM; then
    gum style --foreground 39 "  → $msg"
  else
    echo -e "  ${CYAN}→${RESET} $msg"
  fi
}

ui_input() {
  local prompt="$1"
  local default="${2:-}"
  if $HAS_GUM; then
    if [ -n "$default" ]; then
      gum input --placeholder "$prompt" --value "$default"
    else
      gum input --placeholder "$prompt"
    fi
  else
    local reply
    if [ -n "$default" ]; then
      read -rp "  $prompt [$default]: " reply
      echo "${reply:-$default}"
    else
      read -rp "  $prompt: " reply
      echo "$reply"
    fi
  fi
}

ui_password() {
  local prompt="$1"
  if $HAS_GUM; then
    gum input --password --placeholder "$prompt"
  else
    local reply
    read -rsp "  $prompt: " reply
    echo ""  # newline after hidden input
    echo "$reply"
  fi
}

ui_confirm() {
  local prompt="$1"
  if $HAS_GUM; then
    gum confirm "$prompt"
  else
    local reply
    read -rp "  $prompt [y/N]: " reply
    [[ "$reply" =~ ^[Yy] ]]
  fi
}

ui_choose() {
  local prompt="$1"
  shift
  if $HAS_GUM; then
    gum choose --header "$prompt" "$@"
  else
    echo "  $prompt"
    local i=1
    for opt in "$@"; do
      echo "    $i) $opt"
      ((i++))
    done
    local reply
    read -rp "  Choice [1]: " reply
    reply="${reply:-1}"
    local j=1
    for opt in "$@"; do
      if [ "$j" = "$reply" ]; then
        echo "$opt"
        return
      fi
      ((j++))
    done
    echo "$1"  # default to first
  fi
}

ui_spin() {
  local title="$1"
  shift
  if $HAS_GUM; then
    gum spin --spinner dot --title "$title" -- "$@"
  else
    echo -e "  ${CYAN}⏳${RESET} $title ..."
    "$@"
  fi
}

# ── Template Engine ──

render_template() {
  local src="$1"
  local dst="$2"
  # Start with template content
  cp "$src" "$dst"
  # Replace all __PLACEHOLDER__ values from config
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi
  local placeholders
  placeholders=$(grep -oE '__[A-Z_]+__' "$dst" 2>/dev/null | sort -u || true)
  for ph in $placeholders; do
    local var_name
    var_name=$(echo "$ph" | sed 's/^__//; s/__$//')
    local var_value="${!var_name:-}"
    if [ -n "$var_value" ]; then
      # Escape sed special characters in the value
      local escaped_value
      escaped_value=$(printf '%s\n' "$var_value" | sed 's/[&/\]/\\&/g')
      sed -i '' "s|${ph}|${escaped_value}|g" "$dst"
    fi
  done
}

render_all_templates() {
  for tmpl in "$INSTALL_DIR/templates/"*.tmpl; do
    local basename
    basename=$(basename "$tmpl" .tmpl)
    render_template "$tmpl" "$INSTALL_DIR/$basename"
  done
}

# ── Config helpers ──

save_config() {
  local key="$1"
  local value="$2"
  # Remove existing entry if present
  if [ -f "$CONFIG_FILE" ] && grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
    grep -v "^${key}=" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  fi
  # Escape single quotes in value, then write single-quoted to prevent bash interpretation
  local escaped_value="${value//\'/\'\\\'\'}"
  printf "%s='%s'\n" "$key" "$escaped_value" >> "$CONFIG_FILE"
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi
}

# ── State management ──

get_last_phase() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    echo "0"
  fi
}

set_phase_complete() {
  echo "$1" > "$STATE_FILE"
}

# ── API helpers ──

paperless_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local url="http://localhost:8000/api${endpoint}"
  load_config
  local token="${PAPERLESS_TOKEN:-}"
  if [ -z "$token" ]; then
    ui_fail "No Paperless API token available"
    return 1
  fi
  if [ -n "$data" ]; then
    curl -s -w "\n%{http_code}" -X "$method" "$url" \
      -H "Authorization: Token $token" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    curl -s -w "\n%{http_code}" -X "$method" "$url" \
      -H "Authorization: Token $token"
  fi
}

api_post() {
  local endpoint="$1"
  local data="$2"
  local result
  result=$(paperless_api POST "$endpoint" "$data")
  local code
  code=$(echo "$result" | tail -1)
  local body
  body=$(echo "$result" | sed '$d')
  if [ "$code" = "201" ] || [ "$code" = "200" ]; then
    local name
    name=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name','ok'))" 2>/dev/null || echo "ok")
    ui_pass "$name"
    return 0
  else
    local item_name
    item_name=$(echo "$data" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || echo "")
    ui_warn "Skipped (may exist): $item_name"
    return 0
  fi
}

# ── Phase error handling ──

handle_phase_error() {
  local phase="$1"
  local msg="$2"
  ui_fail "$msg"
  local choice
  choice=$(ui_choose "Phase $phase failed. What to do?" "Retry" "Skip" "Abort")
  case "$choice" in
    Retry) return 1 ;;   # caller should re-run
    Skip)  return 0 ;;   # caller should continue
    Abort) echo "Aborted."; exit 1 ;;
  esac
}

# ── Wait helpers ──

wait_for_url() {
  local url="$1"
  local timeout="${2:-120}"
  local elapsed=0
  while [ $elapsed -lt "$timeout" ]; do
    if curl -sf -o /dev/null "$url" 2>/dev/null; then
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  return 1
}

wait_for_container() {
  local name="$1"
  local timeout="${2:-60}"
  local elapsed=0
  while [ $elapsed -lt "$timeout" ]; do
    local status
    status=$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || echo "unknown")
    if [ "$status" = "healthy" ]; then
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  return 1
}
