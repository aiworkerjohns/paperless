#!/bin/bash
# Phase 7: Tailscale — Configure Tailscale Serve, update URLs

phase7_tailscale() {
  ui_phase 7 "Tailscale"
  load_config

  # ── Check Tailscale connectivity ──
  if ! command -v tailscale &>/dev/null; then
    ui_warn "Tailscale not installed — skipping Phase 7"
    ui_info "You can run this phase later after installing Tailscale"
    return 0
  fi

  local ts_status
  ts_status=$(tailscale status --json 2>/dev/null)
  if [ -z "$ts_status" ]; then
    ui_warn "Tailscale not connected — skipping Phase 7"
    ui_info "Start Tailscale, log in, then re-run: ./install.sh --phase 7"
    return 0
  fi

  # ── Get hostname ──
  local ts_hostname
  ts_hostname=$(echo "$ts_status" | python3 -c "
import sys, json
data = json.load(sys.stdin)
dns = data.get('MagicDNSSuffix', '')
self_key = data.get('Self', {}).get('HostName', '')
if dns and self_key:
    print(f'{self_key}.{dns}')
else:
    print('')
" 2>/dev/null)

  if [ -z "$ts_hostname" ]; then
    ui_warn "Could not determine Tailscale hostname"
    return 0
  fi

  ui_pass "Tailscale hostname: $ts_hostname"

  # ── Configure Tailscale Serve ──
  ui_info "Setting up Tailscale Serve..."

  # Port 443 → Paperless (8000)
  if ! tailscale serve --bg --https=443 http://localhost:8000 2>/dev/null; then
    if ! tailscale serve --https=443 http://localhost:8000 2>/dev/null; then
      if ! tailscale serve 443 http://localhost:8000 2>/dev/null; then
        ui_warn "Could not set up Tailscale Serve for port 443"
        ui_info "Try manually: tailscale serve --https=443 http://localhost:8000"
      fi
    fi
  fi

  # Port 8443 → paperless-ai (3000)
  if ! tailscale serve --bg --https=8443 http://localhost:3000 2>/dev/null; then
    if ! tailscale serve --https=8443 http://localhost:3000 2>/dev/null; then
      if ! tailscale serve 8443 http://localhost:3000 2>/dev/null; then
        ui_warn "Could not set up Tailscale Serve for port 8443"
      fi
    fi
  fi

  # Verify
  if tailscale serve status 2>/dev/null | grep -q "443"; then
    ui_pass "Tailscale Serve configured"
  else
    ui_warn "Tailscale Serve may not be configured — check: tailscale serve status"
  fi

  # ── Update Paperless URL ──
  local paperless_url="https://${ts_hostname}"
  save_config "PAPERLESS_URL" "$paperless_url"
  save_config "CSRF_ORIGINS" "$paperless_url"

  sed -i '' "s|^PAPERLESS_URL=.*|PAPERLESS_URL=${paperless_url}|" "$INSTALL_DIR/paperless.env"
  sed -i '' "s|^PAPERLESS_CSRF_TRUSTED_ORIGINS=.*|PAPERLESS_CSRF_TRUSTED_ORIGINS=${paperless_url}|" "$INSTALL_DIR/paperless.env"

  ui_pass "Updated PAPERLESS_URL to $paperless_url"

  # ── Update Google SSO redirect URI hint ──
  if [ -n "${GOOGLE_CLIENT_ID:-}" ]; then
    ui_info "Google SSO redirect URI: ${paperless_url}/accounts/google/login/callback/"
  fi

  # ── Restart Paperless to pick up URL change ──
  ui_info "Restarting Paperless..."
  export COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
  $DC restart paperless
  sleep 5

  # ── Test ──
  echo ""
  ui_info "Verifying Tailscale setup..."

  if tailscale serve status 2>/dev/null | grep "443" >/dev/null; then
    ui_pass "Tailscale Serve active on port 443"
  else
    ui_warn "Tailscale Serve status could not be verified"
  fi

  ui_pass "Phase 7 complete"
}
