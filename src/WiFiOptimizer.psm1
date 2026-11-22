function Get-ActiveWiFiInterface {
    [CmdletBinding()]
    param()
    $interfaces = netsh wlan show interfaces
    $nameLine = $interfaces | Where-Object { $_ -match '^\s*Name\s*:\s*(.+)$' }
    if ($nameLine -match ':\s*(.+)$') {
        return $matches[1].Trim()
    }
    return "Wi-Fi"
}

function Get-WiFiDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InterfaceName = (Get-ActiveWiFiInterface)
    )

    $interfaceText = netsh wlan show interfaces
    $driverText = netsh wlan show drivers

    $info = [ordered]@{}
    $info["Interface"] = $InterfaceName

    foreach ($line in $interfaceText) {
        if ($line -match '^\s*Description\s*:\s*(.+)$') { $info["Adapter"] = $matches[1].Trim() }
        if ($line -match '^\s*State\s*:\s*(.+)$') { $info["State"] = $matches[1].Trim() }
        if ($line -match '^\s*SSID\s*:\s*(.+)$') { $info["SSID"] = $matches[1].Trim() }
        if ($line -match '^\s*BSSID\s*:\s*(.+)$') { $info["BSSID"] = $matches[1].Trim() }
        if ($line -match '^\s*Radio type\s*:\s*(.+)$') { $info["RadioType"] = $matches[1].Trim() }
        if ($line -match '^\s*Authentication\s*:\s*(.+)$') { $info["Auth"] = $matches[1].Trim() }
        if ($line -match '^\s*Channel\s*:\s*(.+)$') { $info["Channel"] = [int]$matches[1].Trim() }
        if ($line -match '^\s*Receive rate\s*\(Mbps\)\s*:\s*(.+)$') { $info["RxRateMbps"] = [double]$matches[1].Trim() }
        if ($line -match '^\s*Transmit rate\s*\(Mbps\)\s*:\s*(.+)$') { $info["TxRateMbps"] = [double]$matches[1].Trim() }
        if ($line -match '^\s*Signal\s*:\s*(\d+)%') { $info["SignalPercent"] = [int]$matches[1].Trim() }
    }

    foreach ($line in $driverText) {
        if ($line -match '^\s*Driver\s*:\s*(.+)$') { $info["DriverName"] = $matches[1].Trim() }
        if ($line -match '^\s*Version\s*:\s*(.+)$') { $info["DriverVersion"] = $matches[1].Trim() }
        if ($line -match '^\s*Date\s*:\s*(.+)$') { $info["DriverDate"] = $matches[1].Trim() }
        if ($line -match '^\s*Radio types supported\s*:\s*(.+)$') { $info["SupportedRadios"] = $matches[1].Trim() }
    }

    $ipConfig = Get-NetIPConfiguration -InterfaceAlias $InterfaceName -ErrorAction SilentlyContinue
    if ($ipConfig) {
        $info["IPv4Address"] = ($ipConfig.IPv4Address.IPAddress) -join ', '
        $info["DefaultGateway"] = ($ipConfig.IPv4DefaultGateway.NextHop) -join ', '
    }

    $dnsServers = Get-DnsClientServerAddress -InterfaceAlias $InterfaceName -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($dnsServers) {
        $info["DnsServers"] = ($dnsServers.ServerAddresses) -join ', '
    }

    return [PSCustomObject]$info
}

function Test-GatewayHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GatewayIp
    )

    $pings = ping.exe -n 5 $GatewayIp

    $loss = 100
    $avg = $null
    foreach ($line in $pings) {
        if ($line -match 'Lost = \d+ \((\d+)% loss\)') {
            $loss = [int]$matches[1]
        }
        if ($line -match 'Average = (\d+)ms') {
            $avg = [int]$matches[1]
        }
    }

    return [PSCustomObject]@{
        Gateway = $GatewayIp
        PacketLossPercent = $loss
        AverageLatencyMs = $avg
    }
}

function Test-DNSResolvers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CurrentDns
    )

    $testDomains = @("google.com", "cloudflare.com", "microsoft.com")
    $resolvers = @(
        @{ Name = "Current DNS ($CurrentDns)"; IP = $CurrentDns }
        @{ Name = "Cloudflare Primary"; IP = "1.1.1.1" }
        @{ Name = "Cloudflare Secondary"; IP = "1.0.0.1" }
        @{ Name = "Google Primary"; IP = "8.8.8.8" }
        @{ Name = "Quad9 Secure"; IP = "9.9.9.9" }
    )

    $results = @()

    foreach ($res in $resolvers) {
        if (-not $res.IP) { continue }
        $latencies = @()

        foreach ($domain in $testDomains) {
            try {
                $elapsed = Measure-Command {
                    $null = Resolve-DnsName -Name $domain -Server $res.IP -Type A -QuickTimeout -ErrorAction Stop
                }
                $latencies += $elapsed.TotalMilliseconds
            } catch {}
        }

        $avgMs = if ($latencies.Count -gt 0) {
            [Math]::Round(($latencies | Measure-Object -Average).Average, 1)
        } else {
            $null
        }

        $results += [PSCustomObject]@{
            Resolver = $res.Name
            IPAddress = $res.IP
            AverageMs = $avgMs
        }
    }

    return $results
}

function Get-ChannelAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Channel,
        [Parameter(Mandatory = $false)]
        [string]$RadioType
    )

    $recommendations = @()

    if ($Channel -le 14) {
        if ($Channel -notin @(1, 6, 11)) {
            $recommendations += "Channel $Channel is an overlapping 2.4 GHz channel. Change router 2.4 GHz channel to 1, 6, or 11 to avoid adjacent channel interference."
        }
    } else {
        if ($Channel -ge 52 -and $Channel -le 144) {
            $recommendations += "Channel $Channel is a DFS (radar) channel. Consider changing to channel 36, 40, 44, or 48 for lower latency, higher allowable power, and zero radar delays."
        }
    }

    return $recommendations
}

function Backup-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InterfaceName = (Get-ActiveWiFiInterface),
        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory
    )

    if (-not $OutputDirectory) {
        $OutputDirectory = Join-Path $PSScriptRoot "..\backups"
    }

    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $OutputDirectory "wifi_backup_$timestamp.json"

    $adapterProps = Get-NetAdapterAdvancedProperty -Name $InterfaceName -ErrorAction SilentlyContinue |
        Select-Object DisplayName, DisplayValue, RegistryKeyword, RegistryValue

    $dns = Get-DnsClientServerAddress -InterfaceAlias $InterfaceName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty ServerAddresses

    $backupObj = [ordered]@{
        Timestamp = (Get-Date).ToString("o")
        Interface = $InterfaceName
        DnsServers = $dns
        AdvancedProperties = $adapterProps
    }

    $backupObj | ConvertTo-Json -Depth 5 | Set-Content -Path $backupPath -Encoding UTF8
    return $backupPath
}

function Optimize-WiFiSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InterfaceName = (Get-ActiveWiFiInterface)
    )

    # 1. Unlock 802.11ax (Wi-Fi 6)
    $phyProp = Get-NetAdapterAdvancedProperty -Name $InterfaceName -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '802\.11ax' }

    if ($phyProp) {
        $axOption = $phyProp.ValidDisplayValues | Where-Object { $_ -match '802\.11ax' }
        if ($axOption -and $phyProp.DisplayValue -notmatch '802\.11ax') {
            Set-NetAdapterAdvancedProperty -Name $InterfaceName -DisplayName $phyProp.DisplayName -DisplayValue $axOption -ErrorAction SilentlyContinue
        }
    }

    # 2. Preferred Band to 5GHz
    $prefBandProp = Get-NetAdapterAdvancedProperty -Name $InterfaceName -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Preferred Band' }

    if ($prefBandProp) {
        $targetBand = $prefBandProp.ValidDisplayValues | Where-Object { $_ -match '5GHz' }
        if ($targetBand -and $prefBandProp.DisplayValue -notmatch '5GHz') {
            Set-NetAdapterAdvancedProperty -Name $InterfaceName -DisplayName $prefBandProp.DisplayName -DisplayValue $targetBand -ErrorAction SilentlyContinue
        }
    }

    # 3. Roaming Aggressiveness to Medium
    $roamProp = Get-NetAdapterAdvancedProperty -Name $InterfaceName -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Roaming Aggressiveness' }

    if ($roamProp) {
        $mediumOption = $roamProp.ValidDisplayValues | Where-Object { $_ -match '^\s*4\.\s*Medium$|^\s*Medium$' }
        if (-not $mediumOption) {
            $mediumOption = $roamProp.ValidDisplayValues | Where-Object { $_ -match 'Medium' } | Select-Object -First 1
        }
        if ($mediumOption) {
            Set-NetAdapterAdvancedProperty -Name $InterfaceName -DisplayName $roamProp.DisplayName -DisplayValue $mediumOption -ErrorAction SilentlyContinue
        }
    }

    # 4. Transmit Power Level to Highest
    $txProp = Get-NetAdapterAdvancedProperty -Name $InterfaceName -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Transmit Power' }

    if ($txProp) {
        $highestOption = $txProp.ValidDisplayValues | Where-Object { $_ -match 'Highest' } | Select-Object -First 1
        if ($highestOption) {
            Set-NetAdapterAdvancedProperty -Name $InterfaceName -DisplayName $txProp.DisplayName -DisplayValue $highestOption -ErrorAction SilentlyContinue
        }
    }

    # 5. Set Fast DNS (1.1.1.1 / 1.0.0.1)
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceName -ServerAddresses ("1.1.1.1", "1.0.0.1") -ErrorAction SilentlyContinue
    Clear-DnsClientCache

    # 6. Windows TCP Stack Tuning
    netsh int tcp set global autotuninglevel=normal | Out-Null
    netsh int tcp set global rss=enabled | Out-Null
    netsh int tcp set global rsc=enabled | Out-Null

    Start-Sleep -Seconds 5
}

function Restore-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InterfaceName = (Get-ActiveWiFiInterface),
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $backupData = Get-Content -Path $FilePath -Raw | ConvertFrom-Json

    if ($backupData.DnsServers) {
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceName -ServerAddresses $backupData.DnsServers -ErrorAction SilentlyContinue
    }

    foreach ($prop in $backupData.AdvancedProperties) {
        try {
            Set-NetAdapterAdvancedProperty -Name $InterfaceName -DisplayName $prop.DisplayName -DisplayValue $prop.DisplayValue -ErrorAction SilentlyContinue
        } catch {}
    }

    Clear-DnsClientCache
}
