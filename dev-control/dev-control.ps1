$ErrorActionPreference = 'Stop'

$AppId = 'com.indrolend.digitalbreakdown.native'
$Activity = 'com.indrolend.digitalbreakdown.MainActivity'
$Portal = 'https://indrolend.github.io/Digital-breakdown-dev/'
$ManifestUrl = "$Portal/build-info.json"
$PublishedApkUrl = 'https://github.com/indrolend/Digital-breakdown-dev/releases/download/latest-dev/DigitalBreakdown-Android.apk'
$StateRoot = Join-Path $env:LOCALAPPDATA 'DigitalBreakdownDev'
$Workspace = Join-Path $StateRoot 'source'
$DownloadDir = Join-Path $StateRoot 'downloads'
$ConfigPath = Join-Path $StateRoot 'workspace.txt'

New-Item -ItemType Directory -Force -Path $StateRoot, $DownloadDir | Out-Null

function Pause-Control { Read-Host "`nPress Enter to return to Dev Control" | Out-Null }
function Has-Command([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Open-Url([string]$Url) { Start-Process $Url }

function Resolve-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidate = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Resolve-Scrcpy {
    $cmd = Get-Command scrcpy -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:USERPROFILE 'scrcpy\scrcpy.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\scrcpy\scrcpy.exe'),
        (Join-Path $StateRoot 'tools\scrcpy\scrcpy.exe')
    )
    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Get-Workspace {
    if (Test-Path $ConfigPath) {
        $saved = (Get-Content $ConfigPath -Raw).Trim()
        if ($saved -and (Test-Path (Join-Path $saved '.git'))) { return $saved }
    }

    $candidates = @(
        $Workspace,
        (Join-Path $env:USERPROFILE 'Downloads\digital-breakdown-apk'),
        (Join-Path $env:USERPROFILE 'Documents\GitHub\digital-breakdown-apk'),
        (Join-Path $env:USERPROFILE 'source\repos\digital-breakdown-apk')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path (Join-Path $candidate '.git')) {
            Set-Content -Path $ConfigPath -Value $candidate
            return $candidate
        }
    }
    return $null
}

function Ensure-Workspace {
    $repo = Get-Workspace
    if ($repo) { return $repo }
    if (-not (Has-Command git)) { throw 'Git is required to retrieve the private source repository.' }
    Write-Host "`nNo source checkout was found. Creating managed workspace:" -ForegroundColor Yellow
    Write-Host $Workspace
    New-Item -ItemType Directory -Force -Path (Split-Path $Workspace) | Out-Null
    & git clone 'https://github.com/indrolend/digital-breakdown-apk.git' $Workspace
    if ($LASTEXITCODE -ne 0) { throw 'Repository clone failed. GitHub may need you to sign in through Git Credential Manager.' }
    Set-Content -Path $ConfigPath -Value $Workspace
    return $Workspace
}

function Get-Device {
    $adb = Resolve-Adb
    if (-not $adb) { throw 'ADB was not found. Install Android platform-tools or Android Studio.' }
    $lines = & $adb devices
    $devices = @($lines | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" })
    if ($devices.Count -eq 0) { throw 'No authorized Android device is connected. Unlock the Stylo 4 and approve USB debugging.' }
    if ($devices.Count -gt 1) { throw 'More than one authorized Android device is connected.' }
    return @{ Adb = $adb; Serial = ($devices[0] -split "\t")[0] }
}

function Show-Status {
    Clear-Host
    Write-Host 'DIGITAL BREAKDOWN DEV CONTROL' -ForegroundColor Green
    Write-Host '=============================' -ForegroundColor Green
    $repo = Get-Workspace
    $adb = Resolve-Adb
    $scrcpy = Resolve-Scrcpy
    Write-Host ("Workspace : " + $(if ($repo) { $repo } else { 'not retrieved' }))
    Write-Host ("Git       : " + $(if (Has-Command git) { 'ready' } else { 'missing' }))
    Write-Host ("ADB       : " + $(if ($adb) { $adb } else { 'missing' }))
    Write-Host ("scrcpy    : " + $(if ($scrcpy) { $scrcpy } else { 'missing' }))
    try {
        $manifest = Invoke-RestMethod -Uri ("$ManifestUrl?t=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -UseBasicParsing
        Write-Host ("Published : " + $manifest.shortCommit)
        Write-Host ("Built     : " + $manifest.builtAt)
    } catch { Write-Host 'Published : unavailable' -ForegroundColor Yellow }
    if ($repo) {
        Push-Location $repo
        try {
            $branch = (& git branch --show-current).Trim()
            $commit = (& git rev-parse --short HEAD).Trim()
            $dirty = [bool](& git status --porcelain)
            Write-Host ("Local     : $commit" + $(if ($dirty) { '-dirty' } else { '' }) + " ($branch)")
        } finally { Pop-Location }
    }
    try {
        $device = Get-Device
        $model = (& $device.Adb -s $device.Serial shell getprop ro.product.model).Trim()
        Write-Host "Device    : $model ($($device.Serial))" -ForegroundColor Cyan
    } catch { Write-Host ("Device    : " + $_.Exception.Message) -ForegroundColor Yellow }
}

function Sync-Source {
    $repo = Ensure-Workspace
    Push-Location $repo
    try {
        Write-Host "`nChecking source continuity..." -ForegroundColor Cyan
        $dirty = [bool](& git status --porcelain)
        if ($dirty) {
            Write-Host 'Local changes exist. Source was not pulled automatically.' -ForegroundColor Yellow
            & git status --short --branch
            return
        }
        & git fetch origin main
        if ($LASTEXITCODE -ne 0) { throw 'Git fetch failed.' }
        & git checkout main
        if ($LASTEXITCODE -ne 0) { throw 'Could not switch to main.' }
        & git pull --ff-only origin main
        if ($LASTEXITCODE -ne 0) { throw 'Fast-forward pull failed.' }
        Write-Host 'Source is synchronized with GitHub main.' -ForegroundColor Green
    } finally { Pop-Location }
}

function Deploy-Published {
    $device = Get-Device
    $manifest = Invoke-RestMethod -Uri ("$ManifestUrl?t=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -UseBasicParsing
    if (-not $manifest.commit) { throw 'No completed published build is available.' }
    $apk = Join-Path $DownloadDir ("DigitalBreakdown-Android-" + $manifest.shortCommit + '.apk')
    Write-Host "`nDownloading published APK $($manifest.shortCommit)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $PublishedApkUrl -OutFile $apk -UseBasicParsing
    if ($manifest.android.sha256) {
        $actual = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $manifest.android.sha256.ToLowerInvariant()) { throw 'Downloaded APK checksum does not match build-info.json.' }
        Write-Host 'Checksum verified.' -ForegroundColor Green
    }
    & $device.Adb -s $device.Serial install -r $apk
    if ($LASTEXITCODE -ne 0) { throw 'APK replacement failed. A signature mismatch may require one deliberate uninstall.' }
    & $device.Adb -s $device.Serial shell am force-stop $AppId
    & $device.Adb -s $device.Serial shell am start -n "$AppId/$Activity"
    Write-Host "Published build $($manifest.shortCommit) installed and launched." -ForegroundColor Green
}

function Build-Deploy-Local {
    $repo = Ensure-Workspace
    $device = Get-Device
    $script = Join-Path $repo 'tools\device\deploy-local.ps1'
    if (-not (Test-Path $script)) { throw 'deploy-local.ps1 is missing. Run Sync source first.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -NoMirror -NoLogs
    if ($LASTEXITCODE -ne 0) { throw 'Local build/deploy failed.' }
}

function Start-Mirror {
    $device = Get-Device
    $scrcpy = Resolve-Scrcpy
    if (-not $scrcpy) { throw 'scrcpy was not found.' }
    Start-Process $scrcpy -ArgumentList @('-s', $device.Serial, '--max-size', '1024', '--video-bit-rate', '4M', '--stay-awake', '--no-audio')
}

function Start-Logs {
    $device = Get-Device
    $args = "-NoExit -Command & `"$($device.Adb)`" -s $($device.Serial) logcat -s DBNATIVE:I AndroidRuntime:E '*:S'"
    Start-Process powershell.exe -ArgumentList $args
}

function Open-Workspace {
    $repo = Ensure-Workspace
    Start-Process explorer.exe $repo
}

while ($true) {
    Show-Status
    Write-Host "`n 1) INSTALL LATEST PUBLISHED + LAUNCH"
    Write-Host ' 2) SYNC SOURCE FROM GITHUB'
    Write-Host ' 3) BUILD LOCAL + INSTALL + LAUNCH'
    Write-Host ' 4) MIRROR STYLO 4'
    Write-Host ' 5) NATIVE LOGS'
    Write-Host ' 6) OPEN DEV PORTAL'
    Write-Host ' 7) OPEN MANAGED SOURCE FOLDER'
    Write-Host ' 8) REFRESH STATUS'
    Write-Host ' 0) EXIT'
    $choice = Read-Host "`nSelect"
    try {
        switch ($choice) {
            '1' { Deploy-Published; Start-Mirror; Start-Logs; Pause-Control }
            '2' { Sync-Source; Pause-Control }
            '3' { Build-Deploy-Local; Start-Mirror; Start-Logs; Pause-Control }
            '4' { Start-Mirror; Pause-Control }
            '5' { Start-Logs; Pause-Control }
            '6' { Open-Url $Portal }
            '7' { Open-Workspace }
            '8' { continue }
            '0' { break }
            default { Write-Host 'Unknown selection.' -ForegroundColor Yellow; Pause-Control }
        }
    } catch {
        Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
        Pause-Control
    }
}
