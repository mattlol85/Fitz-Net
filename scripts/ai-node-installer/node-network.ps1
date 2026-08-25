<#
.SYNOPSIS
    Shared address-selection helpers for the Fitz-Net AI node installer and
    scheduled heartbeat.
#>

function Test-UsableIPv4Address {
    param([Parameter(Mandatory = $true)]$Address)

    return $Address.IPAddress -and
        $Address.IPAddress -ne "127.0.0.1" -and
        $Address.IPAddress -notlike "169.254.*" -and
        (-not $Address.PSObject.Properties["AddressState"] -or $Address.AddressState -eq "Preferred")
}

function Test-VpnInterfaceName {
    param(
        [string]$InterfaceAlias,
        [string]$InterfaceDescription
    )

    return $InterfaceAlias -match "OpenVPN|TAP|Wintun" -or
        $InterfaceDescription -match "OpenVPN|TAP|Wintun"
}

function Get-VpnIPv4Address {
    $candidate = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            (Test-UsableIPv4Address $_) -and
            (Test-VpnInterfaceName -InterfaceAlias $_.InterfaceAlias)
        } |
        Sort-Object InterfaceIndex, IPAddress |
        Select-Object -First 1

    if ($candidate) { return $candidate.IPAddress }
    return $null
}

function Get-LanIPv4Address {
    $candidate = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            (Test-UsableIPv4Address $_) -and
            -not (Test-VpnInterfaceName -InterfaceAlias $_.InterfaceAlias) -and
            $_.InterfaceAlias -notmatch "Loopback|vEthernet|VirtualBox|VMware|Hyper-V"
        } |
        Sort-Object InterfaceIndex, IPAddress |
        Select-Object -First 1

    if ($candidate) { return $candidate.IPAddress }
    return $null
}

function Get-VpnInterfaceAliases {
    $aliases = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object {
            Test-VpnInterfaceName -InterfaceAlias $_.Name -InterfaceDescription $_.InterfaceDescription
        } |
        ForEach-Object { $_.Name } |
        Sort-Object -Unique

    return @($aliases)
}

function Get-OllamaAddress {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("vpn", "lan", "fixed")]
        [string]$AddressMode,

        [string]$FixedAddress
    )

    switch ($AddressMode) {
        "fixed" {
            if ([string]::IsNullOrWhiteSpace($FixedAddress)) { return "" }
            return $FixedAddress.Trim()
        }
        "vpn" {
            $ip = Get-VpnIPv4Address
        }
        "lan" {
            $ip = Get-LanIPv4Address
        }
    }

    if ($ip) { return "${ip}:11434" }
    return ""
}

function Get-NodeHeartbeatState {
    param(
        [bool]$OllamaAvailable,
        [object[]]$Models,
        [string]$Address
    )

    $modelCount = @($Models).Count
    $chatReady = $OllamaAvailable -and $modelCount -gt 0 -and
        -not [string]::IsNullOrWhiteSpace($Address)

    return [pscustomobject]@{
        Status = if ($chatReady) { "ONLINE" } else { "OFFLINE" }
        Address = if ($chatReady) { $Address } else { "" }
    }
}

function Set-SplitTunnelProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilePath,

        [string]$ApiHostAddress = "192.168.1.59"
    )

    $parsedAddress = $null
    if (-not [System.Net.IPAddress]::TryParse($ApiHostAddress, [ref]$parsedAddress) -or
        $parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "ApiHostAddress must be a valid IPv4 address."
    }

    $lines = [System.IO.File]::ReadAllLines($ProfilePath)
    $managedComment = "# Fitz-Net managed split tunnel"
    $apiRoutePattern = "^\s*route\s+$([regex]::Escape($ApiHostAddress))\s+255\.255\.255\.255(?:\s|$)"
    $filteredLines = @($lines | Where-Object {
        $_ -notmatch '^\s*# Fitz-Net managed split tunnel\s*$' -and
        $_ -notmatch '^\s*route-nopull(?:\s|$)' -and
        $_ -notmatch '^\s*redirect-gateway(?:\s|$)' -and
        $_ -notmatch $apiRoutePattern
    })

    $updatedLines = @(
        $managedComment
        "route-nopull"
        "route $ApiHostAddress 255.255.255.255 vpn_gateway"
    ) + $filteredLines

    [System.IO.File]::WriteAllLines(
        $ProfilePath,
        $updatedLines,
        (New-Object System.Text.UTF8Encoding($false))
    )
}
