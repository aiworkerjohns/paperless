#!/bin/bash
# Phase 8: Final Verification — Full stack health check, RAG test, summary

phase8_verify() {
  ui_phase 8 "Final Verification"
  load_config

  local all_ok=true

  # ── Container status ──
  ui_info "Checking containers..."
  local containers=("paperless" "paperless-db" "paperless-redis" "paperless-gotenberg" "paperless-tika" "paperless-ai" "paperless-gpt" "open-webui" "paperless-cron" "dozzle")
  for cname in "${containers[@]}"; do
    local state
    state=$(docker inspect -f '{{.State.Status}}' "$cname" 2>/dev/null || echo "missing")
    if [ "$state" = "running" ]; then
      ui_pass "$cname: running"
    else
      ui_fail "$cname: $state"
      all_ok=false
    fi
  done

  # ── Paperless API ──
  echo ""
  ui_info "Checking Paperless API..."
  local token="${PAPERLESS_TOKEN:-}"
  if [ -n "$token" ]; then
    local api_code
    api_code=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Token $token" "http://localhost:8000/api/")
    if [ "$api_code" = "200" ]; then
      ui_pass "Paperless API: OK (HTTP 200)"
    else
      ui_fail "Paperless API: HTTP $api_code"
      all_ok=false
    fi
  else
    ui_fail "No API token available"
    all_ok=false
  fi

  # ── paperless-ai RAG ──
  echo ""
  ui_info "Checking paperless-ai RAG service (up to 90s for ML models)..."
  local rag_ready=false
  local elapsed=0
  while [ $elapsed -lt 90 ]; do
    local rag_code
    rag_code=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "x-api-key: ${AI_API_KEY:-}" "http://localhost:3000/api/rag/index/status")
    if [ "$rag_code" = "200" ]; then
      rag_ready=true
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  if $rag_ready; then
    ui_pass "paperless-ai RAG service: OK"
  else
    ui_warn "paperless-ai RAG not ready yet (may need more time for model loading)"
  fi

  # ── Summary ──
  echo ""
  echo ""

  local paperless_url="${PAPERLESS_URL:-http://localhost:8000}"

  if $HAS_GUM; then
    gum style --border double --padding "1 2" --border-foreground 46 \
      "Installation Complete!" \
      "" \
      "Services:" \
      "  Paperless-ngx:  $paperless_url" \
      "  paperless-ai:   http://localhost:3000" \
      "  Open WebUI:     http://localhost:3001" \
      "  paperless-gpt:  http://localhost:3002" \
      "  Dozzle (logs):  http://localhost:8080" \
      "" \
      "Credentials:" \
      "  Admin user:     ${ADMIN_USER:-admin}" \
      "  Admin password: ${ADMIN_PASS:-<see .install-config>}" \
      "" \
      "Tips:" \
      "  - Edit AI prompts via paperless-ai UI (port 3000)" \
      "  - Workflows manage auto-tagging rules" \
      "  - Drop files in ./consume/ for auto-import" \
      "  - View logs at http://localhost:8080"
  else
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║         Installation Complete!                ║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
    echo "  Services:"
    echo "    Paperless-ngx:  $paperless_url"
    echo "    paperless-ai:   http://localhost:3000"
    echo "    Open WebUI:     http://localhost:3001"
    echo "    paperless-gpt:  http://localhost:3002"
    echo "    Dozzle (logs):  http://localhost:8080"
    echo ""
    echo "  Credentials:"
    echo "    Admin user:     ${ADMIN_USER:-admin}"
    echo "    Admin password: ${ADMIN_PASS:-<see .install-config>}"
    echo ""
    echo "  Tips:"
    echo "    - Edit AI prompts via paperless-ai UI (port 3000)"
    echo "    - Workflows manage auto-tagging rules"
    echo "    - Drop files in ./consume/ for auto-import"
    echo "    - View logs at http://localhost:8080"
  fi

  if $all_ok; then
    ui_pass "All checks passed"
  else
    ui_warn "Some checks failed — review output above"
  fi
}
