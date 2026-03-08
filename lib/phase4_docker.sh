#!/bin/bash
# Phase 4: Docker Stack — Render templates, pull images, compose up, health checks

phase4_docker() {
  ui_phase 4 "Docker Stack"
  load_config

  # ── Render templates ──
  ui_info "Rendering configuration templates..."
  render_all_templates
  ui_pass "Templates rendered"

  # ── Copy static files ──
  ui_info "Copying static files..."
  cp "$INSTALL_DIR/static/inject-overrides.sh" "$INSTALL_DIR/inject-overrides.sh"
  cp "$INSTALL_DIR/static/patch-paperless-ai.sh" "$INSTALL_DIR/patch-paperless-ai.sh"
  cp "$INSTALL_DIR/static/duplicate-sweep.py" "$INSTALL_DIR/duplicate-sweep.py"
  cp "$INSTALL_DIR/static/rag-patch.py" "$INSTALL_DIR/rag-patch.py"
  cp "$INSTALL_DIR/static/reset-ai-metadata.py" "$INSTALL_DIR/reset-ai-metadata.py"
  chmod +x "$INSTALL_DIR/inject-overrides.sh" "$INSTALL_DIR/patch-paperless-ai.sh"
  ui_pass "Static files copied"

  # ── Render overrides.js from template ──
  ui_info "Rendering overrides.js..."
  render_template "$INSTALL_DIR/static/overrides.js.tmpl" "$INSTALL_DIR/overrides.js"
  ui_pass "overrides.js rendered"

  # ── Create directories ──
  mkdir -p "$INSTALL_DIR/consume" "$INSTALL_DIR/export"
  ui_pass "consume/ and export/ directories created"

  # ── Docker compose pull ──
  ui_info "Pulling Docker images (this may take a while)..."
  ui_spin "Pulling Docker images" (cd "$INSTALL_DIR" && docker compose pull)
  ui_pass "Docker images pulled"

  # ── Docker compose up ──
  ui_info "Starting containers..."
  (cd "$INSTALL_DIR" && docker compose up -d)
  ui_pass "Containers started"

  # ── Health checks ──
  echo ""
  ui_info "Waiting for services to be healthy..."

  ui_info "Waiting for PostgreSQL..."
  if wait_for_container "paperless-db" 60; then
    ui_pass "PostgreSQL healthy"
  else
    ui_fail "PostgreSQL did not become healthy"
    return 1
  fi

  ui_info "Waiting for Redis..."
  if wait_for_container "paperless-redis" 60; then
    ui_pass "Redis healthy"
  else
    ui_fail "Redis did not become healthy"
    return 1
  fi

  # ── Test: wait for Paperless HTTP ──
  ui_info "Waiting for Paperless-ngx (up to 120s)..."
  if wait_for_url "http://localhost:8000" 120; then
    ui_pass "Paperless-ngx responding on port 8000"
  else
    ui_fail "Paperless-ngx did not respond within 120s"
    return 1
  fi

  ui_pass "Phase 4 complete"
}
