<#
.SYNOPSIS
    Live status console for a Fitz-Net AI node.

.DESCRIPTION
    Shows Ollama and VPN health, offers manual Connect/Disconnect commands,
    and reports website-originated connections plus completed Ollama chat
    requests. Prompt and response content are never displayed or logged.
#>
[CmdletBinding()]
param(
    [switch]$Once,

    [ValidateRange(250, 10000)]
    [int]$RefreshMilliseconds = 1000,

    [Parameter(DontShow = $true)]
    [switch]$NoRun
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Fitz-Net AI Node"

$InstallDir = "C:\ProgramData\FitzNetNode"
$NodeConfigPath = Join-Path $InstallDir "node.json"
$NetworkHelperPath = Join-Path $PSScriptRoot "node-network.ps1"
$VpnManagerPath = Join-Path $PSScriptRoot "manage-ai-node-vpn.ps1"
$OllamaManagerPath = Join-Path $PSScriptRoot "manage-ai-node-ollama.ps1"
$HeartbeatPath = Join-Path $PSScriptRoot "heartbeat.ps1"
$WebsiteSourceAddresses = @("192.168.1.59", "10.180.53.1")
$OpenVpnServiceName = "OpenVPNService"

if (-not (Test-Path $NetworkHelperPath)) {
    throw "node-network.ps1 is missing. Re-run install-ai-node.ps1 to repair this node."
}
. $NetworkHelperPath

function ConvertFrom-OllamaChatLogLine {
    param([string]$Line)

    if ($Line -notmatch 'POST\s+"?/api/chat') {
        return $null
    }

    $status = "completed"
    $duration = ""
    if ($Line -match '\|\s*(?<status>\d{3})\s*\|\s*(?<duration>[^|]+?)\s*\|') {
        $status = $Matches.status
        $duration = $Matches.duration.Trim()
    }

    return [pscustomobject]@{
        Status = $status
        Duration = $duration
        Message = if ($duration) {
            "Chat completed - HTTP $status in $duration"
        } else {
            "Chat completed - HTTP $status"
        }
    }
}

function Get-WebsiteRequestConnectionKeys {
    param(
        [object[]]$Connections,
        [string[]]$SourceAddresses = $WebsiteSourceAddresses
    )

    return @($Connections |
        Where-Object {
            $_.LocalPort -eq 11434 -and
            $_.State -eq "Established" -and
            $_.RemoteAddress -in $SourceAddresses
        } |
        ForEach-Object { "$($_.RemoteAddress):$($_.RemotePort)" } |
        Sort-Object -Unique)
}

function Get-NodeConsoleSnapshot {
    $vpnAddress = Get-VpnIPv4Address
    $vpnService = Get-Service -Name $OpenVpnServiceName -ErrorAction SilentlyContinue

    $models = @()
    $ollamaOnline = $false
    try {
        $tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 2 -ErrorAction Stop
        $models = @($tags.models | ForEach-Object { $_.name })
        $ollamaOnline = $true
    } catch {
        $models = @()
    }

    $connections = @()
    try {
        $connections = @(Get-NetTCPConnection -LocalPort 11434 -State Established -ErrorAction Stop)
    } catch {
        $connections = @()
    }
    $requestKeys = Get-WebsiteRequestConnectionKeys -Connections $connections

    return [pscustomobject]@{
        VpnConnected = [bool]$vpnAddress
        VpnAddress = if ($vpnAddress) { $vpnAddress } else { "" }
        VpnServiceStatus = if ($vpnService) { [string]$vpnService.Status } else { "Not installed" }
        VpnStartup = if ($vpnService) { [string]$vpnService.StartType } else { "Not installed" }
        OllamaOnline = $ollamaOnline
        Models = $models
        RequestKeys = $requestKeys
    }
}

function Invoke-VpnControl {
    param([ValidateSet("Connect", "Disconnect")][string]$Action)

    if (-not (Test-Path $VpnManagerPath)) {
        throw "VPN manager is missing. Re-run install-ai-node.ps1 to repair this node."
    }

    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$VpnManagerPath`" -Action $Action"
    $process = Start-Process -FilePath "powershell.exe" -Verb RunAs `
        -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "VPN $Action failed with exit code $($process.ExitCode)."
    }
}

function Invoke-OllamaControl {
    param([ValidateSet("Start", "Stop")][string]$Action)

    if (-not (Test-Path $OllamaManagerPath)) {
        throw "Ollama manager is missing. Re-run install-ai-node.ps1 to repair this node."
    }

    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$OllamaManagerPath`" -Action $Action"
    $process = Start-Process -FilePath "powershell.exe" -Verb RunAs `
        -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Ollama $Action failed with exit code $($process.ExitCode)."
    }
}

function Write-StatusValue {
    param(
        [string]$Label,
        [string]$Value,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host ("  {0,-20}" -f $Label) -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Write-NodeConsole {
    param(
        [object]$Snapshot,
        [object[]]$Activity,
        [int]$RequestCount,
        [string]$NodeName
    )

    Clear-Host
    Write-Host (" " + " FITZ-NET AI NODE ".PadRight(61)) -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host ("  {0}" -f $NodeName) -ForegroundColor Cyan
    Write-Host ("  Updated {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -ForegroundColor DarkGray
    Write-Host ""

    $vpnText = if ($Snapshot.VpnConnected) {
        "CONNECTED  $($Snapshot.VpnAddress)"
    } else {
        "DISCONNECTED"
    }
    Write-StatusValue "Fitz-Net VPN" $vpnText $(if ($Snapshot.VpnConnected) { "Green" } else { "Yellow" })
    Write-StatusValue "VPN startup" "$($Snapshot.VpnStartup) (manual is expected)" $(if ($Snapshot.VpnStartup -eq "Manual") { "Green" } else { "Yellow" })
    Write-StatusValue "VPN service" $Snapshot.VpnServiceStatus $(if ($Snapshot.VpnServiceStatus -eq "Running") { "Green" } else { "DarkGray" })
    Write-StatusValue "Ollama" $(if ($Snapshot.OllamaOnline) { "ONLINE" } else { "OFFLINE" }) $(if ($Snapshot.OllamaOnline) { "Green" } else { "Red" })
    Write-StatusValue "Models" $(if ($Snapshot.Models.Count) { $Snapshot.Models -join ", " } else { "none detected" }) $(if ($Snapshot.Models.Count) { "Cyan" } else { "Yellow" })
    Write-StatusValue "Active web calls" ([string]$Snapshot.RequestKeys.Count) $(if ($Snapshot.RequestKeys.Count) { "Magenta" } else { "DarkGray" })
    Write-StatusValue "Calls this session" ([string]$RequestCount) "Gray"

    if ($Snapshot.VpnConnected) {
        Write-Host ""
        Write-Host "  OpenVPN GUI may still show 'Connect'." -ForegroundColor Yellow
        Write-Host "  The tunnel address above is the authoritative Fitz-Net status." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  RECENT ACTIVITY" -ForegroundColor White -BackgroundColor DarkBlue
    if ($Activity.Count -eq 0) {
        Write-Host "  Waiting for website requests..." -ForegroundColor DarkGray
    } else {
        foreach ($event in $Activity | Select-Object -Last 8) {
            Write-Host ("  [{0}] " -f $event.Time) -NoNewline -ForegroundColor DarkGray
            Write-Host $event.Message -ForegroundColor $event.Color
        }
    }

    Write-Host ""
    Write-Host "  [O] Start Ollama   " -NoNewline -ForegroundColor Green
    Write-Host "[X] Stop Ollama" -ForegroundColor Yellow
    Write-Host "  [C] Connect VPN   " -NoNewline -ForegroundColor Green
    Write-Host "[D] Disconnect VPN   " -NoNewline -ForegroundColor Yellow
    Write-Host "[R] Refresh   " -NoNewline -ForegroundColor Cyan
    Write-Host "[Q] Close console" -ForegroundColor Gray
    Write-Host "  Closing this window does not disconnect the VPN or stop Ollama." -ForegroundColor DarkGray
    Write-Host "  Request metadata only; prompts and responses are never shown." -ForegroundColor DarkGray
}

function Read-NewOllamaLogLines {
    param(
        [string]$Path,
        [ref]$Offset
    )

    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $stream = [System.IO.File]::Open($Path, "Open", "Read", "ReadWrite")
    try {
        if ($stream.Length -lt $Offset.Value) {
            $Offset.Value = 0L
        }
        [void]$stream.Seek($Offset.Value, [System.IO.SeekOrigin]::Begin)
        $reader = New-Object System.IO.StreamReader($stream)
        try {
            $content = $reader.ReadToEnd()
            $Offset.Value = $stream.Length
        } finally {
            $reader.Dispose()
        }
    } finally {
        $stream.Dispose()
    }

    if (-not $content) {
        return @()
    }
    return @($content -split "`r?`n" | Where-Object { $_ })
}

if ($NoRun) {
    return
}

$consoleMutex = New-Object System.Threading.Mutex($false, "Local\FitzNetNodeConsole")
if (-not $consoleMutex.WaitOne(0, $false)) {
    return
}

$config = if (Test-Path $NodeConfigPath) {
    Get-Content -LiteralPath $NodeConfigPath -Raw | ConvertFrom-Json
} else {
    $null
}
$nodeName = if ($config -and $config.nodeName) { [string]$config.nodeName } else { $env:COMPUTERNAME }
$ollamaLogPath = if ($config -and $config.ollamaLogPath) { [string]$config.ollamaLogPath } else { "" }
$activity = @()
$knownRequestKeys = @()
$requestCount = 0
$logOffset = 0L
if ($ollamaLogPath -and (Test-Path -LiteralPath $ollamaLogPath -PathType Leaf)) {
    $logOffset = (Get-Item -LiteralPath $ollamaLogPath).Length
}

function Add-ConsoleActivity {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    $script:activity += [pscustomobject]@{
        Time = Get-Date -Format "HH:mm:ss"
        Message = $Message
        Color = $Color
    }
    if ($script:activity.Count -gt 30) {
        $script:activity = @($script:activity | Select-Object -Last 30)
    }
}

do {
    $snapshot = Get-NodeConsoleSnapshot
    $newRequestKeys = @($snapshot.RequestKeys | Where-Object { $_ -notin $knownRequestKeys })
    foreach ($requestKey in $newRequestKeys) {
        $requestCount++
        Add-ConsoleActivity "Chat request received from the Fitz-Net website" "Magenta"
    }
    $knownRequestKeys = @($snapshot.RequestKeys)

    foreach ($line in (Read-NewOllamaLogLines -Path $ollamaLogPath -Offset ([ref]$logOffset))) {
        $chatEvent = ConvertFrom-OllamaChatLogLine -Line $line
        if ($chatEvent) {
            Add-ConsoleActivity $chatEvent.Message $(if ($chatEvent.Status -match '^2') { "Green" } else { "Red" })
        }
    }

    Write-NodeConsole -Snapshot $snapshot -Activity $activity -RequestCount $requestCount -NodeName $nodeName
    if ($Once) { break }

    $deadline = (Get-Date).AddMilliseconds($RefreshMilliseconds)
    do {
        Start-Sleep -Milliseconds 100
        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true).Key
                switch ($key) {
                    "O" {
                        Add-ConsoleActivity "Starting Ollama - approve the UAC prompt" "Yellow"
                        try {
                            Invoke-OllamaControl -Action Start
                            Add-ConsoleActivity "Ollama started" "Green"
                        } catch {
                            Add-ConsoleActivity "Ollama start failed: $($_.Exception.Message)" "Red"
                        }
                    }
                    "X" {
                        Add-ConsoleActivity "Stopping Ollama - approve the UAC prompt" "Yellow"
                        try {
                            Invoke-OllamaControl -Action Stop
                            Add-ConsoleActivity "Ollama stopped" "Green"
                        } catch {
                            Add-ConsoleActivity "Ollama stop failed: $($_.Exception.Message)" "Red"
                        }
                    }
                    "C" {
                        Add-ConsoleActivity "Connecting VPN - approve the UAC prompt" "Yellow"
                        try {
                            Invoke-VpnControl -Action Connect
                            Add-ConsoleActivity "VPN connected" "Green"
                        } catch {
                            Add-ConsoleActivity "VPN connect failed: $($_.Exception.Message)" "Red"
                        }
                    }
                    "D" {
                        Add-ConsoleActivity "Disconnecting VPN - approve the UAC prompt" "Yellow"
                        try {
                            Invoke-VpnControl -Action Disconnect
                            Add-ConsoleActivity "VPN disconnected" "Green"
                        } catch {
                            Add-ConsoleActivity "VPN disconnect failed: $($_.Exception.Message)" "Red"
                        }
                    }
                    "R" { $deadline = Get-Date }
                    "Q" { return }
                }
            }
        } catch {
            # KeyAvailable can fail in redirected/non-console hosts; refresh-only
            # mode is still useful there.
        }
    } while ((Get-Date) -lt $deadline)
} while ($true)
