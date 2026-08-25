param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$OllamaExecutable
)

$ErrorActionPreference = "Stop"
$env:OLLAMA_HOST = "0.0.0.0"

& $OllamaExecutable serve
exit $LASTEXITCODE
