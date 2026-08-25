$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerPath = Join-Path $here "install-ai-node.ps1"
$installerSource = Get-Content -LiteralPath $installerPath -Raw
$uninstallerSource = Get-Content -LiteralPath (Join-Path $here "uninstall-ai-node.ps1") -Raw
$tokens = $null
$errors = $null
$installerAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $installerPath,
    [ref]$tokens,
    [ref]$errors
)

Describe "Fitz-Net manual node startup" {
    It "does not register any at-logon task triggers" {
        $atLogonTriggers = @($installerAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq "New-ScheduledTaskTrigger" -and
                $node.Extent.Text -match "-AtLogOn"
        }, $true))

        $atLogonTriggers.Count | Should Be 0
    }

    It "registers Ollama and the console as demand-only tasks" {
        $registrations = @($installerAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq "Register-ScheduledTask"
        }, $true))

        $ollamaRegistration = @($registrations | Where-Object { $_.Extent.Text -match '\$OllamaTaskName' })
        $consoleRegistration = @($registrations | Where-Object { $_.Extent.Text -match '\$NodeConsoleTaskName' })

        $ollamaRegistration.Count | Should Be 1
        $ollamaRegistration[0].Extent.Text | Should Not Match "-Trigger"
        $consoleRegistration.Count | Should Be 1
        $consoleRegistration[0].Extent.Text | Should Not Match "-Trigger"
    }

    It "recreates older tasks so their logon triggers cannot survive an upgrade" {
        $unregistrations = @($installerAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq "Unregister-ScheduledTask"
        }, $true))

        @($unregistrations | Where-Object { $_.Extent.Text -match '\$OllamaTaskName' }).Count | Should Be 1
        @($unregistrations | Where-Object { $_.Extent.Text -match '\$NodeConsoleTaskName' }).Count | Should Be 1
    }

    It "stops Ollama before reporting initial readiness" {
        $stopIndex = $installerSource.IndexOf('Write-Step "Leaving the node runtime off"')
        $heartbeatIndex = $installerSource.IndexOf('Write-Step "Sending initial readiness heartbeat"')

        $stopIndex | Should BeGreaterThan -1
        $heartbeatIndex | Should BeGreaterThan $stopIndex
    }

    It "disables and restores vendor-created sign-in entries" {
        $installerSource | Should Match 'Move-Item[^\r\n]+\$ollamaNativeStartupPath[^\r\n]+\$ollamaNativeStartupBackupPath'
        $installerSource | Should Match 'Remove-ItemProperty[^\r\n]+\$interactiveUserRunPath[^\r\n]+"OpenVPN-GUI"'
        $uninstallerSource | Should Match "Restored Ollama's original sign-in shortcut"
        $uninstallerSource | Should Match "Restored OpenVPN GUI's original sign-in entry"
    }

    It "marks the desktop shortcut to run as administrator" {
        $installerSource | Should Match '\$shortcutBytes\[0x15\]\s*=\s*\$shortcutBytes\[0x15\]\s*-bor\s*0x20'
    }
}
