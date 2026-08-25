#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Cleanly removes everything install-ai-node.ps1 set up on this PC.

.DESCRIPTION
    Deregisters this node from fitz-net-api (best-effort), removes the
    heartbeat scheduled task and C:\ProgramData\FitzNetNode\, reverts the
    OLLAMA_HOST environment variable and removes the firewall rule opened
    for it, and removes any Fitz-Net OpenVPN profile files. Does NOT
    uninstall Ollama or the OpenVPN client themselves - only the Fitz-Net
    specific configuration this installer added.

    Safe to re-run: every step checks whether there's anything to remove
    before acting.

.EXAMPLE
    .\uninstall-ai-node.ps1
#>
[CmdletBinding()]
param()

$InstallDir = "C:\ProgramData\FitzNetNode"
$NodeConfigPath = Join-Path $InstallDir "node.json"
$HeartbeatTaskName = "FitzNetNodeHeartbeat"
$OllamaTaskName = "FitzNetOllamaServe"
$NodeConsoleTaskName = "FitzNetNodeConsole"
$FirewallRuleNames = @(
    "Fitz-Net Ollama",
    "Fitz-Net Ollama (LAN)",
    "Fitz-Net Ollama (VPN)"
)
$OpenVpnConfigAutoDir = "C:\Program Files\OpenVPN\config-auto"
$OpenVpnConfigDir = "C:\Program Files\OpenVPN\config"

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

# -- 1. Deregister from fitz-net-api (best-effort) -----------------------------
Write-Step "Deregistering from fitz-net-api"
$config = $null
if (Test-Path $NodeConfigPath) {
    try {
        $config = Get-Content -Path $NodeConfigPath -Raw | ConvertFrom-Json
        Invoke-RestMethod -Method Delete -Uri "$($config.apiBaseUrl)/node/$($config.nodeId)" `
            -Headers @{ "X-Node-Key" = $config.nodeKey } -ErrorAction Stop | Out-Null
        Write-Success "Removed from the node registry (id: $($config.nodeId))."
    } catch {
        Write-Host "    WARNING: couldn't deregister ($($_.Exception.Message)) - continuing with local cleanup anyway." -ForegroundColor Yellow
    }
} else {
    Write-Skip "No node.json found - nothing to deregister."
}

# -- 2. Heartbeat and console scheduled tasks -----------------------------------
Write-Step "Removing heartbeat and node console tasks"
foreach ($taskName in @($HeartbeatTaskName, $NodeConsoleTaskName)) {
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Success "Removed scheduled task '$taskName'."
    } else {
        Write-Skip "Scheduled task '$taskName' was not present."
    }
}

$installedConsolePath = Join-Path $InstallDir "node-console.ps1"
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains($installedConsolePath) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

if ($config -and $config.consoleShortcutPath) {
    $shortcutPath = [System.IO.Path]::GetFullPath([string]$config.consoleShortcutPath)
    $expectedSuffix = "\Desktop\Fitz-Net AI Node Console.lnk"
    if ($shortcutPath.StartsWith("C:\Users\", [System.StringComparison]::OrdinalIgnoreCase) -and
        $shortcutPath.EndsWith($expectedSuffix, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $shortcutPath)) {
        Remove-Item -LiteralPath $shortcutPath -Force
        Write-Success "Removed the Fitz-Net node console desktop shortcut."
    }
}

# -- 3. Ollama scheduled task ----------------------------------------------------
Write-Step "Removing Fitz-Net Ollama task"
$ollamaTask = Get-ScheduledTask -TaskName $OllamaTaskName -ErrorAction SilentlyContinue
if ($ollamaTask) {
    Stop-ScheduledTask -TaskName $OllamaTaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $OllamaTaskName -Confirm:$false
    Write-Success "Removed scheduled task '$OllamaTaskName'."
} else {
    Write-Skip "No Fitz-Net Ollama task found."
}

# -- 4. Local node files ---------------------------------------------------------
Write-Step "Removing local node files"
if (Test-Path $InstallDir) {
    Remove-Item -Path $InstallDir -Recurse -Force
    Write-Success "Removed $InstallDir."
} else {
    Write-Skip "$InstallDir doesn't exist - nothing to remove."
}

# -- 5. OLLAMA_HOST + firewall rule ----------------------------------------------
Write-Step "Reverting Ollama network exposure"
$currentValue = [Environment]::GetEnvironmentVariable("OLLAMA_HOST", "Machine")
if ($currentValue) {
    [Environment]::SetEnvironmentVariable("OLLAMA_HOST", $null, "Machine")
    Get-Process -Name "ollama*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Success "Removed the machine-wide OLLAMA_HOST setting and restarted Ollama (now localhost-only again)."
    Write-Host "    NOTE: if Ollama doesn't relaunch on its own, open it from the Start Menu." -ForegroundColor Yellow
} else {
    Write-Skip "OLLAMA_HOST wasn't set - nothing to revert."
}

$removedRule = $false
foreach ($firewallRuleName in $FirewallRuleNames) {
    $existingRule = Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue
    if ($existingRule) {
        Remove-NetFirewallRule -DisplayName $firewallRuleName
        Write-Success "Removed firewall rule '$firewallRuleName'."
        $removedRule = $true
    }
}
if (-not $removedRule) {
    Write-Skip "No Fitz-Net Ollama firewall rules found."
}

# -- 6. OpenVPN profile -----------------------------------------------------------
Write-Step "Removing OpenVPN profile"
$ovpnLocations = @(
    (Join-Path $OpenVpnConfigAutoDir "fitznet-node.ovpn"),
    (Join-Path $OpenVpnConfigDir "fitznet-node.ovpn")
)
$removedAny = $false
foreach ($path in $ovpnLocations) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Force
        Write-Success "Removed $path."
        $removedAny = $true
    }
}
if (-not $removedAny) {
    Write-Skip "No Fitz-Net OpenVPN profile found - nothing to remove."
} else {
    $service = Get-Service -Name "OpenVPNService" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Restart-Service -Name "OpenVPNService"
        Write-Success "Restarted OpenVPNService so the removed profile drops."
    }
}
Write-Host "    NOTE: the OpenVPN client software itself was left installed (in case you use it for anything else)." -ForegroundColor Yellow

Write-Step "Done"
Write-Host "    This PC's Fitz-Net AI node setup has been removed." -ForegroundColor Green
