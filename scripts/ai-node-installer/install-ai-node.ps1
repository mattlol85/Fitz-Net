#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Frictionless installer for a Fitz-Net AI worker node.

.DESCRIPTION
    Installs Ollama, opens it up to the local network, registers this machine
    as an AI node with fitz-net-api using a one-time enrollment token, and
    schedules a recurring heartbeat task. Optionally installs the OpenVPN
    client and the bundled OpenVPN profile too (you're asked up front) - the
    node works for local/LAN chat routing with or without the VPN.

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
    instance (e.g. "192.168.1.50:11434"). This fixed override is persisted
    and reused by every heartbeat. If omitted, the selected VPN or LAN route
    is detected each heartbeat.

.PARAMETER InstallVpn
    Whether to install/configure OpenVPN on this PC at all ("yes"/"no"). If
    omitted, you'll be asked up front. Choose "no" to skip OpenVPN entirely -
    the node still registers and works for local/LAN chat routing either
    way; the VPN is groundwork for a later phase (reaching a node that's
    remote, off your LAN). Some people would rather not have OpenVPN
    installed on their PC at all.

.PARAMETER AutoStartVpn
    Whether the OpenVPN profile should connect automatically every time this
    PC boots ("yes"/"no"). Only asked if -InstallVpn is "yes". The safe
    default is "no": the tunnel starts disconnected and can be controlled
    later with manage-ai-node-vpn.ps1. "yes" is an explicit opt-in that keeps
    the VPN active in the background and reconnects it after every boot.

.EXAMPLE
    .\install-ai-node.ps1 -Token "abc123..." -NodeName "brother-pc"
#>
[CmdletBinding()]
param(
    [string]$Token,
    [string]$NodeName = $env:COMPUTERNAME,
    [string]$ApiBaseUrl = "https://api.fitznet.doomdns.org",
    [string]$OllamaAddress,
    [string]$InstallVpn,
    [string]$AutoStartVpn
)

$ErrorActionPreference = "Stop"

$InstallDir = "C:\ProgramData\FitzNetNode"
$NodeConfigPath = Join-Path $InstallDir "node.json"
$OvpnSourcePath = Join-Path $PSScriptRoot "node.ovpn"
$OpenVpnConfigAutoDir = "C:\Program Files\OpenVPN\config-auto"
$OpenVpnConfigDir = "C:\Program Files\OpenVPN\config"
$HeartbeatScriptPath = Join-Path $InstallDir "heartbeat.ps1"
$NetworkHelperSourcePath = Join-Path $PSScriptRoot "node-network.ps1"
$NetworkHelperInstallPath = Join-Path $InstallDir "node-network.ps1"
$VpnManagerSourcePath = Join-Path $PSScriptRoot "manage-ai-node-vpn.ps1"
$VpnManagerInstallPath = Join-Path $InstallDir "manage-ai-node-vpn.ps1"
$OllamaLauncherSourcePath = Join-Path $PSScriptRoot "start-ollama.ps1"
$OllamaLauncherInstallPath = Join-Path $InstallDir "start-ollama.ps1"
$NodeConsoleSourcePath = Join-Path $PSScriptRoot "node-console.ps1"
$NodeConsoleInstallPath = Join-Path $InstallDir "node-console.ps1"
$VpnApiHostAddress = "192.168.1.59"
$HeartbeatTaskName = "FitzNetNodeHeartbeat"
$OllamaTaskName = "FitzNetOllamaServe"
$NodeConsoleTaskName = "FitzNetNodeConsole"
$LegacyFirewallRuleName = "Fitz-Net Ollama"
$LanFirewallRuleName = "Fitz-Net Ollama (LAN)"
$VpnFirewallRuleName = "Fitz-Net Ollama (VPN)"

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


if (-not (Test-Path $NetworkHelperSourcePath)) {
    throw "node-network.ps1 was not found next to the installer. Re-download the complete installer package."
}
if (-not (Test-Path $OllamaLauncherSourcePath)) {
    throw "start-ollama.ps1 was not found next to the installer. Re-download the complete installer package."
}
if (-not (Test-Path $NodeConsoleSourcePath)) {
    throw "node-console.ps1 was not found next to the installer. Re-download the complete installer package."
}
. $NetworkHelperSourcePath

$existingConfig = $null
if (Test-Path $NodeConfigPath) {
    $existingConfig = Get-Content -Path $NodeConfigPath -Raw | ConvertFrom-Json
}

# -- 0. Choose the persistent routing mode ------------------------------------
if (-not $InstallVpn) {
    if ($existingConfig -and $existingConfig.addressMode -eq "vpn") {
        $InstallVpn = "yes"
    } elseif ($existingConfig -and $existingConfig.addressMode -eq "lan") {
        $InstallVpn = "no"
    } elseif ($existingConfig -and $existingConfig.addressMode -eq "fixed") {
        $hasInstalledProfile = (Test-Path (Join-Path $OpenVpnConfigAutoDir "fitznet-node.ovpn")) -or
            (Test-Path (Join-Path $OpenVpnConfigDir "fitznet-node.ovpn"))
        $InstallVpn = if ($hasInstalledProfile) { "yes" } else { "no" }
    } else {
        $InstallVpn = Read-Host "Install/connect the Fitz-Net OpenVPN profile on this PC? (yes/no)"
    }
}
$installVpn = $InstallVpn -match '^(y|yes)$'
$addressMode = if ($OllamaAddress) { "fixed" } elseif ($installVpn) { "vpn" } else { "lan" }
if (-not $OllamaAddress -and $existingConfig -and $existingConfig.addressMode -eq "fixed") {
    $addressMode = "fixed"
    $OllamaAddress = [string]$existingConfig.ollamaAddress
}

if ($installVpn -and -not (Test-Path $OvpnSourcePath)) {
    throw "VPN installation was selected, but node.ovpn is missing next to this script. Re-download a complete per-node package or re-run with -InstallVpn no for a LAN-only node."
}
if ($installVpn -and -not (Test-Path $VpnManagerSourcePath)) {
    throw "VPN installation was selected, but manage-ai-node-vpn.ps1 is missing next to this script. Re-download the complete installer package."
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# -- 1. Ollama ------------------------------------------------------------------
Write-Step "Checking for Ollama"
$interactiveUser = (Get-CimInstance Win32_ComputerSystem).UserName
if ([string]::IsNullOrWhiteSpace($interactiveUser)) {
    throw "No signed-in desktop user was found. Sign in as the person who owns the Ollama models, then re-run this installer as Administrator."
}

try {
    $interactiveSid = (New-Object System.Security.Principal.NTAccount($interactiveUser)).Translate(
        [System.Security.Principal.SecurityIdentifier]
    ).Value
} catch {
    throw "Could not resolve the signed-in user '$interactiveUser': $($_.Exception.Message)"
}

$interactiveProfile = Get-CimInstance Win32_UserProfile |
    Where-Object { $_.SID -eq $interactiveSid } |
    Select-Object -First 1
if (-not $interactiveProfile -or [string]::IsNullOrWhiteSpace($interactiveProfile.LocalPath)) {
    throw "Could not locate the Windows profile for signed-in user '$interactiveUser'."
}

$interactiveProfilePath = $interactiveProfile.LocalPath
$ollamaLogPath = Join-Path $interactiveProfilePath "AppData\Local\FitzNetNode\ollama.log"
$consoleShortcutPath = Join-Path $interactiveProfilePath "Desktop\Fitz-Net AI Node Console.lnk"
$windowsTerminalPath = Join-Path $interactiveProfilePath "AppData\Local\Microsoft\WindowsApps\wt.exe"
$ollamaExecutable = $null
$ollamaCandidates = @(
    (Join-Path $interactiveProfilePath "AppData\Local\Programs\Ollama\ollama.exe"),
    (Join-Path $interactiveProfilePath "AppData\Local\Ollama\ollama.exe")
)
$ollamaExecutable = $ollamaCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1

if ($ollamaExecutable) {
    Write-Skip "Ollama already installed for $interactiveUser."
} else {
    $wingetPath = Join-Path $interactiveProfilePath "AppData\Local\Microsoft\WindowsApps\winget.exe"
    if (-not (Test-Path -LiteralPath $wingetPath -PathType Leaf)) {
        throw "Ollama is not installed for '$interactiveUser', and that user's winget.exe could not be found. Install Ollama while signed in as that user, then re-run this installer."
    }

    Write-Host "    Installing Ollama for $interactiveUser via winget..."
    $installTaskName = "FitzNetInstallOllama-$([guid]::NewGuid().ToString('N'))"
    $installAction = New-ScheduledTaskAction -Execute $wingetPath -Argument "install --id Ollama.Ollama --silent --accept-package-agreements --accept-source-agreements"
    $installTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)
    $installPrincipal = New-ScheduledTaskPrincipal -UserId $interactiveUser -LogonType Interactive -RunLevel Limited
    $installSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    try {
        Register-ScheduledTask -TaskName $installTaskName -Action $installAction -Trigger $installTrigger `
            -Principal $installPrincipal -Settings $installSettings -ErrorAction Stop | Out-Null
        $installRequestedAt = Get-Date
        Start-ScheduledTask -TaskName $installTaskName

        $installDeadline = (Get-Date).AddMinutes(10)
        do {
            Start-Sleep -Seconds 2
            $installTask = Get-ScheduledTask -TaskName $installTaskName
            $installInfo = Get-ScheduledTaskInfo -TaskName $installTaskName
            $installHasRun = $installInfo.LastRunTime -ge $installRequestedAt.AddSeconds(-5)
        } while ((-not $installHasRun -or $installTask.State -eq "Running") -and (Get-Date) -lt $installDeadline)

        if (-not $installHasRun -or $installTask.State -eq "Running") {
            throw "Ollama installation did not finish within 10 minutes."
        }
        $installResult = $installInfo.LastTaskResult
        if ($installResult -ne 0) {
            throw "winget could not install Ollama for '$interactiveUser' (task result 0x$($installResult.ToString('X8')))."
        }
    } finally {
        Stop-ScheduledTask -TaskName $installTaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $installTaskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    $ollamaExecutable = $ollamaCandidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $ollamaExecutable) {
        throw "Ollama installation completed, but ollama.exe could not be found in '$interactiveProfilePath'."
    }
    Write-Success "Ollama installed for $interactiveUser."
}

# -- 2. OpenVPN client ------------------------------------------------------------
Write-Step "Checking for OpenVPN client"
if (-not $installVpn) {
    Write-Skip "Skipped - you opted out of OpenVPN for this PC."
} else {
    $openVpnInstalled = Test-Path "C:\Program Files\OpenVPN\bin\openvpn.exe"
    if ($openVpnInstalled) {
        Write-Skip "OpenVPN client already installed."
    } else {
        Write-Host "    Installing OpenVPN client via winget..."
        winget install --id OpenVPNTechnologies.OpenVPN --silent --accept-package-agreements --accept-source-agreements
        Write-Success "OpenVPN client installed."
    }
}

# -- 3. OpenVPN profile ---------------------------------------------------------
Write-Step "Installing OpenVPN profile"
if (-not $installVpn) {
    Write-Skip "Skipped - you opted out of OpenVPN for this PC."
    Write-Skip "The node still registers and works for local/LAN chat routing without it."
} else {
    if (-not $AutoStartVpn) {
        Write-Host "    The recommended default is NO: the VPN stays off until you run the control script." -ForegroundColor Yellow
        Write-Host "    YES keeps the VPN active in the background and reconnects it automatically after every boot." -ForegroundColor Yellow
        $AutoStartVpn = Read-Host "Enable VPN auto-start? Type yes to opt in, or press Enter for no"
    }
    $autoStart = $AutoStartVpn -match '^(y|yes)$'

    if ($autoStart) {
        Write-Host "    WARNING: VPN auto-start explicitly enabled; the tunnel will stay active and reconnect after boot." -ForegroundColor Yellow
        New-Item -ItemType Directory -Force -Path $OpenVpnConfigAutoDir | Out-Null
        $destOvpn = Join-Path $OpenVpnConfigAutoDir "fitznet-node.ovpn"
        Copy-Item -Path $OvpnSourcePath -Destination $destOvpn -Force
        Set-SplitTunnelProfile -ProfilePath $destOvpn -ApiHostAddress $VpnApiHostAddress
        Remove-Item -Path (Join-Path $OpenVpnConfigDir "fitznet-node.ovpn") -Force -ErrorAction SilentlyContinue
        Write-Success "Installed a split-tunnel profile at $destOvpn (auto-connects as a service on boot)."

        $service = Get-Service -Name "OpenVPNService" -ErrorAction SilentlyContinue
        if ($service) {
            Set-Service -Name "OpenVPNService" -StartupType Automatic
            if ($service.Status -ne "Running") {
                Start-Service -Name "OpenVPNService"
            } else {
                Restart-Service -Name "OpenVPNService"
            }
            Write-Success "OpenVPN service is running and set to start automatically."

            # Give the tunnel time to establish. An auto-start VPN node must
            # not register against a LAN fallback if this connection fails.
            $vpnUp = $false
            for ($i = 0; $i -lt 15; $i++) {
                Start-Sleep -Seconds 2
                if (Get-VpnIPv4Address) { $vpnUp = $true; break }
            }
            if ($vpnUp) {
                Write-Success "VPN tunnel is up."
            } else {
                throw "The VPN tunnel did not receive an IPv4 address within 30 seconds. Check the OpenVPN service/logs, then re-run this installer. The node was not registered."
            }
        } else {
            throw "OpenVPNService was not found after installing OpenVPN. Reboot once, then re-run this installer. The node was not registered."
        }
    } else {
        New-Item -ItemType Directory -Force -Path $OpenVpnConfigDir | Out-Null
        $destOvpn = Join-Path $OpenVpnConfigDir "fitznet-node.ovpn"
        Copy-Item -Path $OvpnSourcePath -Destination $destOvpn -Force
        Set-SplitTunnelProfile -ProfilePath $destOvpn -ApiHostAddress $VpnApiHostAddress
        $autoProfilePath = Join-Path $OpenVpnConfigAutoDir "fitznet-node.ovpn"
        if (Test-Path $autoProfilePath) {
            Remove-Item -Path $autoProfilePath -Force
        }
        $service = Get-Service -Name "OpenVPNService" -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -ne "Stopped") {
                Stop-Service -Name "OpenVPNService" -Force
            }
            Set-Service -Name "OpenVPNService" -StartupType Manual
        }
        Write-Success "Installed a split-tunnel profile at $destOvpn with the VPN disconnected and startup disabled."
        Write-Host "    To connect later: run C:\ProgramData\FitzNetNode\manage-ai-node-vpn.ps1 as Administrator." -ForegroundColor Yellow
        Write-Host "    This node will report OFFLINE until the VPN is connected." -ForegroundColor Yellow
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
Copy-Item -Path $OllamaLauncherSourcePath -Destination $OllamaLauncherInstallPath -Force
Write-Success "Updated the Ollama background launcher."

Write-Host "    Replacing the Ollama startup task..." -ForegroundColor DarkGray
$ollamaAction = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$OllamaLauncherInstallPath`" -OllamaExecutable `"$ollamaExecutable`" -LogPath `"$ollamaLogPath`""
$ollamaTrigger = New-ScheduledTaskTrigger -AtLogOn -User $interactiveUser
$ollamaPrincipal = New-ScheduledTaskPrincipal -UserId $interactiveUser -LogonType Interactive -RunLevel Limited
$ollamaSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Days 3650) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$existingOllamaTask = Get-ScheduledTask -TaskName $OllamaTaskName -ErrorAction SilentlyContinue
if ($existingOllamaTask) {
    Stop-ScheduledTask -TaskName $OllamaTaskName -ErrorAction SilentlyContinue
}
Register-ScheduledTask -TaskName $OllamaTaskName -Action $ollamaAction -Trigger $ollamaTrigger `
    -Principal $ollamaPrincipal -Settings $ollamaSettings -Force -ErrorAction Stop | Out-Null

Write-Host "    Stopping the previous Ollama process..." -ForegroundColor DarkGray
Get-Process -Name "ollama*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Success "Set OLLAMA_HOST=0.0.0.0 and configured Ollama to run as $interactiveUser."

Start-Sleep -Seconds 1
Write-Host "    Starting Ollama and waiting up to 30 seconds for its API..." -ForegroundColor DarkGray
try {
    Start-ScheduledTask -TaskName $OllamaTaskName -ErrorAction Stop
} catch {
    throw "Ollama could not be started as '$interactiveUser': $($_.Exception.Message)"
}

$ollamaBackUp = $false
for ($i = 0; $i -lt 15; $i++) {
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
    Write-Success "Ollama was restarted as $interactiveUser and is reachable."
} else {
    throw "Ollama did not become reachable within 30 seconds after starting it as '$interactiveUser'. Check Task Scheduler task '$OllamaTaskName' and the Ollama logs, then re-run this installer."
}

# Replace the legacy profile-only rule with a route-specific rule. VPN
# adapters are often classified Public by Windows, so the VPN rule is scoped
# to the actual adapter aliases rather than a mutable network category.
Get-NetFirewallRule -DisplayName $LegacyFirewallRuleName -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

if ($installVpn) {
    Get-NetFirewallRule -DisplayName $LanFirewallRuleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
    $vpnAliases = @(Get-VpnInterfaceAliases)
    if ($vpnAliases.Count -eq 0) {
        throw "No OpenVPN/TAP adapter was found, so a safe VPN-scoped firewall rule could not be created. Repair OpenVPN and re-run this installer."
    }
    Get-NetFirewallRule -DisplayName $VpnFirewallRuleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $VpnFirewallRuleName -Direction Inbound -Protocol TCP `
        -LocalPort 11434 -Action Allow -Profile Any -InterfaceAlias $vpnAliases | Out-Null
    Write-Success "Opened inbound TCP 11434 on the OpenVPN adapter only."
} else {
    Get-NetFirewallRule -DisplayName $VpnFirewallRuleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
    Get-NetFirewallRule -DisplayName $LanFirewallRuleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $LanFirewallRuleName -Direction Inbound -Protocol TCP `
        -LocalPort 11434 -Action Allow -Profile Private | Out-Null
    Write-Success "Opened inbound TCP 11434 on Private networks."
}

$detectedAddress = Get-OllamaAddress -AddressMode $addressMode -FixedAddress $OllamaAddress
if ($addressMode -eq "fixed") {
    Write-Skip "Using persistent -OllamaAddress: $detectedAddress"
} elseif ($detectedAddress) {
    Write-Success "Detected $($addressMode.ToUpperInvariant()) address: $detectedAddress"
} else {
    Write-Host "    No $addressMode address is currently available; the node will report OFFLINE until one appears." -ForegroundColor Yellow
}

# -- 6. Register the node ------------------------------------------------------
Write-Step "Registering node with fitz-net-api"
if (Test-Path $NodeConfigPath) {
    Write-Skip "node.json already exists at $NodeConfigPath - preserving the existing registration."
} else {
    if (-not $Token) {
        $Token = Read-Host "Enter the enrollment token given to you"
    }
    if ([string]::IsNullOrWhiteSpace($Token)) {
        throw "An enrollment token is required for a new registration."
    }

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

    $registrationAddress = if ($installedModels.Count -gt 0) { $detectedAddress } else { "" }

    $body = @{
        token   = $Token
        name    = $NodeName
        os      = "Windows"
        models  = @($installedModels)
        vramGb  = $vramGb
        address = $registrationAddress
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Method Post -Uri "$ApiBaseUrl/node/register" `
            -ContentType "application/json" -Body $body -ErrorAction Stop
    } catch {
        $statusCode = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        if ($statusCode -eq 401) {
            throw "The enrollment token was rejected. Generate a new token on the Fitz-Net website and re-run the installer within 30 minutes. Enrollment tokens can only be used once."
        }

        throw
    }

    $nodeConfig = @{
        nodeId     = $response.nodeId
        nodeKey    = $response.nodeKey
        apiBaseUrl = $ApiBaseUrl
        nodeName   = $NodeName
        addressMode = $addressMode
        ollamaAddress = if ($addressMode -eq "fixed") { $OllamaAddress } else { "" }
        ollamaOwner = $interactiveUser
        ollamaLogPath = $ollamaLogPath
        consoleShortcutPath = $consoleShortcutPath
    } | ConvertTo-Json

    Set-Content -Path $NodeConfigPath -Value $nodeConfig -Encoding UTF8
    Write-Success "Registered as node '$NodeName' (id: $($response.nodeId))."
}

# Persist the routing choice for both new and existing registrations. This is
# what prevents a scheduled heartbeat from overwriting a fixed/VPN address
# with an unrelated LAN address after the installer exits.
$nodeConfig = Get-Content -Path $NodeConfigPath -Raw | ConvertFrom-Json
$nodeConfig | Add-Member -NotePropertyName addressMode -NotePropertyValue $addressMode -Force
$nodeConfig | Add-Member -NotePropertyName ollamaAddress `
    -NotePropertyValue $(if ($addressMode -eq "fixed") { $OllamaAddress } else { "" }) -Force
$nodeConfig | Add-Member -NotePropertyName ollamaOwner -NotePropertyValue $interactiveUser -Force
$nodeConfig | Add-Member -NotePropertyName ollamaLogPath -NotePropertyValue $ollamaLogPath -Force
$nodeConfig | Add-Member -NotePropertyName consoleShortcutPath -NotePropertyValue $consoleShortcutPath -Force
$nodeConfig | ConvertTo-Json | Set-Content -Path $NodeConfigPath -Encoding UTF8
Write-Success "Saved routing mode '$addressMode' for future heartbeats."

# -- 7. Heartbeat script + scheduled task --------------------------------------
Write-Step "Setting up recurring heartbeat"
Copy-Item -Path (Join-Path $PSScriptRoot "heartbeat.ps1") -Destination $HeartbeatScriptPath -Force
Copy-Item -Path $NetworkHelperSourcePath -Destination $NetworkHelperInstallPath -Force
Copy-Item -Path $NodeConsoleSourcePath -Destination $NodeConsoleInstallPath -Force
if ($installVpn) {
    Copy-Item -Path $VpnManagerSourcePath -Destination $VpnManagerInstallPath -Force
}

$existingConsoleTask = Get-ScheduledTask -TaskName $NodeConsoleTaskName -ErrorAction SilentlyContinue
if ($existingConsoleTask) {
    Stop-ScheduledTask -TaskName $NodeConsoleTaskName -ErrorAction SilentlyContinue
}
# A previous Explorer/Terminal launch outlives its short scheduled-task action.
# Stop only consoles running our installed script so an installer re-run can
# replace an older hidden instance instead of losing to the single-instance lock.
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains($NodeConsoleInstallPath) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
$consoleAction = New-ScheduledTaskAction -Execute "explorer.exe" -Argument "`"$consoleShortcutPath`""
$consoleTrigger = New-ScheduledTaskTrigger -AtLogOn -User $interactiveUser
$consolePrincipal = New-ScheduledTaskPrincipal -UserId $interactiveUser -LogonType Interactive -RunLevel Limited
$consoleSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Days 3650)
Register-ScheduledTask -TaskName $NodeConsoleTaskName -Action $consoleAction -Trigger $consoleTrigger `
    -Principal $consolePrincipal -Settings $consoleSettings -Force -ErrorAction Stop | Out-Null
Write-Success "Configured the visible node console to open for $interactiveUser at sign-in."

if (Test-Path -LiteralPath (Split-Path -Parent $consoleShortcutPath)) {
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($consoleShortcutPath)
    if (Test-Path -LiteralPath $windowsTerminalPath -PathType Leaf) {
        # Explicitly use Windows Terminal. Launching powershell.exe indirectly
        # from Task Scheduler can otherwise create a headless pseudo-console
        # when Windows Terminal is configured as the default terminal host.
        $shortcut.TargetPath = $windowsTerminalPath
        $shortcut.Arguments = "-w new new-tab --title `"Fitz-Net AI Node`" powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$NodeConsoleInstallPath`""
    } else {
        $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$NodeConsoleInstallPath`""
    }
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = "Fitz-Net AI node status and VPN controls"
    $shortcut.WindowStyle = 1
    $shortcut.Save()
    Write-Success "Created desktop shortcut 'Fitz-Net AI Node Console'."
}

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

Write-Step "Sending initial readiness heartbeat"
& $HeartbeatScriptPath
Write-Success "Reported the node's current chat readiness."

Write-Step "Done"
Write-Host "    This machine is now registered as a Fitz-Net AI node." -ForegroundColor Green
Write-Host "    Check the Status tab at fitznet.org to see it come online." -ForegroundColor Green
if ($installVpn -and -not $autoStart) {
    Write-Host "    VPN is OFF and will stay off after reboot. Run the installed VPN control script when you want to make this node available." -ForegroundColor Yellow
}
Write-Host "    The status console opens now and at sign-in; it never connects the VPN automatically." -ForegroundColor Cyan
try {
    Start-ScheduledTask -TaskName $NodeConsoleTaskName -ErrorAction Stop
} catch {
    Write-Host "    WARNING: the node console could not be opened automatically. Use the desktop shortcut instead." -ForegroundColor Yellow
}
