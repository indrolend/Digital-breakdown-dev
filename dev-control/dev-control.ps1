[CmdletBinding()]
param(
    [ValidateSet('Menu','RetrieveBuildTest','InstallPublished','Debug','BuildCache','Mirror','Logs')]
    [string]$Mode = 'Menu'
)

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
$LastResultPath = Join-Path $StateRoot 'last-result.json'
$ActivityLog = Join-Path $LogDir 'recent-activity.log'

New-Item -ItemType Directory -Force -Path $StateRoot, $DownloadDir, $LogDir | Out-Null

function Add-Activity([string]$Text) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text
    Add-Content -Path $ActivityLog -Value $line
    if (Test-Path $ActivityLog) {
        $lines = @(Get-Content $ActivityLog -ErrorAction SilentlyContinue)
        if ($lines.Count -gt 80) { $lines | Select-Object -Last 80 | Set-Content $ActivityLog }
    }
}

function Save-Result([string]$Action, [string]$State, [string]$Summary, [string]$Detail = '') {
    [pscustomobject]@{
        action = $Action
        state = $State
        summary = $Summary
        detail = $Detail
        time = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -Path $LastResultPath -Encoding UTF8
    Add-Activity ("$State $Action - $Summary")
}

function Get-LastResult {
    if (-not (Test-Path $LastResultPath)) { return $null }
    try { return Get-Content $LastResultPath -Raw | ConvertFrom-Json } catch { return $null }
}

function Has-Command([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

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
            return [pscustomobject]@{ Manifest=(Get-Content $ManifestCachePath -Raw | ConvertFrom-Json); Source='cached' }
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
    Write-Host '[1/1] Clone authoritative GitHub source' -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path (Split-Path $Workspace) | Out-Null
    $cloneLog = Join-Path $LogDir 'last-git.log'
    & git clone $RepositoryUrl $Workspace *> $cloneLog
    if ($LASTEXITCODE -ne 0) { throw "GitHub source retrieval failed. See $cloneLog" }
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
    if ([bool](& git -C $repo status --porcelain)) {
        throw 'Managed source cache has local edits. Retrieval stopped without overwriting them.'
    }
    $gitLog = Join-Path $LogDir 'last-git.log'
    Write-Host '[1/4] Fetch authoritative GitHub main' -ForegroundColor Cyan
    & git -C $repo fetch origin main --prune *> $gitLog
    if ($LASTEXITCODE -ne 0) { throw "Git fetch failed. See $gitLog" }
    Write-Host '[2/4] Switch cache to main' -ForegroundColor Cyan
    & git -C $repo checkout main *>> $gitLog
    if ($LASTEXITCODE -ne 0) { throw "Could not switch cache to main. See $gitLog" }
    Write-Host '[3/4] Fast-forward cache to GitHub' -ForegroundColor Cyan
    & git -C $repo pull --ff-only origin main *>> $gitLog
    if ($LASTEXITCODE -ne 0) { throw "Cache cannot fast-forward to GitHub main. See $gitLog" }
    Write-Host '[4/4] Verify exact retrieved commit' -ForegroundColor Cyan
    $local = (& git -C $repo rev-parse HEAD).Trim()
    $remote = (& git -C $repo rev-parse origin/main).Trim()
    if ($local -ne $remote) { throw 'Retrieved cache does not exactly match origin/main.' }
    Write-Host "SUCCESS  GitHub source $($local.Substring(0,7))" -ForegroundColor Green
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

function Build-Cache([switch]$GitHubAuthoritative) {
    $repo=Ensure-Workspace
    $device=Get-Device
    $deployScript=Join-Path $repo 'tools\device\deploy-local.ps1'
    if (-not (Test-Path $deployScript)) { throw 'Deployment script is missing from the retrieved repository.' }
    $commit=(& git -C $repo rev-parse --short HEAD).Trim()
    $dirty=[bool](& git -C $repo status --porcelain)
    $buildId=$(if ($dirty) { "$commit-dirty" } else { $commit })
    $buildLog=Join-Path $LogDir 'last-build.log'
    Write-Host "[1/4] Build and install source $buildId" -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $deployScript -NoMirror -NoLogs *> $buildLog
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Last build output:' -ForegroundColor Yellow
        Get-Content $buildLog -Tail 18 -ErrorAction SilentlyContinue
        throw "Build/deploy failed. Full bounded log: $buildLog"
    }
    Write-Host '[2/4] Verify package installation' -ForegroundColor Cyan
    if (-not (Test-AppInstalled $device)) { throw 'Build completed, but the package is not installed.' }
    Write-Host '[3/4] Verify app launch' -ForegroundColor Cyan
    $pid=Start-AppAndVerify $device
    Write-Host '[4/4] Record exact tested revision' -ForegroundColor Cyan
    $apk=Join-Path $repo 'native-android\app\build\outputs\apk\debug\app-debug.apk'
    $hash=$(if (Test-Path $apk) { (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant() } else { 'unknown' })
    $kind=$(if ($GitHubAuthoritative) { 'github-source' } else { 'local-cache' })
    Save-InstalledRecord $buildId $kind $device.Serial $hash
    Write-Host "SUCCESS  $buildId running on $($device.Model)  PID $pid" -ForegroundColor Green
    try { Start-Mirror -Device $device } catch { Write-Host "Mirror skipped: $($_.Exception.Message)" -ForegroundColor Yellow }
    try { Start-Logs -Device $device } catch { Write-Host "Logs skipped: $($_.Exception.Message)" -ForegroundColor Yellow }
    return $buildId
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
    Write-Host '[1/5] Read published build manifest' -ForegroundColor Cyan
    $manifest=(Get-PublishedManifest).Manifest
    $device=Get-Device
    Write-Host "[2/5] Download and verify APK $($manifest.shortCommit)" -ForegroundColor Cyan
    $apk=Download-VerifiedApk $manifest
    Write-Host '[3/5] Install published APK' -ForegroundColor Cyan
    $output=& $device.Adb -s $device.Serial install -r -d $apk 2>&1
    if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -notmatch 'Success') { throw "APK installation failed: $($output -join ' ')" }
    Write-Host '[4/5] Launch and verify process' -ForegroundColor Cyan
    $pid=Start-AppAndVerify $device
    Write-Host '[5/5] Record published revision' -ForegroundColor Cyan
    $hash=(Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    Save-InstalledRecord ([string]$manifest.commit) 'published' $device.Serial $hash
    Write-Host "SUCCESS  Published $($manifest.shortCommit) running on $($device.Model)  PID $pid" -ForegroundColor Green
    try { Start-Mirror -Device $device } catch { Write-Host "Mirror skipped: $($_.Exception.Message)" -ForegroundColor Yellow }
    try { Start-Logs -Device $device } catch { Write-Host "Logs skipped: $($_.Exception.Message)" -ForegroundColor Yellow }
    return [string]$manifest.shortCommit
}

function Invoke-Worker([string]$Name, [scriptblock]$Work) {
    $started=Get-Date
    Clear-Host
    Write-Host 'DIGITAL BREAKDOWN WORKFLOW' -ForegroundColor Green
    Write-Host '--------------------------' -ForegroundColor DarkGreen
    Write-Host $Name -ForegroundColor White
    Write-Host ''
    try {
        $result=& $Work
        $seconds=[math]::Round(((Get-Date)-$started).TotalSeconds,1)
        $summary="$Name completed in ${seconds}s"
        if ($result) { $summary="$summary - $result" }
        Save-Result $Name 'SUCCESS' $summary
        Write-Host "`nSUCCESS" -ForegroundColor Green
        Write-Host $summary
    } catch {
        $seconds=[math]::Round(((Get-Date)-$started).TotalSeconds,1)
        Save-Result $Name 'FAILED' $_.Exception.Message $_.Exception.ToString()
        Write-Host "`nFAILED" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Elapsed: ${seconds}s" -ForegroundColor DarkGray
        Write-Host "Recent activity: $ActivityLog" -ForegroundColor DarkGray
    }
    Read-Host "`nPress Enter to close this workflow window" | Out-Null
}

function Start-ActionWindow([string]$Action) {
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Mode',$Action)
    $process=Start-Process powershell.exe -ArgumentList $args -PassThru
    $process.WaitForExit()
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
    $last=Get-LastResult
    Write-Host ''
    if ($last) {
        $color=$(if ($last.state -eq 'SUCCESS') { 'Green' } else { 'Red' })
        Write-Host ("Last result: {0}  {1}" -f $last.state,$last.summary) -ForegroundColor $color
    } else {
        Write-Host 'Last result: NONE' -ForegroundColor DarkGray
    }
}

if ($Mode -ne 'Menu') {
    switch ($Mode) {
        'RetrieveBuildTest' { Invoke-Worker 'RETRIEVE, BUILD, AND TEST GITHUB SOURCE' { Sync-GitHubSource | Out-Null; Build-Cache -GitHubAuthoritative } }
        'InstallPublished'  { Invoke-Worker 'INSTALL PUBLISHED BUILD' { Install-Published } }
        'Debug'             { Invoke-Worker 'DEBUG CURRENT BUILD' { $device=Get-Device; Start-Mirror -Device $device; Start-Logs -Device $device; 'debug tools opened' } }
        'BuildCache'        { Invoke-Worker 'BUILD LOCAL CACHE WITHOUT SYNCING' { Build-Cache } }
        'Mirror'            { Invoke-Worker 'MIRROR PHONE' { Start-Mirror; 'mirror opened' } }
        'Logs'              { Invoke-Worker 'OPEN NATIVE LOGS' { Start-Logs; 'log window opened' } }
    }
    exit
}

while ($true) {
    Show-Status
    Write-Host "`nMAIN WORKFLOWS" -ForegroundColor DarkGreen
    Write-Host ' 1) RETRIEVE, BUILD, AND TEST GITHUB SOURCE'
    Write-Host ' 2) DEBUG CURRENT BUILD'
    Write-Host ' 3) INSTALL PUBLISHED BUILD'
    Write-Host ' 4) BUILD LOCAL CACHE WITHOUT SYNCING'
    Write-Host ' 5) OPEN SOURCE CACHE'
    Write-Host ' 6) OPEN DEV WEBSITE'
    Write-Host ' 7) OPEN RECENT ACTIVITY'
    Write-Host ' 0) EXIT'
    $choice=Read-Host "`nSelect"
    switch ($choice) {
        '1' { Start-ActionWindow 'RetrieveBuildTest' }
        '2' { Start-ActionWindow 'Debug' }
        '3' { Start-ActionWindow 'InstallPublished' }
        '4' { Start-ActionWindow 'BuildCache' }
        '5' { Start-Process explorer.exe (Ensure-Workspace) }
        '6' { Start-Process $Portal }
        '7' { if (Test-Path $ActivityLog) { Start-Process notepad.exe $ActivityLog } }
        '0' { break }
        default { Start-Sleep -Milliseconds 500 }
    }
}
