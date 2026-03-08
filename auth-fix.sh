#!/bin/bash
# auth-fix.sh — Fix Google SSO login
#
# Run twice:
#   1st run: clears email conflict, restarts Paperless
#   2nd run (after signing in via Google SSO): promotes your SSO user
#
# Usage: ./auth-fix.sh

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

ui_header "Google SSO Auth Fix"

# ── Check state ──
user_count=$(docker exec paperless python3 manage.py shell -c "
from django.contrib.auth.models import User
print(User.objects.count())
" 2>/dev/null | tr -d '[:space:]')

# ── Show current users ──
ui_info "Current users:"
echo ""
docker exec paperless python3 manage.py shell -c "
from django.contrib.auth.models import User
print(f'  {\"ID\":<5} {\"Username\":<20} {\"Email\":<35} {\"Super\":<6}')
print(f'  {\"--\":<5} {\"--------\":<20} {\"-----\":<35} {\"-----\":<6}')
for u in User.objects.all():
    print(f'  {u.id:<5} {u.username:<20} {u.email:<35} {u.is_superuser!s:<6}')
"
echo ""

# ── Detect if there's a non-superuser to promote ──
has_non_super=$(docker exec paperless python3 manage.py shell -c "
from django.contrib.auth.models import User
non_supers = User.objects.filter(is_superuser=False)
if non_supers.exists():
    for u in non_supers:
        print(u.username)
" 2>/dev/null | tr -d '[:space:]')

if [ -n "$has_non_super" ]; then
  # ── Phase 2: Promote the SSO user ──
  promote_user=$(ui_input "Enter the SSO username to promote to superuser")
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
  ui_pass "Done — refresh Paperless in your browser"
else
  # ── Phase 1: Clear email conflict and prep for SSO ──
  ui_info "Preparing for Google SSO..."

  docker exec paperless python3 manage.py shell -c "
from django.contrib.auth.models import User
try:
    from allauth.socialaccount.models import SocialAccount
    SocialAccount.objects.all().delete()
    print('  Cleared SocialAccount records')
except: pass
try:
    from allauth.account.models import EmailAddress
    EmailAddress.objects.all().delete()
    print('  Cleared EmailAddress records')
except: pass

# Clear email from all users to prevent conflict
for u in User.objects.all():
    if u.email:
        print(f'  Cleared email from user: {u.username}')
        u.email = ''
        u.save()
"

  # Add auto signup setting
  env_file="$INSTALL_DIR/paperless.env"
  if ! grep -q "^PAPERLESS_SOCIAL_AUTO_SIGNUP=" "$env_file" 2>/dev/null; then
    echo "PAPERLESS_SOCIAL_AUTO_SIGNUP=true" >> "$env_file"
    ui_info "Added PAPERLESS_SOCIAL_AUTO_SIGNUP=true"
  fi

  # Restart
  ui_info "Restarting Paperless..."
  export COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
  $DC restart paperless
  sleep 5

  echo ""
  ui_pass "Ready for Google SSO"
  ui_info "Now:"
  ui_info "  1. Sign in with Google SSO (pick any username)"
  ui_info "  2. Run ./auth-fix.sh again to promote your account"
fi
