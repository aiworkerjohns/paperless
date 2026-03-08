#!/bin/bash
# auth-fix.sh — Clean up allauth state and promote a user to superuser
#
# Usage: ./auth-fix.sh

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

ui_header "Google SSO Auth Fix"

# ── Clean up and show users ──
ui_info "Cleaning up stale allauth records..."
echo ""
docker exec paperless python3 manage.py shell -c "
from django.contrib.auth.models import User

# Clean up allauth tables
try:
    from allauth.socialaccount.models import SocialAccount
    SocialAccount.objects.all().delete()
    print('  Cleared all SocialAccount records')
except Exception as e:
    print(f'  SocialAccount cleanup: {e}')

try:
    from allauth.account.models import EmailAddress
    EmailAddress.objects.all().delete()
    print('  Cleared all EmailAddress records')
except Exception as e:
    print(f'  EmailAddress cleanup: {e}')

print()
print('  Current users:')
print(f'  {\"ID\":<5} {\"Username\":<20} {\"Email\":<35} {\"Super\":<6}')
print(f'  {\"--\":<5} {\"--------\":<20} {\"-----\":<35} {\"-----\":<6}')
for u in User.objects.all():
    print(f'  {u.id:<5} {u.username:<20} {u.email:<35} {u.is_superuser!s:<6}')
"
echo ""

# ── Get username to promote ──
promote_user=$(ui_input "Enter the username to promote to superuser")

# ── Promote ──
ui_info "Promoting '$promote_user'..."
docker exec paperless python3 manage.py shell -c "
from django.contrib.auth.models import User
u = User.objects.get(username='${promote_user}')
u.is_staff = True
u.is_superuser = True
u.save()
print(f'  {u.username} is now superuser')
"

echo ""
ui_pass "Done — now sign in with Google SSO again"
ui_info "allauth will re-create the link cleanly on next login"
