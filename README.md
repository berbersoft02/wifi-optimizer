# wifi-optimizer

PowerShell diagnostic and configuration tool for Wi-Fi network adapters on Windows.

## Overview

Windows often uses conservative default driver properties for wireless network adapters. On many systems, Wi-Fi 6 cards remain locked to 802.11ac PHY modes, DNS queries default to high-latency local router relays, and aggressive roaming settings trigger frequent background network scans that introduce latency spikes.

This tool audits current Wi-Fi adapter properties, benchmarks DNS performance, applies recommended driver configurations, and creates automatic backups for easy rollback.

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or later
- Administrator privileges (for applying adapter and DNS changes)

## Usage

### Quick Start

Run the batch wrapper as Administrator:

```cmd
run.bat
```

Or execute the PowerShell script directly:

```powershell
# Audit current connection and display diagnostics
powershell -ExecutionPolicy Bypass -File .\WiFiOptimizer.ps1 -Audit

# Benchmark available DNS resolvers
powershell -ExecutionPolicy Bypass -File .\WiFiOptimizer.ps1 -BenchmarkDNS

# Apply all optimizations (creates automatic backup first)
powershell -ExecutionPolicy Bypass -File .\WiFiOptimizer.ps1 -OptimizeAll

# Restore previous configuration from backup
powershell -ExecutionPolicy Bypass -File .\WiFiOptimizer.ps1 -Restore
```

### Module Import

The tool can also be imported into an existing PowerShell session:

```powershell
Import-Module .\src\WiFiOptimizer.psd1

Get-WiFiDiagnostics
Test-DNSResolvers -CurrentDns "192.168.1.254"
Optimize-WiFiSettings
```

## What It Configures

### 1. Adapter Properties
- **PHY Mode**: Sets driver mode to 802.11ax (Wi-Fi 6) when supported by the hardware and router.
- **Preferred Band**: Sets preference to 5 GHz.
- **Roaming Aggressiveness**: Sets threshold to Medium to prevent background scan stutter while stationary.
- **Transmit Power Level**: Ensures transmit power is set to 100%.

### 2. DNS and Network Stack
- **Resolvers**: Sets Cloudflare DNS (1.1.1.1 and 1.0.0.1) on the active wireless adapter.
- **Cache**: Clears the Windows DNS resolver cache.
- **TCP Parameters**: Enables Receive Window Auto-Tuning, Receive-Side Scaling (RSS), and Receive Segment Coalescing (RSC).

### 3. Router Recommendations
The diagnostic audit checks:
- 2.4 GHz channel selection (recommends switching from overlapping channels to 1, 6, or 11).
- 5 GHz channel selection (identifies DFS channels 52-144 and recommends non-DFS channels 36, 40, 44, or 48).

## Backup and Rollback

Every optimization run generates a timestamped JSON backup under `backups/`:

```
backups/wifi_backup_YYYYMMDD_HHMMSS.json
```

To restore the original adapter settings and DNS configuration:

```powershell
powershell -ExecutionPolicy Bypass -File .\WiFiOptimizer.ps1 -Restore
```

Or specify a specific backup file:

```powershell
powershell -ExecutionPolicy Bypass -File .\WiFiOptimizer.ps1 -Restore -BackupFile .\backups\wifi_backup_example.json
```

## File Structure

```
wifi-optimizer/
|-- WiFiOptimizer.ps1      # Main script with CLI and interactive menu
|-- run.bat                # Administrator launcher
|-- README.md              # Documentation
|-- .gitignore             # Git ignore file
`-- src/
    |-- WiFiOptimizer.psd1 # Module manifest
    `-- WiFiOptimizer.psm1 # Module implementation
```

## License

MIT
