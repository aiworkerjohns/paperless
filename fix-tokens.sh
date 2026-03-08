#!/bin/bash
# fix-tokens.sh — Diagnose and fix API tokens across all services
#
# Usage: ./fix-tokens.sh

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

ui_header "Token Diagnostic & Fix"

# ── Step 1: Get the real token from Paperless ──
ui_info "Getting token from Paperless..."

raw=$(docker exec paperless python3 manage.py shell -c "
from rest_framework.authtoken.models import Token
from django.contrib.auth.models import User
u = User.objects.filter(is_superuser=True).first()
if u is None:
    print('ERROR:No superuser found')
else:
    t, _ = Token.objects.get_or_create(user=u)
    print('TOKEN:' + t.key)
    print('USER:' + u.username)
" 2>/dev/null)

token=$(echo "$raw" | grep '^TOKEN:' | sed 's/^TOKEN://' | tr -d '[:space:]')
token_user=$(echo "$raw" | grep '^USER:' | sed 's/^USER://' | tr -d '[:space:]')

if [ -z "$token" ] || [ ${#token} -ne 40 ]; then
  ui_fail "Could not get token from Paperless"
  ui_info "Is Paperless running? Check: docker ps | grep paperless"
  exit 1
fi

ui_pass "Paperless token: ${token:0:8}...${token:32} (user: $token_user)"

# ── Step 2: Check all token locations ──
echo ""
ui_info "Checking token in all services..."

issues=0

# paperless.env
env_token=$(grep '^PAPERLESS_TOKEN=' "$INSTALL_DIR/paperless.env" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || echo "")
if [ "$env_token" = "$token" ]; then
  ui_pass "paperless.env — correct"
else
  ui_warn "paperless.env — wrong (${env_token:0:8}...)"
  ((issues++)) || true
fi

# paperless-ai.env
ai_env_token=$(grep '^PAPERLESS_API_TOKEN=' "$INSTALL_DIR/paperless-ai.env" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || echo "")
if [ "$ai_env_token" = "$token" ]; then
  ui_pass "paperless-ai.env — correct"
else
  ui_warn "paperless-ai.env — wrong (${ai_env_token:0:8}...)"
  ((issues++)) || true
fi

# paperless-ai internal data
ai_data_token=$(docker exec paperless-ai cat /app/data/.env 2>/dev/null | grep '^PAPERLESS_API_TOKEN=' | cut -d= -f2 | tr -d '[:space:]' || echo "")
if [ -n "$ai_data_token" ]; then
  if [ "$ai_data_token" = "$token" ]; then
    ui_pass "paperless-ai /app/data/.env — correct"
  else
    ui_warn "paperless-ai /app/data/.env — wrong (${ai_data_token:0:8}...)"
    ((issues++)) || true
  fi
else
  ui_info "paperless-ai /app/data/.env — not set (will use env file)"
fi

# paperless-gpt.env
gpt_env_token=$(grep '^PAPERLESS_API_TOKEN=' "$INSTALL_DIR/paperless-gpt.env" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || echo "")
if [ "$gpt_env_token" = "$token" ]; then
  ui_pass "paperless-gpt.env — correct"
else
  ui_warn "paperless-gpt.env — wrong (${gpt_env_token:0:8}...)"
  ((issues++)) || true
fi

# docker-compose.yml cron token
cron_token=$(grep 'PAPERLESS_TOKEN:' "$INSTALL_DIR/docker-compose.yml" 2>/dev/null | head -1 | sed 's/.*PAPERLESS_TOKEN: *//' | tr -d '[:space:]' || echo "")
if [ -n "$cron_token" ]; then
  if [ "$cron_token" = "$token" ]; then
    ui_pass "docker-compose.yml cron — correct"
  else
    ui_warn "docker-compose.yml cron — wrong (${cron_token:0:8}...)"
    ((issues++)) || true
  fi
fi

# ── Step 3: Test API access ──
echo ""
ui_info "Testing API access..."
api_result=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Token $token" http://localhost:8000/api/ 2>/dev/null || echo "000")
if [ "$api_result" = "200" ]; then
  ui_pass "API access OK (HTTP $api_result)"
else
  ui_fail "API access failed (HTTP $api_result)"
  ((issues++)) || true
fi

# ── Step 4: Fix if needed ──
if [ "$issues" -gt 0 ]; then
  echo ""
  ui_info "Fixing $issues issue(s)..."

  # Fix paperless.env
  if grep -q '^PAPERLESS_TOKEN=' "$INSTALL_DIR/paperless.env" 2>/dev/null; then
    sed -i '' "s|^PAPERLESS_TOKEN=.*|PAPERLESS_TOKEN=$token|" "$INSTALL_DIR/paperless.env"
  else
    echo "PAPERLESS_TOKEN=$token" >> "$INSTALL_DIR/paperless.env"
  fi
  ui_pass "Fixed paperless.env"

  # Fix paperless-ai.env
  if grep -q '^PAPERLESS_API_TOKEN=' "$INSTALL_DIR/paperless-ai.env" 2>/dev/null; then
    sed -i '' "s|^PAPERLESS_API_TOKEN=.*|PAPERLESS_API_TOKEN=$token|" "$INSTALL_DIR/paperless-ai.env"
  else
    echo "PAPERLESS_API_TOKEN=$token" >> "$INSTALL_DIR/paperless-ai.env"
  fi
  ui_pass "Fixed paperless-ai.env"

  # Fix paperless-ai internal data
  if docker exec paperless-ai test -f /app/data/.env 2>/dev/null; then
    docker exec paperless-ai sed -i "s|^PAPERLESS_API_TOKEN=.*|PAPERLESS_API_TOKEN=$token|" /app/data/.env 2>/dev/null
    ui_pass "Fixed paperless-ai /app/data/.env"
  fi

  # Fix paperless-gpt.env
  if grep -q '^PAPERLESS_API_TOKEN=' "$INSTALL_DIR/paperless-gpt.env" 2>/dev/null; then
    sed -i '' "s|^PAPERLESS_API_TOKEN=.*|PAPERLESS_API_TOKEN=$token|" "$INSTALL_DIR/paperless-gpt.env"
  else
    echo "PAPERLESS_API_TOKEN=$token" >> "$INSTALL_DIR/paperless-gpt.env"
  fi
  ui_pass "Fixed paperless-gpt.env"

  # Save to install config
  save_config "PAPERLESS_TOKEN" "$token"
  ui_pass "Saved token to install config"

  # Restart affected services
  echo ""
  ui_info "Restarting services..."
  export COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
  $DC restart paperless-ai paperless-gpt cron 2>/dev/null || true
  sleep 5

  # Re-test
  ui_info "Re-testing paperless-ai..."
  sleep 10
  ai_log=$(docker logs paperless-ai --tail 5 2>/dev/null)
  if echo "$ai_log" | grep -qi "401\|unauthorized\|error"; then
    ui_warn "paperless-ai may still have issues — check: docker logs paperless-ai --tail 20"
  else
    ui_pass "paperless-ai looks good"
  fi
else
  echo ""
  ui_pass "All tokens correct — no fixes needed"
fi

echo ""
ui_pass "Token diagnostic complete"
