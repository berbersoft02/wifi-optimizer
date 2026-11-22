<#
.SYNOPSIS
    WiFi Optimizer - Diagnostic & Performance Tuning Tool for Windows
.DESCRIPTION
    Audits Wi-Fi link parameters, unlocks Wi-Fi 6 (802.11ax) PHY modes,
    tunes roaming aggressiveness, benchmarks and updates DNS resolvers,
    and inspects channel overlap and DFS channel usage.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Audit,

    [Parameter(Mandatory = $false)]
    [switch]$OptimizeAll,

    [Parameter(Mandatory = $false)]
    [switch]$BenchmarkDNS,

    [Parameter(Mandatory = $false)]
    [switch]$Restore,

    [Parameter(Mandatory = $false)]
    [string]$BackupFile
)

$ErrorActionPreference = 'Continue'

function Write-Banner {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "             WIFI OPTIMIZER FOR WINDOWS                   " -ForegroundColor Yellow
    Write-Host "        Automated Wi-Fi Diagnostics & Tuning              " -ForegroundColor White
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Elevation {
    if (-not (Test-IsAdmin)) {
        Write-Warning "Administrator privileges required to apply adapter/DNS settings."
        Write-Host "Relaunching in an elevated PowerShell session..." -ForegroundColor Yellow
        Start-Process powershell -Verb RunAs -ArgumentList "-NoExit", "-File", "`"$PSCommandPath`""
        exit
    }
}

function Get-ActiveWiFiInterface {
    $interfaces = netsh wlan show interfaces
    $nameLine = $interfaces | Where-Object { $_ -match '^\s*Name\s*:\s*(.+)$' }
    if ($nameLine -match ':\s*(.+)$') {
        return $matches[1].Trim()
    }
    return "Wi-Fi"
}

function Get-WiFiDiagnostics {
    param([string]$InterfaceName)

    Write-Host "[+] Collecting Wi-Fi interface and driver metrics..." -ForegroundColor Cyan

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
    param([string]$GatewayIp)

    if (-not $GatewayIp) {
        return [PSCustomObject]@{ Status = "No Gateway Found"; AverageMs = $null; PacketLossPercent = 100 }
    }

    Write-Host "[+] Testing Gateway Ping ($GatewayIp)..." -ForegroundColor Cyan
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
    param([string]$CurrentDns)

    Write-Host "[+] Benchmarking DNS Resolvers..." -ForegroundColor Cyan

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
            } catch {
                # Ignore resolution misses or timeouts
            }
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
    param([int]$Channel, [string]$RadioType)

    $recommendations = @()

    if ($Channel -le 14) {
        # 2.4 GHz band
        if ($Channel -notin @(1, 6, 11)) {
            $recommendations += "Channel $Channel is an overlapping 2.4 GHz channel. Change router 2.4 GHz channel to 1, 6, or 11 to avoid adjacent channel interference."
        }
    } else {
        # 5 GHz band
        if ($Channel -ge 52 -and $Channel -le 144) {
            $recommendations += "Channel $Channel is a DFS (radar) channel. Consider changing to channel 36, 40, 44, or 48 for lower latency, higher allowable power, and zero radar delays."
        }
    }

    return $recommendations
}

function Show-AuditReport {
    param($diag, $gwHealth, $dnsResults, $channelAdvice)

    Write-Host "`n--- SYSTEM & CONNECTION AUDIT ---" -ForegroundColor Green
    Write-Host ("Adapter          : {0}" -f $diag.Adapter)
    Write-Host ("Driver Version   : {0} ({1})" -f $diag.DriverVersion, $diag.DriverDate)
    Write-Host ("Supported Modes  : {0}" -f $diag.SupportedRadios)
    Write-Host ("Current SSID     : {0}" -f $diag.SSID)
    Write-Host ("Current Protocol : {0}" -f $diag.RadioType)
    Write-Host ("Channel          : {0}" -f $diag.Channel)
    Write-Host ("Signal Strength  : {0}%" -f $diag.SignalPercent)
    Write-Host ("Link Speeds      : Rx: {0} Mbps | Tx: {1} Mbps" -f $diag.RxRateMbps, $diag.TxRateMbps)
    Write-Host ("Default Gateway  : {0}" -f $diag.DefaultGateway)
    Write-Host ("Active DNS       : {0}" -f $diag.DnsServers)

    Write-Host "`n--- GATEWAY HEALTH ---" -ForegroundColor Green
    Write-Host ("Gateway Ping Latency : {0} ms (Loss: {1}%)" -f $gwHealth.AverageLatencyMs, $gwHealth.PacketLossPercent)

    Write-Host "`n--- DNS RESOLUTION BENCHMARK ---" -ForegroundColor Green
    $dnsResults | Format-Table -AutoSize | Out-String | Write-Host

    if ($channelAdvice.Count -gt 0) {
        Write-Host "--- ROUTER RECOMMENDATIONS ---" -ForegroundColor Yellow
        foreach ($adv in $channelAdvice) {
            Write-Host (" [!] {0}" -f $adv) -ForegroundColor Yellow
        }
    }
}

function Backup-Configuration {
    param([string]$InterfaceName)

    $backupDir = Join-Path $PSScriptRoot "backups"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $backupDir "wifi_backup_$timestamp.json"

    Write-Host "[+] Creating configuration backup at $backupPath..." -ForegroundColor Cyan

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
    Write-Host "[✓] Backup saved successfully." -ForegroundColor Green
    return $backupPath
}

function Optimize-WiFiSettings {
    param([string]$InterfaceName)

    Ensure-Elevation

    Write-Host "`n[+] Applying Optimal Wi-Fi Adapter Configuration..." -ForegroundColor Yellow

    # 1. Check and Unlock 802.11ax (Wi-Fi 6)
    $phyProp = Get-NetAdapterAdvancedProperty -Name $InterfaceName -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '802\.11ax' }

    if ($phyProp) {
        $axOption = $phyProp.ValidDisplayValues | Where-Object { $_ -match '802\.11ax' }
        if ($axOption -and $phyProp.DisplayValue -notmatch '802\.11ax') {
            Write-Host " -> Upgrading PHY mode to: $axOption" -ForegroundColor Cyan
            Set-NetAdapterAdvancedProperty -Name $InterfaceName -DisplayName $phyProp.DisplayName -DisplayValue $axOption -ErrorAction SilentlyContinue
        } else {
            Write-Host " -> PHY mode already optimized for Wi-Fi 6 ($($phyProp.DisplayValue))" -ForegroundColor DarkGray
        }
    }

    # 2. Preferred Band to 5GHz
    $prefBandProp = Get-NetAdapterAdvancedProperty -Name $InterfaceName -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Preferred Band' }

    if ($prefBandProp) {
        $targetBand = $prefBandProp.ValidDisplayValues | Where-Object { $_ -match '5GHz' }
        if ($targetBand -and $prefBandProp.DisplayValue -notmatch '5GHz') {
            Write-Host " -> Setting Preferred Band to: $targetBand" -ForegroundColor Cyan
            Set-NetAdapterAdvancedProperty -Name $InterfaceName -DisplayName $prefBandProp.DisplayName -DisplayValue $targetBand -ErrorAction SilentlyContinue
        }
    }

    # 3. Roaming Aggressiveness to Medium (prevents background scan stutter)
    $roamProp = Get-NetAdapterAdvancedProperty -Name $InterfaceName -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Roaming Aggressiveness' }

    if ($roamProp) {
        $mediumOption = $roamProp.ValidDisplayValues | Where-Object { $_ -match '^\s*4\.\s*Medium$|^\s*Medium$' }
        if (-not $mediumOption) {
            $mediumOption = $roamProp.ValidDisplayValues | Where-Object { $_ -match 'Medium' } | Select-Object -First 1
        }
        if ($mediumOption) {
            Write-Host " -> Setting Roaming Aggressiveness to: $mediumOption" -ForegroundColor Cyan
            Set-NetAdapterAdvancedProperty -Name $InterfaceName -DisplayName $roamProp.DisplayName -DisplayValue $mediumOption -ErrorAction SilentlyContinue
        }
    }

    # 4. Transmit Power Level to Highest
    $txProp = Get-NetAdapterAdvancedProperty -Name $InterfaceName -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Transmit Power' }

    if ($txProp) {
        $highestOption = $txProp.ValidDisplayValues | Where-Object { $_ -match 'Highest' } | Select-Object -First 1
        if ($highestOption -and $txProp.DisplayValue -ne $highestOption) {
            Write-Host " -> Setting Transmit Power to: $highestOption" -ForegroundColor Cyan
            Set-NetAdapterAdvancedProperty -Name $InterfaceName -DisplayName $txProp.DisplayName -DisplayValue $highestOption -ErrorAction SilentlyContinue
        }
    }

    # 5. Set Fast DNS (Cloudflare 1.1.1.1 / 1.0.0.1)
    Write-Host " -> Setting Fast Primary and Secondary DNS (1.1.1.1, 1.0.0.1)..." -ForegroundColor Cyan
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceName -ServerAddresses ("1.1.1.1", "1.0.0.1") -ErrorAction SilentlyContinue
    Clear-DnsClientCache

    # 6. Windows TCP Stack Tuning
    Write-Host " -> Tuning Windows TCP Global Parameters..." -ForegroundColor Cyan
    netsh int tcp set global autotuninglevel=normal | Out-Null
    netsh int tcp set global rss=enabled | Out-Null
    netsh int tcp set global rsc=enabled | Out-Null

    Write-Host "`n[✓] Optimization applied successfully!" -ForegroundColor Green
    Write-Host "Re-evaluating connection metrics in 5 seconds..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
}

function Restore-Configuration {
    param([string]$InterfaceName, [string]$FilePath)

    Ensure-Elevation

    if (-not $FilePath) {
        $backupDir = Join-Path $PSScriptRoot "backups"
        $latest = Get-ChildItem -Path $backupDir -Filter "wifi_backup_*.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) {
            Write-Error "No backup files found in $backupDir."
            return
        }
        $FilePath = $latest.FullName
    }

    Write-Host "[+] Restoring configuration from $FilePath..." -ForegroundColor Yellow
    $backupData = Get-Content -Path $FilePath -Raw | ConvertFrom-Json

    if ($backupData.DnsServers) {
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceName -ServerAddresses $backupData.DnsServers -ErrorAction SilentlyContinue
        Write-Host " -> Restored DNS: $($backupData.DnsServers -join ', ')" -ForegroundColor Cyan
    }

    foreach ($prop in $backupData.AdvancedProperties) {
        try {
            Set-NetAdapterAdvancedProperty -Name $InterfaceName -DisplayName $prop.DisplayName -DisplayValue $prop.DisplayValue -ErrorAction SilentlyContinue
        } catch {
            # continue
        }
    }

    Clear-DnsClientCache
    Write-Host "[✓] Configuration restored successfully." -ForegroundColor Green
}

# --- Main Entry Point ---
Write-Banner

$iface = Get-ActiveWiFiInterface

if ($Restore) {
    Restore-Configuration -InterfaceName $iface -FilePath $BackupFile
    exit
}

if ($BenchmarkDNS) {
    $currentDns = (Get-DnsClientServerAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ', '
    $bench = Test-DNSResolvers -CurrentDns $currentDns
    $bench | Format-Table -AutoSize
    exit
}

if ($OptimizeAll) {
    Backup-Configuration -InterfaceName $iface | Out-Null
    Optimize-WiFiSettings -InterfaceName $iface
    $diag = Get-WiFiDiagnostics -InterfaceName $iface
    Write-Host "`n--- UPDATED STATUS ---" -ForegroundColor Green
    Write-Host ("Protocol : {0}" -f $diag.RadioType)
    Write-Host ("Channel  : {0}" -f $diag.Channel)
    Write-Host ("Speeds   : Rx {0} Mbps / Tx {1} Mbps" -f $diag.RxRateMbps, $diag.TxRateMbps)
    Write-Host ("Signal   : {0}%" -f $diag.SignalPercent)
    exit
}

if ($Audit) {
    $diag = Get-WiFiDiagnostics -InterfaceName $iface
    $gwHealth = Test-GatewayHealth -GatewayIp $diag.DefaultGateway
    $dnsBench = Test-DNSResolvers -CurrentDns $diag.DnsServers
    $advice = Get-ChannelAnalysis -Channel $diag.Channel -RadioType $diag.RadioType
    Show-AuditReport -diag $diag -gwHealth $gwHealth -dnsResults $dnsBench -channelAdvice $advice
    exit
}

# Default Interactive Menu
while ($true) {
    Write-Host "Select an option:" -ForegroundColor Cyan
    Write-Host " 1. Run Complete Wi-Fi Diagnostic Audit"
    Write-Host " 2. Optimize Wi-Fi Adapter, DNS & TCP Stack (Auto-Backup Included)"
    Write-Host " 3. Benchmark DNS Resolvers"
    Write-Host " 4. Restore Previous Configuration"
    Write-Host " 5. Exit"
    Write-Host ""
    $choice = Read-Host "Enter option (1-5)"

    switch ($choice) {
        "1" {
            $diag = Get-WiFiDiagnostics -InterfaceName $iface
            $gwHealth = Test-GatewayHealth -GatewayIp $diag.DefaultGateway
            $dnsBench = Test-DNSResolvers -CurrentDns $diag.DnsServers
            $advice = Get-ChannelAnalysis -Channel $diag.Channel -RadioType $diag.RadioType
            Show-AuditReport -diag $diag -gwHealth $gwHealth -dnsResults $dnsBench -channelAdvice $advice
            Write-Host ""
        }
        "2" {
            Backup-Configuration -InterfaceName $iface | Out-Null
            Optimize-WiFiSettings -InterfaceName $iface
            $diag = Get-WiFiDiagnostics -InterfaceName $iface
            Write-Host "`n--- UPDATED STATUS ---" -ForegroundColor Green
            Write-Host ("Protocol : {0}" -f $diag.RadioType)
            Write-Host ("Channel  : {0}" -f $diag.Channel)
            Write-Host ("Speeds   : Rx {0} Mbps / Tx {1} Mbps" -f $diag.RxRateMbps, $diag.TxRateMbps)
            Write-Host ("Signal   : {0}%" -f $diag.SignalPercent)
            Write-Host ""
        }
        "3" {
            $currentDns = (Get-DnsClientServerAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ', '
            $bench = Test-DNSResolvers -CurrentDns $currentDns
            $bench | Format-Table -AutoSize
            Write-Host ""
        }
        "4" {
            Restore-Configuration -InterfaceName $iface
            Write-Host ""
        }
        "5" {
            Write-Host "Exiting." -ForegroundColor Green
            exit
        }
        default {
            Write-Warning "Invalid selection. Please choose between 1 and 5."
        }
    }
}
