#!/bin/bash
# Phase 2: Configuration — Collect admin credentials, timezone, OAuth, generate secrets

phase2_config() {
  ui_phase 2 "Configuration"

  # Initialize config file
  touch "$CONFIG_FILE"

  # ── Admin credentials ──
  ui_info "Admin account setup"
  local admin_user
  admin_user=$(ui_input "Admin username" "admin")
  save_config "ADMIN_USER" "$admin_user"

  local admin_pass
  admin_pass=$(ui_password "Admin password")
  if [ -z "$admin_pass" ]; then
    admin_pass=$(openssl rand -base64 18)
    ui_info "Generated random password: $admin_pass"
  fi
  save_config "ADMIN_PASS" "$admin_pass"

  # ── Timezone ──
  local detected_tz
  detected_tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || echo "UTC")
  if ui_confirm "Use detected timezone: $detected_tz?"; then
    save_config "TIMEZONE" "$detected_tz"
  else
    local tz
    tz=$(ui_input "Enter timezone (e.g. America/New_York)" "$detected_tz")
    save_config "TIMEZONE" "$tz"
  fi

  # ── Google OAuth (optional) ──
  local google_sso_apps=""
  local google_sso_providers=""
  if ui_confirm "Configure Google SSO login?"; then
    ui_info "Create OAuth credentials at https://console.cloud.google.com/apis/credentials"
    local client_id
    client_id=$(ui_input "Google OAuth Client ID")
    local client_secret
    client_secret=$(ui_input "Google OAuth Client Secret")

    if [ -n "$client_id" ] && [ -n "$client_secret" ]; then
      google_sso_apps="allauth.socialaccount.providers.google"
      google_sso_providers="{\"google\": {\"APPS\": [{\"client_id\": \"${client_id}\", \"secret\": \"${client_secret}\", \"key\": \"\"}], \"SCOPE\": [\"profile\", \"email\"], \"AUTH_PARAMS\": {\"access_type\": \"online\"}}}"
      save_config "GOOGLE_CLIENT_ID" "$client_id"
      save_config "GOOGLE_CLIENT_SECRET" "$client_secret"
      ui_pass "Google SSO configured"
    fi
  fi
  save_config "GOOGLE_SSO_APPS" "$google_sso_apps"
  save_config "GOOGLE_SSO_PROVIDERS" "$google_sso_providers"

  # ── Generate secrets ──
  ui_info "Generating secrets..."
  local secret_key
  secret_key=$(openssl rand -hex 32)
  save_config "SECRET_KEY" "$secret_key"

  local db_pass
  db_pass=$(openssl rand -hex 16)
  save_config "DB_PASS" "$db_pass"

  local ai_api_key
  ai_api_key=$(openssl rand -hex 32)
  save_config "AI_API_KEY" "$ai_api_key"

  ui_pass "Secrets generated"

  # ── Set initial URL (updated in Phase 7 if Tailscale available) ──
  save_config "PAPERLESS_URL" "http://localhost:8000"
  save_config "CSRF_ORIGINS" "http://localhost:8000"

  # ── Test ──
  echo ""
  ui_info "Verifying configuration..."
  load_config

  local required_vars=("ADMIN_USER" "ADMIN_PASS" "TIMEZONE" "SECRET_KEY" "DB_PASS" "AI_API_KEY")
  local missing=0
  for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
      ui_fail "Missing config: $var"
      missing=1
    fi
  done

  if [ "$missing" -eq 1 ]; then
    return 1
  fi

  ui_pass "All required config values present"
  ui_pass "Phase 2 complete"
}
