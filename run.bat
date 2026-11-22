@echo off
:: WiFi Optimizer Launcher with Administrator Check
NET SESSION >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WiFiOptimizer.ps1"
) ELSE (
    echo Requesting Administrator Privileges...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"\"%~dp0WiFiOptimizer.ps1\"\"' -Verb RunAs"
)
