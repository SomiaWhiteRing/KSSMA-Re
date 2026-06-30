param(
  [string]$PreferredSerial = "emulator-5556",
  [string[]]$FallbackSerials = @("127.0.0.1:5557")
)

$ErrorActionPreference = "Stop"

$repo = Split-Path $PSScriptRoot -Parent
$adbExe = "C:\Program Files (x86)\platform-tools\adb.exe"
$package = "com.square_enix.million_cn"
$deviceSaveDir = "/storage/sdcard/Android/data/$package/files/save"
$internalSaveDir = "/data/local/tmp/kssma-save"
$requiredHosts = @(
  "10.0.2.2 game.ma.mobimon.com.tw",
  "10.0.2.2 dlc.game-CBT.ma.sdo.com"
)
$requiredFiles = @(
  "download/rest/treasurebox",
  "download/image/adv/adv_chara111",
  "download/sound/bgm_common1.ogg",
  "download/pack/mainbg/mainbg_an_0_0"
)

function Invoke-Adb {
  param(
    [string[]]$Arguments,
    [int]$TimeoutSeconds = 15,
    [switch]$AllowFailure
  )

  $stdoutPath = [System.IO.Path]::GetTempFileName()
  $stderrPath = [System.IO.Path]::GetTempFileName()
  try {
    $process = Start-Process -FilePath $adbExe -ArgumentList $Arguments -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      if ($AllowFailure) {
        return @()
      }
      throw "adb timed out after ${TimeoutSeconds}s: adb $($Arguments -join ' ')"
    }
    $process.Refresh()

    $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
    $exitCode = if ($null -eq $process.ExitCode) { 0 } else { $process.ExitCode }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
      throw "adb failed with exit code ${exitCode}: adb $($Arguments -join ' ')`n$stderr"
    }

    return ($stdout -split "\r?\n" | Where-Object { $_ -ne "" })
  } finally {
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
  }
}

function Test-Port {
  param([int]$Port)
  [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Test-Health {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:50005/healthz" -TimeoutSec 2
    return $response.StatusCode -eq 200
  } catch {
    return $false
  }
}

function Get-DeviceRows {
  Invoke-Adb @("devices") | Where-Object { $_ -match "\s+(device|offline|unauthorized)$" }
}

function Test-UsableSerial {
  param([string]$Serial)

  $row = Get-DeviceRows | Where-Object { $_ -match "^$([regex]::Escape($Serial))\s+device\b" } | Select-Object -First 1
  if (-not $row) {
    return $false
  }

  $abi = (Invoke-Adb -Arguments @("-s", $Serial, "shell", "getprop", "ro.product.cpu.abi") -AllowFailure | Out-String).Trim()
  $release = (Invoke-Adb -Arguments @("-s", $Serial, "shell", "getprop", "ro.build.version.release") -AllowFailure | Out-String).Trim()
  return $abi -eq "armeabi-v7a" -and $release -eq "4.4.2"
}

function Resolve-Serial {
  if (Test-UsableSerial $PreferredSerial) {
    return $PreferredSerial
  }

  foreach ($candidate in $FallbackSerials) {
    if (Test-UsableSerial $candidate) {
      return $candidate
    }
  }

  return $null
}

function Get-FocusedActivity {
  param([string]$Serial)

  $dump = Invoke-Adb -Arguments @("-s", $Serial, "shell", "dumpsys", "activity", "activities") -TimeoutSeconds 20 -AllowFailure
  ($dump | Select-String -Pattern "mFocusedActivity|mResumedActivity" | Select-Object -First 1).Line.Trim()
}

function Test-DeviceFile {
  param(
    [string]$Serial,
    [string]$Path
  )

  $output = (Invoke-Adb -Arguments @("-s", $Serial, "shell", "ls", $Path, "2>/dev/null") -AllowFailure | Out-String).Trim()
  return $output -ne ""
}

function Get-MusicState {
  param([string]$Serial)

  $audio = Invoke-Adb -Arguments @("-s", $Serial, "shell", "dumpsys", "audio") -TimeoutSeconds 20 -AllowFailure
  $streamIndex = [array]::IndexOf($audio, ($audio | Where-Object { $_ -match "STREAM_MUSIC" } | Select-Object -First 1))
  if ($streamIndex -lt 0) {
    return "STREAM_MUSIC unavailable"
  }

  $window = $audio[$streamIndex..([Math]::Min($audio.Count - 1, $streamIndex + 10))]
  return (($window | Select-String -Pattern "Muted|mute|Volume|volume|Current|Index|index" | Select-Object -First 4) -join "; ").Trim()
}

$checks = [ordered]@{}
$recommendations = New-Object System.Collections.Generic.List[string]

$checks.ServerPort50005 = Test-Port 50005
$checks.ServerPort10001 = Test-Port 10001
$checks.ServerHealth50005 = Test-Health
if (-not ($checks.ServerPort50005 -and $checks.ServerPort10001 -and $checks.ServerHealth50005)) {
  $recommendations.Add("Start or repair the local server: powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 start")
}

$checks.AdbDevices = (Get-DeviceRows | Out-String).Trim()
$serial = Resolve-Serial
$checks.Serial = if ($serial) { $serial } else { "" }
$checks.Arm19Device = [bool]$serial
if (-not $serial) {
  $recommendations.Add("Start ARM19 or fix ADB: powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-runtime")
} else {
  $checks.Abi = (Invoke-Adb -Arguments @("-s", $serial, "shell", "getprop", "ro.product.cpu.abi") -AllowFailure | Out-String).Trim()
  $checks.Android = (Invoke-Adb -Arguments @("-s", $serial, "shell", "getprop", "ro.build.version.release") -AllowFailure | Out-String).Trim()
  $checks.Display = ((@(Invoke-Adb -Arguments @("-s", $serial, "shell", "wm", "size") -AllowFailure) + @(Invoke-Adb -Arguments @("-s", $serial, "shell", "wm", "density") -AllowFailure)) -join "; ").Trim()
  $checks.Activity = Get-FocusedActivity $serial

  $hosts = Invoke-Adb -Arguments @("-s", $serial, "shell", "cat", "/system/etc/hosts") -AllowFailure
  $hostsText = (($hosts | ForEach-Object { $_.Trim() }) -join "`n")
  $missingHosts = $requiredHosts | Where-Object { $hostsText -notmatch [regex]::Escape($_) }
  $checks.HostsOk = $missingHosts.Count -eq 0
  $checks.Hosts = ($hostsText -replace "`n", "; ")
  if ($missingHosts.Count -gt 0) {
    $recommendations.Add("Repair ARM19 hosts: powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 hosts")
  }

  foreach ($relativePath in $requiredFiles) {
    $checks["File:$relativePath"] = Test-DeviceFile -Serial $serial -Path "$deviceSaveDir/$relativePath"
  }
  $internalTreasurebox = Test-DeviceFile -Serial $serial -Path "$internalSaveDir/download/rest/treasurebox"
  $checks.InternalFullResourceStash = $internalTreasurebox
  $missingFiles = $requiredFiles | Where-Object { -not $checks["File:$_"] }
  if ($missingFiles.Count -gt 0) {
    if ($internalTreasurebox) {
      $recommendations.Add("Remount existing full runtime resources: powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 mount")
    } else {
      $recommendations.Add("Preload full runtime resources before visual/audio checks: powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 preload-full")
    }
  }

  $checks.MusicState = Get-MusicState $serial
}

[pscustomobject]$checks | Format-List

if ($recommendations.Count -eq 0) {
  Write-Host "Preflight: OK for manual/runtime testing."
} else {
  Write-Host "Preflight: action needed."
  foreach ($item in $recommendations) {
    Write-Host "- $item"
  }
}
