<#
.SYNOPSIS
    Connects, disconnects, or reports the Fitz-Net AI node's VPN status.

.DESCRIPTION
    Manual control for the Fitz-Net OpenVPN profile. Connect starts the VPN
    only for the current Windows session; the service remains Manual and the
    profile is moved out of config-auto again on Disconnect. With no -Action,
    an interactive menu is shown.
#>
[CmdletBinding()]
param(
    [ValidateSet("Connect", "Disconnect", "Status")]
    [string]$Action
)

$ErrorActionPreference = "Stop"
$interactiveInvocation = -not $Action

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdministrator) {
    $elevationArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Action) {
        $elevationArguments += " -Action $Action"
    }
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $elevationArguments
    exit
}

trap {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($interactiveInvocation) {
        Read-Host "Press Enter to close"
    }
    exit 1
}

$OpenVpnConfigAutoDir = "C:\Program Files\OpenVPN\config-auto"
$OpenVpnConfigDir = "C:\Program Files\OpenVPN\config"
$AutoProfilePath = Join-Path $OpenVpnConfigAutoDir "fitznet-node.ovpn"
$ManualProfilePath = Join-Path $OpenVpnConfigDir "fitznet-node.ovpn"
$HeartbeatScriptPath = "C:\ProgramData\FitzNetNode\heartbeat.ps1"
$NetworkHelperPath = Join-Path $PSScriptRoot "node-network.ps1"
$ServiceName = "OpenVPNService"

if (-not (Test-Path $NetworkHelperPath)) {
    throw "node-network.ps1 was not found next to this script. Re-run install-ai-node.ps1 to repair the installation."
}
. $NetworkHelperPath

function Get-FitzNetVpnStatus {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $vpnAddress = Get-VpnIPv4Address
    $profileLocation = if (Test-Path $AutoProfilePath) {
        "service"
    } elseif (Test-Path $ManualProfilePath) {
        "manual"
    } else {
        "missing"
    }

    return [pscustomobject]@{
        Connected = [bool]$vpnAddress
        Address = if ($vpnAddress) { $vpnAddress } else { "" }
        ServiceStatus = if ($service) { [string]$service.Status } else { "NotInstalled" }
        ServiceStartup = if ($service) { [string]$service.StartType } else { "NotInstalled" }
        ProfileLocation = $profileLocation
    }
}

function Write-FitzNetVpnStatus {
    $status = Get-FitzNetVpnStatus
    $connectionText = if ($status.Connected) { "CONNECTED ($($status.Address))" } else { "DISCONNECTED" }
    Write-Host "Fitz-Net VPN: $connectionText" -ForegroundColor $(if ($status.Connected) { "Green" } else { "Yellow" })
    Write-Host "OpenVPN service: $($status.ServiceStatus) (startup: $($status.ServiceStartup))"
    Write-Host "Profile location: $($status.ProfileLocation)"
}

if (-not $Action) {
    Write-Host ""
    Write-Host "Fitz-Net AI node VPN control" -ForegroundColor Cyan
    Write-Host "  1. Connect for this Windows session"
    Write-Host "  2. Disconnect"
    Write-Host "  3. Show status"
    $choice = Read-Host "Choose 1, 2, or 3"
    $Action = switch ($choice) {
        "1" { "Connect" }
        "2" { "Disconnect" }
        "3" { "Status" }
        default { throw "Invalid choice '$choice'." }
    }
}

switch ($Action) {
    "Connect" {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $service) {
            throw "OpenVPNService is not installed. Re-run install-ai-node.ps1 with VPN enabled."
        }
        if (-not (Test-Path $AutoProfilePath) -and -not (Test-Path $ManualProfilePath)) {
            throw "The Fitz-Net VPN profile is missing. Re-run install-ai-node.ps1 with the complete node package."
        }

        New-Item -ItemType Directory -Force -Path $OpenVpnConfigAutoDir | Out-Null
        if (Test-Path $ManualProfilePath) {
            Move-Item -LiteralPath $ManualProfilePath -Destination $AutoProfilePath -Force
        }
        Set-Service -Name $ServiceName -StartupType Manual
        if ($service.Status -eq "Running") {
            Restart-Service -Name $ServiceName
        } else {
            Start-Service -Name $ServiceName
        }

        $vpnAddress = $null
        for ($i = 0; $i -lt 15; $i++) {
            Start-Sleep -Seconds 2
            $vpnAddress = Get-VpnIPv4Address
            if ($vpnAddress) { break }
        }
        if (-not $vpnAddress) {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            if (Test-Path $AutoProfilePath) {
                New-Item -ItemType Directory -Force -Path $OpenVpnConfigDir | Out-Null
                Move-Item -LiteralPath $AutoProfilePath -Destination $ManualProfilePath -Force
            }
            throw "The VPN did not connect within 30 seconds. Check the OpenVPN logs and try again."
        }
        Write-Host "Fitz-Net VPN connected at $vpnAddress. It will not start automatically after a reboot." -ForegroundColor Green
    }

    "Disconnect" {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -ne "Stopped") {
                Stop-Service -Name $ServiceName -Force
            }
            Set-Service -Name $ServiceName -StartupType Manual
        }

        if (Test-Path $AutoProfilePath) {
            New-Item -ItemType Directory -Force -Path $OpenVpnConfigDir | Out-Null
            Move-Item -LiteralPath $AutoProfilePath -Destination $ManualProfilePath -Force
        }
        Write-Host "Fitz-Net VPN disconnected and disabled for startup." -ForegroundColor Green
    }

    "Status" {
        Write-FitzNetVpnStatus
    }
}

if ($Action -ne "Status" -and (Test-Path $HeartbeatScriptPath)) {
    & $HeartbeatScriptPath
}

if ($interactiveInvocation) {
    Read-Host "Press Enter to close"
}
