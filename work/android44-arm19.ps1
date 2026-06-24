param(
  [ValidateSet("status", "configure", "start", "wait", "install", "hosts", "mount", "preload-rest", "preload-small", "preload-full", "launch", "run", "logcat", "stop")]
  [string]$Action = "status",
  [string]$ApkPath,
  [switch]$WipeData
)

$ErrorActionPreference = "Stop"

$avdName = "kssma_arm19"
$preferredSerial = "emulator-5582"
$fallbackSerials = @("127.0.0.1:5583")
$serial = $preferredSerial
$package = "com.square_enix.million_cn"
$activity = "com.test.enter.LogoActivity"
$sdkClassic = Join-Path $env:USERPROFILE "AppData\Local\Android\Sdk-classic-arm"
$emulatorExe = Join-Path $sdkClassic "tools\emulator.exe"
$emulatorArmExe = Join-Path $sdkClassic "tools\emulator-arm.exe"
$mksdcardExe = Join-Path $sdkClassic "tools\mksdcard.exe"
$adbExe = "C:\Program Files (x86)\platform-tools\adb.exe"
$avdDir = Join-Path $env:USERPROFILE ".android\avd\$avdName.avd"
$configPath = Join-Path $avdDir "config.ini"
$sdcardPath = Join-Path $avdDir "sdcard.img"
$stdoutLog = Join-Path $PSScriptRoot "android44-arm19-runtime.out.log"
$stderrLog = Join-Path $PSScriptRoot "android44-arm19-runtime.err.log"
$runLogcat = Join-Path $PSScriptRoot "android44-arm19-last-run-logcat.txt"
$runEvents = Join-Path $PSScriptRoot "android44-arm19-last-run-events.txt"
$runProcesses = Join-Path $PSScriptRoot "android44-arm19-last-run-processes.txt"
$runScreenshot = Join-Path $PSScriptRoot "kssma-arm19-last-run.png"
$sampleDumpRoot = Join-Path $PSScriptRoot "million_cn\sdcard_dump"
$sampleSaveDir = Join-Path $PSScriptRoot "million_cn\sdcard_dump\sdcard\Android\data\com.square_enix.million_cn\files\save"
$resourceZipPath = Join-Path (Split-Path $PSScriptRoot -Parent) "base\com.square_enix.million_cn-140330.zip"
$deviceSaveDir = "/storage/sdcard/Android/data/$package/files/save"
$mediaSaveDir = "/mnt/media_rw/sdcard/Android/data/$package/files/save"
$internalSaveDir = "/data/local/tmp/kssma-save"
$sdcardSize = "4096M"
$displaySize = "1280x720"
$displayDensity = "240"

function Ensure-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing file: $Path"
  }
}

function Set-AvdConfigValue {
  param(
    [string]$Key,
    [string]$Value
  )

  $lines = @(Get-Content -LiteralPath $configPath)
  $pattern = "^$([regex]::Escape($Key))="
  $updated = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $pattern) {
      $lines[$i] = "$Key=$Value"
      $updated = $true
      break
    }
  }

  if (-not $updated) {
    $lines += "$Key=$Value"
  }

  Set-Content -LiteralPath $configPath -Value $lines
}

function Get-ShortPath {
  param([string]$Path)
  $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).Path
  if (-not $resolved) {
    return $Path
  }

  try {
    return (New-Object -ComObject Scripting.FileSystemObject).GetFile($resolved).ShortPath
  } catch {
    return $resolved
  }
}

function Assert-LocalChildPath {
  param(
    [string]$Child,
    [string]$Parent
  )

  $childFull = [System.IO.Path]::GetFullPath($Child)
  $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
  if (-not $childFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to modify path outside ${parentFull}: $childFull"
  }
}

function Restore-SampleSaveDump {
  Ensure-File $resourceZipPath

  $sampleRoot = Join-Path $PSScriptRoot "million_cn"
  Assert-LocalChildPath $sampleDumpRoot $sampleRoot

  # ponytail: resource corruption is cheaper to fix by restoring the original 140330 save dump than by auditing every file.
  if (Test-Path -LiteralPath $sampleDumpRoot) {
    Remove-Item -LiteralPath $sampleDumpRoot -Recurse -Force
  }
  New-Item -ItemType Directory -Path $sampleDumpRoot | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($resourceZipPath, $sampleDumpRoot)

  Ensure-File $sampleSaveDir
}

function Resolve-ApkPath {
  if ($ApkPath) {
    return (Resolve-Path -LiteralPath $ApkPath).Path
  }

  $latest = Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*signed.apk" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if (-not $latest) {
    throw "No signed APK found under $PSScriptRoot"
  }

  return $latest.FullName
}

function Invoke-Adb {
  param(
    [string[]]$Arguments,
    [int]$TimeoutSeconds = 120,
    [switch]$AllowFailure
  )

  $stdoutPath = [System.IO.Path]::GetTempFileName()
  $stderrPath = [System.IO.Path]::GetTempFileName()
  try {
    $process = Start-Process -FilePath $adbExe -ArgumentList $Arguments -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      throw "adb timed out after ${TimeoutSeconds}s: adb $($Arguments -join ' ')"
    }
    $process.Refresh()

    $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
    $exitCode = if ($null -eq $process.ExitCode) { 0 } else { $process.ExitCode }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
      throw "adb failed with exit code ${exitCode}: adb $($Arguments -join ' ')`n$stderr"
    }

    if ($stdout) {
      $stdout -split "\r?\n" | Where-Object { $_ -ne "" }
    }
  } finally {
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
  }
}

function Test-DeviceFile {
  param([string]$Path)
  $output = (Invoke-Adb -Arguments @("-s", $serial, "shell", "ls", $Path, "2>/dev/null") -AllowFailure | Out-String).Trim()
  return $output -ne ""
}

function Get-DeviceState {
  $line = Invoke-Adb @("devices") | Where-Object { $_ -match "^$([regex]::Escape($serial))\s+" } | Select-Object -First 1
  if (-not $line) {
    return "missing"
  }
  return (($line -split "\s+")[1]).Trim()
}

function Test-UsableSerial {
  param([string]$Candidate)

  $line = Invoke-Adb @("devices") | Where-Object { $_ -match "^$([regex]::Escape($Candidate))\s+device\b" } | Select-Object -First 1
  if (-not $line) {
    return $false
  }

  $abi = try {
    (Invoke-Adb -Arguments @("-s", $Candidate, "shell", "getprop", "ro.product.cpu.abi") -TimeoutSeconds 5 | Out-String).Trim()
  } catch {
    ""
  }
  $release = try {
    (Invoke-Adb -Arguments @("-s", $Candidate, "shell", "getprop", "ro.build.version.release") -TimeoutSeconds 5 | Out-String).Trim()
  } catch {
    ""
  }

  return $abi -eq "armeabi-v7a" -and $release -eq "4.4.2"
}

function Resolve-Serial {
  if (Test-UsableSerial $preferredSerial) {
    $script:serial = $preferredSerial
    return $serial
  }

  foreach ($candidate in $fallbackSerials) {
    if (Test-UsableSerial $candidate) {
      $script:serial = $candidate
      return $serial
    }
  }

  $script:serial = $preferredSerial
  return $serial
}

function Configure-Runtime {
  Ensure-File $configPath
  Ensure-File $mksdcardExe

  Set-AvdConfigValue "abi.type" "armeabi-v7a"
  Set-AvdConfigValue "target" "android-19"
  Set-AvdConfigValue "image.sysdir.1" "system-images\android-19\default\armeabi-v7a\"
  Set-AvdConfigValue "disk.dataPartition.size" "1536M"
  Set-AvdConfigValue "hw.ramSize" "2048"
  Set-AvdConfigValue "vm.heapSize" "256M"
  Set-AvdConfigValue "hw.audioInput" "yes"
  Set-AvdConfigValue "hw.audioOutput" "yes"
  Set-AvdConfigValue "hw.lcd.width" "1280"
  Set-AvdConfigValue "hw.lcd.height" "720"
  Set-AvdConfigValue "hw.lcd.density" "240"
  Set-AvdConfigValue "hw.initialOrientation" "landscape"
  Set-AvdConfigValue "skin.name" "1280x720"
  Set-AvdConfigValue "hw.sdCard" "yes"
  Set-AvdConfigValue "sdcard.size" $sdcardSize

  $needsSdcard = -not (Test-Path -LiteralPath $sdcardPath)
  if (-not $needsSdcard) {
    $sdcardInfo = Get-Item -LiteralPath $sdcardPath
    $needsSdcard = $sdcardInfo.Length -lt 3900MB -or $sdcardInfo.Length -gt 4200MB
  }

  if ($needsSdcard) {
    if (Test-Path -LiteralPath $sdcardPath) {
      $backupPath = "$sdcardPath.$((Get-Date).ToString('yyyyMMddHHmmss')).bak"
      Move-Item -LiteralPath $sdcardPath -Destination $backupPath
    }
    & $mksdcardExe $sdcardSize $sdcardPath | Out-Null
  }

  Set-AvdConfigValue "sdcard.path" (Get-ShortPath $sdcardPath)
}

function Start-Runtime {
  Ensure-File $emulatorExe
  Configure-Runtime
  Resolve-Serial | Out-Null

  $deviceState = Get-DeviceState
  if ($deviceState -eq "device") {
    return
  }
  if ($deviceState -ne "missing") {
    Stop-Runtime
  }

  Remove-Item -LiteralPath $stdoutLog, $stderrLog -ErrorAction SilentlyContinue
  $args = @(
    "-avd", $avdName,
    "-engine", "classic",
    "-ports", "5582,5583",
    "-no-snapshot-load",
    "-no-snapshot-save",
    "-no-boot-anim",
    "-gpu", "on",
    "-show-kernel",
    "-verbose"
  )

  if ($WipeData) {
    $args += "-wipe-data"
  }

  # ponytail: classic ARM is the least-wrong runtime for this ARM-only 2013 APK; x86/Houdini crashes are a false target.
  Start-Process -FilePath $emulatorExe -ArgumentList $args -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -WindowStyle Hidden
}

function Wait-Runtime {
  param([int]$TimeoutSeconds = 300)

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    Resolve-Serial | Out-Null
    if ((Get-DeviceState) -eq "device") {
      $boot = try {
        (Invoke-Adb -Arguments @("-s", $serial, "shell", "getprop", "sys.boot_completed") -TimeoutSeconds 5 | Out-String).Trim()
      } catch {
        ""
      }
      if ($boot -eq "1") {
        Set-DisplayProfile
        return
      }
    }
    Start-Sleep -Seconds 10
  }

  throw "Timed out waiting for $serial"
}

function Set-DisplayProfile {
  # ponytail: the classic ARM emulator can boot from stale 320x480 hardware-qemu.ini; wm override is the shortest reliable fix.
  Invoke-Adb -Arguments @("-s", $serial, "shell", "wm", "size", $displaySize) -TimeoutSeconds 10 | Out-Null
  Invoke-Adb -Arguments @("-s", $serial, "shell", "wm", "density", $displayDensity) -TimeoutSeconds 10 | Out-Null
}

function Install-Game {
  $resolvedApkPath = Resolve-ApkPath
  Wait-Runtime
  Invoke-Adb -Arguments @("-s", $serial, "install", "-r", "-f", $resolvedApkPath) -TimeoutSeconds 600
}

function Set-LocalHosts {
  Wait-Runtime
  Invoke-Adb -Arguments @("-s", $serial, "root") -TimeoutSeconds 10 -AllowFailure | Out-Null
  Invoke-Adb -Arguments @("-s", $serial, "remount") -TimeoutSeconds 20 | Out-Null
  $hosts = "127.0.0.1 localhost`n10.0.2.2 game.ma.mobimon.com.tw`n10.0.2.2 dlc.game-CBT.ma.sdo.com`n"
  $hostsPath = Join-Path $env:TEMP "kssma-arm19-hosts"
  try {
    Set-Content -LiteralPath $hostsPath -Value $hosts -NoNewline
    Invoke-Adb -Arguments @("-s", $serial, "push", $hostsPath, "/system/etc/hosts") -TimeoutSeconds 20 | Out-Null
    Invoke-Adb -Arguments @("-s", $serial, "shell", "chmod", "644", "/system/etc/hosts") | Out-Null
  } finally {
    Remove-Item -LiteralPath $hostsPath -Force -ErrorAction SilentlyContinue
  }
  Invoke-Adb -Arguments @("-s", $serial, "shell", "cat", "/system/etc/hosts")
}

function Preload-DownloadDir {
  param(
    [string]$Name,
    [string]$Sentinel
  )

  Wait-Runtime
  if ($Sentinel -and (Test-DeviceFile "$deviceSaveDir/download/$Name/$Sentinel")) {
    return [pscustomobject]@{
      Directory = "download/$Name"
      Files = 0
      Status = "already-present"
    }
  }

  $sourceDir = Join-Path $sampleSaveDir "download\$Name"
  Ensure-File $sourceDir
  Invoke-Adb @("-s", $serial, "shell", "mkdir", "-p", "$deviceSaveDir/download/$Name") | Out-Null

  $files = Get-ChildItem -LiteralPath $sourceDir -Recurse -File
  foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($sourceDir.Length).TrimStart("\", "/") -replace "\\", "/"
    $devicePath = "$deviceSaveDir/download/$Name/$relativePath"
    $deviceParent = $devicePath -replace "/[^/]+$", ""
    Invoke-Adb @("-s", $serial, "shell", "mkdir", "-p", $deviceParent) | Out-Null
    Invoke-Adb @("-s", $serial, "push", $file.FullName, $devicePath) | Out-Null
  }

  [pscustomobject]@{
    Directory = "download/$Name"
    Files = $files.Count
    Status = "pushed"
  }
}

function Preload-SaveFile {
  param([string]$RelativePath)

  Wait-Runtime
  $sourcePath = Join-Path $sampleSaveDir $RelativePath
  Ensure-File $sourcePath

  $devicePath = "$deviceSaveDir/$($RelativePath -replace '\\', '/')"
  if (Test-DeviceFile $devicePath) {
    return [pscustomobject]@{
      File = $RelativePath
      Status = "already-present"
    }
  }

  $deviceParent = $devicePath -replace "/[^/]+$", ""
  Invoke-Adb @("-s", $serial, "shell", "mkdir", "-p", $deviceParent) | Out-Null
  Invoke-Adb @("-s", $serial, "push", $sourcePath, $devicePath) | Out-Null

  [pscustomobject]@{
    File = $RelativePath
    Status = "pushed"
  }
}

function Preload-RestResources {
  Preload-DownloadDir "rest" "que_adv"
  Invoke-Adb @("-s", $serial, "shell", "ls", "-l", "$deviceSaveDir/download/rest/que_adv")
}

function Preload-SmallResources {
  # ponytail: preload only the small tutorial-adjacent dumps; full save/image/sound can wait until a screen proves it needs them.
  # ponytail: also seed the tiny version/masterdata files so the main path skips first-run updater churn.
  Preload-SaveFile "appdata/save_version"
  Preload-SaveFile "database/master_card"
  Preload-SaveFile "database/master_item"
  Preload-SaveFile "database/master_cardcategory"
  Preload-SaveFile "database/master_boss"
  Preload-SaveFile "database/master_scol"
  Preload-SaveFile "database/master_combo"
  Preload-SaveFile "download/image/adv/adv_chara111"
  Preload-SaveFile "download/sound/bgm_common1.ogg"
  Preload-DownloadDir "rest" "que_adv"
  Preload-DownloadDir "scenario" "scsc_1010101"
  Preload-DownloadDir "pack" "mainbg/mainbg_an_0_0"
}

function Repair-SaveAppDataMainBg {
  $sourcePath = Join-Path $sampleSaveDir "appdata\save_appdata"
  Ensure-File $sourcePath

  $bytes = [System.IO.File]::ReadAllBytes($sourcePath)
  $needle = [System.Text.Encoding]::ASCII.GetBytes("mainbg_70_sp")
  $replacement = [System.Text.Encoding]::ASCII.GetBytes("mainbg_an")
  $patched = $false

  for ($i = 0; $i -le $bytes.Length - $needle.Length; $i++) {
    $matched = $true
    for ($j = 0; $j -lt $needle.Length; $j++) {
      if ($bytes[$i + $j] -ne $needle[$j]) {
        $matched = $false
        break
      }
    }
    if (-not $matched) {
      continue
    }

    # ponytail: the dump references missing mainbg_70_sp; fall back to the bundled mainbg_an set already present in the 140330 pack.
    for ($j = 0; $j -lt $needle.Length; $j++) {
      $bytes[$i + $j] = if ($j -lt $replacement.Length) { $replacement[$j] } else { 0 }
    }
    $patched = $true
    $i += $needle.Length - 1
  }

  $tempPath = Join-Path $env:TEMP "kssma-save_appdata"
  try {
    [System.IO.File]::WriteAllBytes($tempPath, $bytes)
    Invoke-Adb -Arguments @("-s", $serial, "shell", "mkdir", "-p", "$internalSaveDir/appdata") | Out-Null
    Invoke-Adb -Arguments @("-s", $serial, "push", $tempPath, "$internalSaveDir/appdata/save_appdata") | Out-Null
    Invoke-Adb -Arguments @("-s", $serial, "shell", "chmod", "644", "$internalSaveDir/appdata/save_appdata") | Out-Null
  } finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
  }

  [pscustomobject]@{
    File = "appdata/save_appdata"
    Status = if ($patched) { "patched-mainbg" } else { "unchanged" }
  }
}

function Repair-MainBgPack {
  $sourceDir = Join-Path $sampleSaveDir "download\pack\mainbg"
  Ensure-File $sourceDir

  $deviceDir = "$internalSaveDir/download/pack/mainbg"
  Invoke-Adb -Arguments @("-s", $serial, "shell", "mkdir", "-p", $deviceDir) | Out-Null

  Invoke-Adb -Arguments @("-s", $serial, "push", "$sourceDir\.", $deviceDir) -TimeoutSeconds 300 | Out-Null

  # ponytail: delete only the stale two-part aliases; globs here also match real mainbg_*_*_* shards.
  foreach ($prefix in @("an", "mg", "nn", "nt")) {
    foreach ($part in @("0", "1")) {
      Invoke-Adb -Arguments @("-s", $serial, "shell", "rm", "-f", "$deviceDir/mainbg_${prefix}_${part}", "$deviceDir/mainbg_${prefix}_${part}.png") -AllowFailure | Out-Null
    }
  }

  Invoke-Adb -Arguments @("-s", $serial, "shell", "chmod", "-R", "755", $deviceDir) | Out-Null

  [pscustomobject]@{
    Directory = "download/pack/mainbg"
    Status = "repaired"
  }
}

function Preload-FullResources {
  # ponytail: put the full 140330 runtime dump on /data and bind it to the path the client already uses; keep this until direct sdcard import is revalidated.
  Wait-Runtime
  Restore-SampleSaveDump
  Invoke-Adb -Arguments @("-s", $serial, "root") -TimeoutSeconds 10 -AllowFailure | Out-Null
  Invoke-Adb -Arguments @("-s", $serial, "shell", "umount", $deviceSaveDir) -AllowFailure | Out-Null
  Invoke-Adb -Arguments @("-s", $serial, "shell", "rm", "-rf", $internalSaveDir) -TimeoutSeconds 120 | Out-Null
  Invoke-Adb -Arguments @("-s", $serial, "shell", "mkdir", "-p", $internalSaveDir) | Out-Null
  Invoke-Adb -Arguments @("-s", $serial, "push", "$sampleSaveDir\.", $internalSaveDir) -TimeoutSeconds 3600
  Invoke-Adb -Arguments @("-s", $serial, "shell", "chmod", "-R", "755", $internalSaveDir) | Out-Null
  Repair-SaveAppDataMainBg
  Repair-MainBgPack
  Mount-SaveResources
  Invoke-Adb -Arguments @("-s", $serial, "shell", "df", "/data", $deviceSaveDir)
}

function Mount-SaveResources {
  Wait-Runtime
  Invoke-Adb -Arguments @("-s", $serial, "root") -TimeoutSeconds 10 -AllowFailure | Out-Null
  Invoke-Adb -Arguments @("-s", $serial, "shell", "umount", $deviceSaveDir) -AllowFailure | Out-Null
  Invoke-Adb -Arguments @("-s", $serial, "shell", "umount", $mediaSaveDir) -AllowFailure | Out-Null
  Invoke-Adb -Arguments @("-s", $serial, "shell", "mkdir", "-p", $mediaSaveDir, $deviceSaveDir) | Out-Null
  # ponytail: bind both the raw sdcard and FUSE paths; Android 4.4 can leave one mount as a deleted shadow after app startup.
  Invoke-Adb -Arguments @("-s", $serial, "shell", "mount", "-o", "bind", $internalSaveDir, $mediaSaveDir) | Out-Null
  Invoke-Adb -Arguments @("-s", $serial, "shell", "mount", "-o", "bind", $internalSaveDir, $deviceSaveDir) | Out-Null
}

function Restore-RuntimeBaseline {
  Set-LocalHosts | Out-Null
  if (Test-DeviceFile "$internalSaveDir/download/rest/treasurebox") {
    Mount-SaveResources
  }
}

function Launch-Game {
  Wait-Runtime
  Restore-RuntimeBaseline
  Invoke-Adb @("-s", $serial, "shell", "input", "keyevent", "66") | Out-Null
  Invoke-Adb @("-s", $serial, "shell", "am", "force-stop", $package) | Out-Null
  Invoke-Adb @("-s", $serial, "shell", "am", "start", "-n", "$package/$activity")
}

function Save-AdbOutput {
  param(
    [string[]]$Arguments,
    [string]$Path,
    [int]$TimeoutSeconds = 20
  )

  try {
    Invoke-Adb -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds | Set-Content -LiteralPath $Path
  } catch {
    "adb capture failed: $($_.Exception.Message)" | Set-Content -LiteralPath $Path
  }
}

function Save-RunArtifacts {
  Save-AdbOutput -Arguments @("-s", $serial, "logcat", "-d", "-v", "time") -Path $runLogcat
  Save-AdbOutput -Arguments @("-s", $serial, "logcat", "-b", "events", "-d", "-v", "time") -Path $runEvents
  Save-AdbOutput -Arguments @("-s", $serial, "shell", "dumpsys", "activity", "processes") -Path $runProcesses
  try {
    Invoke-Adb -Arguments @("-s", $serial, "shell", "screencap", "-p", "/sdcard/kssma-arm19-last-run.png") -TimeoutSeconds 10 | Out-Null
    Invoke-Adb -Arguments @("-s", $serial, "pull", "/sdcard/kssma-arm19-last-run.png", $runScreenshot) -TimeoutSeconds 20 | Out-Null
  } catch {
    "adb screenshot failed: $($_.Exception.Message)" | Set-Content -LiteralPath "$runScreenshot.txt"
  }
  Get-Content -LiteralPath $runLogcat | Select-String -Pattern "Fatal signal|signal 6|signal 11|librooneyj|jni_loadTexture|connect/app|check_inspection" |
    Select-Object -Last 80
  Get-Content -LiteralPath $runEvents | Select-String -Pattern "am_crash|am_anr|million_cn" |
    Select-Object -Last 20
}

function Stop-Runtime {
  try {
    Invoke-Adb -Arguments @("-s", $serial, "emu", "kill") -TimeoutSeconds 5 -AllowFailure | Out-Null
  } catch {}
  Start-Sleep -Seconds 2
  Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -in @($emulatorExe, $emulatorArmExe) } |
    Stop-Process -Force
}

function Show-Status {
  Resolve-Serial | Out-Null
  $display = if ((Get-DeviceState) -eq "device") {
    try {
      ((Invoke-Adb -Arguments @("-s", $serial, "shell", "wm", "size") -TimeoutSeconds 5) + (Invoke-Adb -Arguments @("-s", $serial, "shell", "wm", "density") -TimeoutSeconds 5)) -join "; "
    } catch {
      "unavailable"
    }
  } else {
    "device not ready"
  }

  [pscustomobject]@{
    AvdName      = $avdName
    Serial       = $serial
    PreferredSerial = $preferredSerial
    DeviceState  = Get-DeviceState
    EmulatorExe  = $emulatorExe
    AdbExe       = $adbExe
    Config       = $configPath
    Sdcard       = $sdcardPath
    StdoutLog    = $stdoutLog
    StderrLog    = $stderrLog
    RunLogcat    = $runLogcat
    RunEvents    = $runEvents
    RunProcesses = $runProcesses
    RunScreenshot = $runScreenshot
    Display      = $display
  }
}

switch ($Action) {
  "status" { Show-Status }
  "configure" { Configure-Runtime; Show-Status }
  "start" { Start-Runtime; Show-Status }
  "wait" { Wait-Runtime; Show-Status }
  "install" { Start-Runtime; Install-Game }
  "hosts" { Start-Runtime; Set-LocalHosts }
  "mount" { Start-Runtime; Mount-SaveResources }
  "preload-rest" { Start-Runtime; Preload-RestResources }
  "preload-small" { Start-Runtime; Preload-SmallResources }
  "preload-full" { Start-Runtime; Preload-FullResources }
  "launch" { Launch-Game }
  "run" {
    Start-Runtime
    Wait-Runtime
    Restore-RuntimeBaseline
    Invoke-Adb @("-s", $serial, "logcat", "-c") | Out-Null
    Launch-Game
    Start-Sleep -Seconds 35
    Save-RunArtifacts
  }
  "logcat" { Save-RunArtifacts }
  "stop" { Stop-Runtime }
}
