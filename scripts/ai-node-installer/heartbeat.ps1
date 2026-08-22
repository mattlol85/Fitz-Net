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
    Write-Error "No node.json found at $NodeConfigPath — has this machine been registered? Run install-ai-node.ps1 first."
    exit 1
}

$config = Get-Content -Path $NodeConfigPath -Raw | ConvertFrom-Json

$models = @()
try {
    $models = (& ollama list | Select-Object -Skip 1 | ForEach-Object { ($_ -split '\s+')[0] }) | Where-Object { $_ }
} catch {
    $models = @()
}

$status = "ONLINE"
try {
    $ollamaPs = & ollama ps 2>$null
    if ($ollamaPs -and ($ollamaPs | Select-Object -Skip 1)) {
        $status = "BUSY"
    }
} catch {
    # ollama not reachable locally; still report ONLINE since the node itself is up
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
