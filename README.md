# Paperless-ngx + AI Stack Installer

One-command installer for a fully configured Paperless-ngx document management system with AI-powered auto-tagging, vision OCR, document chat, and remote access.

## Quick Start

```bash
git clone git@github.com:aiworkerjohns/paperless.git
cd paperless
./install.sh
```

## What Gets Installed

- **Paperless-ngx** — Document management system
- **paperless-ai** — AI auto-tagging, classification, and RAG document chat
- **paperless-gpt** — Vision model OCR (minicpm-v)
- **Ollama** — Local LLM runtime (llama3.1:8b + minicpm-v)
- **Open WebUI** — Ollama management interface
- **Tailscale Serve** — Secure remote access (HTTPS)
- **Duplicate detection** — Nightly sweep using semantic search
- **AI Chat panel** — Injected into Paperless dashboard

## Requirements

- macOS (Apple Silicon recommended)
- ~20GB free disk space for Docker images + models

## Usage

```bash
./install.sh              # Full install (resumes on failure)
./install.sh --phase 5    # Run a specific phase
./install.sh --reset      # Start over
```

## Installer Phases

| Phase | Description |
|-------|-------------|
| 1 | Prerequisites (Homebrew, Colima, Docker, Ollama, Tailscale) |
| 2 | Configuration (admin credentials, timezone, OAuth, secrets) |
| 3 | Ollama models (llama3.1:8b, minicpm-v) |
| 4 | Docker stack (render templates, pull images, compose up) |
| 5 | Paperless setup (API token, update AI configs) |
| 6 | Default data (document types, tags, custom fields, workflows) |
| 7 | Tailscale (Serve config, HTTPS URLs) |
| 8 | Final verification (health checks, summary) |

## Service Ports

| Service | Port |
|---------|------|
| Paperless-ngx | 8000 |
| paperless-ai | 3000 |
| Open WebUI | 3001 |
| paperless-gpt | 3002 |
| Dozzle (logs) | 8080 |
