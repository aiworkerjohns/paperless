#!/bin/bash
# auth-fix.sh — Link Google SSO to the admin account
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
from allauth.socialaccount.models import SocialAccount
print(f'  {\"ID\":<5} {\"Username\":<20} {\"Email\":<35} {\"Admin\":<6}')
print(f'  {\"--\":<5} {\"--------\":<20} {\"-----\":<35} {\"-----\":<6}')
for u in User.objects.all():
    socials = SocialAccount.objects.filter(user=u)
    social_str = ', '.join([f'{s.provider}:{s.uid}' for s in socials]) or 'none'
    print(f'  {u.id:<5} {u.username:<20} {u.email:<35} {u.is_superuser}  SSO: {social_str}')
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
ui_info "Linking Google SSO to admin account..."
docker exec paperless python3 manage.py shell -c "
from django.contrib.auth.models import User
from allauth.socialaccount.models import SocialAccount, SocialApp
from allauth.account.models import EmailAddress

admin_user = User.objects.get(username='${local_admin}')

# Delete any non-admin users with this Google email
dupes = User.objects.filter(email='${google_email}').exclude(username='${local_admin}')
for d in dupes:
    print(f'  Deleting duplicate user: {d.username} (id={d.id})')
    SocialAccount.objects.filter(user=d).delete()
    d.delete()

# Set admin email
admin_user.email = '${google_email}'
admin_user.save()
print(f'  Set {admin_user.username} email to ${google_email}')

# Ensure verified EmailAddress exists (allauth uses this for matching)
ea, created = EmailAddress.objects.get_or_create(
    user=admin_user,
    email='${google_email}',
    defaults={'verified': True, 'primary': True}
)
if not created:
    ea.verified = True
    ea.primary = True
    ea.save()
# Clear any other email addresses for this user
EmailAddress.objects.filter(user=admin_user).exclude(email='${google_email}').delete()
print(f'  Verified email address: ${google_email}')

print('  Done — sign in with Google SSO now')
print('  allauth will auto-link by verified email')
"

# ── Ensure env settings are present ──
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
env_file="$INSTALL_DIR/paperless.env"
for setting in PAPERLESS_SOCIALACCOUNT_EMAIL_AUTHENTICATION PAPERLESS_SOCIALACCOUNT_EMAIL_AUTHENTICATION_AUTO_CONNECT; do
  if ! grep -q "^${setting}=" "$env_file" 2>/dev/null; then
    echo "${setting}=true" >> "$env_file"
    ui_info "Added ${setting}=true to paperless.env"
  fi
done

# ── Restart ──
ui_info "Restarting Paperless..."
$DC restart paperless
sleep 5

echo ""
ui_pass "Auth fix complete"
ui_info "Sign in with Google SSO — it will auto-link to the '$local_admin' admin account"
