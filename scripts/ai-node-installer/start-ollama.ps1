param(
    [Parameter(Mandatory = $true)]
    [string]$OllamaExecutable,

    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

$ErrorActionPreference = "Stop"
$env:OLLAMA_HOST = "0.0.0.0"

$logDirectory = Split-Path -Parent $LogPath
$stderrLogPath = "$LogPath.stderr"
$launchErrorPath = "$LogPath.launch-error"

try {
    New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
    Remove-Item -LiteralPath $launchErrorPath -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $OllamaExecutable -PathType Leaf)) {
        throw "Ollama executable was not found at '$OllamaExecutable'."
    }

    foreach ($path in @($LogPath, $stderrLogPath)) {
        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 10MB) {
            Move-Item -LiteralPath $path -Destination "$path.previous" -Force
        }
    }

    $process = Start-Process -FilePath $OllamaExecutable -ArgumentList "serve" -NoNewWindow `
        -RedirectStandardError $stderrLogPath -RedirectStandardOutput $LogPath -Wait -PassThru
    exit $process.ExitCode
} catch {
    $_ | Out-String | Set-Content -LiteralPath $launchErrorPath -Encoding UTF8
    exit 1
}
