# Testing Status & Handoff Notes

## What This Is
A Paperless-ngx + AI stack installer wizard. Run `./install.sh` on a fresh Mac Mini (Apple Silicon) to deploy the full stack with one command.

## Testing Completed (on existing dev machine)

### Phase 1: Prerequisites — PASSED
- All tools detected correctly (Homebrew, Colima, Docker, Ollama, Tailscale, gum)
- Colima running check works
- Docker credential store fix works
- Verification tests all pass

### Phase 3: Ollama Models — PASSED
- Correctly detects existing models (skips re-download)
- Pull works when models are missing
- Fixed: `grep -q` + `pipefail` causes SIGPIPE (exit 141) — replaced with `grep >/dev/null`

### Template Rendering — PASSED
- All 5 templates render correctly with placeholder substitution
- `docker compose config` validates the rendered docker-compose.yml
- All `__PLACEHOLDER__` values correctly replaced from `.install-config`

### shellcheck — PASSED
- All scripts pass shellcheck with zero warnings

### Phase 2: Configuration — NOT TESTED (interactive)
- Requires TTY for gum/read prompts
- Structurally reviewed and looks correct
- Generates secrets via `openssl rand -hex`

## What Needs Testing on a Fresh Machine

### Phase 4: Docker Stack
- Renders templates and copies static files
- Runs `docker compose pull` (downloads ~10GB of images)
- Runs `docker compose up -d`
- Waits for Postgres + Redis health checks
- Waits for Paperless HTTP on port 8000
- **Risk**: Port conflicts if anything else is on 8000/3000/3001/3002/8080

### Phase 5: Paperless Setup
- Waits for login page to load
- Generates API token via `docker exec paperless python3 manage.py shell`
- Updates paperless-ai.env, paperless-gpt.env, docker-compose.yml with real token
- Re-renders overrides.js with both tokens
- Restarts paperless-ai, paperless-gpt, paperless, cron
- Tests API access with token

### Phase 6: Default Data
- Creates 16 document types via API
- Creates all tags (status, AI, category, health subtags, possible-duplicate)
- Creates 4 custom fields (Amount, Due Date, Expiry Date, Reference Number)
- Creates storage path
- Creates 4 workflows (auto-process, health→personal, work receipts, non-work finance→personal)
- All API calls are idempotent (skips existing items)

### Phase 7: Tailscale
- Detects Tailscale connection status
- Gets MagicDNS hostname from `tailscale status --json`
- Sets up Tailscale Serve (443→8000, 8443→3000)
- Updates PAPERLESS_URL and CSRF_TRUSTED_ORIGINS
- Restarts Paperless container
- **Requires**: Tailscale logged in and connected

### Phase 8: Final Verification
- Checks all 10 containers are running
- Tests Paperless API with token
- Tests paperless-ai RAG service (waits up to 90s for ML model loading)
- Displays summary with URLs and credentials

## Known Issues / Watch For

1. **SIGPIPE with pipefail**: Fixed in phase3 and phase7, but if you add new `cmd | grep -q` patterns, use `grep >/dev/null` instead
2. **Phase 2 Google SSO**: The `GOOGLE_SSO_PROVIDERS` value contains JSON with quotes — the sed-based template engine may need escaping for complex values. Test with actual Google OAuth credentials.
3. **Tailscale Serve syntax**: The `tailscale serve` CLI has changed across versions. Phase 7 tries multiple syntaxes but may need adjustment for newer Tailscale versions.
4. **State resume**: The `.install-state` file tracks last completed phase. If a phase fails mid-way, re-running will retry the whole phase (not resume within it).
5. **overrides.js token injection**: Phase 5 does a two-step token injection (render_template + sed for PAPERLESS_TOKEN). Verify both `__AI_API_KEY__` and `__PAPERLESS_TOKEN__` are replaced in the final overrides.js.

## How to Test

```bash
# On a fresh Mac Mini:
git clone git@github.com:aiworkerjohns/paperless.git
cd paperless
./install.sh

# Or run phases individually:
./install.sh --phase 1   # Install prerequisites
./install.sh --phase 2   # Configure (interactive prompts)
./install.sh --phase 3   # Pull Ollama models
./install.sh --phase 4   # Start Docker stack
./install.sh --phase 5   # Generate API token, update configs
./install.sh --phase 6   # Create default data
./install.sh --phase 7   # Set up Tailscale
./install.sh --phase 8   # Verify everything

# Reset and start over:
./install.sh --reset
```

## File Overview

```
install.sh          — Main orchestrator (~80 lines)
lib/common.sh       — UI wrappers, template engine, API helpers, state mgmt
lib/phase[1-8]*.sh  — One file per phase
templates/*.tmpl    — Docker/env configs with __PLACEHOLDERS__
static/*            — Files copied as-is (or rendered from .tmpl)
```
