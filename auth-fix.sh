#!/bin/bash
# auth-fix.sh — Promote a Google SSO user to superuser/admin
#
# Usage: ./auth-fix.sh
#
# Steps:
#   1. Sign in with Google SSO using any username
#   2. Run this script
#   3. It will show all users and let you pick which one to promote

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

ui_header "Google SSO Auth Fix"

# ── Show current users ──
ui_info "Current users:"
echo ""
docker exec paperless python3 manage.py shell -c "
from django.contrib.auth.models import User
print(f'  {\"ID\":<5} {\"Username\":<20} {\"Email\":<35} {\"Staff\":<6} {\"Super\":<6}')
print(f'  {\"--\":<5} {\"--------\":<20} {\"-----\":<35} {\"-----\":<6} {\"-----\":<6}')
for u in User.objects.all():
    print(f'  {u.id:<5} {u.username:<20} {u.email:<35} {u.is_staff!s:<6} {u.is_superuser!s:<6}')
"
echo ""

# ── Get username to promote ──
promote_user=$(ui_input "Enter the username to promote to superuser")

# ── Promote ──
ui_info "Promoting '$promote_user' to superuser..."
docker exec paperless python3 manage.py shell -c "
from django.contrib.auth.models import User
u = User.objects.get(username='${promote_user}')
u.is_staff = True
u.is_superuser = True
u.save()
print(f'  {u.username} is now staff={u.is_staff} superuser={u.is_superuser}')
"

echo ""
ui_pass "Done — $promote_user is now a superuser"
ui_info "Refresh Paperless in your browser"
