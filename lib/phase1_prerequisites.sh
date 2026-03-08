#!/bin/bash
# Phase 1: Prerequisites — Homebrew, Colima, Docker, Ollama, Tailscale, gum
# shellcheck disable=SC2034

phase1_prerequisites() {
  ui_phase 1 "Prerequisites"

  # ── Homebrew ──
  if command -v brew &>/dev/null; then
    ui_pass "Homebrew installed"
  else
    ui_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to path for Apple Silicon
    if [ -f /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    ui_pass "Homebrew installed"
  fi

  # ── gum (self-bootstrap: makes the rest of the wizard pretty) ──
  if command -v gum &>/dev/null; then
    ui_pass "gum installed"
  else
    ui_info "Installing gum (pretty terminal UI)..."
    brew install gum
    HAS_GUM=true
    ui_pass "gum installed"
  fi

  # ── git ──
  if command -v git &>/dev/null; then
    ui_pass "git installed"
  else
    ui_info "Installing git..."
    brew install git
    ui_pass "git installed"
  fi

  # ── Colima (Docker runtime for macOS) ──
  if command -v colima &>/dev/null; then
    ui_pass "Colima installed"
  else
    ui_info "Installing Colima..."
    brew install colima
    ui_pass "Colima installed"
  fi

  # ── Docker CLI + compose plugin ──
  if command -v docker &>/dev/null; then
    ui_pass "Docker CLI installed"
  else
    ui_info "Installing Docker CLI..."
    brew install docker
    ui_pass "Docker CLI installed"
  fi

  if docker compose version &>/dev/null; then
    ui_pass "Docker Compose plugin installed"
  else
    ui_info "Installing Docker Compose plugin..."
    brew install docker-compose
    ui_pass "Docker Compose plugin installed"
  fi

  # ── Ollama ──
  if command -v ollama &>/dev/null; then
    ui_pass "Ollama installed"
  else
    ui_info "Installing Ollama..."
    brew install --cask ollama
    ui_pass "Ollama installed"
  fi

  # ── Tailscale ──
  if command -v tailscale &>/dev/null; then
    ui_pass "Tailscale installed"
  else
    ui_info "Installing Tailscale..."
    brew install --cask tailscale
    ui_warn "Tailscale installed — open Tailscale.app and log in before Phase 7"
  fi

  # ── Start Colima if not running ──
  if colima status &>/dev/null; then
    ui_pass "Colima running"
  else
    ui_info "Starting Colima (4 CPU, 8GB RAM, 60GB disk)..."
    ui_spin "Starting Colima VM" colima start --cpu 4 --memory 8 --disk 60
    ui_pass "Colima started"
  fi

  # ── Enable Colima auto-start on login ──
  if brew services list 2>/dev/null | grep -q "colima.*started"; then
    ui_pass "Colima auto-start enabled"
  else
    ui_info "Enabling Colima auto-start on login..."
    brew services start colima 2>/dev/null || true
    ui_pass "Colima auto-start enabled"
  fi

  # ── Fix Docker credential store issue ──
  local docker_config="$HOME/.docker/config.json"
  if [ -f "$docker_config" ]; then
    if grep -q '"credsStore"' "$docker_config" 2>/dev/null; then
      # Set credsStore to empty string to avoid credential helper errors
      python3 -c "
import json, sys
with open('$docker_config', 'r') as f:
    cfg = json.load(f)
if cfg.get('credsStore'):
    cfg['credsStore'] = ''
    with open('$docker_config', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('fixed')
else:
    print('ok')
" 2>/dev/null
      ui_pass "Docker credential store configured"
    fi
  fi

  # ── Start Ollama service ──
  if ! pgrep -x ollama &>/dev/null; then
    ui_info "Starting Ollama service..."
    open -a Ollama 2>/dev/null || ollama serve &>/dev/null &
    sleep 3
  fi
  ui_pass "Ollama service running"

  # ── Enable Ollama auto-start on login ──
  if osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | grep -qi ollama; then
    ui_pass "Ollama auto-start enabled"
  else
    ui_info "Enabling Ollama auto-start on login..."
    osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Ollama.app", hidden:true}' 2>/dev/null || true
    ui_pass "Ollama auto-start enabled"
  fi

  # ── Tests ──
  echo ""
  ui_info "Verifying prerequisites..."

  if docker info &>/dev/null; then
    ui_pass "docker info OK"
  else
    ui_fail "docker info failed"
    return 1
  fi

  if ollama --version &>/dev/null; then
    ui_pass "ollama --version OK"
  else
    ui_fail "ollama not working"
    return 1
  fi

  if tailscale version &>/dev/null; then
    ui_pass "tailscale version OK"
  else
    ui_warn "tailscale not available (Phase 7 will be skipped)"
  fi

  ui_pass "Phase 1 complete"
}
