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

# No BUSY detection: Ollama's /api/ps lists models currently loaded into
# memory, not ones actively generating a response - a model stays "loaded"
# for several minutes after each use (its keep-alive window) even while
# completely idle, so that endpoint can't actually tell "busy" from "warm
# and idle". Rather than report a wrong status, just report ONLINE.
$status = "ONLINE"

# Re-detect the address each cycle in case DHCP handed out a new lease, the
# VPN (re)connected since the last cycle, etc. Prefer the VPN address - it's
# the only one reachable from fitz-net-api for a node that isn't on the same
# LAN as it - falling back to the LAN address for a node that is.
$vpnCandidate = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -ne "127.0.0.1" -and
        $_.IPAddress -notlike "169.254.*" -and
        $_.InterfaceAlias -match "OpenVPN|TAP"
    } |
    Select-Object -First 1

if ($vpnCandidate) {
    # Windows can silently reclassify a VPN adapter back to "Public" after a
    # reconnect or reboot, which would make the firewall rule (scoped to
    # Private) stop applying to it. Self-heal this every cycle rather than
    # letting it break again unnoticed.
    $vpnProfile = Get-NetConnectionProfile -InterfaceIndex $vpnCandidate.InterfaceIndex -ErrorAction SilentlyContinue
    if ($vpnProfile -and $vpnProfile.NetworkCategory -ne "Private") {
        Set-NetConnectionProfile -InterfaceIndex $vpnCandidate.InterfaceIndex -NetworkCategory Private -ErrorAction SilentlyContinue
    }
    $address = "$($vpnCandidate.IPAddress):11434"
} else {
    $lanCandidate = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -ne "127.0.0.1" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.InterfaceAlias -notmatch "Loopback|OpenVPN|TAP|vEthernet"
        } |
        Select-Object -First 1
    $address = if ($lanCandidate) { "$($lanCandidate.IPAddress):11434" } else { $null }
}

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
