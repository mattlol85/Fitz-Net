<#
.SYNOPSIS
    Starts, stops, or reports the Fitz-Net node's Ollama status.

.DESCRIPTION
    Manual control for the demand-only FitzNetOllamaServe scheduled task.
    Neither this script nor the installer adds a Windows startup trigger.
#>
[CmdletBinding()]
param(
    [ValidateSet("Start", "Stop", "Status")]
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
    $process = Start-Process -FilePath "powershell.exe" -Verb RunAs `
        -ArgumentList $elevationArguments -Wait -PassThru
    exit $process.ExitCode
}

trap {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($interactiveInvocation) {
        Read-Host "Press Enter to close"
    }
    exit 1
}

$TaskName = "FitzNetOllamaServe"
$HeartbeatScriptPath = "C:\ProgramData\FitzNetNode\heartbeat.ps1"

function Test-OllamaApi {
    try {
        $tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 3 -ErrorAction Stop
        return [pscustomobject]@{
            Online = $true
            Models = @($tags.models | ForEach-Object { $_.name })
        }
    } catch {
        return [pscustomobject]@{ Online = $false; Models = @() }
    }
}

function Write-OllamaStatus {
    $status = Test-OllamaApi
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Write-Host "Ollama: $(if ($status.Online) { 'ONLINE' } else { 'OFFLINE' })" `
        -ForegroundColor $(if ($status.Online) { "Green" } else { "Yellow" })
    Write-Host "Task: $(if ($task) { $task.State } else { 'Not installed' })"
    Write-Host "Models: $(if ($status.Models.Count) { $status.Models -join ', ' } else { 'none detected' })"
}

if (-not $Action) {
    Write-Host ""
    Write-Host "Fitz-Net AI node Ollama control" -ForegroundColor Cyan
    Write-Host "  1. Start Ollama"
    Write-Host "  2. Stop Ollama"
    Write-Host "  3. Show status"
    $choice = Read-Host "Choose 1, 2, or 3"
    $Action = switch ($choice) {
        "1" { "Start" }
        "2" { "Stop" }
        "3" { "Status" }
        default { throw "Invalid choice '$choice'." }
    }
}

switch ($Action) {
    "Start" {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $task) {
            throw "The '$TaskName' task is missing. Re-run install-ai-node.ps1 to repair this node."
        }

        $status = Test-OllamaApi
        if (-not $status.Online) {
            if ($task.State -eq "Running") {
                Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
            }
            Start-ScheduledTask -TaskName $TaskName
            for ($i = 0; $i -lt 15; $i++) {
                Start-Sleep -Seconds 2
                $status = Test-OllamaApi
                if ($status.Online) { break }
            }
        }

        if (-not $status.Online) {
            throw "Ollama did not become reachable within 30 seconds. Check the Ollama logs and try again."
        }
        Write-Host "Ollama started. Models: $($status.Models -join ', ')" -ForegroundColor Green
    }

    "Stop" {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Get-Process -Name "ollama*" -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host "Ollama stopped. It will stay off after reboot." -ForegroundColor Green
    }

    "Status" {
        Write-OllamaStatus
    }
}

if ($Action -ne "Status" -and (Test-Path $HeartbeatScriptPath)) {
    & $HeartbeatScriptPath
}

if ($interactiveInvocation) {
    Read-Host "Press Enter to close"
}
