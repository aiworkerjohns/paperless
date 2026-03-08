#!/bin/bash
# get-token.sh — Get or create the Paperless API token (clean output)
#
# Usage: ./get-token.sh

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

ui_header "Paperless API Token"

# Extract only the 40-char hex token from shell output
raw=$(docker exec paperless python3 manage.py shell -c "
from rest_framework.authtoken.models import Token
from django.contrib.auth.models import User
u = User.objects.filter(is_superuser=True).first()
t, _ = Token.objects.get_or_create(user=u)
print('TOKEN:' + t.key)
" 2>/dev/null)

token=$(echo "$raw" | grep '^TOKEN:' | sed 's/^TOKEN://' | tr -d '[:space:]')

if [ -z "$token" ] || [ ${#token} -ne 40 ]; then
  ui_fail "Could not get token — is Paperless running?"
  ui_info "Raw output: $raw"
  exit 1
fi

echo ""
ui_pass "API Token: $token"
echo ""
