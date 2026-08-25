$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "node-network.ps1")

Describe "Fitz-Net AI node address selection" {
    It "selects a connected OpenVPN address in VPN mode" {
        Mock Get-NetIPAddress {
            @(
                [pscustomobject]@{ IPAddress = "192.168.1.85"; InterfaceAlias = "Wi-Fi"; InterfaceIndex = 12; AddressState = "Preferred" },
                [pscustomobject]@{ IPAddress = "10.8.0.23"; InterfaceAlias = "OpenVPN Data Channel Offload"; InterfaceIndex = 50; AddressState = "Preferred" }
            )
        }

        Get-OllamaAddress -AddressMode vpn | Should Be "10.8.0.23:11434"
    }

    It "does not fall back to LAN when VPN mode has no tunnel address" {
        Mock Get-NetIPAddress {
            @([pscustomobject]@{ IPAddress = "192.168.1.85"; InterfaceAlias = "Wi-Fi"; InterfaceIndex = 12; AddressState = "Preferred" })
        }

        Get-OllamaAddress -AddressMode vpn | Should Be ""
    }

    It "excludes VPN, virtual, loopback, and APIPA addresses in LAN mode" {
        Mock Get-NetIPAddress {
            @(
                [pscustomobject]@{ IPAddress = "127.0.0.1"; InterfaceAlias = "Loopback"; InterfaceIndex = 1; AddressState = "Preferred" },
                [pscustomobject]@{ IPAddress = "169.254.1.2"; InterfaceAlias = "Ethernet"; InterfaceIndex = 2; AddressState = "Preferred" },
                [pscustomobject]@{ IPAddress = "172.20.0.1"; InterfaceAlias = "vEthernet (Default Switch)"; InterfaceIndex = 3; AddressState = "Preferred" },
                [pscustomobject]@{ IPAddress = "10.8.0.23"; InterfaceAlias = "TAP-Windows Adapter"; InterfaceIndex = 4; AddressState = "Preferred" },
                [pscustomobject]@{ IPAddress = "192.168.1.85"; InterfaceAlias = "Wi-Fi"; InterfaceIndex = 12; AddressState = "Preferred" }
            )
        }

        Get-OllamaAddress -AddressMode lan | Should Be "192.168.1.85:11434"
    }

    It "returns the persistent fixed address without adapter detection" {
        Mock Get-NetIPAddress { throw "Adapter detection should not run" }

        Get-OllamaAddress -AddressMode fixed -FixedAddress " 10.9.0.7:11434 " | Should Be "10.9.0.7:11434"
    }

    It "finds VPN firewall aliases by adapter description" {
        Mock Get-NetAdapter {
            @(
                [pscustomobject]@{ Name = "Ethernet 2"; InterfaceDescription = "TAP-Windows Adapter V9" },
                [pscustomobject]@{ Name = "Wi-Fi"; InterfaceDescription = "Qualcomm Wireless" }
            )
        }

        @(Get-VpnInterfaceAliases) | Should Be @("Ethernet 2")
    }
}

Describe "Fitz-Net AI node heartbeat readiness" {
    It "reports ONLINE only when Ollama, a model, and the route are available" {
        $state = Get-NodeHeartbeatState -OllamaAvailable $true -Models @("llama3.2:latest") -Address "10.8.0.23:11434"

        $state.Status | Should Be "ONLINE"
        $state.Address | Should Be "10.8.0.23:11434"
    }

    It "clears the address when the selected route is unavailable" {
        $state = Get-NodeHeartbeatState -OllamaAvailable $true -Models @("llama3.2:latest") -Address ""

        $state.Status | Should Be "OFFLINE"
        $state.Address | Should Be ""
    }

    It "clears the address when Ollama is unavailable" {
        $state = Get-NodeHeartbeatState -OllamaAvailable $false -Models @() -Address "10.8.0.23:11434"

        $state.Status | Should Be "OFFLINE"
        $state.Address | Should Be ""
    }

    It "reports OFFLINE when Ollama has no installed model" {
        $state = Get-NodeHeartbeatState -OllamaAvailable $true -Models @() -Address "10.8.0.23:11434"

        $state.Status | Should Be "OFFLINE"
        $state.Address | Should Be ""
    }
}

Describe "Fitz-Net OpenVPN split-tunnel profile" {
    It "removes full-tunnel directives and keeps only the API host route" {
        $profilePath = Join-Path $TestDrive "node.ovpn"
        @(
            "client"
            "redirect-gateway def1"
            "route-nopull"
            "route 192.168.1.59 255.255.255.255"
            "<ca>"
            "certificate-data"
            "</ca>"
        ) | Set-Content -Path $profilePath -Encoding ASCII

        Set-SplitTunnelProfile -ProfilePath $profilePath
        $result = Get-Content -Path $profilePath

        @($result | Where-Object { $_ -eq "route-nopull" }).Count | Should Be 1
        @($result | Where-Object { $_ -eq "route 192.168.1.59 255.255.255.255 vpn_gateway" }).Count | Should Be 1
        @($result | Where-Object { $_ -eq "route 192.168.1.59 255.255.255.255" }).Count | Should Be 0
        @($result | Where-Object { $_ -match "^redirect-gateway" }).Count | Should Be 0
        @($result | Where-Object { $_ -eq "certificate-data" }).Count | Should Be 1
    }

    It "rejects a non-IPv4 API host address" {
        $profilePath = Join-Path $TestDrive "invalid.ovpn"
        "client" | Set-Content -Path $profilePath -Encoding ASCII

        { Set-SplitTunnelProfile -ProfilePath $profilePath -ApiHostAddress "not-an-ip" } | Should Throw
    }
}
