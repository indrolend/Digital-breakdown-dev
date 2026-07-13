$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$AppId = 'com.indrolend.digitalbreakdown.native'
$Activity = 'com.indrolend.digitalbreakdown.MainActivity'
$Portal = 'https://indrolend.github.io/Digital-breakdown-dev/'
$ManifestUrl = "${Portal}build-info.json"
$PublishedApkUrl = 'https://github.com/indrolend/Digital-breakdown-dev/releases/download/latest-dev/DigitalBreakdown-Android.apk'
$RepositoryUrl = 'https://github.com/indrolend/digital-breakdown-apk.git'
$StateRoot = Join-Path $env:LOCALAPPDATA 'DigitalBreakdownDev'
$Workspace = Join-Path $StateRoot 'source'
$DownloadDir = Join-Path $StateRoot 'downloads'
$LogDir = Join-Path $StateRoot 'logs'
$ManifestCachePath = Join-Path $StateRoot 'build-info.cached.json'
$InstalledStatePath = Join-Path $StateRoot 'installed-build.json'
$SessionLog = Join-Path $LogDir ("dev-control-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

New-Item -ItemType Directory -Force -Path $StateRoot, $DownloadDir, $LogDir | Out-Null

function Write-Log([string]$Message) {
    Add-Content -Path $SessionLog -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}
function Pause-Control { Read-Host "`nPress Enter to return" | Out-Null }
function Has-Command([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Show-Step([int]$Current, [int]$Total, [string]$Text) {
    Write-Host ("[{0}/{1}] {2}" -f $Current, $Total, $Text) -ForegroundColor Cyan
    Write-Log ("STEP $Current/$Total $Text")
}
function Resolve-Adb {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
        (Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk\platform-tools\adb.exe')
    )
    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
function Resolve-Scrcpy {
    $command = Get-Command scrcpy -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidates = @(
        (Join-Path $env:USERPROFILE 'scrcpy\scrcpy.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\scrcpy\scrcpy.exe'),
        (Join-Path $StateRoot 'tools\scrcpy\scrcpy.exe')
    )
    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
function Get-Device {
    $adb = Resolve-Adb
    if (-not $adb) { throw 'ADB is missing. Install Android platform-tools or Android Studio.' }
    & $adb start-server | Out-Null
    $lines = & $adb devices 2>&1
    if (@($lines | Select-Object -Skip 1 | Where-Object { $_ -match '\sunauthorized$' }).Count -gt 0) {
        throw 'Phone detected but unauthorized. Unlock it and approve USB debugging.'
    }
    if (@($lines | Select-Object -Skip 1 | Where-Object { $_ -match '\soffline$' }).Count -gt 0) {
        throw 'Phone is offline. Reconnect USB and restart ADB.'
    }
    $devices = @($lines | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' })
    if ($devices.Count -eq 0) { throw 'No authorized Android device is connected.' }
    if ($devices.Count -gt 1) { throw 'More than one Android device is connected.' }
    $serial = ($devices[0] -split '\s+')[0]
    $model = (& $adb -s $serial shell getprop ro.product.model 2>$null).Trim()
    return [pscustomobject]@{ Adb=$adb; Serial=$serial; Model=$model }
}
function Get-PublishedManifest([switch]$AllowCache) {
    try {
        $uri = "${ManifestUrl}?t=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        $manifest = Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 12
        if (-not $manifest.commit -or -not $manifest.shortCommit) { throw 'Manifest is missing commit identity.' }
        if (-not $manifest.android -or -not $manifest.android.available) { throw 'Manifest does not expose an Android build.' }
        if (-not $manifest.android.sha256) { throw 'Manifest is missing the APK checksum.' }
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $ManifestCachePath -Encoding UTF8
        return [pscustomobject]@{ Manifest=$manifest; Source='live' }
    } catch {
        if ($AllowCache -and (Test-Path $ManifestCachePath)) {
            return [pscustomobject]@{ Manifest=(Get-Content $ManifestCachePath -Raw | ConvertFrom-Json); Source='cached'; Error=$_.Exception.Message }
        }
        throw
    }
}
function Ensure-Workspace {
    if (Test-Path (Join-Path $Workspace '.git')) { return $Workspace }
    if (-not (Has-Command git)) { throw 'Git is missing. Install Git for Windows.' }
    if (Test-Path $Workspace) {
        $items = @(Get-ChildItem -Force $Workspace -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) { throw "Managed cache exists but is not a Git repository: $Workspace" }
    }
    Show-Step 1 1 'Clone authoritative GitHub source'
    New-Item -ItemType Directory -Force -Path (Split-Path $Workspace) | Out-Null
    & git clone $RepositoryUrl $Workspace
    if ($LASTEXITCODE -ne 0) { throw 'GitHub source retrieval failed. Sign in through Git Credential Manager and retry.' }
    return $Workspace
}
function Get-CacheInfo {
    if (-not (Test-Path (Join-Path $Workspace '.git'))) { return $null }
    $commit = (& git -C $Workspace rev-parse --short HEAD 2>$null).Trim()
    $branch = (& git -C $Workspace branch --show-current 2>$null).Trim()
    $dirty = [bool](& git -C $Workspace status --porcelain 2>$null)
    return [pscustomobject]@{ Commit=$commit; Branch=$branch; Dirty=$dirty }
}
function Sync-GitHubSource {
    $repo = Ensure-Workspace
    $dirty = [bool](& git -C $repo status --porcelain)
    if ($dirty) {
        & git -C $repo status --short --branch
        throw 'Managed source cache has local edits. GitHub retrieval stopped without overwriting them.'
    }
    Show-Step 1 4 'Fetch authoritative GitHub main'
    & git -C $repo fetch origin main --prune
    if ($LASTEXITCODE -ne 0) { throw 'Git fetch failed.' }
    Show-Step 2 4 'Switch cache to main'
    & git -C $repo checkout main
    if ($LASTEXITCODE -ne 0) { throw 'Could not switch cache to main.' }
    Show-Step 3 4 'Fast-forward cache to GitHub'
    & git -C $repo pull --ff-only origin main
    if ($LASTEXITCODE -ne 0) { throw 'Cache cannot fast-forward to GitHub main.' }
    Show-Step 4 4 'Verify exact retrieved commit'
    $local = (& git -C $repo rev-parse HEAD).Trim()
    $remote = (& git -C $repo rev-parse origin/main).Trim()
    if ($local -ne $remote) { throw 'Retrieved cache does not exactly match origin/main.' }
    Write-Host "GITHUB SOURCE READY: $($local.Substring(0,7))" -ForegroundColor Green
    return $repo
}
function Test-AppInstalled($Device) {
    return ((& $Device.Adb -s $Device.Serial shell pm path $AppId 2>$null | Out-String).Trim() -match '^package:')
}
function Start-AppAndVerify($Device) {
    & $Device.Adb -s $Device.Serial shell am force-stop $AppId | Out-Null
    $output = & $Device.Adb -s $Device.Serial shell am start -W -n "$AppId/$Activity" 2>&1
    if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -match 'Error type|does not exist|Exception') {
        throw "App launch failed: $($output -join ' ')"
    }
    Start-Sleep -Milliseconds 800
    $pid = (& $Device.Adb -s $Device.Serial shell pidof $AppId 2>$null | Out-String).Trim()
    if (-not $pid) { throw 'The app launched but no running process was found.' }
    return $pid
}
function Save-InstalledRecord([string]$Commit, [string]$Kind, [string]$Serial, [string]$ApkHash) {
    [pscustomobject]@{
        commit=$Commit
        shortCommit=$(if ($Commit.Length -ge 7) { $Commit.Substring(0,7) } else { $Commit })
        kind=$Kind
        serial=$Serial
        apkSha256=$ApkHash
        installedAt=(Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -Path $InstalledStatePath -Encoding UTF8
}
function Get-InstalledRecord {
    if (-not (Test-Path $InstalledStatePath)) { return $null }
    try { return Get-Content $InstalledStatePath -Raw | ConvertFrom-Json } catch { return $null }
}
function Start-Mirror($Device=$null) {
    if (-not $Device) { $Device=Get-Device }
    $scrcpy=Resolve-Scrcpy
    if (-not $scrcpy) { throw 'scrcpy is missing.' }
    Start-Process -FilePath $scrcpy -ArgumentList @('-s',$Device.Serial,'--max-size=1024','--video-bit-rate=4M','--stay-awake','--no-audio','--window-title=Digital Breakdown - Stylo 4')
}
function Start-Logs($Device=$null) {
    if (-not $Device) { $Device=Get-Device }
    $command="& `"$($Device.Adb)`" -s $($Device.Serial) logcat -v color -s DBNATIVE:I AndroidRuntime:E '*:S'"
    Start-Process powershell.exe -ArgumentList @('-NoExit','-ExecutionPolicy','Bypass','-Command',$command)
}
function Start-DebugTools($Device=$null) {
    if (-not $Device) { $Device=Get-Device }
    try { Start-Mirror -Device $Device } catch { Write-Host "Mirror skipped: $($_.Exception.Message)" -ForegroundColor Yellow }
    try { Start-Logs -Device $Device } catch { Write-Host "Logs skipped: $($_.Exception.Message)" -ForegroundColor Yellow }
}
function Build-Cache {
    $repo=Ensure-Workspace
    $device=Get-Device
    $deployScript=Join-Path $repo 'tools\device\deploy-local.ps1'
    if (-not (Test-Path $deployScript)) { throw 'Local deployment script is missing from the retrieved repository.' }
    $commit=(& git -C $repo rev-parse --short HEAD).Trim()
    $dirty=[bool](& git -C $repo status --porcelain)
    $buildId=$(if ($dirty) { "$commit-dirty" } else { $commit })
    Show-Step 1 4 "Build and install source $buildId"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $deployScript -NoMirror -NoLogs
    if ($LASTEXITCODE -ne 0) { throw 'Local build/deploy script failed.' }
    Show-Step 2 4 'Verify package installation'
    if (-not (Test-AppInstalled $device)) { throw 'Build completed, but the package is not installed.' }
    Show-Step 3 4 'Verify app launch'
    $pid=Start-AppAndVerify $device
    Show-Step 4 4 'Record exact tested revision'
    $apk=Join-Path $repo 'native-android\app\build\outputs\apk\debug\app-debug.apk'
    $hash=$(if (Test-Path $apk) { (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant() } else { 'unknown' })
    Save-InstalledRecord $buildId 'github-source' $device.Serial $hash
    Write-Host "SOURCE BUILD READY: $buildId (PID $pid)" -ForegroundColor Green
    Start-DebugTools -Device $device
}
function Retrieve-Build-Test {
    Sync-GitHubSource | Out-Null
    Build-Cache
}
function Download-VerifiedApk($Manifest) {
    $commit=[string]$Manifest.shortCommit
    $expected=([string]$Manifest.android.sha256).ToLowerInvariant()
    $apk=Join-Path $DownloadDir "DigitalBreakdown-Android-$commit.apk"
    if (Test-Path $apk) {
        if ((Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expected) { return $apk }
        Remove-Item $apk -Force
    }
    $temp="$apk.download"
    Remove-Item $temp -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -UseBasicParsing -Uri $PublishedApkUrl -OutFile $temp -TimeoutSec 120
    $actual=(Get-FileHash $temp -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { Remove-Item $temp -Force; throw 'Published APK checksum mismatch.' }
    Move-Item $temp $apk -Force
    return $apk
}
function Install-Published {
    Show-Step 1 5 'Read published build manifest'
    $manifest=(Get-PublishedManifest).Manifest
    $device=Get-Device
    Show-Step 2 5 "Download and verify APK $($manifest.shortCommit)"
    $apk=Download-VerifiedApk $manifest
    Show-Step 3 5 'Install published APK'
    $output=& $device.Adb -s $device.Serial install -r -d $apk 2>&1
    if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -notmatch 'Success') { throw "APK installation failed: $($output -join ' ')" }
    Show-Step 4 5 'Launch and verify process'
    $pid=Start-AppAndVerify $device
    Show-Step 5 5 'Record published revision'
    $hash=(Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    Save-InstalledRecord ([string]$manifest.commit) 'published' $device.Serial $hash
    Write-Host "PUBLISHED BUILD READY: $($manifest.shortCommit) (PID $pid)" -ForegroundColor Green
    Start-DebugTools -Device $device
}
function Show-Status {
    Clear-Host
    Write-Host 'DIGITAL BREAKDOWN DEV CONTROL' -ForegroundColor Green
    Write-Host '-----------------------------' -ForegroundColor DarkGreen
    try {
        $published=Get-PublishedManifest -AllowCache
        $label=$(if ($published.Source -eq 'live') { 'READY' } else { 'CACHED' })
        Write-Host ("Published : {0}  {1}" -f $published.Manifest.shortCommit,$label)
    } catch { Write-Host ("Published : ERROR  {0}" -f $_.Exception.Message) -ForegroundColor Yellow }
    try { $device=Get-Device; Write-Host ("Phone     : {0}  CONNECTED" -f $device.Model) -ForegroundColor Cyan }
    catch { $device=$null; Write-Host ("Phone     : {0}" -f $_.Exception.Message) -ForegroundColor Yellow }
    $cache=Get-CacheInfo
    if ($cache) {
        $suffix=$(if ($cache.Dirty) { '-dirty' } else { '' })
        Write-Host ("Cache     : {0}{1}  {2}" -f $cache.Commit,$suffix,$cache.Branch)
    } else { Write-Host 'Cache     : NOT RETRIEVED' }
    $record=Get-InstalledRecord
    if ($device -and (Test-AppInstalled $device)) {
        if ($record -and $record.serial -eq $device.Serial) { Write-Host ("Installed : {0}  {1}" -f $record.shortCommit,$record.kind.ToUpperInvariant()) -ForegroundColor Green }
        else { Write-Host 'Installed : PRESENT  REVISION UNKNOWN' -ForegroundColor Yellow }
    } elseif ($device) { Write-Host 'Installed : NOT INSTALLED' -ForegroundColor Yellow }
    else { Write-Host 'Installed : PHONE UNAVAILABLE' -ForegroundColor DarkGray }
}
function Show-MoreMenu {
    while ($true) {
        Clear-Host
        Write-Host 'MORE TOOLS' -ForegroundColor Green
        Write-Host '----------' -ForegroundColor DarkGreen
        Write-Host ' 1) BUILD LOCAL CACHE WITHOUT SYNCING'
        Write-Host ' 2) OPEN SOURCE CACHE'
        Write-Host ' 3) OPEN DEV WEBSITE'
        Write-Host ' 4) MIRROR ONLY'
        Write-Host ' 5) LOGS ONLY'
        Write-Host ' 6) OPEN SESSION LOG'
        Write-Host ' 0) BACK'
        $choice=Read-Host "`nSelect"
        try {
            switch ($choice) {
                '1' { Build-Cache; Pause-Control }
                '2' { Start-Process explorer.exe (Ensure-Workspace) }
                '3' { Start-Process $Portal }
                '4' { Start-Mirror; Pause-Control }
                '5' { Start-Logs; Pause-Control }
                '6' { Start-Process notepad.exe $SessionLog }
                '0' { return }
                default { Write-Host 'Choose a number shown in the menu.' -ForegroundColor Yellow; Pause-Control }
            }
        } catch { Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red; Pause-Control }
    }
}

Write-Log 'Dev Control started.'
while ($true) {
    Show-Status
    Write-Host "`nMAIN WORKFLOWS" -ForegroundColor DarkGreen
    Write-Host ' 1) RETRIEVE, BUILD, AND TEST GITHUB SOURCE'
    Write-Host ' 2) DEBUG CURRENT BUILD'
    Write-Host ' 3) INSTALL PUBLISHED BUILD'
    Write-Host ' 4) MORE'
    Write-Host ' 0) EXIT'
    $choice=Read-Host "`nSelect"
    try {
        switch ($choice) {
            '1' { Retrieve-Build-Test; Pause-Control }
            '2' { Start-DebugTools; Pause-Control }
            '3' { Install-Published; Pause-Control }
            '4' { Show-MoreMenu }
            '0' { Write-Log 'Dev Control exited normally.'; break }
            default { Write-Host 'Choose a number shown in the menu.' -ForegroundColor Yellow; Pause-Control }
        }
    } catch {
        Write-Log ("ERROR: " + $_.Exception.ToString())
        Write-Host "`nFAILED SAFELY" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host 'No local edits were overwritten and no app was uninstalled.' -ForegroundColor Yellow
        Write-Host "Details: $SessionLog" -ForegroundColor DarkGray
        Pause-Control
    }
}
