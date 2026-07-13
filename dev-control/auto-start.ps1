$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$StateRoot = Join-Path $env:LOCALAPPDATA 'DigitalBreakdownDev'
$Workspace = Join-Path $StateRoot 'source'
$InstalledStatePath = Join-Path $StateRoot 'installed-build.json'
$ControllerPath = Join-Path $StateRoot 'control\dev-control.ps1'
$RepositoryUrl = 'https://github.com/indrolend/digital-breakdown-apk.git'
$AppId = 'com.indrolend.digitalbreakdown.native'
$ResultPath = Join-Path $StateRoot 'startup-check.json'

function Save-StartupResult([string]$State,[string]$Summary) {
    New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
    [pscustomobject]@{state=$State;summary=$Summary;time=(Get-Date).ToString('o')} |
        ConvertTo-Json | Set-Content $ResultPath -Encoding UTF8
}

try {
    if (-not (Test-Path $ControllerPath)) { throw 'Controller is not available.' }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is not available.' }

    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adb) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
        if (Test-Path $candidate) { $adb = Get-Item $candidate }
    }
    if (-not $adb) { throw 'ADB is not available.' }

    & $adb.Source start-server | Out-Null
    $deviceLines = & $adb.Source devices 2>&1
    $device = @($deviceLines | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' })
    if ($device.Count -ne 1) { throw 'Exactly one authorized Android device must be connected.' }
    $serial = ($device[0] -split '\s+')[0]

    $remoteLine = (& git ls-remote $RepositoryUrl refs/heads/main 2>$null | Select-Object -First 1)
    if (-not $remoteLine) { throw 'Could not read GitHub main.' }
    $remoteCommit = ($remoteLine -split '\s+')[0]

    $record = $null
    if (Test-Path $InstalledStatePath) {
        try { $record = Get-Content $InstalledStatePath -Raw | ConvertFrom-Json } catch { $record = $null }
    }

    $installed = ((& $adb.Source -s $serial shell pm path $AppId 2>$null | Out-String).Trim() -match '^package:')
    $current = $installed -and $record -and $record.serial -eq $serial -and $record.commit -eq $remoteCommit -and $record.kind -eq 'github-source'

    if ($current) {
        Save-StartupResult 'CURRENT' ("GitHub {0} is already installed." -f $remoteCommit.Substring(0,7))
        exit 0
    }

    Save-StartupResult 'UPDATE_REQUIRED' ("Deploying GitHub {0}." -f $remoteCommit.Substring(0,7))
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ControllerPath -Mode RetrieveBuildTest
    if ($LASTEXITCODE -ne 0) { throw 'Automatic deployment workflow failed.' }

    Save-StartupResult 'SUCCESS' ("GitHub {0} deployment workflow completed." -f $remoteCommit.Substring(0,7))
    exit 0
}
catch {
    Save-StartupResult 'SKIPPED' $_.Exception.Message
    exit 0
}
