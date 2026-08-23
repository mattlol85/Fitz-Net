<#
.SYNOPSIS
    Sends a heartbeat for this Fitz-Net AI node. Run on a schedule by the
    "FitzNetNodeHeartbeat" scheduled task created by install-ai-node.ps1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$NodeConfigPath = "C:\ProgramData\FitzNetNode\node.json"

if (-not (Test-Path $NodeConfigPath)) {
    Write-Error "No node.json found at $NodeConfigPath - has this machine been registered? Run install-ai-node.ps1 first."
    exit 1
}

$config = Get-Content -Path $NodeConfigPath -Raw | ConvertFrom-Json

# Talk to Ollama's local HTTP API rather than shelling out to the ollama.exe
# CLI: this task runs as SYSTEM (so it works with nobody logged in), and
# Ollama's Windows installer only adds itself to the *current user's* PATH,
# not machine-wide - so `& ollama ...` silently fails to resolve here even
# though the Ollama server itself is still reachable over localhost.
$models = @()
try {
    $tags = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 5 -ErrorAction Stop
    $models = @($tags.models | ForEach-Object { $_.name })
} catch {
    $models = @()
}

$status = "ONLINE"
try {
    $running = Invoke-RestMethod -Uri "http://localhost:11434/api/ps" -Method Get -TimeoutSec 5 -ErrorAction Stop
    if ($running.models -and $running.models.Count -gt 0) {
        $status = "BUSY"
    }
} catch {
    # Ollama not reachable locally; still report ONLINE since the node itself is up
}

$body = @{
    status = $status
    models = @($models)
} | ConvertTo-Json

try {
    Invoke-RestMethod -Method Post -Uri "$($config.apiBaseUrl)/node/heartbeat" `
        -Headers @{ "X-Node-Id" = $config.nodeId; "X-Node-Key" = $config.nodeKey } `
        -ContentType "application/json" -Body $body | Out-Null
} catch {
    Write-Warning "Heartbeat failed: $($_.Exception.Message)"
}
