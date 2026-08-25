$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$iconPath = Join-Path $here "node-console-icon.ico"
$sourcePath = Join-Path $here "node-console-icon.png"
$installerSource = Get-Content -LiteralPath (Join-Path $here "install-ai-node.ps1") -Raw

Describe "Fitz-Net node console robot icon" {
    It "contains valid multi-resolution Windows icon entries" {
        $bytes = [System.IO.File]::ReadAllBytes($iconPath)

        [BitConverter]::ToUInt16($bytes, 0) | Should Be 0
        [BitConverter]::ToUInt16($bytes, 2) | Should Be 1
        $count = [BitConverter]::ToUInt16($bytes, 4)
        $count | Should Be 7

        $dimensions = @()
        for ($i = 0; $i -lt $count; $i++) {
            $entryOffset = 6 + (16 * $i)
            $dimension = [int]$bytes[$entryOffset]
            if ($dimension -eq 0) { $dimension = 256 }
            $dimensions += $dimension

            $imageLength = [BitConverter]::ToUInt32($bytes, $entryOffset + 8)
            $imageOffset = [BitConverter]::ToUInt32($bytes, $entryOffset + 12)
            (($imageOffset + $imageLength) -le $bytes.Length) | Should Be $true
        }

        $dimensions -join "," | Should Be "16,24,32,48,64,128,256"
    }

    It "renders through the Windows icon decoder" {
        Add-Type -AssemblyName System.Drawing
        $icon = New-Object System.Drawing.Icon($iconPath, 64, 64)
        try {
            $bitmap = $icon.ToBitmap()
            try {
                $bitmap.Width | Should Be 64
                $bitmap.Height | Should Be 64
            } finally {
                $bitmap.Dispose()
            }
        } finally {
            $icon.Dispose()
        }
    }

    It "keeps transparent source art and assigns the installed icon" {
        Add-Type -AssemblyName System.Drawing
        $source = [System.Drawing.Image]::FromFile($sourcePath)
        try {
            $source.PixelFormat.ToString() | Should Match "Argb"
        } finally {
            $source.Dispose()
        }

        $installerSource | Should Match '\$shortcut\.IconLocation\s*=\s*"\$NodeConsoleIconInstallPath,0"'
    }
}
