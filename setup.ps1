<#
.SYNOPSIS
    Open Brain — Interactive Setup Wizard (PowerShell)
.DESCRIPTION
    Checks prerequisites, generates .env, starts Docker Compose,
    waits for health, and configures your AI client.
.PARAMETER Force
    Skip confirmation prompts and use defaults where possible.
.PARAMETER EmbedderProvider
    Embedder to use: ollama, openrouter, or azure-openai. Default: ollama.
.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -Force
    .\setup.ps1 -EmbedderProvider openrouter
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [ValidateSet('ollama','openrouter','azure-openai')]
    [string]$EmbedderProvider
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────

function Write-Step  { param([string]$msg) Write-Host "`n▸ $msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$msg) Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn  { param([string]$msg) Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$msg) Write-Host "  ✗ $msg" -ForegroundColor Red }

function Ask {
    param([string]$Prompt, [string]$Default)
    if ($Force -and $Default) { return $Default }
    $result = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($result)) { return $Default }
    return $result
}

function Ask-Choice {
    param([string]$Prompt, [string[]]$Options, [string]$Default)
    if ($Force -and $Default) { return $Default }
    $optStr = ($Options | ForEach-Object { if ($_ -eq $Default) { "$_*" } else { $_ } }) -join ' / '
    $result = Read-Host "$Prompt ($optStr)"
    if ([string]::IsNullOrWhiteSpace($result)) { return $Default }
    if ($result -notin $Options) {
        Write-Warn "Invalid choice '$result' — using '$Default'"
        return $Default
    }
    return $result
}

# ── Banner ───────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "  ║         🧠  Open Brain Setup Wizard          ║" -ForegroundColor Magenta
Write-Host "  ║   Persistent Memory for Every AI Tool        ║" -ForegroundColor Magenta
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

# ── Step 1: Check Prerequisites ─────────────────────────────────────

Write-Step "Checking prerequisites..."

# Docker
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Write-Fail "Docker not found. Install from https://docs.docker.com/get-docker/"
    exit 1
}
$dockerVersion = (docker --version) -replace 'Docker version ([0-9.]+).*','$1'
Write-Ok "Docker $dockerVersion"

# Docker Compose
try {
    $null = docker compose version 2>&1
    Write-Ok "Docker Compose (plugin)"
} catch {
    $compose = Get-Command docker-compose -ErrorAction SilentlyContinue
    if (-not $compose) {
        Write-Fail "Docker Compose not found. Install from https://docs.docker.com/compose/install/"
        exit 1
    }
    Write-Ok "Docker Compose (standalone)"
}

# Docker running?
try {
    $null = docker info 2>&1
    Write-Ok "Docker daemon is running"
} catch {
    Write-Fail "Docker daemon is not running. Start Docker Desktop and try again."
    exit 1
}

# Node.js (optional but needed for tests and mcp-remote)
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    $nodeVersion = (node --version) -replace 'v',''
    Write-Ok "Node.js $nodeVersion"
} else {
    Write-Warn "Node.js not found — needed for integration tests and mcp-remote bridge"
}

# ── Step 2: Embedder Selection ──────────────────────────────────────

Write-Step "Configuring embedder..."

if (-not $EmbedderProvider) {
    Write-Host ""
    Write-Host "  Which embedding provider do you want to use?" -ForegroundColor White
    Write-Host "    1) ollama       — Local, free, requires Ollama running" -ForegroundColor Gray
    Write-Host "    2) openrouter   — Cloud API, pay-per-use, no local GPU needed" -ForegroundColor Gray
    Write-Host "    3) azure-openai — Azure OpenAI Service" -ForegroundColor Gray
    Write-Host ""
    $choice = Ask -Prompt "  Choice (1/2/3)" -Default "1"
    $EmbedderProvider = switch ($choice) {
        '1' { 'ollama' }
        '2' { 'openrouter' }
        '3' { 'azure-openai' }
        'ollama' { 'ollama' }
        'openrouter' { 'openrouter' }
        'azure-openai' { 'azure-openai' }
        default { 'ollama' }
    }
}

Write-Ok "Embedder: $EmbedderProvider"

# Provider-specific prompts
$ollamaEndpoint = "http://host.docker.internal:11434"
$openrouterKey = ""
$azureEndpoint = ""
$azureKey = ""
$azureEmbedDeploy = "text-embedding-3-small"
$azureLlmDeploy = "gpt-4o-mini"

switch ($EmbedderProvider) {
    'ollama' {
        $ollama = Get-Command ollama -ErrorAction SilentlyContinue
        if ($ollama) {
            Write-Ok "Ollama CLI found"
            Write-Step "Pulling embedding model..."
            & ollama pull nomic-embed-text 2>&1 | Out-Null
            Write-Ok "nomic-embed-text ready"
            & ollama pull llama3.2 2>&1 | Out-Null
            Write-Ok "llama3.2 ready"
        } else {
            Write-Warn "Ollama CLI not found — make sure Ollama is running and accessible"
        }
        $ollamaEndpoint = Ask -Prompt "  Ollama endpoint (from inside Docker)" -Default "http://host.docker.internal:11434"
    }
    'openrouter' {
        $openrouterKey = Ask -Prompt "  OpenRouter API key" -Default ""
        if ([string]::IsNullOrWhiteSpace($openrouterKey)) {
            Write-Fail "OpenRouter API key is required. Get one at https://openrouter.ai/keys"
            exit 1
        }
    }
    'azure-openai' {
        $azureEndpoint = Ask -Prompt "  Azure OpenAI endpoint (https://your-resource.openai.azure.com)" -Default ""
        if ([string]::IsNullOrWhiteSpace($azureEndpoint)) {
            Write-Fail "Azure OpenAI endpoint is required."
            exit 1
        }
        $azureKey = Ask -Prompt "  Azure OpenAI API key" -Default ""
        if ([string]::IsNullOrWhiteSpace($azureKey)) {
            Write-Fail "Azure OpenAI key is required."
            exit 1
        }
        $azureEmbedDeploy = Ask -Prompt "  Embedding deployment name" -Default "text-embedding-3-small"
        $azureLlmDeploy = Ask -Prompt "  LLM deployment name" -Default "gpt-4o-mini"
    }
}

# ── Step 3: Generate .env ────────────────────────────────────────────

Write-Step "Generating .env file..."

$envFile = Join-Path $PSScriptRoot '.env'

if (Test-Path $envFile) {
    if (-not $Force) {
        $overwrite = Ask -Prompt "  .env already exists. Overwrite? (y/N)" -Default "N"
        if ($overwrite -notin @('y','Y','yes')) {
            Write-Ok "Keeping existing .env"
            $skipEnv = $true
        }
    }
}

if (-not $skipEnv) {
    # Generate MCP access key
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $mcpKey = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''

    $dbPassword = Ask -Prompt "  Database password" -Default "openbrain-$(Get-Random -Maximum 9999)"

    $envContent = @"
# Open Brain — Generated by setup.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm')

# Database
DB_HOST=postgres
DB_PORT=5432
DB_NAME=openbrain
DB_USER=openbrain
DB_PASSWORD=$dbPassword

# Embedder
EMBEDDER_PROVIDER=$EmbedderProvider
EMBEDDING_DIMENSIONS=768

"@

    switch ($EmbedderProvider) {
        'ollama' {
            $envContent += @"
# Ollama
OLLAMA_ENDPOINT=$ollamaEndpoint
OLLAMA_EMBED_MODEL=nomic-embed-text
OLLAMA_LLM_MODEL=llama3.2

"@
        }
        'openrouter' {
            $envContent += @"
# OpenRouter
OPENROUTER_API_KEY=$openrouterKey

"@
        }
        'azure-openai' {
            $envContent += @"
# Azure OpenAI
AZURE_OPENAI_ENDPOINT=$azureEndpoint
AZURE_OPENAI_KEY=$azureKey
AZURE_OPENAI_EMBED_DEPLOYMENT=$azureEmbedDeploy
AZURE_OPENAI_LLM_DEPLOYMENT=$azureLlmDeploy
AZURE_OPENAI_API_VERSION=2024-06-01

"@
        }
    }

    $envContent += @"
# MCP Authentication
MCP_ACCESS_KEY=$mcpKey

# Server Ports
API_PORT=8000
MCP_PORT=8080

# Logging
LOG_LEVEL=info
"@

    Set-Content -Path $envFile -Value $envContent -Encoding UTF8
    Write-Ok ".env created (MCP key: $($mcpKey.Substring(0,12))...)"
}

# Read MCP key from .env for later
$mcpKeyFromEnv = (Get-Content $envFile | Where-Object { $_ -match '^MCP_ACCESS_KEY=' }) -replace 'MCP_ACCESS_KEY=',''

# ── Step 4: Start Docker Compose ─────────────────────────────────────

Write-Step "Starting Docker Compose..."

docker compose up -d --build 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

# Wait for health
Write-Step "Waiting for services to become healthy..."
$maxWait = 60
$waited = 0
$healthy = $false
while ($waited -lt $maxWait) {
    try {
        $resp = Invoke-RestMethod -Uri "http://localhost:8000/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($resp.status -eq 'healthy') {
            $healthy = $true
            break
        }
    } catch { }
    Start-Sleep -Seconds 2
    $waited += 2
    Write-Host "." -NoNewline -ForegroundColor DarkGray
}
Write-Host ""

if ($healthy) {
    Write-Ok "REST API healthy (port 8000)"
} else {
    Write-Warn "REST API not responding yet — check 'docker compose logs api'"
}

try {
    $mcpResp = Invoke-RestMethod -Uri "http://localhost:8080/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
    if ($mcpResp.status -eq 'healthy') {
        Write-Ok "MCP Server healthy (port 8080)"
    }
} catch {
    Write-Warn "MCP Server not responding yet — check 'docker compose logs api'"
}

# ── Step 5: Configure AI Client ──────────────────────────────────────

Write-Step "Configure your AI client..."

Write-Host ""
Write-Host "  Which AI client do you want to configure?" -ForegroundColor White
Write-Host "    1) VS Code Copilot  — settings.json MCP config" -ForegroundColor Gray
Write-Host "    2) Claude Desktop   — claude_desktop_config.json (uses mcp-remote)" -ForegroundColor Gray
Write-Host "    3) Claude Code      — ~/.claude/settings.json" -ForegroundColor Gray
Write-Host "    4) Skip             — I'll configure it manually" -ForegroundColor Gray
Write-Host ""
$clientChoice = Ask -Prompt "  Choice (1/2/3/4)" -Default "1"

$mcpUrl = "http://localhost:8080/sse?key=$mcpKeyFromEnv"

switch ($clientChoice) {
    '1' {
        # VS Code Copilot
        $vscodePath = Join-Path $PSScriptRoot '.vscode'
        if (-not (Test-Path $vscodePath)) { New-Item -ItemType Directory -Path $vscodePath -Force | Out-Null }
        $settingsFile = Join-Path $vscodePath 'settings.json'

        $mcpSettings = @{
            "mcp" = @{
                "servers" = @{
                    "openbrain" = @{
                        "type" = "sse"
                        "url"  = $mcpUrl
                    }
                }
            }
        }

        if (Test-Path $settingsFile) {
            $existing = Get-Content $settingsFile -Raw | ConvertFrom-Json -AsHashtable
            $existing["mcp"] = $mcpSettings["mcp"]
            $existing | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
        } else {
            $mcpSettings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
        }
        Write-Ok "VS Code .vscode/settings.json updated with MCP config"
        Write-Host "  → Reload VS Code window to activate" -ForegroundColor Gray
    }
    '2' {
        # Claude Desktop
        $claudePath = Join-Path $env:APPDATA 'Claude'
        if (-not (Test-Path $claudePath)) { New-Item -ItemType Directory -Path $claudePath -Force | Out-Null }
        $configFile = Join-Path $claudePath 'claude_desktop_config.json'

        $claudeConfig = @{
            "mcpServers" = @{
                "openbrain" = @{
                    "command" = "npx"
                    "args" = @("-y", "mcp-remote", $mcpUrl)
                }
            }
        }

        if (Test-Path $configFile) {
            try {
                $existing = Get-Content $configFile -Raw | ConvertFrom-Json -AsHashtable
                if (-not $existing["mcpServers"]) { $existing["mcpServers"] = @{} }
                $existing["mcpServers"]["openbrain"] = $claudeConfig["mcpServers"]["openbrain"]
                $existing | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8
            } catch {
                $claudeConfig | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8
            }
        } else {
            $claudeConfig | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8
        }
        Write-Ok "Claude Desktop config updated"
        Write-Host "  → Fully quit Claude Desktop (system tray → Quit) and relaunch" -ForegroundColor Gray
    }
    '3' {
        # Claude Code
        $claudeDir = Join-Path $HOME '.claude'
        if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
        $settingsFile = Join-Path $claudeDir 'settings.json'

        $claudeCodeConfig = @{
            "mcpServers" = @{
                "openbrain" = @{
                    "type" = "sse"
                    "url"  = $mcpUrl
                }
            }
        }

        if (Test-Path $settingsFile) {
            try {
                $existing = Get-Content $settingsFile -Raw | ConvertFrom-Json -AsHashtable
                if (-not $existing["mcpServers"]) { $existing["mcpServers"] = @{} }
                $existing["mcpServers"]["openbrain"] = $claudeCodeConfig["mcpServers"]["openbrain"]
                $existing | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
            } catch {
                $claudeCodeConfig | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
            }
        } else {
            $claudeCodeConfig | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
        }
        Write-Ok "Claude Code settings updated"
        Write-Host "  → Restart Claude Code to activate" -ForegroundColor Gray
    }
    default {
        Write-Ok "Skipped — configure manually using the docs"
    }
}

# ── Summary ──────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║          🧠  Open Brain is running!          ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  REST API:    http://localhost:8000" -ForegroundColor White
Write-Host "  MCP Server:  http://localhost:8080" -ForegroundColor White
Write-Host "  MCP Key:     $($mcpKeyFromEnv.Substring(0,16))..." -ForegroundColor White
Write-Host "  Embedder:    $EmbedderProvider" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    • Open your AI tool and ask: ""Use thought_stats to show brain statistics""" -ForegroundColor Gray
Write-Host "    • Try: ""Remember that we chose PostgreSQL for the database""" -ForegroundColor Gray
Write-Host "    • Try: ""Search for thoughts about database decisions""" -ForegroundColor Gray
Write-Host "    • Run tests: npm run test:integration" -ForegroundColor Gray
Write-Host ""
Write-Host "  Docs:  https://srnichols.github.io/OpenBrain/" -ForegroundColor DarkGray
Write-Host "  Repo:  https://github.com/srnichols/OpenBrain" -ForegroundColor DarkGray
Write-Host ""
