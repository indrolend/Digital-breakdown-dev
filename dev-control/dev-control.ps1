$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$AppId = 'com.indrolend.digitalbreakdown.native'
$Activity = 'com.indrolend.digitalbreakdown.MainActivity'
$Portal = 'https://indrolend.github.io/Digital-breakdown-dev/'
$ManifestUrl = "$Portal/build-info.json"
$PublishedApkUrl = 'https://github.com/indrolend/Digital-breakdown-dev/releases/download/latest-dev/DigitalBreakdown-Android.apk'
$StateRoot = Join-Path $env:LOCALAPPDATA 'DigitalBreakdownDev'
$WorkspaceDefault = Join-Path $StateRoot 'source'
$DownloadDir = Join-Path $StateRoot 'downloads'
$LogDir = Join-Path $StateRoot 'logs'
$ConfigPath = Join-Path $StateRoot 'workspace.txt'
$ManifestCachePath = Join-Path $StateRoot 'build-info.cached.json'
$InstalledStatePath = Join-Path $StateRoot 'installed-build.json'
$SessionLog = Join-Path $LogDir ("dev-control-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

New-Item -ItemType Directory -Force -Path $StateRoot, $DownloadDir, $LogDir | Out-Null

function Write-Log([string]$Message) {
    Add-Content -Path $SessionLog -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Pause-Control { Read-Host "`nPress Enter to return" | Out-Null }
function Has-Command([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Open-Url([string]$Url) { Start-Process $Url }
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

function Get-Workspace {
    if (Test-Path $ConfigPath) {
        $saved = (Get-Content $ConfigPath -Raw).Trim()
        if ($saved -and (Test-Path (Join-Path $saved '.git'))) { return $saved }
    }
    $candidates = @(
        $WorkspaceDefault,
        (Join-Path $env:USERPROFILE 'Downloads\digital-breakdown-apk'),
        (Join-Path $env:USERPROFILE 'Documents\GitHub\digital-breakdown-apk'),
        (Join-Path $env:USERPROFILE 'source\repos\digital-breakdown-apk'),
        (Join-Path $env:USERPROFILE 'Desktop\digital-breakdown-apk')
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
    if (-not (Has-Command git)) { throw 'Git is missing. Install Git for Windows, then reopen Dev Control.' }
    Show-Step 1 1 'Retrieving source from GitHub'
    if (Test-Path $WorkspaceDefault) {
        $items = @(Get-ChildItem -Force $WorkspaceDefault -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) { throw "Managed source folder exists but is not a Git repository: $WorkspaceDefault" }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $WorkspaceDefault) | Out-Null
    & git clone 'https://github.com/indrolend/digital-breakdown-apk.git' $WorkspaceDefault
    if ($LASTEXITCODE -ne 0) { throw 'Repository retrieval failed. Sign in through Git Credential Manager and try again.' }
    Set-Content -Path $ConfigPath -Value $WorkspaceDefault
    return $WorkspaceDefault
}

function Get-Device {
    $adb = Resolve-Adb
    if (-not $adb) { throw 'ADB is missing. Install Android platform-tools or Android Studio.' }
    & $adb start-server | Out-Null
    $lines = & $adb devices 2>&1
    $unauthorized = @($lines | Select-Object -Skip 1 | Where-Object { $_ -match '\sunauthorized$' })
    if ($unauthorized.Count -gt 0) { throw 'Phone detected but unauthorized. Unlock it and approve USB debugging.' }
    $offline = @($lines | Select-Object -Skip 1 | Where-Object { $_ -match '\soffline$' })
    if ($offline.Count -gt 0) { throw 'Phone is offline. Reconnect USB, then restart ADB or accept the debugging prompt.' }
    $devices = @($lines | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' })
    if ($devices.Count -eq 0) { throw 'No authorized Android device is connected.' }
    if ($devices.Count -gt 1) { throw 'More than one Android device is connected. Disconnect the extra device.' }
    $serial = ($devices[0] -split '\s+')[0]
    $model = (& $adb -s $serial shell getprop ro.product.model 2>$null).Trim()
    $android = (& $adb -s $serial shell getprop ro.build.version.release 2>$null).Trim()
    return [pscustomobject]@{ Adb = $adb; Serial = $serial; Model = $model; Android = $android }
}

function Get-PublishedManifest([switch]$AllowCache) {
    try {
        $uri = "$ManifestUrl?t=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        $manifest = Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 12
        if (-not $manifest.commit -or -not $manifest.shortCommit) { throw 'Manifest is missing commit identity.' }
        if (-not $manifest.android -or -not $manifest.android.available) { throw 'Manifest does not expose an Android build.' }
        if (-not $manifest.android.sha256) { throw 'Manifest is missing the APK checksum.' }
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $ManifestCachePath -Encoding UTF8
        return [pscustomobject]@{ Manifest = $manifest; Source = 'live' }
    } catch {
        if ($AllowCache -and (Test-Path $ManifestCachePath)) {
            $cached = Get-Content $ManifestCachePath -Raw | ConvertFrom-Json
            return [pscustomobject]@{ Manifest = $cached; Source = 'cached'; Error = $_.Exception.Message }
        }
        throw
    }
}

function Get-LocalInfo {
    $repo = Get-Workspace
    if (-not $repo) { return $null }
    if (-not (Has-Command git)) { return [pscustomobject]@{ Path = $repo; State = 'GIT MISSING' } }
    $commit = (& git -C $repo rev-parse --short HEAD 2>$null).Trim()
    $branch = (& git -C $repo branch --show-current 2>$null).Trim()
    $dirty = [bool](& git -C $repo status --porcelain 2>$null)
    return [pscustomobject]@{ Path = $repo; Commit = $commit; Branch = $branch; Dirty = $dirty; State = 'READY' }
}

function Get-InstalledRecord {
    if (-not (Test-Path $InstalledStatePath)) { return $null }
    try { return Get-Content $InstalledStatePath -Raw | ConvertFrom-Json } catch { return $null }
}

function Save-InstalledRecord([string]$Commit, [string]$Kind, [string]$Serial, [string]$ApkHash) {
    [pscustomobject]@{
        commit = $Commit
        shortCommit = if ($Commit.Length -ge 7) { $Commit.Substring(0,7) } else { $Commit }
        kind = $Kind
        serial = $Serial
        apkSha256 = $ApkHash
        installedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -Path $InstalledStatePath -Encoding UTF8
}

function Test-AppInstalled($Device) {
    $path = (& $Device.Adb -s $Device.Serial shell pm path $AppId 2>$null | Out-String).Trim()
    return $path -match '^package:'
}

function Start-AppAndVerify($Device) {
    & $Device.Adb -s $Device.Serial shell am force-stop $AppId | Out-Null
    $output = & $Device.Adb -s $Device.Serial shell am start -W -n "$AppId/$Activity" 2>&1
    if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -match 'Error type|does not exist|Exception') {
        throw "App launch failed: $($output -join ' ')"
    }
    Start-Sleep -Milliseconds 800
    $pid = (& $Device.Adb -s $Device.Serial shell pidof $AppId 2>$null | Out-String).Trim()
    if (-not $pid) { throw 'The app was launched but no running process was found.' }
    return $pid
}

function Install-Apk($Device, [string]$ApkPath) {
    if (-not (Test-Path $ApkPath)) { throw "APK not found: $ApkPath" }
    $output = & $Device.Adb -s $Device.Serial install -r -d $ApkPath 2>&1
    $text = $output -join "`n"
    $output | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or $text -notmatch 'Success') {
        if ($text -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
            throw 'APK signature mismatch. Local and published builds are signed differently. Do not uninstall automatically; normalize the development signing key.'
        }
        if ($text -match 'INSTALL_FAILED_VERSION_DOWNGRADE') {
            throw 'Android rejected a version downgrade. The installer already requested downgrade permission; inspect package version metadata.'
        }
        throw "ADB installation failed: $text"
    }
    if (-not (Test-AppInstalled $Device)) { throw 'ADB reported success, but the package is not installed.' }
}

function Download-VerifiedApk($Manifest) {
    $commit = [string]$Manifest.shortCommit
    $expected = ([string]$Manifest.android.sha256).ToLowerInvariant()
    $apk = Join-Path $DownloadDir ("DigitalBreakdown-Android-$commit.apk")
    if (Test-Path $apk) {
        $cachedHash = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($cachedHash -eq $expected) {
            Write-Host 'Using verified cached APK.' -ForegroundColor DarkGreen
            return $apk
        }
        Remove-Item $apk -Force
    }
    $temp = "$apk.download"
    Remove-Item $temp -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -UseBasicParsing -Uri $PublishedApkUrl -OutFile $temp -TimeoutSec 120
    $actual = (Get-FileHash $temp -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
        throw "APK checksum mismatch. Expected $expected but received $actual. Nothing was installed."
    }
    Move-Item $temp $apk -Force
    return $apk
}

function Sync-Source {
    $repo = Ensure-Workspace
    if (-not (Has-Command git)) { throw 'Git is missing.' }
    $dirty = [bool](& git -C $repo status --porcelain)
    if ($dirty) {
        Write-Host 'Source was not changed because local edits exist:' -ForegroundColor Yellow
        & git -C $repo status --short --branch
        return
    }
    Show-Step 1 3 'Fetch GitHub main'
    & git -C $repo fetch origin main
    if ($LASTEXITCODE -ne 0) { throw 'Git fetch failed.' }
    Show-Step 2 3 'Switch to main'
    & git -C $repo checkout main
    if ($LASTEXITCODE -ne 0) { throw 'Could not switch to main.' }
    Show-Step 3 3 'Fast-forward local source'
    & git -C $repo pull --ff-only origin main
    if ($LASTEXITCODE -ne 0) { throw 'Fast-forward pull failed. Local history differs from GitHub main.' }
    Write-Host 'Source is synchronized.' -ForegroundColor Green
}

function Build-Test-Local {
    $repo = Ensure-Workspace
    $device = Get-Device
    $deployScript = Join-Path $repo 'tools\device\deploy-local.ps1'
    if (-not (Test-Path $deployScript)) { throw 'Local deployment script is missing. Sync source from GitHub.' }
    if (-not (Has-Command git)) { throw 'Git is needed to identify the local build.' }
    $commit = (& git -C $repo rev-parse --short HEAD).Trim()
    $dirty = [bool](& git -C $repo status --porcelain)
    $buildId = if ($dirty) { "$commit-dirty" } else { $commit }

    Show-Step 1 4 "Build and install local source $buildId"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $deployScript -NoMirror -NoLogs
    if ($LASTEXITCODE -ne 0) { throw 'Local build/deploy script failed. Review the output above.' }
    Show-Step 2 4 'Verify package installation'
    if (-not (Test-AppInstalled $device)) { throw 'Local deploy returned success, but the package is not installed.' }
    Show-Step 3 4 'Verify app launch'
    $pid = Start-AppAndVerify $device
    Show-Step 4 4 'Record exact tested revision'
    $apk = Join-Path $repo 'native-android\app\build\outputs\apk\debug\app-debug.apk'
    $hash = if (Test-Path $apk) { (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant() } else { 'unknown' }
    Save-InstalledRecord $buildId 'local' $device.Serial $hash
    Write-Host "LOCAL BUILD READY: $buildId (PID $pid)" -ForegroundColor Green
    Start-DebugTools -Device $device
}

function Install-Published {
    Show-Step 1 6 'Read completed build manifest'
    $published = Get-PublishedManifest
    $manifest = $published.Manifest
    $device = Get-Device
    Show-Step 2 6 "Download APK $($manifest.shortCommit)"
    $apk = Download-VerifiedApk $manifest
    Show-Step 3 6 'Verify APK checksum'
    $hash = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$manifest.android.sha256).ToLowerInvariant()) { throw 'Cached APK failed final checksum verification.' }
    Show-Step 4 6 'Install without deleting app data'
    Install-Apk $device $apk
    Show-Step 5 6 'Launch and verify process'
    $pid = Start-AppAndVerify $device
    Show-Step 6 6 'Record exact tested revision'
    Save-InstalledRecord ([string]$manifest.commit) 'published' $device.Serial $hash
    Write-Host "PUBLISHED BUILD READY: $($manifest.shortCommit) (PID $pid)" -ForegroundColor Green
    Start-DebugTools -Device $device
}

function Start-Mirror($Device = $null) {
    if (-not $Device) { $Device = Get-Device }
    $scrcpy = Resolve-Scrcpy
    if (-not $scrcpy) { throw 'scrcpy is missing. Install scrcpy or place scrcpy.exe in a recognized location.' }
    Start-Process -FilePath $scrcpy -ArgumentList @('-s', $Device.Serial, '--max-size=1024', '--video-bit-rate=4M', '--stay-awake', '--no-audio', '--window-title=Digital Breakdown - Stylo 4')
}

function Start-Logs($Device = $null) {
    if (-not $Device) { $Device = Get-Device }
    $command = "& `"$($Device.Adb)`" -s $($Device.Serial) logcat -v color -s DBNATIVE:I AndroidRuntime:E '*:S'"
    Start-Process powershell.exe -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $command)
}

function Start-DebugTools($Device = $null) {
    if (-not $Device) { $Device = Get-Device }
    try { Start-Mirror -Device $Device } catch { Write-Host "Mirror skipped: $($_.Exception.Message)" -ForegroundColor Yellow }
    try { Start-Logs -Device $Device } catch { Write-Host "Logs skipped: $($_.Exception.Message)" -ForegroundColor Yellow }
}

function Show-EnvironmentCheck {
    Clear-Host
    Write-Host 'DEVELOPMENT ENVIRONMENT' -ForegroundColor Green
    Write-Host '-----------------------' -ForegroundColor DarkGreen
    $items = @()
    $items += [pscustomobject]@{ Name='PowerShell'; Ready=$PSVersionTable.PSVersion.Major -ge 5; Detail=$PSVersionTable.PSVersion.ToString() }
    $items += [pscustomobject]@{ Name='Git'; Ready=(Has-Command git); Detail=$(if (Has-Command git) { (& git --version) } else { 'missing' }) }
    $adb = Resolve-Adb
    $items += [pscustomobject]@{ Name='ADB'; Ready=[bool]$adb; Detail=$(if ($adb) { $adb } else { 'missing' }) }
    $scrcpy = Resolve-Scrcpy
    $items += [pscustomobject]@{ Name='scrcpy'; Ready=[bool]$scrcpy; Detail=$(if ($scrcpy) { $scrcpy } else { 'missing' }) }
    $repo = Get-Workspace
    $items += [pscustomobject]@{ Name='Source'; Ready=[bool]$repo; Detail=$(if ($repo) { $repo } else { 'not retrieved yet' }) }
    try { $device = Get-Device; $items += [pscustomobject]@{ Name='Phone'; Ready=$true; Detail="$($device.Model), Android $($device.Android)" } }
    catch { $items += [pscustomobject]@{ Name='Phone'; Ready=$false; Detail=$_.Exception.Message } }
    try { $published = Get-PublishedManifest; $items += [pscustomobject]@{ Name='Published'; Ready=$true; Detail="$($published.Manifest.shortCommit), manifest valid" } }
    catch { $items += [pscustomobject]@{ Name='Published'; Ready=$false; Detail=$_.Exception.Message } }
    foreach ($item in $items) {
        $state = if ($item.Ready) { 'READY' } else { 'NEEDS ATTENTION' }
        $color = if ($item.Ready) { 'Green' } else { 'Yellow' }
        Write-Host ("{0,-11} {1,-15} {2}" -f $item.Name, $state, $item.Detail) -ForegroundColor $color
    }
    Write-Host "`nSession log: $SessionLog" -ForegroundColor DarkGray
    Pause-Control
}

function Show-Status {
    Clear-Host
    Write-Host 'DIGITAL BREAKDOWN DEV CONTROL' -ForegroundColor Green
    Write-Host '-----------------------------' -ForegroundColor DarkGreen

    try {
        $published = Get-PublishedManifest -AllowCache
        $sourceLabel = if ($published.Source -eq 'live') { 'READY' } else { 'CACHED / PORTAL OFFLINE' }
        $color = if ($published.Source -eq 'live') { 'Green' } else { 'Yellow' }
        Write-Host ("Published : {0}  {1}" -f $published.Manifest.shortCommit, $sourceLabel) -ForegroundColor $color
    } catch {
        Write-Host ("Published : PORTAL ERROR  {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }

    $device = $null
    try {
        $device = Get-Device
        Write-Host ("Phone     : {0}  CONNECTED" -f $device.Model) -ForegroundColor Cyan
    } catch {
        Write-Host ("Phone     : {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }

    $local = Get-LocalInfo
    if ($local -and $local.State -eq 'READY') {
        $suffix = if ($local.Dirty) { '-dirty' } else { '' }
        Write-Host ("Local     : {0}{1}  {2}" -f $local.Commit, $suffix, $local.Branch)
    } elseif ($local) {
        Write-Host ("Local     : {0}" -f $local.State) -ForegroundColor Yellow
    } else {
        Write-Host 'Local     : NOT RETRIEVED'
    }

    $record = Get-InstalledRecord
    if ($device -and (Test-AppInstalled $device)) {
        if ($record -and $record.serial -eq $device.Serial) {
            Write-Host ("Installed : {0}  {1}" -f $record.shortCommit, $record.kind.ToUpperInvariant()) -ForegroundColor Green
        } else {
            Write-Host 'Installed : PRESENT  REVISION UNKNOWN' -ForegroundColor Yellow
        }
    } elseif ($device) {
        Write-Host 'Installed : NOT INSTALLED' -ForegroundColor Yellow
    } else {
        Write-Host 'Installed : PHONE UNAVAILABLE' -ForegroundColor DarkGray
    }
}

function Show-MoreMenu {
    while ($true) {
        Clear-Host
        Write-Host 'MORE TOOLS' -ForegroundColor Green
        Write-Host '----------' -ForegroundColor DarkGreen
        Write-Host ' 1) OPEN SOURCE FOLDER'
        Write-Host ' 2) OPEN DEV WEBSITE'
        Write-Host ' 3) MIRROR ONLY'
        Write-Host ' 4) LOGS ONLY'
        Write-Host ' 5) CHECK ENVIRONMENT'
        Write-Host ' 6) OPEN SESSION LOG'
        Write-Host ' 0) BACK'
        $choice = Read-Host "`nSelect"
        try {
            switch ($choice) {
                '1' { Start-Process explorer.exe (Ensure-Workspace) }
                '2' { Open-Url $Portal }
                '3' { Start-Mirror; Pause-Control }
                '4' { Start-Logs; Pause-Control }
                '5' { Show-EnvironmentCheck }
                '6' { Start-Process notepad.exe $SessionLog }
                '0' { return }
                default { Write-Host 'Choose a number shown in the menu.' -ForegroundColor Yellow; Pause-Control }
            }
        } catch {
            Write-Log ("ERROR More menu: " + $_.Exception.Message)
            Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
            Pause-Control
        }
    }
}

Write-Log 'Dev Control started.'
while ($true) {
    Show-Status
    Write-Host "`nMAIN WORKFLOWS" -ForegroundColor DarkGreen
    Write-Host ' 1) BUILD AND TEST LOCAL SOURCE'
    Write-Host ' 2) INSTALL PUBLISHED BUILD'
    Write-Host ' 3) DEBUG CURRENT BUILD'
    Write-Host ' 4) SYNC SOURCE FROM GITHUB'
    Write-Host ' 5) MORE'
    Write-Host ' 0) EXIT'
    $choice = Read-Host "`nSelect"
    try {
        switch ($choice) {
            '1' { Build-Test-Local; Pause-Control }
            '2' { Install-Published; Pause-Control }
            '3' { Start-DebugTools; Pause-Control }
            '4' { Sync-Source; Pause-Control }
            '5' { Show-MoreMenu }
            '0' { Write-Log 'Dev Control exited normally.'; break }
            default { Write-Host 'Choose a number shown in the menu.' -ForegroundColor Yellow; Pause-Control }
        }
    } catch {
        Write-Log ("ERROR Main menu: " + $_.Exception.ToString())
        Write-Host "`nFAILED SAFELY" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "No source was overwritten and no app was uninstalled." -ForegroundColor Yellow
        Write-Host "Details: $SessionLog" -ForegroundColor DarkGray
        Pause-Control
    }
}
