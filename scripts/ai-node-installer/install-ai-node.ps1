#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Frictionless installer for a Fitz-Net AI worker node.

.DESCRIPTION
    Installs Ollama and the OpenVPN client (if missing), drops in the bundled
    OpenVPN profile so it auto-connects as a Windows service, registers this
    machine as an AI node with fitz-net-api using a one-time enrollment token,
    and schedules a recurring heartbeat task.

    Safe to re-run: every step checks whether it's already done before acting.

.PARAMETER Token
    The one-time enrollment token generated on the Fitz-Net website
    (POST /node/enrollment-token). If omitted, you'll be prompted.

.PARAMETER NodeName
    A friendly name for this node (e.g. "brother-pc"). Defaults to the
    machine's hostname if omitted.

.PARAMETER ApiBaseUrl
    Base URL of fitz-net-api. Defaults to the production API.

.PARAMETER OllamaAddress
    "host:port" that fitz-net-api should use to reach this node's Ollama
    instance (e.g. "192.168.1.50:11434"). If omitted, auto-detected from
    this machine's LAN IPv4 address. Only needed as an override if
    auto-detection picks the wrong network adapter.

.PARAMETER AutoStartVpn
    Whether the OpenVPN profile should connect automatically every time this
    PC boots ("yes"/"no"). If omitted, you'll be asked. Choose "no" if you'd
    rather this PC's VPN tunnel only be active when you deliberately start it
    yourself (via the OpenVPN GUI) - some people don't want a VPN silently
    up in the background all the time.

.EXAMPLE
    .\install-ai-node.ps1 -Token "abc123..." -NodeName "brother-pc"
#>
[CmdletBinding()]
param(
    [string]$Token,
    [string]$NodeName = $env:COMPUTERNAME,
    [string]$ApiBaseUrl = "https://api.fitznet.doomdns.org",
    [string]$OllamaAddress,
    [string]$AutoStartVpn
)

$ErrorActionPreference = "Stop"

$InstallDir = "C:\ProgramData\FitzNetNode"
$NodeConfigPath = Join-Path $InstallDir "node.json"
$OvpnSourcePath = Join-Path $PSScriptRoot "node.ovpn"
$OpenVpnConfigAutoDir = "C:\Program Files\OpenVPN\config-auto"
$HeartbeatScriptPath = Join-Path $InstallDir "heartbeat.ps1"
$HeartbeatTaskName = "FitzNetNodeHeartbeat"

function Write-Step($message) {
    Write-Host ""
    Write-Host "==> $message" -ForegroundColor Cyan
}

function Write-Success($message) {
    Write-Host "    $message" -ForegroundColor Green
}

function Write-Skip($message) {
    Write-Host "    $message" -ForegroundColor DarkGray
}

function Get-LanIPv4Address {
    $candidate = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -ne "127.0.0.1" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.InterfaceAlias -notmatch "Loopback|OpenVPN|TAP|vEthernet"
        } |
        Select-Object -First 1
    if ($candidate) { return $candidate.IPAddress }
    return $null
}

# -- 0. Prompt for token if not supplied --------------------------------------
if (-not $Token) {
    $Token = Read-Host "Enter the enrollment token given to you"
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "An enrollment token is required."
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# -- 1. Ollama ------------------------------------------------------------------
Write-Step "Checking for Ollama"
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-Skip "Ollama already installed."
} else {
    Write-Host "    Installing Ollama via winget..."
    winget install --id Ollama.Ollama --silent --accept-package-agreements --accept-source-agreements
    Write-Success "Ollama installed."
}

# -- 2. OpenVPN client ------------------------------------------------------------
Write-Step "Checking for OpenVPN client"
$openVpnInstalled = Test-Path "C:\Program Files\OpenVPN\bin\openvpn.exe"
if ($openVpnInstalled) {
    Write-Skip "OpenVPN client already installed."
} else {
    Write-Host "    Installing OpenVPN client via winget..."
    winget install --id OpenVPNTechnologies.OpenVPN --silent --accept-package-agreements --accept-source-agreements
    Write-Success "OpenVPN client installed."
}

# -- 3. OpenVPN profile ---------------------------------------------------------
Write-Step "Installing OpenVPN profile"
if (-not (Test-Path $OvpnSourcePath)) {
    Write-Host "    WARNING: node.ovpn not found next to this script - skipping VPN setup." -ForegroundColor Yellow
    Write-Host "    The node will still register, but won't have a VPN tunnel until you add the profile and re-run this script." -ForegroundColor Yellow
} else {
    if (-not $AutoStartVpn) {
        $AutoStartVpn = Read-Host "Connect the VPN automatically every time this PC boots? (yes/no)"
    }
    $autoStart = $AutoStartVpn -match '^(y|yes)$'

    if ($autoStart) {
        New-Item -ItemType Directory -Force -Path $OpenVpnConfigAutoDir | Out-Null
        $destOvpn = Join-Path $OpenVpnConfigAutoDir "fitznet-node.ovpn"
        Copy-Item -Path $OvpnSourcePath -Destination $destOvpn -Force
        Write-Success "Profile copied to $destOvpn (auto-connects as a service on boot)."

        $service = Get-Service -Name "OpenVPNService" -ErrorAction SilentlyContinue
        if ($service) {
            Set-Service -Name "OpenVPNService" -StartupType Automatic
            if ($service.Status -ne "Running") {
                Start-Service -Name "OpenVPNService"
            } else {
                Restart-Service -Name "OpenVPNService"
            }
            Write-Success "OpenVPN service is running and set to start automatically."
        } else {
            Write-Host "    WARNING: OpenVPNService not found - you may need to reboot or start it manually from the OpenVPN GUI." -ForegroundColor Yellow
        }
    } else {
        $manualConfigDir = "C:\Program Files\OpenVPN\config"
        New-Item -ItemType Directory -Force -Path $manualConfigDir | Out-Null
        $destOvpn = Join-Path $manualConfigDir "fitznet-node.ovpn"
        Copy-Item -Path $OvpnSourcePath -Destination $destOvpn -Force
        Write-Success "Profile copied to $destOvpn (does NOT auto-connect)."
        Write-Host "    To connect: open the OpenVPN GUI, right-click its tray icon, and choose 'fitznet-node' > Connect." -ForegroundColor Yellow
    }
}

# -- 4. Best-effort GPU detection --------------------------------------------
Write-Step "Detecting GPU"
$vramGb = $null
$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidiaSmi) {
    try {
        $memMiB = (& nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | Select-Object -First 1).Trim()
        $vramGb = [math]::Round([double]$memMiB / 1024, 1)
        Write-Success "Detected GPU with ${vramGb} GB VRAM."
    } catch {
        Write-Skip "nvidia-smi present but VRAM detection failed; continuing without it."
    }
} else {
    Write-Skip "nvidia-smi not found; continuing without GPU info."
}

# -- 5. Enable remote access to Ollama -----------------------------------------
Write-Step "Enabling remote access to Ollama"
[Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0", "Machine")
$env:OLLAMA_HOST = "0.0.0.0"
Get-Process -Name "ollama*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Success "Set OLLAMA_HOST=0.0.0.0 (machine-wide)."

# Give whatever relaunches Ollama (its own tray-app supervisor, if present) a
# few seconds, then confirm it's actually back up before moving on - the next
# step queries this same endpoint for the installed model list.
$ollamaBackUp = $false
for ($i = 0; $i -lt 5; $i++) {
    Start-Sleep -Seconds 2
    try {
        Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 3 -ErrorAction Stop | Out-Null
        $ollamaBackUp = $true
        break
    } catch {
        continue
    }
}
if ($ollamaBackUp) {
    Write-Success "Ollama is back up and reachable."
} else {
    Write-Host "    WARNING: Ollama didn't come back up on its own - open it from the Start Menu, or sign out/in or reboot once, then re-run this script." -ForegroundColor Yellow
}

$firewallRuleName = "Fitz-Net Ollama"
$existingRule = Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue
if ($existingRule) {
    Write-Skip "Firewall rule '$firewallRuleName' already exists."
} else {
    New-NetFirewallRule -DisplayName $firewallRuleName -Direction Inbound -Protocol TCP -LocalPort 11434 -Action Allow -Profile Private | Out-Null
    Write-Success "Opened inbound TCP 11434 (Private network profile only)."
}

if ($OllamaAddress) {
    Write-Skip "Using provided -OllamaAddress: $OllamaAddress"
} else {
    $lanIp = Get-LanIPv4Address
    if ($lanIp) {
        $OllamaAddress = "${lanIp}:11434"
        Write-Success "Detected LAN address: $OllamaAddress"
    } else {
        Write-Host "    WARNING: could not auto-detect a LAN IPv4 address - fitz-net-api won't be able to reach this node's Ollama until you re-run with -OllamaAddress." -ForegroundColor Yellow
    }
}

# -- 6. Register the node ------------------------------------------------------
Write-Step "Registering node with fitz-net-api"
if (Test-Path $NodeConfigPath) {
    Write-Skip "node.json already exists at $NodeConfigPath - skipping registration."
    Write-Skip "Delete that file and re-run this script if you need to re-register."
} else {
    # Query Ollama's local HTTP API rather than shelling out to ollama.exe -
    # see the matching note in heartbeat.ps1 for why (PATH isn't reliable
    # for every context this can run in).
    $installedModels = @()
    try {
        $tags = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 5 -ErrorAction Stop
        $installedModels = @($tags.models | ForEach-Object { $_.name })
    } catch {
        $installedModels = @()
    }

    $body = @{
        token   = $Token
        name    = $NodeName
        os      = "Windows"
        models  = @($installedModels)
        vramGb  = $vramGb
        address = $OllamaAddress
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Method Post -Uri "$ApiBaseUrl/node/register" -ContentType "application/json" -Body $body

    $nodeConfig = @{
        nodeId     = $response.nodeId
        nodeKey    = $response.nodeKey
        apiBaseUrl = $ApiBaseUrl
        nodeName   = $NodeName
    } | ConvertTo-Json

    Set-Content -Path $NodeConfigPath -Value $nodeConfig -Encoding UTF8
    Write-Success "Registered as node '$NodeName' (id: $($response.nodeId))."
}

# -- 7. Heartbeat script + scheduled task --------------------------------------
Write-Step "Setting up recurring heartbeat"
Copy-Item -Path (Join-Path $PSScriptRoot "heartbeat.ps1") -Destination $HeartbeatScriptPath -Force

$existingTask = Get-ScheduledTask -TaskName $HeartbeatTaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Skip "Scheduled task '$HeartbeatTaskName' already exists."
} else {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$HeartbeatScriptPath`""
    # NOTE: [TimeSpan]::MaxValue (~29,247 years) serializes to an ISO-8601
    # duration Task Scheduler's XML schema rejects ("out of range"). 10 years
    # is effectively "forever" for this purpose and stays within range.
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration (New-TimeSpan -Days 3650)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $HeartbeatTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -ErrorAction Stop | Out-Null
    Write-Success "Scheduled task '$HeartbeatTaskName' created (runs every 2 minutes)."
}

Write-Step "Done"
Write-Host "    This machine is now registered as a Fitz-Net AI node." -ForegroundColor Green
Write-Host "    Check the Status tab at fitznet.org to see it come online." -ForegroundColor Green
