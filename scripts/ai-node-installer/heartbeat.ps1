<#
.SYNOPSIS
    Sends a heartbeat for this Fitz-Net AI node. Run on a schedule by the
    "FitzNetNodeHeartbeat" scheduled task created by install-ai-node.ps1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$NodeConfigPath = "C:\ProgramData\FitzNetNode\node.json"
$NetworkHelperPath = Join-Path $PSScriptRoot "node-network.ps1"

if (-not (Test-Path $NodeConfigPath)) {
    Write-Error "No node.json found at $NodeConfigPath - has this machine been registered? Run install-ai-node.ps1 first."
    exit 1
}

if (-not (Test-Path $NetworkHelperPath)) {
    Write-Error "No network helper found at $NetworkHelperPath - re-run install-ai-node.ps1 to repair this installation."
    exit 1
}

. $NetworkHelperPath

$config = Get-Content -Path $NodeConfigPath -Raw | ConvertFrom-Json

# Talk to Ollama's local HTTP API rather than shelling out to the ollama.exe
# CLI: this task runs as SYSTEM (so it works with nobody logged in), and
# Ollama's Windows installer only adds itself to the *current user's* PATH,
# not machine-wide - so `& ollama ...` silently fails to resolve here even
# though the Ollama server itself is still reachable over localhost.
$models = @()
$ollamaAvailable = $false
try {
    $tags = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 5 -ErrorAction Stop
    $models = @($tags.models | ForEach-Object { $_.name })
    $ollamaAvailable = $true
} catch {
    $models = @()
}

# The installed routing mode is deliberate. In particular, VPN mode must not
# fall back to a same-looking 192.168.x.x LAN address that the API cannot route
# to when the tunnel is down. Empty string intentionally clears any stale
# address already stored by fitz-net-api; JSON null would leave it unchanged.
$addressMode = if ($config.addressMode) { [string]$config.addressMode } else { "lan" }
$fixedAddress = if ($config.ollamaAddress) { [string]$config.ollamaAddress } else { "" }
$address = Get-OllamaAddress -AddressMode $addressMode -FixedAddress $fixedAddress

# ONLINE means the node can currently serve a chat, not merely that this task
# can reach the public heartbeat endpoint. Ollama must answer, expose a model,
# and have an address for the configured route.
$heartbeatState = Get-NodeHeartbeatState -OllamaAvailable $ollamaAvailable -Models $models -Address $address
$status = $heartbeatState.Status
$address = $heartbeatState.Address

$body = @{
    status  = $status
    models  = @($models)
    address = $address
} | ConvertTo-Json

try {
    Invoke-RestMethod -Method Post -Uri "$($config.apiBaseUrl)/node/heartbeat" `
        -Headers @{ "X-Node-Id" = $config.nodeId; "X-Node-Key" = $config.nodeKey } `
        -ContentType "application/json" -Body $body | Out-Null
} catch {
    Write-Warning "Heartbeat failed: $($_.Exception.Message)"
}
