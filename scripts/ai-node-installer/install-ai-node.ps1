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

.EXAMPLE
    .\install-ai-node.ps1 -Token "abc123..." -NodeName "brother-pc"
#>
[CmdletBinding()]
param(
    [string]$Token,
    [string]$NodeName = $env:COMPUTERNAME,
    [string]$ApiBaseUrl = "https://api.fitznet.doomdns.org"
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

# ── 0. Prompt for token if not supplied ─────────────────────────────────────
if (-not $Token) {
    $Token = Read-Host "Enter the enrollment token given to you"
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "An enrollment token is required."
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# ── 1. Ollama ────────────────────────────────────────────────────────────────
Write-Step "Checking for Ollama"
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-Skip "Ollama already installed."
} else {
    Write-Host "    Installing Ollama via winget..."
    winget install --id Ollama.Ollama --silent --accept-package-agreements --accept-source-agreements
    Write-Success "Ollama installed."
}

# ── 2. OpenVPN client ────────────────────────────────────────────────────────
Write-Step "Checking for OpenVPN client"
$openVpnInstalled = Test-Path "C:\Program Files\OpenVPN\bin\openvpn.exe"
if ($openVpnInstalled) {
    Write-Skip "OpenVPN client already installed."
} else {
    Write-Host "    Installing OpenVPN client via winget..."
    winget install --id OpenVPNTechnologies.OpenVPN --silent --accept-package-agreements --accept-source-agreements
    Write-Success "OpenVPN client installed."
}

# ── 3. OpenVPN profile (auto-start service, no GUI needed) ─────────────────
Write-Step "Installing OpenVPN profile"
if (-not (Test-Path $OvpnSourcePath)) {
    Write-Host "    WARNING: node.ovpn not found next to this script — skipping VPN setup." -ForegroundColor Yellow
    Write-Host "    The node will still register, but won't have a VPN tunnel until you add the profile and re-run this script." -ForegroundColor Yellow
} else {
    New-Item -ItemType Directory -Force -Path $OpenVpnConfigAutoDir | Out-Null
    $destOvpn = Join-Path $OpenVpnConfigAutoDir "fitznet-node.ovpn"
    Copy-Item -Path $OvpnSourcePath -Destination $destOvpn -Force
    Write-Success "Profile copied to $destOvpn (auto-starts as a service on boot)."

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
        Write-Host "    WARNING: OpenVPNService not found — you may need to reboot or start it manually from the OpenVPN GUI." -ForegroundColor Yellow
    }
}

# ── 4. Best-effort GPU detection ────────────────────────────────────────────
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

# ── 5. Register the node ────────────────────────────────────────────────────
Write-Step "Registering node with fitz-net-api"
if (Test-Path $NodeConfigPath) {
    Write-Skip "node.json already exists at $NodeConfigPath — skipping registration."
    Write-Skip "Delete that file and re-run this script if you need to re-register."
} else {
    $installedModels = @()
    $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($ollamaCmd) {
        try {
            $installedModels = (& ollama list | Select-Object -Skip 1 | ForEach-Object { ($_ -split '\s+')[0] }) | Where-Object { $_ }
        } catch {
            $installedModels = @()
        }
    }

    $body = @{
        token   = $Token
        name    = $NodeName
        os      = "Windows"
        models  = @($installedModels)
        vramGb  = $vramGb
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

# ── 6. Heartbeat script + scheduled task ────────────────────────────────────
Write-Step "Setting up recurring heartbeat"
Copy-Item -Path (Join-Path $PSScriptRoot "heartbeat.ps1") -Destination $HeartbeatScriptPath -Force

$existingTask = Get-ScheduledTask -TaskName $HeartbeatTaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Skip "Scheduled task '$HeartbeatTaskName' already exists."
} else {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$HeartbeatScriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration ([TimeSpan]::MaxValue)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $HeartbeatTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
    Write-Success "Scheduled task '$HeartbeatTaskName' created (runs every 2 minutes)."
}

Write-Step "Done"
Write-Host "    This machine is now registered as a Fitz-Net AI node." -ForegroundColor Green
Write-Host "    Check the Status tab at fitznet.org to see it come online." -ForegroundColor Green
