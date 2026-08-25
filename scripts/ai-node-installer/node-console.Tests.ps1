$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "node-console.ps1") -NoRun

Describe "Fitz-Net node console request activity" {
    It "parses an Ollama chat completion without exposing request content" {
        $line = '[GIN] 2026/08/24 - 21:55:02 | 200 | 12.345s | 192.168.1.59 | POST "/api/chat"'

        $event = ConvertFrom-OllamaChatLogLine -Line $line

        $event.Status | Should Be "200"
        $event.Duration | Should Be "12.345s"
        $event.Message | Should Be "Chat completed - HTTP 200 in 12.345s"
        ($event.PSObject.Properties.Name -contains "Prompt") | Should Be $false
    }

    It "ignores non-chat Ollama access log lines" {
        $line = '[GIN] 2026/08/24 - 21:55:02 | 200 | 1ms | 127.0.0.1 | GET "/api/tags"'

        ConvertFrom-OllamaChatLogLine -Line $line | Should BeNullOrEmpty
    }

    It "detects only established website connections to Ollama" {
        $connections = @(
            [pscustomobject]@{ LocalPort=11434; State="Established"; RemoteAddress="192.168.1.59"; RemotePort=51001 },
            [pscustomobject]@{ LocalPort=11434; State="TimeWait"; RemoteAddress="192.168.1.59"; RemotePort=51002 },
            [pscustomobject]@{ LocalPort=11434; State="Established"; RemoteAddress="127.0.0.1"; RemotePort=51003 },
            [pscustomobject]@{ LocalPort=8080; State="Established"; RemoteAddress="192.168.1.59"; RemotePort=51004 },
            [pscustomobject]@{ LocalPort=11434; State="Established"; RemoteAddress="10.180.53.1"; RemotePort=51005 }
        )

        $keys = @(Get-WebsiteRequestConnectionKeys -Connections $connections)

        $keys.Count | Should Be 2
        ($keys -contains "192.168.1.59:51001") | Should Be $true
        ($keys -contains "10.180.53.1:51005") | Should Be $true
    }
}

Describe "Fitz-Net node console elevation" {
    It "requests administrator elevation once when launching the console" {
        Mock Test-Path { $true }
        Mock Start-Process { return $null }

        Start-ElevatedNodeConsole

        Assert-MockCalled Start-Process 1 -ParameterFilter { $Verb -eq "RunAs" }
    }

    It "reuses an elevated console without another RunAs prompt" {
        $script:IsAdministrator = $true
        Mock Test-Path { $true }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        Invoke-NodeControl -ScriptPath "C:\ProgramData\FitzNetNode\manager.ps1" `
            -Action "Start" -Component "Test"

        Assert-MockCalled Start-Process 1 -ParameterFilter {
            $WindowStyle -eq "Hidden" -and -not $Verb
        }
    }
}
