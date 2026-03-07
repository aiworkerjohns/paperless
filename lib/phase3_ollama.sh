#!/bin/bash
# Phase 3: Ollama Models — Pull llama3.1:8b and minicpm-v

phase3_ollama() {
  ui_phase 3 "Ollama Models"

  # ── Pull llama3.1:8b ──
  # Note: use grep >/dev/null instead of grep -q to avoid SIGPIPE with pipefail
  if ollama list 2>/dev/null | grep "llama3.1:8b" >/dev/null; then
    ui_pass "llama3.1:8b already available"
  else
    ui_info "Pulling llama3.1:8b (this may take a while)..."
    ui_spin "Downloading llama3.1:8b" ollama pull llama3.1:8b
    ui_pass "llama3.1:8b downloaded"
  fi

  # ── Pull minicpm-v ──
  if ollama list 2>/dev/null | grep "minicpm-v" >/dev/null; then
    ui_pass "minicpm-v already available"
  else
    ui_info "Pulling minicpm-v (vision model for OCR)..."
    ui_spin "Downloading minicpm-v" ollama pull minicpm-v
    ui_pass "minicpm-v downloaded"
  fi

  # ── Test ──
  echo ""
  ui_info "Verifying models..."

  if ollama list 2>/dev/null | grep "llama3.1:8b" >/dev/null; then
    ui_pass "llama3.1:8b confirmed"
  else
    ui_fail "llama3.1:8b not found"
    return 1
  fi

  if ollama list 2>/dev/null | grep "minicpm-v" >/dev/null; then
    ui_pass "minicpm-v confirmed"
  else
    ui_fail "minicpm-v not found"
    return 1
  fi

  ui_pass "Phase 3 complete"
}
