#!/bin/bash
# Phase 6: Default Data — Document types, tags, custom fields, storage path, workflows

phase6_defaults() {
  ui_phase 6 "Default Data"
  load_config

  local token="${PAPERLESS_TOKEN:-}"
  if [ -z "$token" ]; then
    ui_fail "No API token — run Phase 5 first"
    return 1
  fi

  # ── Document Types (16) ──
  ui_info "Creating document types..."
  for dtype in "Invoice" "Receipt" "Statement" "Contract" "Insurance" "Letter" \
               "Report" "Certificate" "Identity" "Tax Return" "Payslip" "Manual" \
               "Quote" "Purchase Order" "Expense Report" "Form"; do
    api_post "/document_types/" "{\"name\": \"$dtype\"}"
  done

  # ── Tags ──
  echo ""
  ui_info "Creating tags..."

  # Status tags (red)
  for tag in "inbox" "todo" "needs-review"; do
    api_post "/tags/" "{\"name\": \"$tag\", \"color\": \"#e74c3c\", \"is_inbox_tag\": false}"
  done

  # AI processing tags (grey)
  for tag in "ai-processed" "paperless-gpt-auto" "paperless-gpt-ocr-auto" "paperless-gpt-ocr-complete"; do
    api_post "/tags/" "{\"name\": \"$tag\", \"color\": \"#95a5a6\"}"
  done

  # Category tags (blue)
  for tag in "finance" "home" "vehicle" "health" "legal" "work" "personal"; do
    api_post "/tags/" "{\"name\": \"$tag\", \"color\": \"#3498db\"}"
  done

  # Health subtags (teal)
  for tag in "health-medical" "health-dental" "health-optical" "health-pharmacy" "health-insurance"; do
    api_post "/tags/" "{\"name\": \"$tag\", \"color\": \"#1abc9c\"}"
  done

  # Duplicate tag (red)
  api_post "/tags/" "{\"name\": \"possible-duplicate\", \"color\": \"#e74c3c\", \"is_inbox_tag\": false}"

  # ── Custom Fields ──
  echo ""
  ui_info "Creating custom fields..."
  api_post "/custom_fields/" '{"name": "Amount", "data_type": "monetary"}'
  api_post "/custom_fields/" '{"name": "Due Date", "data_type": "date"}'
  api_post "/custom_fields/" '{"name": "Expiry Date", "data_type": "date"}'
  api_post "/custom_fields/" '{"name": "Reference Number", "data_type": "string"}'

  # ── Storage Path ──
  echo ""
  ui_info "Creating storage path..."
  api_post "/storage_paths/" '{"name": "Default", "path": "{created_year}/{document_type}/{correspondent} - {title}", "match": "", "matching_algorithm": 0}'

  # ── Workflows ──
  echo ""
  ui_info "Creating workflows..."

  # Get tag IDs for workflow
  local inbox_id gpt_auto_id gpt_ocr_id
  inbox_id=$(curl -s "http://localhost:8000/api/tags/?name__iexact=inbox" \
    -H "Authorization: Token $token" | \
    python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)
  gpt_auto_id=$(curl -s "http://localhost:8000/api/tags/?name__iexact=paperless-gpt-auto" \
    -H "Authorization: Token $token" | \
    python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)
  gpt_ocr_id=$(curl -s "http://localhost:8000/api/tags/?name__iexact=paperless-gpt-ocr-auto" \
    -H "Authorization: Token $token" | \
    python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)
  local health_id personal_id work_id finance_id
  health_id=$(curl -s "http://localhost:8000/api/tags/?name__iexact=health" \
    -H "Authorization: Token $token" | \
    python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)
  personal_id=$(curl -s "http://localhost:8000/api/tags/?name__iexact=personal" \
    -H "Authorization: Token $token" | \
    python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)
  work_id=$(curl -s "http://localhost:8000/api/tags/?name__iexact=work" \
    -H "Authorization: Token $token" | \
    python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)
  finance_id=$(curl -s "http://localhost:8000/api/tags/?name__iexact=finance" \
    -H "Authorization: Token $token" | \
    python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)

  # Workflow 1: Auto-process new documents
  if [ -n "$inbox_id" ] && [ -n "$gpt_auto_id" ] && [ -n "$gpt_ocr_id" ]; then
    local wf_data
    wf_data=$(cat <<WFEOF
{
  "name": "Auto-process new documents",
  "order": 1,
  "enabled": true,
  "triggers": [{"type": 1, "sources": [], "content_types": [], "filter_filename": null, "filter_path": null, "filter_mailrule": null}],
  "actions": [{"type": 0, "assign_tags": [$inbox_id, $gpt_auto_id, $gpt_ocr_id], "assign_correspondent": null, "assign_document_type": null, "assign_storage_path": null, "assign_owner": null, "assign_title": null, "assign_view_users": [], "assign_view_groups": [], "assign_change_users": [], "assign_change_groups": [], "assign_custom_fields": [], "remove_tags": [], "remove_correspondents": [], "remove_document_types": [], "remove_storage_paths": [], "remove_custom_fields": [], "remove_owners": []}]
}
WFEOF
)
    local result code
    result=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8000/api/workflows/" \
      -H "Authorization: Token $token" -H "Content-Type: application/json" -d "$wf_data")
    code=$(echo "$result" | tail -1)
    if [ "$code" = "201" ]; then
      ui_pass "Workflow: Auto-process new documents"
    else
      ui_warn "Workflow may already exist: Auto-process new documents"
    fi
  fi

  # Workflow 2: Health → Personal
  if [ -n "$health_id" ] && [ -n "$personal_id" ]; then
    local wf2_data
    wf2_data=$(cat <<WF2EOF
{
  "name": "Health documents are personal",
  "order": 2,
  "enabled": true,
  "triggers": [{"type": 1, "sources": [], "content_types": [], "filter_filename": null, "filter_path": null, "filter_mailrule": null, "filter_has_tags": [$health_id]}],
  "actions": [{"type": 0, "assign_tags": [$personal_id], "assign_correspondent": null, "assign_document_type": null, "assign_storage_path": null, "assign_owner": null, "assign_title": null, "assign_view_users": [], "assign_view_groups": [], "assign_change_users": [], "assign_change_groups": [], "assign_custom_fields": [], "remove_tags": [], "remove_correspondents": [], "remove_document_types": [], "remove_storage_paths": [], "remove_custom_fields": [], "remove_owners": []}]
}
WF2EOF
)
    result=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8000/api/workflows/" \
      -H "Authorization: Token $token" -H "Content-Type: application/json" -d "$wf2_data")
    code=$(echo "$result" | tail -1)
    if [ "$code" = "201" ]; then
      ui_pass "Workflow: Health documents are personal"
    else
      ui_warn "Workflow may already exist: Health documents are personal"
    fi
  fi

  # Workflow 3: Work receipts
  local receipt_type_id
  receipt_type_id=$(curl -s "http://localhost:8000/api/document_types/?name__iexact=Receipt" \
    -H "Authorization: Token $token" | \
    python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)

  if [ -n "$work_id" ] && [ -n "$receipt_type_id" ]; then
    local wf3_data
    wf3_data=$(cat <<WF3EOF
{
  "name": "Work receipts",
  "order": 3,
  "enabled": true,
  "triggers": [{"type": 1, "sources": [], "content_types": [], "filter_filename": null, "filter_path": null, "filter_mailrule": null, "filter_has_tags": [$work_id], "filter_has_document_type": $receipt_type_id}],
  "actions": [{"type": 0, "assign_tags": [$finance_id], "assign_correspondent": null, "assign_document_type": null, "assign_storage_path": null, "assign_owner": null, "assign_title": null, "assign_view_users": [], "assign_view_groups": [], "assign_change_users": [], "assign_change_groups": [], "assign_custom_fields": [], "remove_tags": [], "remove_correspondents": [], "remove_document_types": [], "remove_storage_paths": [], "remove_custom_fields": [], "remove_owners": []}]
}
WF3EOF
)
    result=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8000/api/workflows/" \
      -H "Authorization: Token $token" -H "Content-Type: application/json" -d "$wf3_data")
    code=$(echo "$result" | tail -1)
    if [ "$code" = "201" ]; then
      ui_pass "Workflow: Work receipts"
    else
      ui_warn "Workflow may already exist: Work receipts"
    fi
  fi

  # Workflow 4: Non-work finance → personal
  if [ -n "$finance_id" ] && [ -n "$personal_id" ] && [ -n "$work_id" ]; then
    local wf4_data
    wf4_data=$(cat <<WF4EOF
{
  "name": "Non-work finance is personal",
  "order": 4,
  "enabled": true,
  "triggers": [{"type": 1, "sources": [], "content_types": [], "filter_filename": null, "filter_path": null, "filter_mailrule": null, "filter_has_tags": [$finance_id], "filter_does_not_have_tags": [$work_id]}],
  "actions": [{"type": 0, "assign_tags": [$personal_id], "assign_correspondent": null, "assign_document_type": null, "assign_storage_path": null, "assign_owner": null, "assign_title": null, "assign_view_users": [], "assign_view_groups": [], "assign_change_users": [], "assign_change_groups": [], "assign_custom_fields": [], "remove_tags": [], "remove_correspondents": [], "remove_document_types": [], "remove_storage_paths": [], "remove_custom_fields": [], "remove_owners": []}]
}
WF4EOF
)
    result=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8000/api/workflows/" \
      -H "Authorization: Token $token" -H "Content-Type: application/json" -d "$wf4_data")
    code=$(echo "$result" | tail -1)
    if [ "$code" = "201" ]; then
      ui_pass "Workflow: Non-work finance is personal"
    else
      ui_warn "Workflow may already exist: Non-work finance is personal"
    fi
  fi

  # ── Test ──
  echo ""
  ui_info "Verifying defaults..."
  local tag_count
  tag_count=$(curl -s "http://localhost:8000/api/tags/" \
    -H "Authorization: Token $token" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null)

  if [ -n "$tag_count" ] && [ "$tag_count" -ge 10 ]; then
    ui_pass "Tags created: $tag_count"
  else
    ui_warn "Only $tag_count tags found (expected 20+)"
  fi

  ui_pass "Phase 6 complete"
}
