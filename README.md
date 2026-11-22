# Wi-Fi Optimizer for Windows

A lightweight, automated diagnostic and tuning utility for Windows that analyzes wireless performance bottlenecks, unlocks hardware-supported Wi-Fi 6 (802.11ax) capabilities, optimizes DNS resolution, eliminates background roaming lag, and diagnoses router channel overlap.

---

## ⚡ What It Solves

Many modern Windows laptops and PCs experience sub-optimal Wi-Fi performance due to configuration mismatches:

1. **Restricted Wi-Fi 6 Capabilities**: Wireless cards (such as MediaTek MT7921, Intel AX200/AX201/AX210, etc.) are sometimes defaulted by OEM drivers to older 802.11ac PHY modes, preventing Wi-Fi 6 modulation and falling back to legacy 802.11n on 2.4 GHz.
2. **High-Latency DNS Relays**: Default ISP router DNS relays often take 200–350 ms per domain lookup. Switching to secure, low-latency providers (such as Cloudflare `1.1.1.1` or Google `8.8.8.8`) cuts query times down to ~15–40 ms.
3. **Roaming Aggressiveness Stutter**: When set to "Medium-High" or "High" on stationary devices, Windows periodically scans for alternative BSSIDs in the background, creating packet spikes and micro-stutters during calls, streaming, and gaming.
4. **Channel Overlap & DFS Interference**: Identifying if 2.4 GHz is on an overlapping channel (anything outside 1, 6, and 11) or if 5 GHz is on a DFS radar channel (52–144) causing radar delays.

---

## 🚀 Quick Start

### Option A: One-Click Runner (Recommended)
1. Right-click `run.bat`.
2. Select **Run as administrator**.
3. Choose an option from the interactive menu:
   - `1`: Run Full Diagnostic Audit
   - `2`: Optimize Wi-Fi Adapter, DNS & TCP Stack (with automatic backup)
   - `3`: Benchmark DNS Resolvers
   - `4`: Restore Previous Configuration
   - `5`: Exit

### Option B: PowerShell CLI
Open PowerShell as Administrator:

```powershell
# Run a non-destructive audit
powershell -ExecutionPolicy Bypass -File .\WiFiOptimizer.ps1 -Audit

# Benchmark DNS servers
powershell -ExecutionPolicy Bypass -File .\WiFiOptimizer.ps1 -BenchmarkDNS

# Apply full optimizations with automatic backup
powershell -ExecutionPolicy Bypass -File .\WiFiOptimizer.ps1 -OptimizeAll

# Restore previous configuration from backup
powershell -ExecutionPolicy Bypass -File .\WiFiOptimizer.ps1 -Restore
```

### Option C: Import as a PowerShell Module
```powershell
Import-Module .\src\WiFiOptimizer.psd1

# Run audit
Get-WiFiDiagnostics

# Benchmark DNS
Test-DNSResolvers -CurrentDns "192.168.1.254"

# Apply optimizations
Optimize-WiFiSettings
```

---

## 🛠️ Optimizations Applied

### 1. Adapter Tuning
* **PHY Mode**: Unlocks `802.11ax` (Wi-Fi 6) if supported by the hardware and router.
* **Preferred Band**: Sets priority to 5 GHz (or 6 GHz for Wi-Fi 6E/7 cards).
* **Roaming Aggressiveness**: Tuned to `Medium` to halt unnecessary background discovery scans while maintaining healthy handoffs if moved.
* **Transmit Power**: Set to `Highest` (100%).

### 2. Network & DNS Tuning
* **DNS Providers**: Configures Cloudflare Primary (`1.1.1.1`) and Secondary (`1.0.0.1`) on the active wireless adapter.
* **DNS Client Cache**: Flushed automatically via `Clear-DnsClientCache`.
* **TCP Stack**: Tunes Windows Receive Window Auto-Tuning, RSS (Receive-Side Scaling), and RSC (Receive Segment Coalescing).

### 3. Router Recommendations
The audit tool analyzes your current channel and provides concrete router guidance:
* **2.4 GHz**: Flags overlapping channels (2–5, 7–10) and suggests switching to non-overlapping channels (1, 6, or 11).
* **5 GHz**: Flags DFS channels (52–144) and suggests switching to clean non-DFS channels (36, 40, 44, or 48) with 80 MHz width.
* **MU-MIMO**: Recommends enabling Multi-User MIMO on the router.

---

## 🔒 Safety & Rollback

Before applying any change, `WiFiOptimizer` automatically takes a snapshot of your network adapter settings, registry values, and DNS configuration into `./backups/wifi_backup_<timestamp>.json`.

To revert all changes at any time:
```powershell
powershell -ExecutionPolicy Bypass -File .\WiFiOptimizer.ps1 -Restore
```

---

## 📂 Project Structure

```
wifi-optimizer/
├── WiFiOptimizer.ps1      # Main standalone diagnostic and optimization script
├── run.bat                # Windows launcher with administrative self-elevation
├── src/
│   ├── WiFiOptimizer.psd1 # PowerShell module manifest
│   └── WiFiOptimizer.psm1 # Modular PowerShell functions
├── backups/               # Automatically generated configuration snapshots
└── README.md              # Project documentation
```
