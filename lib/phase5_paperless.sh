#!/bin/bash
# Phase 5: Paperless Setup — Generate API token, update AI service configs, restart

phase5_paperless() {
  ui_phase 5 "Paperless Setup"
  load_config

  # ── Wait for Paperless to be fully ready ──
  ui_info "Waiting for Paperless to be fully ready..."
  if wait_for_url "http://localhost:8000/accounts/login/" 120; then
    ui_pass "Paperless login page is up"
  else
    ui_fail "Paperless login page did not load"
    return 1
  fi

  # ── Generate API token ──
  ui_info "Generating API token via manage.py..."
  local admin_user="${ADMIN_USER:-admin}"
  local token
  token=$(docker exec paperless python3 manage.py shell -c "
from rest_framework.authtoken.models import Token
from django.contrib.auth.models import User
u = User.objects.get(username='${admin_user}')
t, _ = Token.objects.get_or_create(user=u)
print(t.key)
" 2>/dev/null)

  if [ -z "$token" ]; then
    ui_fail "Failed to generate API token"
    return 1
  fi

  save_config "PAPERLESS_TOKEN" "$token"
  ui_pass "API token generated: ${token:0:8}..."

  # ── Update env files with real token ──
  ui_info "Updating service configurations with API token..."

  # paperless-ai.env
  sed -i '' "s|PAPERLESS_API_TOKEN=.*|PAPERLESS_API_TOKEN=${token}|" "$INSTALL_DIR/paperless-ai.env"

  # paperless-gpt.env
  sed -i '' "s|PAPERLESS_API_TOKEN=.*|PAPERLESS_API_TOKEN=${token}|" "$INSTALL_DIR/paperless-gpt.env"

  # docker-compose.yml (cron env)
  sed -i '' "s|PAPERLESS_TOKEN: __PAPERLESS_TOKEN__|PAPERLESS_TOKEN: ${token}|" "$INSTALL_DIR/docker-compose.yml"

  ui_pass "Service configs updated"

  # ── Re-render overrides.js with both tokens ──
  ui_info "Updating overrides.js with tokens..."
  render_template "$INSTALL_DIR/static/overrides.js.tmpl" "$INSTALL_DIR/overrides.js"
  # Also substitute the Paperless token directly (may not be a __PLACEHOLDER__)
  sed -i '' "s|__PAPERLESS_TOKEN__|${token}|g" "$INSTALL_DIR/overrides.js"
  ui_pass "overrides.js updated"

  # ── Restart services to pick up new config ──
  ui_info "Restarting services..."
  docker compose -f "$INSTALL_DIR/docker-compose.yml" restart paperless-ai paperless-gpt paperless cron
  ui_pass "Services restarted"

  # ── Wait for services to come back ──
  sleep 5
  if wait_for_url "http://localhost:8000" 60; then
    ui_pass "Paperless back up"
  fi

  # ── Test: API with token ──
  echo ""
  ui_info "Verifying API access..."
  local api_result
  api_result=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Token $token" \
    "http://localhost:8000/api/")

  if [ "$api_result" = "200" ]; then
    ui_pass "API token verified (HTTP 200)"
  else
    ui_fail "API token check returned HTTP $api_result"
    return 1
  fi

  ui_pass "Phase 5 complete"
}
