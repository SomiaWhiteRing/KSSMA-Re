param(
  [ValidateSet("status", "configure", "start", "wait", "install", "preload-rest", "preload-small", "launch", "run", "logcat", "stop")]
  [string]$Action = "status",
  [string]$ApkPath,
  [switch]$WipeData
)

$ErrorActionPreference = "Stop"

$avdName = "kssma_arm19"
$serial = "emulator-5582"
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
$sampleSaveDir = Join-Path $PSScriptRoot "million_cn\sdcard_dump\sdcard\Android\data\com.square_enix.million_cn\files\save"
$deviceSaveDir = "/storage/sdcard/Android/data/$package/files/save"

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
  param([string[]]$Arguments)
  & $adbExe @Arguments
}

function Test-DeviceFile {
  param([string]$Path)
  $output = (Invoke-Adb @("-s", $serial, "shell", "ls", $Path, "2>/dev/null") | Out-String).Trim()
  return $output -ne ""
}

function Get-DeviceState {
  $line = Invoke-Adb @("devices") | Where-Object { $_ -match "^$serial\s+" } | Select-Object -First 1
  if (-not $line) {
    return "missing"
  }
  return (($line -split "\s+")[1]).Trim()
}

function Configure-Runtime {
  Ensure-File $configPath
  Ensure-File $mksdcardExe

  Set-AvdConfigValue "abi.type" "armeabi-v7a"
  Set-AvdConfigValue "target" "android-19"
  Set-AvdConfigValue "image.sysdir.1" "system-images\android-19\default\armeabi-v7a\"
  Set-AvdConfigValue "disk.dataPartition.size" "1024M"
  Set-AvdConfigValue "hw.ramSize" "1024"
  Set-AvdConfigValue "vm.heapSize" "128M"
  Set-AvdConfigValue "hw.lcd.width" "720"
  Set-AvdConfigValue "hw.lcd.height" "1280"
  Set-AvdConfigValue "hw.lcd.density" "320"
  Set-AvdConfigValue "hw.sdCard" "yes"
  Set-AvdConfigValue "sdcard.size" "512 MB"
  Set-AvdConfigValue "sdcard.path" $sdcardPath

  if (-not (Test-Path -LiteralPath $sdcardPath)) {
    & $mksdcardExe 512M $sdcardPath | Out-Null
  }
}

function Start-Runtime {
  Ensure-File $emulatorExe
  Configure-Runtime

  if ((Get-DeviceState) -ne "missing") {
    return
  }

  Remove-Item -LiteralPath $stdoutLog, $stderrLog -ErrorAction SilentlyContinue
  $args = @(
    "-avd", $avdName,
    "-engine", "classic",
    "-ports", "5582,5583",
    "-no-snapshot-load",
    "-no-snapshot-save",
    "-no-boot-anim",
    "-no-audio",
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
    if ((Get-DeviceState) -eq "device") {
      $boot = (Invoke-Adb @("-s", $serial, "shell", "getprop", "sys.boot_completed") | Out-String).Trim()
      if ($boot -eq "1") {
        return
      }
    }
    Start-Sleep -Seconds 10
  }

  throw "Timed out waiting for $serial"
}

function Install-Game {
  $resolvedApkPath = Resolve-ApkPath
  Wait-Runtime
  Invoke-Adb @("-s", $serial, "install", "-r", "-f", $resolvedApkPath)
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

function Preload-RestResources {
  Preload-DownloadDir "rest" "que_adv"
  Invoke-Adb @("-s", $serial, "shell", "ls", "-l", "$deviceSaveDir/download/rest/que_adv")
}

function Preload-SmallResources {
  # ponytail: preload only the small tutorial-adjacent dumps; full save/image/sound can wait until a screen proves it needs them.
  Preload-DownloadDir "rest" "que_adv"
  Preload-DownloadDir "scenario" "scsc_1010101"
  Preload-DownloadDir "pack" "mainbg/mainbg_an_0_0"
}

function Launch-Game {
  Wait-Runtime
  Invoke-Adb @("-s", $serial, "shell", "input", "keyevent", "66") | Out-Null
  Invoke-Adb @("-s", $serial, "shell", "am", "force-stop", $package) | Out-Null
  Invoke-Adb @("-s", $serial, "shell", "am", "start", "-n", "$package/$activity")
}

function Save-RunArtifacts {
  Invoke-Adb @("-s", $serial, "logcat", "-d", "-v", "time") | Set-Content -LiteralPath $runLogcat
  Invoke-Adb @("-s", $serial, "logcat", "-b", "events", "-d", "-v", "time") | Set-Content -LiteralPath $runEvents
  Invoke-Adb @("-s", $serial, "shell", "dumpsys", "activity", "processes") | Set-Content -LiteralPath $runProcesses
  Invoke-Adb @("-s", $serial, "shell", "screencap", "-p", "/sdcard/kssma-arm19-last-run.png") | Out-Null
  Invoke-Adb @("-s", $serial, "pull", "/sdcard/kssma-arm19-last-run.png", $runScreenshot) | Out-Null
  Get-Content -LiteralPath $runLogcat | Select-String -Pattern "Fatal signal|signal 6|signal 11|librooneyj|jni_loadTexture|connect/app|check_inspection" |
    Select-Object -Last 80
  Get-Content -LiteralPath $runEvents | Select-String -Pattern "am_crash|am_anr|million_cn" |
    Select-Object -Last 20
}

function Stop-Runtime {
  Invoke-Adb @("-s", $serial, "emu", "kill") | Out-Null
  Start-Sleep -Seconds 2
  Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -in @($emulatorExe, $emulatorArmExe) } |
    Stop-Process -Force
}

function Show-Status {
  [pscustomobject]@{
    AvdName      = $avdName
    Serial       = $serial
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
  }
}

switch ($Action) {
  "status" { Show-Status }
  "configure" { Configure-Runtime; Show-Status }
  "start" { Start-Runtime; Show-Status }
  "wait" { Wait-Runtime; Show-Status }
  "install" { Start-Runtime; Install-Game }
  "preload-rest" { Start-Runtime; Preload-RestResources }
  "preload-small" { Start-Runtime; Preload-SmallResources }
  "launch" { Launch-Game }
  "run" {
    Start-Runtime
    Wait-Runtime
    Invoke-Adb @("-s", $serial, "logcat", "-c") | Out-Null
    Launch-Game
    Start-Sleep -Seconds 35
    Save-RunArtifacts
  }
  "logcat" { Save-RunArtifacts }
  "stop" { Stop-Runtime }
}
