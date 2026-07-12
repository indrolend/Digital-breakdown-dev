@echo off
setlocal
set "CONTROL_DIR=%LOCALAPPDATA%\DigitalBreakdownDev\control"
set "CONTROL_PS1=%CONTROL_DIR%\dev-control.ps1"
set "CONTROL_URL=https://indrolend.github.io/Digital-breakdown-dev/dev-control/dev-control.ps1"

if not exist "%CONTROL_DIR%" mkdir "%CONTROL_DIR%"

echo Updating Digital Breakdown Dev Control...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $url='%CONTROL_URL%?t=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile '%CONTROL_PS1%'; exit 0 } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
if errorlevel 1 (
  echo.
  echo Could not update the control script.
  if not exist "%CONTROL_PS1%" (
    pause
    exit /b 1
  )
  echo Starting the last downloaded copy.
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CONTROL_PS1%"
endlocal
