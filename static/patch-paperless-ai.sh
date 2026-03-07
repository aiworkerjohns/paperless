#!/bin/bash
# Patches applied at container startup for paperless-ai

# 1. Limit RAG context to top 2 sources (prevents irrelevant docs confusing the LLM)
sed -i 's/max_sources: 5/max_sources: 2/' /app/services/ragService.js 2>/dev/null

# 2. Seed data/.env if empty or missing (first-run only)
#    Once seeded, the user manages settings via the paperless-ai web UI (port 3000).
#    This script will NOT overwrite an existing config.
if [ ! -s /app/data/.env ] || ! grep -q 'PAPERLESS_AI_INITIAL_SETUP' /app/data/.env; then
  echo "First run: seeding /app/data/.env from environment variables..."
  cat > /app/data/.env << ENVEOF
PAPERLESS_API_URL=${PAPERLESS_API_URL:-http://paperless:8000/api}
PAPERLESS_API_TOKEN=${PAPERLESS_API_TOKEN}
PAPERLESS_USERNAME=${PAPERLESS_USERNAME:-}
AI_PROVIDER=${AI_PROVIDER:-ollama}
SCAN_INTERVAL=${SCAN_INTERVAL:-30}
SYSTEM_PROMPT=\`You are a document classification AI for a personal document management system. Analyze each document and assign metadata.

RULES:
- Select only the 1-2 MOST relevant tags per document. Do NOT over-tag.
- Never assign workflow tags (inbox, todo, needs-review) — those are managed by workflows.
- The correspondent is the SENDER or ISSUER, not the recipient.
- Pick the single most specific document type.
- Keep titles short and descriptive with key identifiers (invoice numbers, dates, names).\`
PROCESS_PREDEFINED_DOCUMENTS=${PROCESS_PREDEFINED_DOCUMENTS:-no}
TOKEN_LIMIT=${OLLAMA_TOKEN_LIMIT:-128000}
RESPONSE_TOKENS=${OLLAMA_TOKEN_RESPONSE:-1000}
TAGS=
ADD_AI_PROCESSED_TAG=${ADD_AI_TAG:-yes}
AI_PROCESSED_TAG_NAME=${AI_TAG_NAME:-ai-processed}
USE_PROMPT_TAGS=no
PROMPT_TAGS=
USE_EXISTING_DATA=yes
API_KEY=${API_KEY:-}
JWT_SECRET=$(head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n')
CUSTOM_API_KEY=
CUSTOM_BASE_URL=
CUSTOM_MODEL=
PAPERLESS_AI_INITIAL_SETUP=yes
ACTIVATE_TAGGING=yes
ACTIVATE_CORRESPONDENTS=yes
ACTIVATE_DOCUMENT_TYPE=yes
ACTIVATE_TITLE=yes
ACTIVATE_CUSTOM_FIELDS=no
CUSTOM_FIELDS={"custom_fields":[]}
DISABLE_AUTOMATIC_PROCESSING=no
AZURE_ENDPOINT=
AZURE_API_KEY=
AZURE_DEPLOYMENT_NAME=
AZURE_API_VERSION=
OLLAMA_API_URL=${OLLAMA_URL:-http://host.docker.internal:11434}
OLLAMA_MODEL=${OLLAMA_MODEL:-llama3.1:8b}
ENVEOF
  echo "Seeded /app/data/.env — edit via paperless-ai settings UI going forward"
fi

exec /app/start-services.sh "$@"
