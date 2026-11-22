# Module manifest for WiFiOptimizer

@{
    RootModule = 'WiFiOptimizer.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'b8d4e92a-3c1f-4f81-a621-e948c2b7d901'
    Author = 'WiFi Optimizer Project'
    Description = 'Automated Wi-Fi diagnostic, tuning, and optimization module for Windows.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-ActiveWiFiInterface',
        'Get-WiFiDiagnostics',
        'Test-GatewayHealth',
        'Test-DNSResolvers',
        'Get-ChannelAnalysis',
        'Optimize-WiFiSettings',
        'Backup-Configuration',
        'Restore-Configuration'
    )
}
