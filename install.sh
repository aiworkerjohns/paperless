#!/bin/bash
# Paperless-ngx + AI Stack Installer Wizard
# Deploys a fully configured Paperless-ngx with AI auto-tagging, vision OCR,
# chat panel, duplicate detection, workflows, and Tailscale remote access.
#
# Usage:
#   ./install.sh              # Run full install (resumes from last completed phase)
#   ./install.sh --phase N    # Run a specific phase (1-8)
#   ./install.sh --reset      # Reset state and start fresh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_DIR="$SCRIPT_DIR"

# Source libraries
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/phase1_prerequisites.sh"
source "$SCRIPT_DIR/lib/phase2_config.sh"
source "$SCRIPT_DIR/lib/phase3_ollama.sh"
source "$SCRIPT_DIR/lib/phase4_docker.sh"
source "$SCRIPT_DIR/lib/phase5_paperless.sh"
source "$SCRIPT_DIR/lib/phase6_defaults.sh"
source "$SCRIPT_DIR/lib/phase7_tailscale.sh"
source "$SCRIPT_DIR/lib/phase8_verify.sh"

# Parse arguments
SINGLE_PHASE=""
DO_RESET=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) SINGLE_PHASE="$2"; shift 2 ;;
    --reset) DO_RESET=true; shift ;;
    --help|-h)
      echo "Usage: ./install.sh [--phase N] [--reset]"
      echo "  --phase N   Run only phase N (1-8)"
      echo "  --reset     Clear state and start from scratch"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if $DO_RESET; then
  rm -f "$STATE_FILE"
  echo "State reset. Run ./install.sh to start fresh."
  exit 0
fi

# Run a single phase with error handling
run_phase() {
  local num="$1"
  local func="$2"
  while true; do
    if $func; then
      set_phase_complete "$num"
      return 0
    else
      if ! handle_phase_error "$num" "Phase $num failed"; then
        continue  # Retry
      else
        return 0  # Skip
      fi
    fi
  done
}

# ── Banner ──
ui_header "Paperless-ngx + AI Stack Installer"

# ── Single phase mode ──
if [ -n "$SINGLE_PHASE" ]; then
  case "$SINGLE_PHASE" in
    1) run_phase 1 phase1_prerequisites ;;
    2) run_phase 2 phase2_config ;;
    3) run_phase 3 phase3_ollama ;;
    4) run_phase 4 phase4_docker ;;
    5) run_phase 5 phase5_paperless ;;
    6) run_phase 6 phase6_defaults ;;
    7) run_phase 7 phase7_tailscale ;;
    8) run_phase 8 phase8_verify ;;
    *) echo "Invalid phase: $SINGLE_PHASE (must be 1-8)"; exit 1 ;;
  esac
  exit 0
fi

# ── Full install (resume from last completed phase) ──
LAST_PHASE=$(get_last_phase)
if [ "$LAST_PHASE" -gt 0 ]; then
  ui_info "Resuming from phase $((LAST_PHASE + 1)) (phases 1-$LAST_PHASE already done)"
fi

for phase_num in 1 2 3 4 5 6 7 8; do
  if [ "$phase_num" -le "$LAST_PHASE" ]; then
    continue
  fi
  case "$phase_num" in
    1) run_phase 1 phase1_prerequisites ;;
    2) run_phase 2 phase2_config ;;
    3) run_phase 3 phase3_ollama ;;
    4) run_phase 4 phase4_docker ;;
    5) run_phase 5 phase5_paperless ;;
    6) run_phase 6 phase6_defaults ;;
    7) run_phase 7 phase7_tailscale ;;
    8) run_phase 8 phase8_verify ;;
  esac
  echo ""
done
