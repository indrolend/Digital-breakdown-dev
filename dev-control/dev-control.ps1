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

function Pause-Control { Read-Host "`nPress Enter to return" | Out-Null }
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
    Write-Host "`nRetrieving the project from GitHub..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path (Split-Path $Workspace) | Out-Null
    & git clone 'https://github.com/indrolend/digital-breakdown-apk.git' $Workspace
    if ($LASTEXITCODE -ne 0) { throw 'Repository download failed. GitHub may need you to sign in once.' }
    Set-Content -Path $ConfigPath -Value $Workspace
    return $Workspace
}

function Get-Device {
    $adb = Resolve-Adb
    if (-not $adb) { throw 'ADB was not found. Install Android platform-tools or Android Studio.' }
    $lines = & $adb devices
    $unauthorized = @($lines | Select-Object -Skip 1 | Where-Object { $_ -match "\tunauthorized$" })
    if ($unauthorized.Count -gt 0) { throw 'Unlock the phone and approve the USB debugging prompt.' }
    $devices = @($lines | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" })
    if ($devices.Count -eq 0) { throw 'Connect the Stylo 4 with USB debugging enabled.' }
    if ($devices.Count -gt 1) { throw 'More than one Android device is connected.' }
    return @{ Adb = $adb; Serial = ($devices[0] -split "\t")[0] }
}

function Get-PublishedManifest {
    return Invoke-RestMethod -Uri ("$ManifestUrl?t=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -UseBasicParsing
}

function Show-Status {
    Clear-Host
    Write-Host 'DIGITAL BREAKDOWN' -ForegroundColor Green
    Write-Host 'DEV CONTROL' -ForegroundColor Green
    Write-Host '-----------' -ForegroundColor DarkGreen

    try {
        $manifest = Get-PublishedManifest
        Write-Host "Latest build : $($manifest.shortCommit)  READY"
    } catch {
        Write-Host 'Latest build : unavailable' -ForegroundColor Yellow
    }

    try {
        $device = Get-Device
        $model = (& $device.Adb -s $device.Serial shell getprop ro.product.model).Trim()
        Write-Host "Phone        : $model  CONNECTED" -ForegroundColor Cyan
    } catch {
        Write-Host 'Phone        : not connected' -ForegroundColor Yellow
    }

    $repo = Get-Workspace
    if ($repo) {
        Push-Location $repo
        try {
            $commit = (& git rev-parse --short HEAD).Trim()
            $dirty = [bool](& git status --porcelain)
            Write-Host ("Source       : $commit" + $(if ($dirty) { '-dirty' } else { '' }))
        } finally { Pop-Location }
    } else {
        Write-Host 'Source       : retrieved automatically when needed'
    }
}

function Sync-Source {
    $repo = Ensure-Workspace
    Push-Location $repo
    try {
        $dirty = [bool](& git status --porcelain)
        if ($dirty) {
            Write-Host 'Local changes exist, so they were preserved without pulling.' -ForegroundColor Yellow
            & git status --short --branch
            return
        }
        Write-Host "`nUpdating source from GitHub..." -ForegroundColor Cyan
        & git fetch origin main
        if ($LASTEXITCODE -ne 0) { throw 'Git fetch failed.' }
        & git checkout main
        if ($LASTEXITCODE -ne 0) { throw 'Could not switch to main.' }
        & git pull --ff-only origin main
        if ($LASTEXITCODE -ne 0) { throw 'Source update failed.' }
    } finally { Pop-Location }
}

function Deploy-Published {
    $device = Get-Device
    $manifest = Get-PublishedManifest
    if (-not $manifest.commit) { throw 'No completed published build is available.' }
    $apk = Join-Path $DownloadDir ("DigitalBreakdown-Android-" + $manifest.shortCommit + '.apk')
    Write-Host "`nInstalling completed build $($manifest.shortCommit)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $PublishedApkUrl -OutFile $apk -UseBasicParsing
    if ($manifest.android.sha256) {
        $actual = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $manifest.android.sha256.ToLowerInvariant()) { throw 'The APK checksum did not match the published build.' }
    }
    & $device.Adb -s $device.Serial install -r $apk
    if ($LASTEXITCODE -ne 0) { throw 'APK replacement failed. The installed copy may use a different signing key.' }
    & $device.Adb -s $device.Serial shell am force-stop $AppId | Out-Null
    & $device.Adb -s $device.Serial shell am start -n "$AppId/$Activity" | Out-Null
    Write-Host "Build $($manifest.shortCommit) is running on the phone." -ForegroundColor Green
}

function Build-Deploy-Local {
    $repo = Ensure-Workspace
    $device = Get-Device
    $script = Join-Path $repo 'tools\device\deploy-local.ps1'
    if (-not (Test-Path $script)) { throw 'Local deployment tooling is missing after source synchronization.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -NoMirror -NoLogs
    if ($LASTEXITCODE -ne 0) { throw 'Local build and installation failed.' }
}

function Continue-Development {
    Sync-Source
    Build-Deploy-Local
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
    Write-Host "`nWHAT ARE YOU DOING?" -ForegroundColor DarkGreen
    Write-Host ' 1) TEST LATEST BUILD ON STYLO 4'
    Write-Host ' 2) CONTINUE NATIVE DEVELOPMENT'
    Write-Host ' 3) MIRROR PHONE'
    Write-Host ' 4) VIEW NATIVE LOGS'
    Write-Host ' 5) OPEN DEV WEBSITE'
    Write-Host ' 6) OPEN SOURCE FOLDER'
    Write-Host ' 0) EXIT'
    $choice = Read-Host "`nSelect"
    try {
        switch ($choice) {
            '1' { Deploy-Published; Start-Mirror; Start-Logs; Pause-Control }
            '2' { Continue-Development; Start-Mirror; Start-Logs; Pause-Control }
            '3' { Start-Mirror; Pause-Control }
            '4' { Start-Logs; Pause-Control }
            '5' { Open-Url $Portal }
            '6' { Open-Workspace }
            '0' { break }
            default { Write-Host 'Choose a number shown in the menu.' -ForegroundColor Yellow; Pause-Control }
        }
    } catch {
        Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
        Pause-Control
    }
}
