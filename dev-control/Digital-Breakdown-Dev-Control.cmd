@echo off
setlocal
set "CONTROL_DIR=%LOCALAPPDATA%\DigitalBreakdownDev\control"
set "CONTROL_PS1=%CONTROL_DIR%\dev-control.ps1"
set "CONTROL_TMP=%CONTROL_DIR%\dev-control.ps1.download"
set "CONTROL_URL=https://indrolend.github.io/Digital-breakdown-dev/dev-control/dev-control.ps1"

if not exist "%CONTROL_DIR%" mkdir "%CONTROL_DIR%"
del /q "%CONTROL_TMP%" >nul 2>&1

echo Updating Digital Breakdown Dev Control...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { $url='%CONTROL_URL%?t=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile '%CONTROL_TMP%' -TimeoutSec 30; $text=Get-Content '%CONTROL_TMP%' -Raw; if ($text -notmatch 'DIGITAL BREAKDOWN DEV CONTROL') { throw 'Downloaded control script failed validation.' }; Move-Item -Force '%CONTROL_TMP%' '%CONTROL_PS1%'; exit 0 } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Remove-Item '%CONTROL_TMP%' -Force -ErrorAction SilentlyContinue; exit 1 }"
if errorlevel 1 (
  echo.
  if not exist "%CONTROL_PS1%" (
    echo Dev Control could not be downloaded and no cached copy exists.
    echo Check your internet connection, then try again.
    pause
    exit /b 1
  )
  echo Update failed. Starting the last validated copy.
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CONTROL_PS1%"
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" (
  echo.
  echo Dev Control exited with code %EXIT_CODE%.
  pause
)
endlocal & exit /b %EXIT_CODE%
