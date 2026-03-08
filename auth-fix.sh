#!/bin/bash
# auth-fix.sh — Fix Google SSO user by linking it to the admin account
#
# Usage: ./auth-fix.sh

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

ui_header "Google SSO Auth Fix"

# ── Show current users ──
ui_info "Current users:"
echo ""
docker exec paperless python3 manage.py shell -c "
from django.contrib.auth.models import User
print(f'  {\"ID\":<5} {\"Username\":<20} {\"Email\":<35} {\"Admin\":<6}')
print(f'  {\"--\":<5} {\"--------\":<20} {\"-----\":<35} {\"-----\":<6}')
for u in User.objects.all():
    print(f'  {u.id:<5} {u.username:<20} {u.email:<35} {u.is_superuser}')
"
echo ""

# ── Get the admin username ──
load_config
local_admin="${ADMIN_USER:-}"
if [ -z "$local_admin" ]; then
  local_admin=$(ui_input "Enter the admin username (created during install)")
fi
ui_info "Admin account: $local_admin"

# ── Get the Google email ──
google_email=$(ui_input "Enter your Google SSO email address")

# ── Run the fix ──
ui_info "Removing duplicate SSO accounts and linking Google email to admin..."
docker exec paperless python3 manage.py shell -c "
from django.contrib.auth.models import User
from allauth.socialaccount.models import SocialAccount

admin_user = User.objects.get(username='${local_admin}')

# Delete any non-admin users with this Google email
dupes = User.objects.filter(email='${google_email}').exclude(username='${local_admin}')
if dupes.exists():
    for d in dupes:
        print(f'  Deleting duplicate user: {d.username} (id={d.id})')
    dupes.delete()

# Set admin email to Google email
admin_user.email = '${google_email}'
admin_user.save()
print(f'  Set {admin_user.username} email to ${google_email}')

# Remove any stale social account links
SocialAccount.objects.filter(user=admin_user).delete()
print('  Cleared old social account links')
print('  Done — sign in with Google SSO now')
"

echo ""
ui_pass "Auth fix complete"
ui_info "Sign in with Google SSO — it will link to the '$local_admin' admin account"
