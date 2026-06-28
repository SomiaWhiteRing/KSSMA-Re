param(
  [ValidateSet("status", "install", "launch", "force-stop", "restart", "run", "crash", "tombstone")]
  [string]$Action = "status",
  [string]$ApkPath
)

$ErrorActionPreference = "Stop"

$instance = "Nougat32"
$package = "com.square_enix.million_cn"
$blueStacksDir = "C:\Program Files\BlueStacks_nxt"
$playerExe = Join-Path $blueStacksDir "HD-Player.exe"
$adbExe = Join-Path $blueStacksDir "HD-Adb.exe"
$adbServerPort = 5038
$configPath = "C:\ProgramData\BlueStacks_nxt\bluestacks.conf"
$playerLogPath = "C:\ProgramData\BlueStacks_nxt\Logs\Player.log"
$crashSlicePath = Join-Path $PSScriptRoot "nougat32-latest-crash.txt"
$tombstonePath = Join-Path $PSScriptRoot "nougat32-latest-tombstone.txt"
$clientBaselineApk = Join-Path $PSScriptRoot "client-baseline\KSSMA-Re-client-baseline.apk"

function Ensure-File {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing file: $Path"
  }
}

function Resolve-ApkPath {
  param([string]$Candidate)

  if ($Candidate) {
    return (Resolve-Path -LiteralPath $Candidate -ErrorAction Stop).Path
  }

  if (-not (Test-Path -LiteralPath $clientBaselineApk)) {
    throw "Missing unique client baseline APK: $clientBaselineApk"
  }

  return (Resolve-Path -LiteralPath $clientBaselineApk -ErrorAction Stop).Path
}

function Get-ConfigValue {
  param([string]$Key)

  Ensure-File $configPath
  $raw = Get-Content -LiteralPath $configPath -Raw
  $pattern = '(?m)^' + [regex]::Escape($Key) + '="([^"]*)"$'
  $match = [regex]::Match($raw, $pattern)

  if (-not $match.Success) {
    throw "Config key not found: $Key"
  }

  return $match.Groups[1].Value
}

function Get-InstanceAdbPort {
  return [int](Get-ConfigValue "bst.instance.$instance.adb_port")
}

function Get-InstanceAdbEndpoint {
  return "127.0.0.1:$(Get-InstanceAdbPort)"
}

function Test-TcpPort {
  param(
    [string]$HostName,
    [int]$Port,
    [int]$TimeoutMs = 500
  )

  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $connect = $client.BeginConnect($HostName, $Port, $null, $null)
    if (-not $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
      return $false
    }
    $client.EndConnect($connect)
    return $true
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

function Wait-Nougat32Ready {
  param(
    [datetime]$Since,
    [int]$TimeoutSeconds = 90
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $playerLogPath) {
      $readyLine = Get-Content -LiteralPath $playerLogPath -Tail 400 |
        Where-Object { $_ -match 'Nougat32 \[Ready\]' } |
        Select-Object -Last 1

      if ($readyLine -and $readyLine -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
        $readyTime = [datetime]::ParseExact(
          $matches[1],
          "yyyy-MM-dd HH:mm:ss",
          [Globalization.CultureInfo]::InvariantCulture
        )
        if ($readyTime -ge $Since.AddSeconds(-2)) {
          return
        }
      }
    }

    Start-Sleep -Seconds 2
  }

  throw "Timed out waiting for $instance to reach [Ready]"
}

function Get-HostLogTime {
  param([string]$Line)

  if ($Line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
    return [datetime]::ParseExact(
      $matches[1],
      "yyyy-MM-dd HH:mm:ss",
      [Globalization.CultureInfo]::InvariantCulture
    )
  }

  return $null
}

function Wait-GameLaunchAccepted {
  param(
    [datetime]$Since,
    [int]$TimeoutSeconds = 15
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $playerLogPath) {
      $accepted = Get-Content -LiteralPath $playerLogPath -Tail 500 |
        Where-Object {
          ($_ -match "plrLaunchAppClbk: package = $([regex]::Escape($package))") -or
          ($_ -match "gcallLaunchActivityClbk.*package $([regex]::Escape($package))") -or
          ($_ -match "ActivityManager: START .*cmp=$([regex]::Escape($package))/")
        } |
        Where-Object {
          $time = Get-HostLogTime $_
          $time -and $time -ge $Since.AddSeconds(-2)
        } |
        Select-Object -First 1

      if ($accepted) {
        return $true
      }
    }

    Start-Sleep -Seconds 1
  }

  return $false
}

function Ensure-GuestLogcatRedirect {
  Ensure-File $configPath
  $raw = Get-Content -LiteralPath $configPath -Raw

  if ($raw.Contains('bst.instance.Nougat32.enable_logcat_redirection="1"')) {
    return $false
  }

  if (-not $raw.Contains('bst.instance.Nougat32.enable_logcat_redirection="0"')) {
    throw "Nougat32 logcat setting not found in $configPath"
  }

  $updated = $raw.Replace(
    'bst.instance.Nougat32.enable_logcat_redirection="0"',
    'bst.instance.Nougat32.enable_logcat_redirection="1"'
  )

  Set-Content -LiteralPath $configPath -Value $updated -NoNewline
  return $true
}

function Ensure-Nougat32Player {
  Ensure-File $playerExe
  $configChanged = Ensure-GuestLogcatRedirect
  $player = Get-Process -Name HD-Player -ErrorAction SilentlyContinue

  if ($configChanged -and $player) {
    Stop-Process -Name HD-Player -Force
    Start-Sleep -Seconds 2
    $player = $null
  }

  if (-not $player) {
    $startedAt = Get-Date
    Start-Process -FilePath $playerExe -ArgumentList "--instance", $instance, "--hidden" -WindowStyle Hidden
    # ponytail: launchApp sent during BlueStacks [StartingAndroid] is dropped; wait for the host log's Ready marker instead of guessing a sleep.
    Wait-Nougat32Ready -Since $startedAt
  }
}

function Invoke-BlueStacksCommand {
  param([string[]]$Arguments)

  & $playerExe @Arguments | Out-Null
}

function Invoke-BlueStacksAdb {
  param(
    [string[]]$Arguments,
    [switch]$AllowFailure
  )

  Ensure-File $adbExe
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $adbExe
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $allArgs = @("-P", "$adbServerPort") + $Arguments
  $psi.Arguments = [string]::Join(
    " ",
    ($allArgs | ForEach-Object {
      if ($_ -match '[\s"]') {
        '"' + ($_ -replace '"', '\"') + '"'
      } else {
        $_
      }
    })
  )

  $process = [System.Diagnostics.Process]::Start($psi)
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()

  $output = @()
  if ($stdout) {
    $output += [regex]::Split($stdout.TrimEnd("`r", "`n"), "`r?`n")
  }
  if ($stderr) {
    $output += [regex]::Split($stderr.TrimEnd("`r", "`n"), "`r?`n")
  }

  $exitCode = $process.ExitCode
  $text = ($output | Out-String).Trim()
  $payloadOutput = @($output | Where-Object {
    $line = "$_".Trim()
    $line -and $line -ne "error: closed"
  })
  $closedWithOutput = $exitCode -ne 0 -and $text -match '(^|\r?\n)error: closed\s*$' -and $payloadOutput.Count -gt 0

  # ponytail: HD-Adb often prints the shell payload and only then dies with "error: closed"; keep the payload so crash triage can continue unless this ever masks a real failure.
  if ($closedWithOutput) {
    $output = $payloadOutput
    $exitCode = 0
  }

  if (-not $AllowFailure -and $exitCode -ne 0) {
    throw "HD-Adb failed: $($output -join [Environment]::NewLine)"
  }

  return $output
}

function Connect-BlueStacksAdb {
  Ensure-Nougat32Player
  $endpoint = Get-InstanceAdbEndpoint
  Invoke-BlueStacksAdb @("start-server") | Out-Null
  $connectOutput = Invoke-BlueStacksAdb @("connect", $endpoint) -AllowFailure
  $connectText = ($connectOutput | Out-String).Trim()

  if ($connectText -match 'unable|failed|cannot|refused|timed out') {
    throw "Failed to connect HD-Adb to ${endpoint}: $connectText"
  }

  return $endpoint
}

function Invoke-DeviceShell {
  param(
    [string]$Device,
    [string]$Command,
    [switch]$AllowFailure
  )

  return Invoke-BlueStacksAdb @("-s", $Device, "shell", $Command) -AllowFailure:$AllowFailure
}

function Install-Game {
  param([string]$ResolvedApkPath)

  Ensure-Nougat32Player
  Invoke-BlueStacksCommand @("--instance", $instance, "--cmd", "installApk", "--filepath", $ResolvedApkPath)
  Start-Sleep -Seconds 10
}

function Launch-Game {
  Ensure-Nougat32Player
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    $startedAt = Get-Date
    Invoke-BlueStacksCommand @("--instance", $instance, "--cmd", "launchApp", "--package", $package)
    if (Wait-GameLaunchAccepted -Since $startedAt) {
      return
    }
    Write-Warning "BlueStacks did not accept launchApp for $package; retrying."
    Start-Sleep -Seconds 3
  }

  throw "BlueStacks did not accept launchApp for $package"
}

function Stop-Game {
  $device = Connect-BlueStacksAdb
  Invoke-DeviceShell -Device $device -Command "am force-stop $package" | Out-Null
}

function Stop-GameBestEffort {
  try {
    Stop-Game
  } catch {
    Write-Warning "ADB force-stop unavailable; restarting BlueStacks for a cold app start. $($_.Exception.Message)"
    Get-Process -Name HD-Player -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
  }
}

function Write-LatestCrashSlice {
  Ensure-File $playerLogPath
  $lines = Get-Content -LiteralPath $playerLogPath

  # ponytail: a host-side crash slice is enough to keep native patching moving; pull the full tombstone only when this stops narrowing the next patch.
  $markerIndexes = for ($i = 0; $i -lt $lines.Count; $i++) {
    if (
      $lines[$i] -match 'com\.square_enix\[[0-9]+\]: segfault at' -or
      $lines[$i] -match 'am_crash: \[[^]]*com\.square_enix\.million_cn' -or
      $lines[$i] -match 'RooneyJActivity' -or
      $lines[$i] -match 'save/download/rest/que_adv' -or
      $lines[$i] -match 'tombstone_[0-9]+'
    ) {
      $i
    }
  }

  if (-not $markerIndexes) {
    $message = "No crash markers found in $playerLogPath"
    Set-Content -LiteralPath $crashSlicePath -Value $message
    return Get-Content -LiteralPath $crashSlicePath
  }

  $start = [Math]::Max(0, $markerIndexes[-1] - 40)
  $count = [Math]::Min(140, $lines.Count - $start)
  $slice = $lines | Select-Object -Skip $start -First $count
  Set-Content -LiteralPath $crashSlicePath -Value $slice
  return $slice
}

function Write-LatestTombstone {
  $device = Connect-BlueStacksAdb
  $listCommands = @(
    "ls -t /data/tombstones 2>/dev/null",
    "su -c 'ls -t /data/tombstones 2>/dev/null'"
  )

  $latest = $null
  foreach ($command in $listCommands) {
    $latest = Invoke-DeviceShell -Device $device -Command $command -AllowFailure |
      ForEach-Object { "$_".Trim() } |
      Where-Object {
        $_ -and
        $_ -notmatch 'permission denied|not found|no such file|adbd cannot run as root'
      } |
      Select-Object -First 1

    if ($latest) {
      break
    }
  }

  if (-not $latest) {
    $message = "No readable tombstone found on $device"
    Set-Content -LiteralPath $tombstonePath -Value $message
    return Get-Content -LiteralPath $tombstonePath
  }

  $readCommands = @(
    "cat /data/tombstones/$latest 2>/dev/null",
    "su -c 'cat /data/tombstones/$latest 2>/dev/null'"
  )

  foreach ($command in $readCommands) {
    $content = @(Invoke-DeviceShell -Device $device -Command $command -AllowFailure)
    $text = ($content -join [Environment]::NewLine).Trim()

    if ($text -and $text -notmatch 'permission denied|not found|no such file') {
      Set-Content -LiteralPath $tombstonePath -Value $content
      return Get-Content -LiteralPath $tombstonePath -Tail 120
    }
  }

  $message = "Failed to read tombstone $latest from $device"
  Set-Content -LiteralPath $tombstonePath -Value $message
  return Get-Content -LiteralPath $tombstonePath
}

function Show-Status {
  Ensure-File $configPath
  $adbPort = Get-InstanceAdbPort
  $logcatSetting = Select-String -Path $configPath -Pattern 'bst\.instance\.Nougat32\.enable_logcat_redirection=' |
    Select-Object -First 1 -ExpandProperty Line
  $player = Get-Process -Name HD-Player -ErrorAction SilentlyContinue | Select-Object -First 1
  [pscustomobject]@{
    Instance        = $instance
    PlayerRunning   = [bool]$player
    PlayerPid       = if ($player) { $player.Id } else { $null }
    HostAdbPort     = $adbPort
    AdbEndpoint     = Get-InstanceAdbEndpoint
    HostAdbListening = Test-TcpPort "127.0.0.1" $adbPort
    LogcatRedirect  = $logcatSetting
    ClientBaselineApk = if (Test-Path -LiteralPath $clientBaselineApk) { (Resolve-Path -LiteralPath $clientBaselineApk).Path } else { $null }
    PlayerLog       = $playerLogPath
    CrashSlice      = $crashSlicePath
    Tombstone       = $tombstonePath
  }
}

switch ($Action) {
  "status" {
    Show-Status
  }
  "install" {
    $resolvedApkPath = Resolve-ApkPath $ApkPath
    Install-Game $resolvedApkPath
    Show-Status
  }
  "launch" {
    Launch-Game
  }
  "force-stop" {
    Stop-Game
  }
  "restart" {
    Stop-GameBestEffort
    Start-Sleep -Seconds 1
    Launch-Game
    Start-Sleep -Seconds 20
    Write-LatestCrashSlice
  }
  "run" {
    Launch-Game
    Start-Sleep -Seconds 20
    Write-LatestCrashSlice
  }
  "crash" {
    Write-LatestCrashSlice
  }
  "tombstone" {
    Write-LatestTombstone
  }
}
