@echo off

where pwsh >nul 2>&1

if errorlevel 1 (
    echo installing PowerShell 7...

    winget install --id Microsoft.PowerShell ^
        --source winget ^
        --accept-source-agreements ^
        --accept-package-agreements

    if errorlevel 1 (
        echo PowerShell 7 installation failed. Please install it manually from https://aka.ms/powershell-release and try again.
        pause
        exit /b 1
    )

    echo.
    echo Installation completed. Restarting JujutsuController...
    timeout /t 2 >nul

    remove-item -literalpath .\.setup-completed -force -erroraction stop

    start "" "%~f0"
    exit /b
)

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0JujutsuController.ps1"