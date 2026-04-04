#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# Open Brain — Interactive Setup Wizard (Bash)
#
# Usage:
#   ./setup.sh                     # Interactive
#   ./setup.sh --force             # Skip prompts, use defaults
#   ./setup.sh --embedder ollama   # Specify embedder
# ──────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────

step()  { printf '\n\033[36m▸ %s\033[0m\n' "$1"; }
ok()    { printf '  \033[32m✓ %s\033[0m\n' "$1"; }
warn()  { printf '  \033[33m⚠ %s\033[0m\n' "$1"; }
fail()  { printf '  \033[31m✗ %s\033[0m\n' "$1"; }

FORCE=false
EMBEDDER=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)   FORCE=true; shift ;;
        --embedder)   EMBEDDER="$2"; shift 2 ;;
        *)            shift ;;
    esac
done

ask() {
    local prompt="$1" default="$2" result
    if $FORCE && [[ -n "$default" ]]; then echo "$default"; return; fi
    printf '%s [%s]: ' "$prompt" "$default"
    read -r result
    echo "${result:-$default}"
}

ask_choice() {
    local prompt="$1" default="$2"
    shift 2
    if $FORCE && [[ -n "$default" ]]; then echo "$default"; return; fi
    printf '%s (%s): ' "$prompt" "$*"
    read -r result
    echo "${result:-$default}"
}

# ── Banner ───────────────────────────────────────────────────────────

echo ""
printf '\033[35m  ╔══════════════════════════════════════════════╗\033[0m\n'
printf '\033[35m  ║         🧠  Open Brain Setup Wizard          ║\033[0m\n'
printf '\033[35m  ║   Persistent Memory for Every AI Tool        ║\033[0m\n'
printf '\033[35m  ╚══════════════════════════════════════════════╝\033[0m\n'
echo ""

# ── Step 1: Check Prerequisites ─────────────────────────────────────

step "Checking prerequisites..."

# Docker
if ! command -v docker &>/dev/null; then
    fail "Docker not found. Install from https://docs.docker.com/get-docker/"
    exit 1
fi
ok "Docker $(docker --version | grep -oP '[\d.]+'| head -1)"

# Docker Compose
if docker compose version &>/dev/null; then
    ok "Docker Compose (plugin)"
elif command -v docker-compose &>/dev/null; then
    ok "Docker Compose (standalone)"
else
    fail "Docker Compose not found. Install from https://docs.docker.com/compose/install/"
    exit 1
fi

# Docker running?
if docker info &>/dev/null; then
    ok "Docker daemon is running"
else
    fail "Docker daemon is not running. Start Docker and try again."
    exit 1
fi

# Node.js (optional)
if command -v node &>/dev/null; then
    ok "Node.js $(node --version | tr -d v)"
else
    warn "Node.js not found — needed for integration tests and mcp-remote bridge"
fi

# ── Step 2: Embedder Selection ──────────────────────────────────────

step "Configuring embedder..."

if [[ -z "$EMBEDDER" ]]; then
    echo ""
    echo "  Which embedding provider do you want to use?"
    echo "    1) ollama       — Local, free, requires Ollama running"
    echo "    2) openrouter   — Cloud API, pay-per-use, no local GPU needed"
    echo "    3) azure-openai — Azure OpenAI Service"
    echo ""
    choice=$(ask "  Choice (1/2/3)" "1")
    case "$choice" in
        1|ollama)       EMBEDDER="ollama" ;;
        2|openrouter)   EMBEDDER="openrouter" ;;
        3|azure-openai) EMBEDDER="azure-openai" ;;
        *)              EMBEDDER="ollama" ;;
    esac
fi

ok "Embedder: $EMBEDDER"

# Provider-specific
OLLAMA_EP="http://host.docker.internal:11434"
OPENROUTER_KEY=""
AZURE_EP=""
AZURE_KEY=""
AZURE_EMBED_DEPLOY="text-embedding-3-small"
AZURE_LLM_DEPLOY="gpt-4o-mini"

case "$EMBEDDER" in
    ollama)
        if command -v ollama &>/dev/null; then
            ok "Ollama CLI found"
            step "Pulling embedding model..."
            ollama pull nomic-embed-text >/dev/null 2>&1 && ok "nomic-embed-text ready"
            ollama pull llama3.2 >/dev/null 2>&1 && ok "llama3.2 ready"
        else
            warn "Ollama CLI not found — make sure Ollama is running and accessible"
        fi
        # macOS/Linux: use host.docker.internal or host-gateway
        if [[ "$(uname)" == "Linux" ]]; then
            OLLAMA_EP="http://host.docker.internal:11434"
        fi
        OLLAMA_EP=$(ask "  Ollama endpoint (from inside Docker)" "$OLLAMA_EP")
        ;;
    openrouter)
        OPENROUTER_KEY=$(ask "  OpenRouter API key" "")
        if [[ -z "$OPENROUTER_KEY" ]]; then
            fail "OpenRouter API key is required. Get one at https://openrouter.ai/keys"
            exit 1
        fi
        ;;
    azure-openai)
        AZURE_EP=$(ask "  Azure OpenAI endpoint" "")
        if [[ -z "$AZURE_EP" ]]; then
            fail "Azure OpenAI endpoint is required."
            exit 1
        fi
        AZURE_KEY=$(ask "  Azure OpenAI API key" "")
        if [[ -z "$AZURE_KEY" ]]; then
            fail "Azure OpenAI key is required."
            exit 1
        fi
        AZURE_EMBED_DEPLOY=$(ask "  Embedding deployment name" "text-embedding-3-small")
        AZURE_LLM_DEPLOY=$(ask "  LLM deployment name" "gpt-4o-mini")
        ;;
esac

# ── Step 3: Generate .env ────────────────────────────────────────────

step "Generating .env file..."

ENV_FILE="$SCRIPT_DIR/.env"
SKIP_ENV=false

if [[ -f "$ENV_FILE" ]]; then
    if ! $FORCE; then
        overwrite=$(ask "  .env already exists. Overwrite? (y/N)" "N")
        if [[ "$overwrite" != [yY]* ]]; then
            ok "Keeping existing .env"
            SKIP_ENV=true
        fi
    fi
fi

if ! $SKIP_ENV; then
    # Generate MCP access key
    MCP_KEY=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p | tr -d '\n')
    DB_PASS=$(ask "  Database password" "openbrain-$RANDOM")

    cat > "$ENV_FILE" << EOF
# Open Brain — Generated by setup.sh on $(date '+%Y-%m-%d %H:%M')

# Database
DB_HOST=postgres
DB_PORT=5432
DB_NAME=openbrain
DB_USER=openbrain
DB_PASSWORD=$DB_PASS

# Embedder
EMBEDDER_PROVIDER=$EMBEDDER
EMBEDDING_DIMENSIONS=768
EOF

    case "$EMBEDDER" in
        ollama)
            cat >> "$ENV_FILE" << EOF

# Ollama
OLLAMA_ENDPOINT=$OLLAMA_EP
OLLAMA_EMBED_MODEL=nomic-embed-text
OLLAMA_LLM_MODEL=llama3.2
EOF
            ;;
        openrouter)
            cat >> "$ENV_FILE" << EOF

# OpenRouter
OPENROUTER_API_KEY=$OPENROUTER_KEY
EOF
            ;;
        azure-openai)
            cat >> "$ENV_FILE" << EOF

# Azure OpenAI
AZURE_OPENAI_ENDPOINT=$AZURE_EP
AZURE_OPENAI_KEY=$AZURE_KEY
AZURE_OPENAI_EMBED_DEPLOYMENT=$AZURE_EMBED_DEPLOY
AZURE_OPENAI_LLM_DEPLOYMENT=$AZURE_LLM_DEPLOY
AZURE_OPENAI_API_VERSION=2024-06-01
EOF
            ;;
    esac

    cat >> "$ENV_FILE" << EOF

# MCP Authentication
MCP_ACCESS_KEY=$MCP_KEY

# Server Ports
API_PORT=8000
MCP_PORT=8080

# Logging
LOG_LEVEL=info
EOF

    ok ".env created (MCP key: ${MCP_KEY:0:12}...)"
fi

# Read MCP key from .env
MCP_KEY_FROM_ENV=$(grep '^MCP_ACCESS_KEY=' "$ENV_FILE" | cut -d= -f2)

# ── Step 4: Start Docker Compose ─────────────────────────────────────

step "Starting Docker Compose..."

docker compose up -d --build 2>&1 | sed 's/^/  /' || true

# Wait for health
step "Waiting for services to become healthy..."
MAX_WAIT=60
WAITED=0
HEALTHY=false

while [[ $WAITED -lt $MAX_WAIT ]]; do
    if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
        HEALTHY=true
        break
    fi
    printf '.'
    sleep 2
    WAITED=$((WAITED + 2))
done
echo ""

if $HEALTHY; then
    ok "REST API healthy (port 8000)"
else
    warn "REST API not responding yet — check 'docker compose logs api'"
fi

if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
    ok "MCP Server healthy (port 8080)"
else
    warn "MCP Server not responding yet — check 'docker compose logs api'"
fi

# ── Step 5: Configure AI Client ──────────────────────────────────────

step "Configure your AI client..."

MCP_URL="http://localhost:8080/sse?key=$MCP_KEY_FROM_ENV"

echo ""
echo "  Which AI client do you want to configure?"
echo "    1) VS Code Copilot  — .vscode/settings.json"
echo "    2) Claude Desktop   — claude_desktop_config.json (uses mcp-remote)"
echo "    3) Claude Code      — ~/.claude/settings.json"
echo "    4) Skip             — I'll configure it manually"
echo ""
CLIENT=$(ask "  Choice (1/2/3/4)" "1")

case "$CLIENT" in
    1)
        mkdir -p "$SCRIPT_DIR/.vscode"
        SETTINGS="$SCRIPT_DIR/.vscode/settings.json"
        cat > "$SETTINGS" << EOJSON
{
  "mcp": {
    "servers": {
      "openbrain": {
        "type": "sse",
        "url": "$MCP_URL"
      }
    }
  }
}
EOJSON
        ok "VS Code .vscode/settings.json created with MCP config"
        echo "  → Reload VS Code window to activate"
        ;;
    2)
        if [[ "$(uname)" == "Darwin" ]]; then
            CLAUDE_DIR="$HOME/Library/Application Support/Claude"
        else
            CLAUDE_DIR="${APPDATA:-$HOME/.config}/Claude"
        fi
        mkdir -p "$CLAUDE_DIR"
        CONFIG="$CLAUDE_DIR/claude_desktop_config.json"
        cat > "$CONFIG" << EOJSON
{
  "mcpServers": {
    "openbrain": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "$MCP_URL"]
    }
  }
}
EOJSON
        ok "Claude Desktop config created at $CONFIG"
        echo "  → Fully quit Claude Desktop and relaunch"
        ;;
    3)
        mkdir -p "$HOME/.claude"
        CONFIG="$HOME/.claude/settings.json"
        cat > "$CONFIG" << EOJSON
{
  "mcpServers": {
    "openbrain": {
      "type": "sse",
      "url": "$MCP_URL"
    }
  }
}
EOJSON
        ok "Claude Code settings updated"
        echo "  → Restart Claude Code to activate"
        ;;
    *)
        ok "Skipped — configure manually using the docs"
        ;;
esac

# ── Summary ──────────────────────────────────────────────────────────

echo ""
printf '\033[32m  ╔══════════════════════════════════════════════╗\033[0m\n'
printf '\033[32m  ║          🧠  Open Brain is running!          ║\033[0m\n'
printf '\033[32m  ╚══════════════════════════════════════════════╝\033[0m\n'
echo ""
echo "  REST API:    http://localhost:8000"
echo "  MCP Server:  http://localhost:8080"
echo "  MCP Key:     ${MCP_KEY_FROM_ENV:0:16}..."
echo "  Embedder:    $EMBEDDER"
echo ""
printf '\033[33m  Next steps:\033[0m\n'
echo '    • Open your AI tool and ask: "Use thought_stats to show brain statistics"'
echo '    • Try: "Remember that we chose PostgreSQL for the database"'
echo '    • Try: "Search for thoughts about database decisions"'
echo '    • Run tests: npm run test:integration'
echo ""
echo "  Docs:  https://srnichols.github.io/OpenBrain/"
echo "  Repo:  https://github.com/srnichols/OpenBrain"
echo ""
