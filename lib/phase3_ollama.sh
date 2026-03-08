#!/bin/bash
# Phase 3: Ollama Models — Pull qwen2.5:7b and qwen2.5vl:7b

phase3_ollama() {
  ui_phase 3 "Ollama Models"

  # ── Pull qwen2.5:7b (text classification, tagging, RAG chat) ──
  # Note: use grep >/dev/null instead of grep -q to avoid SIGPIPE with pipefail
  if ollama list 2>/dev/null | grep "qwen2.5:7b" >/dev/null; then
    ui_pass "qwen2.5:7b already available"
  else
    ui_info "Pulling qwen2.5:7b (this may take a while)..."
    ui_spin "Downloading qwen2.5:7b" ollama pull qwen2.5:7b
    ui_pass "qwen2.5:7b downloaded"
  fi

  # ── Pull qwen2.5vl:7b (vision model for document OCR) ──
  if ollama list 2>/dev/null | grep "qwen2.5vl:7b" >/dev/null; then
    ui_pass "qwen2.5vl:7b already available"
  else
    ui_info "Pulling qwen2.5vl:7b (vision model for OCR)..."
    ui_spin "Downloading qwen2.5vl:7b" ollama pull qwen2.5vl:7b
    ui_pass "qwen2.5vl:7b downloaded"
  fi

  # ── Test ──
  echo ""
  ui_info "Verifying models..."

  if ollama list 2>/dev/null | grep "qwen2.5:7b" >/dev/null; then
    ui_pass "qwen2.5:7b confirmed"
  else
    ui_fail "qwen2.5:7b not found"
    return 1
  fi

  if ollama list 2>/dev/null | grep "qwen2.5vl:7b" >/dev/null; then
    ui_pass "qwen2.5vl:7b confirmed"
  else
    ui_fail "qwen2.5vl:7b not found"
    return 1
  fi

  ui_pass "Phase 3 complete"
}
