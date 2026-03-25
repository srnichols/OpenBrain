#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy OpenBrain to Azure.

.DESCRIPTION
    Creates a resource group and deploys OpenBrain infrastructure via Bicep:
    - Azure Database for PostgreSQL Flexible Server (B1ms + pgvector)
    - Azure Container Apps (Consumption plan)
    - Azure OpenAI (text-embedding-3-small + gpt-4o-mini)
    - Azure Key Vault (secrets)

.PARAMETER ResourceGroup
    Name of the resource group to create/use.

.PARAMETER Location
    Azure region. Default: eastus2.

.PARAMETER SubscriptionId
    Azure subscription ID. If not specified, uses current context.

.EXAMPLE
    .\infra\deploy.ps1 -ResourceGroup rg-openbrain -Location eastus2
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [string]$Location = "eastus2",

    [string]$SubscriptionId,

    [string]$ContainerImage = "ghcr.io/srnichols/openbrain:latest"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Verify Azure CLI ────────────────────────────────────────────────────────

Write-Host "`n=== OpenBrain Azure Deployment ===" -ForegroundColor Cyan

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI (az) is required. Install from https://aka.ms/installazurecli"
    exit 1
}

# ── Set subscription ────────────────────────────────────────────────────────

if ($SubscriptionId) {
    Write-Host "Setting subscription: $SubscriptionId" -ForegroundColor Yellow
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to set subscription"; exit 1 }
}

$currentSub = (az account show --query "id" -o tsv)
Write-Host "Subscription: $currentSub" -ForegroundColor Green

# ── Generate secrets ────────────────────────────────────────────────────────

Write-Host "`nGenerating secrets..." -ForegroundColor Yellow

# Generate a secure random password (16 chars, letters + digits + special)
$dbPasswordChars = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
$dbPassword = "${dbPasswordChars}!Az1"

# Generate MCP access key (64 hex chars)
$mcpKeyBytes = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($mcpKeyBytes)
$mcpAccessKey = ($mcpKeyBytes | ForEach-Object { $_.ToString("x2") }) -join ''

Write-Host "  DB password: generated (${dbPassword.Length} chars)" -ForegroundColor Green
Write-Host "  MCP key:     generated (${mcpAccessKey.Length} chars)" -ForegroundColor Green

# ── Create resource group ───────────────────────────────────────────────────

Write-Host "`nCreating resource group: $ResourceGroup in $Location..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create resource group"; exit 1 }
Write-Host "  Resource group ready." -ForegroundColor Green

# ── Deploy Bicep ────────────────────────────────────────────────────────────

$templateFile = Join-Path $PSScriptRoot "main.bicep"

Write-Host "`nDeploying Bicep template..." -ForegroundColor Yellow
Write-Host "  Template: $templateFile" -ForegroundColor Gray
Write-Host "  This will take 5-15 minutes (PostgreSQL provisioning is slow)." -ForegroundColor Gray

$deployResult = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file $templateFile `
    --parameters `
        location=$Location `
        dbPassword=$dbPassword `
        mcpAccessKey=$mcpAccessKey `
        containerImage=$ContainerImage `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed:`n$deployResult"
    exit 1
}

$outputs = $deployResult | ConvertFrom-Json | Select-Object -ExpandProperty properties | Select-Object -ExpandProperty outputs

$mcpEndpoint = $outputs.mcpEndpoint.value
$restEndpoint = $outputs.restEndpoint.value
$pgHost = $outputs.pgHost.value
$openaiEndpoint = $outputs.openaiEndpoint.value
$kvName = $outputs.keyVaultName.value

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "  MCP Endpoint:   $mcpEndpoint" -ForegroundColor Cyan
Write-Host "  REST Endpoint:  $restEndpoint" -ForegroundColor Cyan
Write-Host "  PostgreSQL:     $pgHost" -ForegroundColor Cyan
Write-Host "  Azure OpenAI:   $openaiEndpoint" -ForegroundColor Cyan
Write-Host "  Key Vault:      $kvName" -ForegroundColor Cyan

# ── Initialize Database ─────────────────────────────────────────────────────

Write-Host "`nInitializing database schema..." -ForegroundColor Yellow

# Read init.sql and replace 768 with the correct dimension for Azure
$initSql = Get-Content (Join-Path $PSScriptRoot ".." ".." "db" "init.sql") -Raw
$initSql = $initSql -replace 'VECTOR\(768\)', 'VECTOR(1536)'

# Write temp file
$tempSql = [System.IO.Path]::GetTempFileName()
$initSql | Set-Content -Path $tempSql -Encoding UTF8

Write-Host "  Waiting 30s for PostgreSQL to be fully ready..." -ForegroundColor Gray
Start-Sleep -Seconds 30

# Connect and run init SQL
$env:PGPASSWORD = $dbPassword
psql "host=$pgHost port=5432 dbname=openbrain user=openbrain sslmode=require" -f $tempSql 2>&1 | ForEach-Object {
    if ($_ -match "ERROR") { Write-Host "  $_" -ForegroundColor Red }
    else { Write-Host "  $_" -ForegroundColor Gray }
}
Remove-Item $tempSql -ErrorAction SilentlyContinue
$env:PGPASSWORD = $null

Write-Host "  Database initialized." -ForegroundColor Green

# ── Test ────────────────────────────────────────────────────────────────────

Write-Host "`nTesting endpoints..." -ForegroundColor Yellow

# Wait for Container App to start
Write-Host "  Waiting 60s for Container App to start..." -ForegroundColor Gray
Start-Sleep -Seconds 60

# Health check
try {
    $health = Invoke-RestMethod -Uri "$restEndpoint/health" -Method Get -TimeoutSec 30
    Write-Host "  REST health: $($health.status)" -ForegroundColor Green
} catch {
    Write-Host "  REST health check failed: $_" -ForegroundColor Red
    Write-Host "  (Container may still be starting — retry in a minute)" -ForegroundColor Yellow
}

# ── Output connection info ──────────────────────────────────────────────────

Write-Host "`n=== Connection Info ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "MCP Access Key: $mcpAccessKey" -ForegroundColor Yellow
Write-Host ""
Write-Host "VS Code (.vscode/mcp.json):" -ForegroundColor White
Write-Host @"
{
  "servers": {
    "openbrain": {
      "type": "sse",
      "url": "${mcpEndpoint}?key=${mcpAccessKey}"
    }
  }
}
"@ -ForegroundColor Gray

Write-Host ""
Write-Host "Copilot CLI:" -ForegroundColor White
Write-Host "  copilot --mcp openbrain=${mcpEndpoint}?key=${mcpAccessKey}" -ForegroundColor Gray

Write-Host ""
Write-Host "Test capture:" -ForegroundColor White
Write-Host "  curl -X POST $restEndpoint/memories -H 'Content-Type: application/json' -d '{`"content`": `"Test thought from Azure deployment`"}'" -ForegroundColor Gray

Write-Host ""
