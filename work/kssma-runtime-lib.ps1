$script:KssmaRuntimeConfig = [ordered]@{
  AvdName = "kssma_arm19"
  PrimarySerial = "127.0.0.1:5583"
  LegacySerial = "emulator-5582"
  Package = "com.square_enix.million_cn"
  Activity = "com.test.enter.LogoActivity"
  ExpectedAbi = "armeabi-v7a"
  ExpectedRelease = "4.4.2"
  DisplaySize = "1280x720"
  DisplayDensity = "240"
  SdcardSize = "4096M"
  StateTtlSeconds = 30
}

$script:RepoRoot = Split-Path $PSScriptRoot -Parent
$script:SdkClassic = Join-Path $env:USERPROFILE "AppData\Local\Android\Sdk-classic-arm"
$script:EmulatorExe = Join-Path $script:SdkClassic "tools\emulator.exe"
$script:EmulatorArmExe = Join-Path $script:SdkClassic "tools\emulator-arm.exe"
$script:MksdcardExe = Join-Path $script:SdkClassic "tools\mksdcard.exe"
$script:AdbExe = "C:\Program Files (x86)\platform-tools\adb.exe"
if (-not (Test-Path -LiteralPath $script:AdbExe)) {
  $script:AdbExe = "adb"
}
$script:AvdDir = Join-Path $env:USERPROFILE ".android\avd\$($script:KssmaRuntimeConfig.AvdName).avd"
$script:ConfigPath = Join-Path $script:AvdDir "config.ini"
$script:SdcardPath = Join-Path $script:AvdDir "sdcard.img"
$script:StatePath = Join-Path $PSScriptRoot "runtime-state.json"
$script:StdoutLog = Join-Path $PSScriptRoot "android44-arm19-runtime.out.log"
$script:StderrLog = Join-Path $PSScriptRoot "android44-arm19-runtime.err.log"
$script:SampleDumpRoot = Join-Path $PSScriptRoot "million_cn\sdcard_dump"
$script:SampleSaveDir = Join-Path $PSScriptRoot "million_cn\sdcard_dump\sdcard\Android\data\$($script:KssmaRuntimeConfig.Package)\files\save"
$script:ResourceZipPath = Join-Path $script:RepoRoot "base\com.square_enix.million_cn-140330.zip"
$script:DeviceSaveDir = "/storage/sdcard/Android/data/$($script:KssmaRuntimeConfig.Package)/files/save"
$script:MediaSaveDir = "/mnt/media_rw/sdcard/Android/data/$($script:KssmaRuntimeConfig.Package)/files/save"
$script:InternalSaveDir = "/data/local/tmp/kssma-save"
$script:ExplorationAcceptedLibPath = Join-Path $PSScriptRoot "librooneyj-exploration-area-return-rerequest.so"
$script:ExplorationAcceptedLibSha256 = "8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D"

function New-RuntimeContext {
  param([string]$Command)

  [ordered]@{
    command = $Command
    serial = $script:KssmaRuntimeConfig.PrimarySerial
    stages = @()
    warnings = @()
    data = [ordered]@{}
    startedAt = Get-Date
  }
}

function Add-Stage {
  param(
    $Context,
    [string]$Name,
    $Stage
  )

  $item = [ordered]@{
    name = $Name
    ok = [bool]$Stage.ok
    elapsedMs = [int]$Stage.elapsedMs
  }
  foreach ($key in @("exitCode", "timedOut", "stdout", "stderr", "failureClass", "details", "skipped", "cached")) {
    if ($Stage.Contains($key)) {
      $item[$key] = $Stage[$key]
    }
  }
  $Context.stages += $item
}

function Complete-RuntimeResult {
  param(
    $Context,
    [bool]$Ok,
    [string]$FailureClass = "",
    [bool]$RestartAllowed = $false,
    [string]$RecommendedCommand = "",
    $Data = $null
  )

  $elapsed = [int]((Get-Date) - $Context.startedAt).TotalMilliseconds
  if ($Data) {
    foreach ($key in $Data.Keys) {
      $Context.data[$key] = $Data[$key]
    }
  }
  [ordered]@{
    ok = $Ok
    command = $Context.command
    serial = $Context.serial
    elapsedMs = $elapsed
    failureClass = $FailureClass
    restartAllowed = $RestartAllowed
    recommendedCommand = $RecommendedCommand
    stages = $Context.stages
    warnings = $Context.warnings
    data = $Context.data
  }
}

function ConvertTo-RuntimeJson {
  param([object]$Result)
  ConvertTo-Json -InputObject $Result -Depth 12
}

function Invoke-RuntimeProcess {
  param(
    [string]$FilePath,
    [string[]]$ArgumentList,
    [int]$TimeoutSeconds = 30,
    [switch]$AllowFailure
  )

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $stdoutPath = [System.IO.Path]::GetTempFileName()
  $stderrPath = [System.IO.Path]::GetTempFileName()
  try {
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      try { $process.WaitForExit(1000) | Out-Null } catch {}
    }
    $process.Refresh()
    $stdout = Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
    $stderr = Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue
    if (-not $timedOut) {
      try { $process.WaitForExit() } catch {}
    }
    $exitCode = if ($timedOut) { $null } elseif ($null -eq $process.ExitCode) { 0 } else { [int]$process.ExitCode }
    $ok = (-not $timedOut) -and ($exitCode -eq 0)
    [ordered]@{
      ok = $ok
      exitCode = $exitCode
      timedOut = $timedOut
      elapsedMs = [int]$sw.ElapsedMilliseconds
      stdout = (($stdout -as [string]).Trim())
      stderr = (($stderr -as [string]).Trim())
    }
  } finally {
    $sw.Stop()
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-Adb {
  param(
    [string[]]$Arguments,
    [int]$TimeoutSeconds = 30,
    [switch]$AllowFailure
  )

  $stage = Invoke-RuntimeProcess -FilePath $script:AdbExe -ArgumentList $Arguments -TimeoutSeconds $TimeoutSeconds -AllowFailure:$AllowFailure
  if (Test-AdbFailureOutput $stage) {
    $stage.ok = $false
    $stage.failureClass = Get-AdbFailureClass $stage
  }
  $stage
}

function Test-AdbFailureOutput {
  param($Stage)
  $text = "$($Stage.stdout)`n$($Stage.stderr)"
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $false
  }
  return $text -match "device '.+' not found" -or
    $text -match "device not found" -or
    $text -match "device offline" -or
    $text -match "unauthorized" -or
    $text -match "cannot connect" -or
    $text -match "actively refused" -or
    $text -match "积极拒绝" -or
    $text -match "protocol fault" -or
    $text -match "no devices/emulators found"
}

function Get-AdbFailureClass {
  param($Stage)
  $text = "$($Stage.stdout)`n$($Stage.stderr)"
  if ($text -match "unauthorized") { return "unauthorized" }
  if ($text -match "device offline") { return "adb-offline" }
  if ($text -match "device '.+' not found" -or $text -match "device not found") { return "device-not-found" }
  if ($text -match "cannot connect" -or $text -match "actively refused" -or $text -match "积极拒绝") { return "adb-port-refused" }
  if ($text -match "protocol fault") { return "adb-protocol-fault" }
  return "adb-failed"
}

function Get-OutputLines {
  param([object]$Output)
  @(($Output -as [string]) -split "\r?\n" | Where-Object { $_ -ne "" })
}

function Require-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing file: $Path"
  }
}

function Read-RuntimeState {
  if (-not (Test-Path -LiteralPath $script:StatePath)) {
    return [ordered]@{}
  }
  try {
    return Get-Content -Raw -LiteralPath $script:StatePath | ConvertFrom-Json
  } catch {
    return [ordered]@{}
  }
}

function Write-RuntimeState {
  param($State)
  $State.updatedAt = (Get-Date).ToString("o")
  $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:StatePath -Encoding UTF8
}

function ConvertTo-StateDictionary {
  param($State)
  $dict = [ordered]@{}
  if ($null -eq $State) {
    return $dict
  }
  if ($State -is [System.Collections.IDictionary]) {
    foreach ($key in $State.Keys) {
      $dict[$key] = $State[$key]
    }
    return $dict
  }
  foreach ($property in $State.PSObject.Properties) {
    $dict[$property.Name] = $property.Value
  }
  return $dict
}

function Test-StateFresh {
  param($State)
  $updatedAt = Get-StateValue -State $State -Key "updatedAt"
  if (-not $updatedAt) {
    return $false
  }
  try {
    return ((Get-Date) - [datetime]$updatedAt).TotalSeconds -le $script:KssmaRuntimeConfig.StateTtlSeconds
  } catch {
    return $false
  }
}

function Get-StateValue {
  param(
    $State,
    [string]$Key
  )
  if ($null -eq $State) {
    return $null
  }
  if ($State -is [System.Collections.IDictionary] -and $State.Contains($Key)) {
    return $State[$Key]
  }
  return $State.$Key
}

function Reset-BaselineStateValues {
  param([hashtable]$Extra = @{})
  $values = [ordered]@{
    serial = $script:KssmaRuntimeConfig.PrimarySerial
    baselineOk = $false
    hostsOk = $false
    mountOk = $false
    displayOk = $false
    audioOk = $false
    packageOk = $false
  }
  foreach ($key in $Extra.Keys) {
    $values[$key] = $Extra[$key]
  }
  Update-RuntimeState $values
}

function Get-DeviceBootFingerprint {
  param(
    [string]$Serial,
    [int]$TimeoutSeconds = 2
  )
  $uptime = Invoke-Adb -Arguments @("-s", $Serial, "shell", "cat", "/proc/uptime") -TimeoutSeconds $TimeoutSeconds -AllowFailure
  $first = (Get-OutputLines $uptime.stdout | Select-Object -First 1)
  $seconds = $null
  if ($first -match "^([0-9]+)") {
    $seconds = [int64]$Matches[1]
  }
  [ordered]@{
    ok = (-not $uptime.timedOut -and $null -ne $seconds)
    uptimeSeconds = $seconds
    stage = $uptime
  }
}

function Invoke-GetPropWithRetry {
  param(
    $Context,
    [string]$Serial,
    [string]$Property,
    [string]$StageName,
    [int[]]$Timeouts = @(2, 5)
  )
  $last = $null
  foreach ($timeout in $Timeouts) {
    $stage = Invoke-Adb -Arguments @("-s", $Serial, "shell", "getprop", $Property) -TimeoutSeconds $timeout -AllowFailure
    $name = if ($last) { "$StageName-retry-$($timeout)s" } else { $StageName }
    Add-Stage $Context $name $stage
    $value = (($stage.stdout -as [string]).Trim())
    $last = $stage
    if ($stage.ok -and -not $stage.timedOut -and $value -ne "") {
      return [ordered]@{ ok = $true; value = $value; stage = $stage }
    }
  }
  [ordered]@{ ok = $false; value = ""; stage = $last }
}

function Update-RuntimeState {
  param([hashtable]$Values)
  $state = ConvertTo-StateDictionary (Read-RuntimeState)
  foreach ($key in $Values.Keys) {
    $state[$key] = $Values[$key]
  }
  Write-RuntimeState $state
}

function Get-EmulatorProcesses {
  @(Get-CimInstance Win32_Process -Filter "name = 'emulator.exe' or name = 'emulator-arm.exe' or name = 'emulator64-crash-service.exe'" -ErrorAction SilentlyContinue |
    Where-Object { ($_.CommandLine -as [string]) -match [regex]::Escape($script:KssmaRuntimeConfig.AvdName) -or ($_.CommandLine -as [string]) -match "5582,5583" } |
    ForEach-Object {
      [ordered]@{
        processId = $_.ProcessId
        name = $_.Name
        commandLine = $_.CommandLine
      }
    })
}

function Test-TcpPortOpen {
  param([int]$Port, [int]$TimeoutMs = 500)
  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $async = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
    if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) {
      return [ordered]@{ port = $Port; open = $false; error = "timeout" }
    }
    $client.EndConnect($async)
    [ordered]@{ port = $Port; open = $true; error = "" }
  } catch {
    [ordered]@{ port = $Port; open = $false; error = $_.Exception.Message }
  } finally {
    $client.Close()
  }
}

function Get-TargetPortSummary {
  [ordered]@{
    console5582 = Test-TcpPortOpen -Port 5582
    adb5583 = Test-TcpPortOpen -Port 5583
  }
}

function Get-AdbDeviceRows {
  $result = Invoke-Adb -Arguments @("devices", "-l") -TimeoutSeconds 5 -AllowFailure
  Get-OutputLines $result.stdout | Where-Object { $_ -match "\s+(device|offline|unauthorized)\b" }
}

function Get-AdbRowState {
  param([string[]]$Rows, [string]$Serial)
  $row = @($Rows | Where-Object { $_ -match "^$([regex]::Escape($Serial))\s+" } | Select-Object -First 1)
  if (-not $row) {
    return [ordered]@{ serial = $Serial; present = $false; state = "missing"; row = "" }
  }
  if ($row -match "\s+device\b") { $state = "device" }
  elseif ($row -match "\s+offline\b") { $state = "offline" }
  elseif ($row -match "\s+unauthorized\b") { $state = "unauthorized" }
  else { $state = "unknown" }
  [ordered]@{ serial = $Serial; present = $true; state = $state; row = $row[0] }
}

function Get-DeviceSummary {
  $rows = @(Get-AdbDeviceRows)
  $primary = Get-AdbRowState -Rows $rows -Serial $script:KssmaRuntimeConfig.PrimarySerial
  $legacy = Get-AdbRowState -Rows $rows -Serial $script:KssmaRuntimeConfig.LegacySerial
  $others = @($rows | Where-Object {
      $_ -notmatch "^$([regex]::Escape($script:KssmaRuntimeConfig.PrimarySerial))\s+" -and
      $_ -notmatch "^$([regex]::Escape($script:KssmaRuntimeConfig.LegacySerial))\s+"
    })
  [ordered]@{
    rows = $rows
    primary = $primary
    legacy = $legacy
    otherDevices = $others
    legacyOffline = $legacy.state -eq "offline"
    primaryDevice = $primary.state -eq "device"
  }
}

function Get-TransportClassification {
  param(
    $PrimaryHealth,
    $LegacyHealth,
    $Devices,
    $EmulatorProcesses,
    $Ports
  )

  $selected = ""
  if ($PrimaryHealth.ok) {
    $selected = $PrimaryHealth.serial
    return [ordered]@{
      class = "healthy-arm19"
      selectedSerial = $selected
      restartAllowed = $false
      reason = "primary ARM19 health check passed"
      devices = $Devices
      ports = $Ports
      emulatorProcesses = $EmulatorProcesses
    }
  }
  if ($LegacyHealth.ok) {
    $selected = $LegacyHealth.serial
    return [ordered]@{
      class = "healthy-arm19"
      selectedSerial = $selected
      restartAllowed = $false
      reason = "legacy ARM19 health check passed"
      devices = $Devices
      ports = $Ports
      emulatorProcesses = $EmulatorProcesses
    }
  }

  $targetRows = @($Devices.primary, $Devices.legacy)
  if ($targetRows | Where-Object { $_.state -eq "unauthorized" }) {
    return [ordered]@{ class = "unauthorized"; selectedSerial = ""; restartAllowed = $false; reason = "target serial is unauthorized"; devices = $Devices; ports = $Ports; emulatorProcesses = $EmulatorProcesses }
  }
  if ($targetRows | Where-Object { $_.state -eq "offline" }) {
    return [ordered]@{ class = "adb-offline"; selectedSerial = ""; restartAllowed = $true; reason = "target serial is offline"; devices = $Devices; ports = $Ports; emulatorProcesses = $EmulatorProcesses }
  }
  if ($PrimaryHealth.transportOk -or $LegacyHealth.transportOk) {
    if ($PrimaryHealth.abi -ne "" -or $LegacyHealth.abi -ne "") {
      return [ordered]@{ class = "wrong-runtime"; selectedSerial = ""; restartAllowed = $false; reason = "target shell responded but ABI/release/boot did not match ARM19"; devices = $Devices; ports = $Ports; emulatorProcesses = $EmulatorProcesses }
    }
    return [ordered]@{ class = "not-booted"; selectedSerial = ""; restartAllowed = $false; reason = "target shell responded without complete boot properties"; devices = $Devices; ports = $Ports; emulatorProcesses = $EmulatorProcesses }
  }
  if ($EmulatorProcesses.Count -gt 0) {
    return [ordered]@{ class = "detached-arm19"; selectedSerial = ""; restartAllowed = $true; reason = "classic ARM19 process exists but no target ADB shell is reachable"; devices = $Devices; ports = $Ports; emulatorProcesses = $EmulatorProcesses }
  }
  if ($Devices.otherDevices.Count -gt 0) {
    return [ordered]@{ class = "wrong-runtime-only"; selectedSerial = ""; restartAllowed = $false; reason = "ADB sees only non-ARM19 devices"; devices = $Devices; ports = $Ports; emulatorProcesses = $EmulatorProcesses }
  }
  [ordered]@{ class = "adb-transport"; selectedSerial = ""; restartAllowed = $false; reason = "no ARM19 target and no classic emulator process"; devices = $Devices; ports = $Ports; emulatorProcesses = $EmulatorProcesses }
}

function Get-PrimaryHealthData {
  param(
    $Context,
    [int]$TimeoutSeconds = 1,
    [switch]$IncludeTransport
  )

  $serial = $script:KssmaRuntimeConfig.PrimarySerial
  $connect = Invoke-Adb -Arguments @("connect", $serial) -TimeoutSeconds $TimeoutSeconds -AllowFailure
  Add-Stage $Context "adb-connect-primary" $connect

  # ponytail: three one-property reads are noisier but avoid the classic ARM shell
  # swallowing later commands; upgrade path is an adb exec-out helper if this
  # becomes too slow.
  $abiRead = Invoke-GetPropWithRetry -Context $Context -Serial $serial -Property "ro.product.cpu.abi" -StageName "getprop-abi"
  $releaseRead = Invoke-GetPropWithRetry -Context $Context -Serial $serial -Property "ro.build.version.release" -StageName "getprop-release"
  $bootRead = Invoke-GetPropWithRetry -Context $Context -Serial $serial -Property "sys.boot_completed" -StageName "getprop-boot"
  $abi = $abiRead.value
  $release = $releaseRead.value
  $boot = $bootRead.value
  $transportOk = $abiRead.ok -or $releaseRead.ok -or $bootRead.ok
  $ok = ($abi -eq $script:KssmaRuntimeConfig.ExpectedAbi -and $release -eq $script:KssmaRuntimeConfig.ExpectedRelease -and $boot -eq "1")
  $primaryHealth = [ordered]@{
    serial = $serial
    connect = $connect.stdout
    abi = $abi
    release = $release
    bootCompleted = $boot
    transportOk = $transportOk
    ok = $ok
  }

  if (-not $IncludeTransport) {
    return $primaryHealth
  }

  $legacySerial = $script:KssmaRuntimeConfig.LegacySerial
  $legacyAbiRead = Invoke-GetPropWithRetry -Context $Context -Serial $legacySerial -Property "ro.product.cpu.abi" -StageName "legacy-getprop-abi"
  $legacyReleaseRead = Invoke-GetPropWithRetry -Context $Context -Serial $legacySerial -Property "ro.build.version.release" -StageName "legacy-getprop-release"
  $legacyBootRead = Invoke-GetPropWithRetry -Context $Context -Serial $legacySerial -Property "sys.boot_completed" -StageName "legacy-getprop-boot"
  $legacyAbi = $legacyAbiRead.value
  $legacyRelease = $legacyReleaseRead.value
  $legacyBoot = $legacyBootRead.value
  $legacyTransportOk = $legacyAbiRead.ok -or $legacyReleaseRead.ok -or $legacyBootRead.ok
  $legacyOk = ($legacyAbi -eq $script:KssmaRuntimeConfig.ExpectedAbi -and $legacyRelease -eq $script:KssmaRuntimeConfig.ExpectedRelease -and $legacyBoot -eq "1")
  $legacyHealth = [ordered]@{
    serial = $legacySerial
    connect = ""
    abi = $legacyAbi
    release = $legacyRelease
    bootCompleted = $legacyBoot
    transportOk = $legacyTransportOk
    ok = $legacyOk
  }

  $devices = Get-DeviceSummary
  $emulators = @(Get-EmulatorProcesses)
  $ports = Get-TargetPortSummary
  $transport = Get-TransportClassification -PrimaryHealth $primaryHealth -LegacyHealth $legacyHealth -Devices $devices -EmulatorProcesses $emulators -Ports $ports

  if ($transport.selectedSerial -and $transport.selectedSerial -ne $script:KssmaRuntimeConfig.PrimarySerial) {
    # ponytail: use the emulator's canonical ADB serial when the TCP alias is stale.
    $Context.warnings += "Primary TCP serial $serial is unavailable; using healthy ARM19 legacy serial $($transport.selectedSerial) for this command."
    $script:KssmaRuntimeConfig.PrimarySerial = $transport.selectedSerial
  }

  $selectedHealth = if ($legacyOk -and -not $ok) { $legacyHealth } else { $primaryHealth }
  [ordered]@{
    serial = $selectedHealth.serial
    connect = $connect.stdout
    abi = $selectedHealth.abi
    release = $selectedHealth.release
    bootCompleted = $selectedHealth.bootCompleted
    transportOk = ($primaryHealth.transportOk -or $legacyHealth.transportOk)
    ok = ($primaryHealth.ok -or $legacyHealth.ok)
    primary = $primaryHealth
    legacy = $legacyHealth
    transport = $transport
  }
}

function Invoke-FastHealth {
  $ctx = New-RuntimeContext "fast-health"
  # ponytail: classic ARM19 can return partial getprop output just over 1s after
  # ADB recovery; if this ever becomes too slow, split transport and boot checks.
  $health = Get-PrimaryHealthData -Context $ctx -TimeoutSeconds 2
  $ctx.serial = $health.serial
  $data = [ordered]@{
    abi = $health.abi
    release = $health.release
    bootCompleted = $health.bootCompleted
    connect = $health.connect
  }

  if ($health.ok) {
    Update-RuntimeState ([ordered]@{
      serial = $health.serial
      fastHealthOk = $true
      bootCompleted = $true
      abi = $health.abi
      release = $health.release
      lastFailureClass = ""
    })
    return Complete-RuntimeResult -Context $ctx -Ok $true -Data $data
  }

  $failure = if (-not $health.transportOk) {
    "adb-transport"
  } elseif ($health.abi -ne $script:KssmaRuntimeConfig.ExpectedAbi -or $health.release -ne $script:KssmaRuntimeConfig.ExpectedRelease) {
    "wrong-runtime"
  } else {
    "not-booted"
  }
  Update-RuntimeState ([ordered]@{
    serial = $health.serial
    fastHealthOk = $false
    lastFailureClass = $failure
  })
  Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $failure -RestartAllowed $false -RecommendedCommand "powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 repair-adb" -Data $data
}

function Invoke-ConnectRuntime {
  $ctx = New-RuntimeContext "connect"
  $health = Get-PrimaryHealthData -Context $ctx -TimeoutSeconds 2 -IncludeTransport
  $ctx.serial = $health.serial
  $devices = $health.transport.devices
  if ($devices.otherDevices.Count -gt 0) {
    $ctx.warnings += "Other ADB devices present; ignored by KSSMA runtime control plane."
  }
  if ($devices.legacyOffline) {
    $ctx.warnings += "emulator-5582 is offline; ignored because primary serial is checked directly."
  }
  $data = [ordered]@{
    abi = $health.abi
    release = $health.release
    bootCompleted = $health.bootCompleted
    devices = $devices
    transport = $health.transport
  }
  if ($health.ok) {
    Update-RuntimeState ([ordered]@{
      serial = $health.serial
      fastHealthOk = $true
      bootCompleted = $true
      lastFailureClass = ""
    })
    return Complete-RuntimeResult -Context $ctx -Ok $true -Data $data
  }
  $failure = if ($health.transport) { $health.transport.class } elseif (-not $health.transportOk) { "adb-transport" } elseif ($health.bootCompleted -ne "1") { "not-booted" } else { "wrong-runtime" }
  Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $failure -RestartAllowed $false -RecommendedCommand "powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 repair-adb" -Data $data
}

function Invoke-RepairAdb {
  $ctx = New-RuntimeContext "repair-adb"
  $serial = $script:KssmaRuntimeConfig.PrimarySerial

  $connect1 = Invoke-Adb -Arguments @("connect", $serial) -TimeoutSeconds 3 -AllowFailure
  Add-Stage $ctx "connect-primary" $connect1
  $health = Get-PrimaryHealthData -Context $ctx -TimeoutSeconds 2 -IncludeTransport
  if ($health.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ abi = $health.abi; release = $health.release; bootCompleted = $health.bootCompleted; transport = $health.transport; recovery = "none" })
  }

  $disconnect = Invoke-Adb -Arguments @("disconnect", $serial) -TimeoutSeconds 3 -AllowFailure
  Add-Stage $ctx "disconnect-primary" $disconnect
  $reconnectOffline = Invoke-Adb -Arguments @("reconnect", "offline") -TimeoutSeconds 5 -AllowFailure
  Add-Stage $ctx "reconnect-offline" $reconnectOffline
  $connect2 = Invoke-Adb -Arguments @("connect", $serial) -TimeoutSeconds 3 -AllowFailure
  Add-Stage $ctx "reconnect-primary" $connect2
  $health2 = Get-PrimaryHealthData -Context $ctx -TimeoutSeconds 2 -IncludeTransport
  if ($health2.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ abi = $health2.abi; release = $health2.release; bootCompleted = $health2.bootCompleted; transport = $health2.transport; recovery = "reconnect" })
  }

  $transport = $health2.transport
  if ($transport.class -eq "detached-arm19") {
    Add-Stage $ctx "transport-recovery-decision" ([ordered]@{ ok = $true; elapsedMs = 0; details = "warm-restart for detached-arm19" })
    $restart = Invoke-RestartRuntime -Force -Reason "automatic warm restart after $($transport.class)"
    $ctx.stages += $restart.stages
    if ($restart.ok) {
      $post = Get-PrimaryHealthData -Context $ctx -TimeoutSeconds 2 -IncludeTransport
      if ($post.ok) {
        $killed = @()
        if ($restart.data -and $restart.data.Contains("killed")) {
          $killed = @($restart.data.killed)
        }
        return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{
            recovery = "warm-restart"
            before = $transport
            after = $post.transport
            abi = $post.abi
            release = $post.release
            bootCompleted = $post.bootCompleted
            restart = [ordered]@{
              reason = $restart.data.reason
              killedCount = $killed.Count
            }
          })
      }
      return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $post.transport.class -RestartAllowed:$post.transport.restartAllowed -RecommendedCommand "Warm restart completed, but ARM19 health check still failed; run status before gameplay work." -Data ([ordered]@{ recovery = "warm-restart-postcheck-failed"; before = $transport; after = $post.transport })
    }
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $restart.failureClass -RestartAllowed:$restart.restartAllowed -RecommendedCommand $restart.recommendedCommand -Data ([ordered]@{ recovery = "warm-restart-failed"; before = $transport; restart = $restart.data })
  }

  Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $transport.class -RestartAllowed:$transport.restartAllowed -RecommendedCommand "Fix the transport class shown in data.transport; detached-arm19 is the only automatic warm-restart path." -Data ([ordered]@{
      lastAbi = $health2.abi
      lastRelease = $health2.release
      lastBootCompleted = $health2.bootCompleted
      transport = $transport
      recovery = "none"
    })
}

function Set-AvdConfigValue {
  param([string]$Key, [string]$Value)
  Require-File $script:ConfigPath
  $lines = @(Get-Content -LiteralPath $script:ConfigPath)
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
  Set-Content -LiteralPath $script:ConfigPath -Value $lines
}

function Get-ShortPath {
  param([string]$Path)
  $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).Path
  if (-not $resolved) { return $Path }
  try {
    return (New-Object -ComObject Scripting.FileSystemObject).GetFile($resolved).ShortPath
  } catch {
    return $resolved
  }
}

function Ensure-AvdConfig {
  Set-AvdConfigValue "abi.type" "armeabi-v7a"
  Set-AvdConfigValue "target" "android-19"
  Set-AvdConfigValue "image.sysdir.1" "system-images\android-19\default\armeabi-v7a\"
  Set-AvdConfigValue "disk.dataPartition.size" "1536M"
  Set-AvdConfigValue "hw.ramSize" "1536"
  Set-AvdConfigValue "vm.heapSize" "256M"
  Set-AvdConfigValue "hw.audioInput" "yes"
  Set-AvdConfigValue "hw.audioOutput" "yes"
  Set-AvdConfigValue "hw.lcd.width" "1280"
  Set-AvdConfigValue "hw.lcd.height" "720"
  Set-AvdConfigValue "hw.lcd.density" "240"
  Set-AvdConfigValue "hw.initialOrientation" "landscape"
  Set-AvdConfigValue "skin.name" "1280x720"
  Set-AvdConfigValue "hw.sdCard" "yes"
  Set-AvdConfigValue "sdcard.size" $script:KssmaRuntimeConfig.SdcardSize
  Require-File $script:MksdcardExe
  $needsSdcard = -not (Test-Path -LiteralPath $script:SdcardPath)
  if (-not $needsSdcard) {
    $sdcardInfo = Get-Item -LiteralPath $script:SdcardPath
    $needsSdcard = $sdcardInfo.Length -lt 3900MB -or $sdcardInfo.Length -gt 4200MB
  }
  if ($needsSdcard) {
    if (Test-Path -LiteralPath $script:SdcardPath) {
      Move-Item -LiteralPath $script:SdcardPath -Destination "$script:SdcardPath.$((Get-Date).ToString('yyyyMMddHHmmss')).bak"
    }
    $mk = Invoke-RuntimeProcess -FilePath $script:MksdcardExe -ArgumentList @($script:KssmaRuntimeConfig.SdcardSize, $script:SdcardPath) -TimeoutSeconds 120
    if (-not $mk.ok) {
      throw "mksdcard failed: $($mk.stderr)"
    }
  }
  Set-AvdConfigValue "sdcard.path" (Get-ShortPath $script:SdcardPath)
}

function Invoke-ConfigureRuntime {
  $ctx = New-RuntimeContext "configure"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    Ensure-AvdConfig
    $stage = [ordered]@{ ok = $true; elapsedMs = [int]$sw.ElapsedMilliseconds; details = "configured" }
    Add-Stage $ctx "configure-avd" $stage
    return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{
        avdName = $script:KssmaRuntimeConfig.AvdName
        config = $script:ConfigPath
        sdcard = $script:SdcardPath
      })
  } catch {
    $stage = [ordered]@{ ok = $false; elapsedMs = [int]$sw.ElapsedMilliseconds; stderr = $_.Exception.Message }
    Add-Stage $ctx "configure-avd" $stage
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "avd-config" -RecommendedCommand "Check classic ARM SDK and AVD config paths." -Data ([ordered]@{ error = $_.Exception.Message })
  }
}

function Start-ClassicEmulator {
  param($Context, [switch]$WipeData)
  Require-File $script:EmulatorExe
  Ensure-AvdConfig
  Remove-Item -LiteralPath $script:StdoutLog, $script:StderrLog -ErrorAction SilentlyContinue
  $args = @(
    "-avd", $script:KssmaRuntimeConfig.AvdName,
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
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  Start-Process -FilePath $script:EmulatorExe -ArgumentList $args -RedirectStandardOutput $script:StdoutLog -RedirectStandardError $script:StderrLog -WindowStyle Hidden | Out-Null
  Add-Stage $Context "start-emulator-process" ([ordered]@{ ok = $true; elapsedMs = [int]$sw.ElapsedMilliseconds; details = "started classic ARM emulator" })
}

function Wait-PrimaryBoot {
  param(
    $Context,
    [int]$TimeoutSeconds = 180
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $health = Get-PrimaryHealthData -Context $Context -TimeoutSeconds 2
    if ($health.ok) {
      return $true
    }
    Start-Sleep -Seconds 2
  }
  return $false
}

function Invoke-EnsureRuntime {
  param([switch]$WipeData)
  $ctx = New-RuntimeContext "ensure-runtime"
  $state = Read-RuntimeState
  if ((Test-StateFresh $state) -and (Get-StateValue $state "fastHealthOk") -and (Get-StateValue $state "serial") -eq $script:KssmaRuntimeConfig.PrimarySerial) {
    # ponytail: after ADB recovery, classic ARM19 sometimes needs just over 1s
    # to return all three getprop lines; the upgrade path is split transport and
    # boot property probes if this grows past the fast path budget.
    $health = Get-PrimaryHealthData -Context $ctx -TimeoutSeconds 2
    if ($health.ok) {
      $boot = Get-DeviceBootFingerprint -Serial $health.serial
      Add-Stage $ctx "boot-fingerprint" $boot.stage
      $cachedUptime = Get-StateValue $state "bootUptimeSeconds"
      if ($boot.ok -and $null -ne $cachedUptime -and $boot.uptimeSeconds -lt [int64]$cachedUptime) {
        Reset-BaselineStateValues ([ordered]@{ fastHealthOk = $true; bootCompleted = $true; abi = $health.abi; release = $health.release; bootUptimeSeconds = $boot.uptimeSeconds })
        $ctx.warnings += "Runtime reboot detected by uptime; baseline cache was invalidated."
        return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ cache = "invalidated-reboot"; abi = $health.abi; release = $health.release; bootCompleted = $health.bootCompleted })
      }
      return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ cache = "validated"; state = $state })
    }
    $ctx.warnings += "Fresh runtime-state cache was invalidated by fast-health."
  }

  $health = Get-PrimaryHealthData -Context $ctx -TimeoutSeconds 2 -IncludeTransport
  if ($health.ok) {
    $boot = Get-DeviceBootFingerprint -Serial $health.serial
    Add-Stage $ctx "boot-fingerprint" $boot.stage
    Update-RuntimeState ([ordered]@{ serial = $health.serial; fastHealthOk = $true; bootCompleted = $true; abi = $health.abi; release = $health.release; bootUptimeSeconds = $boot.uptimeSeconds })
    return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ abi = $health.abi; release = $health.release; bootCompleted = $health.bootCompleted; transport = $health.transport })
  }

  if ($health.transport.class -eq "adb-transport" -and $health.transport.emulatorProcesses.Count -eq 0) {
    Start-ClassicEmulator -Context $ctx -WipeData:$WipeData
    if (Wait-PrimaryBoot -Context $ctx -TimeoutSeconds 240) {
      $boot = Get-DeviceBootFingerprint -Serial $script:KssmaRuntimeConfig.PrimarySerial
      Add-Stage $ctx "boot-fingerprint" $boot.stage
      Reset-BaselineStateValues ([ordered]@{ fastHealthOk = $true; bootCompleted = $true; bootUptimeSeconds = $boot.uptimeSeconds })
      return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ started = $true; transport = $health.transport })
    }
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "boot-timeout" -RestartAllowed $false -RecommendedCommand "powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 diagnose" -Data ([ordered]@{ emulatorProcesses = @(Get-EmulatorProcesses) })
  }

  $repair = Invoke-RepairAdb
  $ctx.stages += $repair.stages
  if ($repair.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ repair = "ok"; repairData = $repair.data })
  }

  Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $repair.failureClass -RestartAllowed:$repair.restartAllowed -RecommendedCommand $repair.recommendedCommand -Data ([ordered]@{ transport = $health.transport; repair = $repair.data })
}

function Assert-RuntimeReady {
  $result = Invoke-EnsureRuntime
  if (-not $result.ok) {
    throw "Runtime is not ready: $($result.failureClass). Recommended: $($result.recommendedCommand)"
  }
}

function Get-DeviceFileExists {
  param([string]$Serial, [string]$Path, [int]$TimeoutSeconds = 5)
  $out = Invoke-Adb -Arguments @("-s", $Serial, "shell", "ls", $Path, "2>/dev/null") -TimeoutSeconds $TimeoutSeconds -AllowFailure
  return $out.stdout.Trim() -ne ""
}

function Get-HostsOk {
  param([string]$Serial)
  $hosts = Invoke-Adb -Arguments @("-s", $Serial, "shell", "cat", "/system/etc/hosts") -TimeoutSeconds 5 -AllowFailure
  [ordered]@{
    ok = ($hosts.stdout -match "10\.0\.2\.2\s+game\.ma\.mobimon\.com\.tw" -and $hosts.stdout -match "10\.0\.2\.2\s+dlc\.game-CBT\.ma\.sdo\.com")
    text = $hosts.stdout
    stage = $hosts
  }
}

function Ensure-Hosts {
  param($Context)
  $serial = $script:KssmaRuntimeConfig.PrimarySerial
  $check = Get-HostsOk -Serial $serial
  Add-Stage $Context "check-hosts" $check.stage
  if ($check.ok) {
    Add-Stage $Context "repair-hosts" ([ordered]@{ ok = $true; elapsedMs = 0; skipped = $true; details = "hosts already match baseline" })
    return [ordered]@{ ok = $true; changed = $false; hosts = $check.text }
  }

  $root = Invoke-Adb -Arguments @("-s", $serial, "root") -TimeoutSeconds 10 -AllowFailure
  Add-Stage $Context "adb-root-for-hosts" $root
  $remount = Invoke-Adb -Arguments @("-s", $serial, "remount") -TimeoutSeconds 20 -AllowFailure
  Add-Stage $Context "remount-system-for-hosts" $remount
  $hosts = "127.0.0.1 localhost`n10.0.2.2 game.ma.mobimon.com.tw`n10.0.2.2 dlc.game-CBT.ma.sdo.com`n"
  $hostsPath = Join-Path $env:TEMP "kssma-arm19-hosts"
  try {
    Set-Content -LiteralPath $hostsPath -Value $hosts -NoNewline
    $push = Invoke-Adb -Arguments @("-s", $serial, "push", $hostsPath, "/system/etc/hosts") -TimeoutSeconds 20 -AllowFailure
    Add-Stage $Context "push-hosts" $push
    $chmod = Invoke-Adb -Arguments @("-s", $serial, "shell", "chmod", "644", "/system/etc/hosts") -TimeoutSeconds 10 -AllowFailure
    Add-Stage $Context "chmod-hosts" $chmod
  } finally {
    Remove-Item -LiteralPath $hostsPath -Force -ErrorAction SilentlyContinue
  }
  $after = Get-HostsOk -Serial $serial
  Add-Stage $Context "verify-hosts" $after.stage
  [ordered]@{ ok = $after.ok; changed = $true; hosts = $after.text }
}

function Get-MountOk {
  param([string]$Serial)
  $mount = Invoke-Adb -Arguments @("-s", $Serial, "shell", "mount") -TimeoutSeconds 8 -AllowFailure
  $text = $mount.stdout
  $stashOk = Get-DeviceFileExists -Serial $Serial -Path "$script:InternalSaveDir/download/rest/treasurebox" -TimeoutSeconds 5
  [ordered]@{
    ok = ($stashOk -and $text -match [regex]::Escape($script:DeviceSaveDir) -and $text -match [regex]::Escape($script:MediaSaveDir))
    text = $text
    stashOk = $stashOk
    stage = $mount
  }
}

function Ensure-Mount {
  param($Context)
  $serial = $script:KssmaRuntimeConfig.PrimarySerial
  $check = Get-MountOk -Serial $serial
  Add-Stage $Context "check-mount" $check.stage
  if ($check.ok) {
    Add-Stage $Context "repair-mount" ([ordered]@{ ok = $true; elapsedMs = 0; skipped = $true; details = "bind mounts already match baseline" })
    return [ordered]@{ ok = $true; changed = $false }
  }
  if (-not (Get-DeviceFileExists -Serial $serial -Path "$script:InternalSaveDir/download/rest/treasurebox")) {
    Add-Stage $Context "repair-mount" ([ordered]@{ ok = $false; elapsedMs = 0; skipped = $true; failureClass = "resource-stash-missing"; details = "$script:InternalSaveDir is not populated" })
    return [ordered]@{ ok = $false; changed = $false; failureClass = "resource-stash-missing" }
  }
  $root = Invoke-Adb -Arguments @("-s", $serial, "root") -TimeoutSeconds 10 -AllowFailure
  Add-Stage $Context "adb-root-for-mount" $root
  foreach ($target in @($script:DeviceSaveDir, $script:MediaSaveDir)) {
    Add-Stage $Context "umount-$target" (Invoke-Adb -Arguments @("-s", $serial, "shell", "umount", $target) -TimeoutSeconds 10 -AllowFailure)
  }
  Add-Stage $Context "mkdir-save-mounts" (Invoke-Adb -Arguments @("-s", $serial, "shell", "mkdir", "-p", $script:MediaSaveDir, $script:DeviceSaveDir) -TimeoutSeconds 10 -AllowFailure)
  Add-Stage $Context "bind-media-save" (Invoke-Adb -Arguments @("-s", $serial, "shell", "mount", "-o", "bind", $script:InternalSaveDir, $script:MediaSaveDir) -TimeoutSeconds 20 -AllowFailure)
  Add-Stage $Context "bind-fuse-save" (Invoke-Adb -Arguments @("-s", $serial, "shell", "mount", "-o", "bind", $script:InternalSaveDir, $script:DeviceSaveDir) -TimeoutSeconds 20 -AllowFailure)
  $after = Get-MountOk -Serial $serial
  Add-Stage $Context "verify-mount" $after.stage
  [ordered]@{ ok = $after.ok; changed = $true }
}

function Ensure-Display {
  param($Context)
  $serial = $script:KssmaRuntimeConfig.PrimarySerial
  $size = Invoke-Adb -Arguments @("-s", $serial, "shell", "wm", "size") -TimeoutSeconds 10 -AllowFailure
  Add-Stage $Context "check-display-size" $size
  $density = Invoke-Adb -Arguments @("-s", $serial, "shell", "wm", "density") -TimeoutSeconds 10 -AllowFailure
  Add-Stage $Context "check-display-density" $density
  $sizeOk = $size.stdout -match [regex]::Escape($script:KssmaRuntimeConfig.DisplaySize)
  $densityOk = $density.stdout -match [regex]::Escape($script:KssmaRuntimeConfig.DisplayDensity)
  $changed = $false
  if (-not $sizeOk) {
    Add-Stage $Context "set-display-size" (Invoke-Adb -Arguments @("-s", $serial, "shell", "wm", "size", $script:KssmaRuntimeConfig.DisplaySize) -TimeoutSeconds 10 -AllowFailure)
    $changed = $true
  } else {
    Add-Stage $Context "set-display-size" ([ordered]@{ ok = $true; elapsedMs = 0; skipped = $true; details = "display size already baseline" })
  }
  if (-not $densityOk) {
    Add-Stage $Context "set-display-density" (Invoke-Adb -Arguments @("-s", $serial, "shell", "wm", "density", $script:KssmaRuntimeConfig.DisplayDensity) -TimeoutSeconds 10 -AllowFailure)
    $changed = $true
  } else {
    Add-Stage $Context "set-display-density" ([ordered]@{ ok = $true; elapsedMs = 0; skipped = $true; details = "display density already baseline" })
  }
  [ordered]@{ ok = $true; changed = $changed; size = $size.stdout; density = $density.stdout }
}

function Ensure-AudioConfig {
  param($Context)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    Require-File $script:ConfigPath
    $config = Get-Content -Raw -LiteralPath $script:ConfigPath
    $ok = $config -match "(?m)^hw\.audioInput=yes$" -and $config -match "(?m)^hw\.audioOutput=yes$"
    if (-not $ok) {
      Set-AvdConfigValue "hw.audioInput" "yes"
      Set-AvdConfigValue "hw.audioOutput" "yes"
    }
    Add-Stage $Context "check-audio-config" ([ordered]@{ ok = $true; elapsedMs = [int]$sw.ElapsedMilliseconds; skipped = $ok; details = if ($ok) { "audio config already enabled" } else { "audio config enabled for next boot" } })
    [ordered]@{ ok = $true; changed = -not $ok }
  } catch {
    Add-Stage $Context "check-audio-config" ([ordered]@{ ok = $false; elapsedMs = [int]$sw.ElapsedMilliseconds; stderr = $_.Exception.Message })
    [ordered]@{ ok = $false; changed = $false; error = $_.Exception.Message }
  }
}

function Ensure-PackageInstalled {
  param($Context)
  $serial = $script:KssmaRuntimeConfig.PrimarySerial
  $pm = Invoke-Adb -Arguments @("-s", $serial, "shell", "pm", "path", $script:KssmaRuntimeConfig.Package) -TimeoutSeconds 10 -AllowFailure
  Add-Stage $Context "check-package" $pm
  [ordered]@{ ok = ($pm.stdout -match "^package:"); path = $pm.stdout.Trim() }
}

function Invoke-EnsureBaseline {
  param([string[]]$Only = @())
  $ctx = New-RuntimeContext "ensure-baseline"
  $runtime = Invoke-EnsureRuntime
  $ctx.stages += $runtime.stages
  if (-not $runtime.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $runtime.failureClass -RestartAllowed:$runtime.restartAllowed -RecommendedCommand $runtime.recommendedCommand -Data ([ordered]@{ runtime = $runtime.data })
  }
  $state = Read-RuntimeState
  $boot = Get-DeviceBootFingerprint -Serial $script:KssmaRuntimeConfig.PrimarySerial
  Add-Stage $ctx "boot-fingerprint" $boot.stage
  $cachedUptime = Get-StateValue $state "bootUptimeSeconds"
  if ($boot.ok -and $null -ne $cachedUptime -and $boot.uptimeSeconds -lt [int64]$cachedUptime) {
    Reset-BaselineStateValues ([ordered]@{ fastHealthOk = $true; bootCompleted = $true; bootUptimeSeconds = $boot.uptimeSeconds })
    $state = Read-RuntimeState
    $ctx.warnings += "Runtime reboot detected by uptime; baseline cache was invalidated."
  }
  $baselineCacheOk = (Get-StateValue $state "baselineOk") -and
    (Get-StateValue $state "hostsOk") -and
    (Get-StateValue $state "mountOk") -and
    (Get-StateValue $state "displayOk") -and
    (Get-StateValue $state "audioOk") -and
    (Get-StateValue $state "packageOk")
  if ($Only.Count -eq 0 -and (Test-StateFresh $state) -and $baselineCacheOk) {
    $hosts = Get-HostsOk -Serial $script:KssmaRuntimeConfig.PrimarySerial
    Add-Stage $ctx "check-hosts-cache-guard" $hosts.stage
    if (-not $hosts.ok) {
      $ctx.warnings += "Fresh baseline cache claimed hostsOk, but device hosts no longer matched; repairing hosts only."
      $data = [ordered]@{ hosts = Ensure-Hosts -Context $ctx }
      Update-RuntimeState ([ordered]@{
        serial = $script:KssmaRuntimeConfig.PrimarySerial
        baselineOk = $data.hosts.ok
        bootUptimeSeconds = $boot.uptimeSeconds
        hostsOk = $data.hosts.ok
      })
      if ($data.hosts.ok) {
        return Complete-RuntimeResult -Context $ctx -Ok $true -Data $data
      }
      return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "baseline-mismatch" -RestartAllowed $false -RecommendedCommand "Fix hosts repair shown in stages, or run diagnose." -Data $data
    }
    $mount = Get-MountOk -Serial $script:KssmaRuntimeConfig.PrimarySerial
    Add-Stage $ctx "check-mount-cache-guard" $mount.stage
    if (-not $mount.ok) {
      $ctx.warnings += "Fresh baseline cache claimed mountOk, but device save mount/stash no longer matched; repairing mount only."
      if (-not $mount.stashOk) {
        $ctx.warnings += "Internal save stash is missing; restoring full sample save before remount."
        $preload = Invoke-PreloadResources -Mode full
        $ctx.stages += $preload.stages
        Update-RuntimeState ([ordered]@{
          serial = $script:KssmaRuntimeConfig.PrimarySerial
          baselineOk = $preload.ok
          bootUptimeSeconds = $boot.uptimeSeconds
          mountOk = $preload.ok
        })
        if ($preload.ok) {
          return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ preload = $preload.data })
        }
        return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "baseline-mismatch" -RestartAllowed $false -RecommendedCommand "Full resource stash restore failed; inspect preload stages before gameplay validation." -Data ([ordered]@{ preload = $preload.data; preloadFailureClass = $preload.failureClass })
      }
      $data = [ordered]@{ mount = Ensure-Mount -Context $ctx }
      Update-RuntimeState ([ordered]@{
        serial = $script:KssmaRuntimeConfig.PrimarySerial
        baselineOk = $data.mount.ok
        bootUptimeSeconds = $boot.uptimeSeconds
        mountOk = $data.mount.ok
      })
      if ($data.mount.ok) {
        return Complete-RuntimeResult -Context $ctx -Ok $true -Data $data
      }
      return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "baseline-mismatch" -RestartAllowed $false -RecommendedCommand "Fix mount repair shown in stages, or run diagnose." -Data $data
    }
    Add-Stage $ctx "baseline-cache" ([ordered]@{ ok = $true; elapsedMs = 0; cached = $true; details = "fresh baseline cache" })
    return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ cache = "fresh"; state = $state })
  }

  $do = {
    param([string]$Name)
    return $Only.Count -eq 0 -or $Only -contains $Name
  }
  $data = [ordered]@{}
  if (& $do "hosts") { $data.hosts = Ensure-Hosts -Context $ctx }
  if (& $do "mount") { $data.mount = Ensure-Mount -Context $ctx }
  if (& $do "display") { $data.display = Ensure-Display -Context $ctx }
  if (& $do "audio") { $data.audio = Ensure-AudioConfig -Context $ctx }
  if (& $do "package") { $data.package = Ensure-PackageInstalled -Context $ctx }

  $ok = $true
  foreach ($value in $data.Values) {
    if ($value.Contains("ok") -and -not $value.ok) {
      $ok = $false
    }
  }
  Update-RuntimeState ([ordered]@{
    serial = $script:KssmaRuntimeConfig.PrimarySerial
    baselineOk = $ok
    bootUptimeSeconds = $boot.uptimeSeconds
    hostsOk = if ($data.hosts) { $data.hosts.ok } else { $null }
    mountOk = if ($data.mount) { $data.mount.ok } else { $null }
    displayOk = if ($data.display) { $data.display.ok } else { $null }
    audioOk = if ($data.audio) { $data.audio.ok } else { $null }
    packageOk = if ($data.package) { $data.package.ok } else { $null }
  })
  if ($ok) {
    Complete-RuntimeResult -Context $ctx -Ok $true -Data $data
  } else {
    Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "baseline-mismatch" -RestartAllowed $false -RecommendedCommand "Fix the failed baseline item shown in data/stages, or run diagnose." -Data $data
  }
}

function Resolve-ApkPath {
  param([string]$ApkPath)
  if ($ApkPath) {
    return (Resolve-Path -LiteralPath $ApkPath).Path
  }
  throw "-ApkPath is required. Refusing to guess a latest signed APK because that can overwrite the accepted librooneyj.so baseline."
}

function Get-InstalledApkPath {
  param($Context)
  $serial = $script:KssmaRuntimeConfig.PrimarySerial
  $pm = Invoke-Adb -Arguments @("-s", $serial, "shell", "pm", "path", $script:KssmaRuntimeConfig.Package) -TimeoutSeconds 10 -AllowFailure
  if ($Context) { Add-Stage $Context "pm-path" $pm }
  if ($pm.timedOut) {
    throw "pm path timed out while checking $($script:KssmaRuntimeConfig.Package); package state is unknown."
  }
  $line = Get-OutputLines $pm.stdout | Where-Object { $_ -match "^package:" } | Select-Object -First 1
  if (-not $line) {
    throw "Package $($script:KssmaRuntimeConfig.Package) is not installed. Use install-apk once before patch-lib."
  }
  return ($line -replace "^package:", "").Trim()
}

function Get-InstalledLibPath {
  param($Context)
  $apkPath = Get-InstalledApkPath -Context $Context
  $apkName = [System.IO.Path]::GetFileNameWithoutExtension($apkPath)
  return "/data/app-lib/$apkName/librooneyj.so"
}

function Get-LibrooneySource {
  param([string]$SourcePath)
  $resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
  if ($resolvedSource.EndsWith(".so", [System.StringComparison]::OrdinalIgnoreCase)) {
    return [ordered]@{ Path = $resolvedSource; Temporary = $false }
  }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $tempPath = Join-Path $env:TEMP "kssma-librooneyj-$([guid]::NewGuid()).so"
  $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedSource)
  try {
    $entry = $zip.GetEntry("lib/armeabi/librooneyj.so")
    if (-not $entry) {
      throw "APK does not contain lib/armeabi/librooneyj.so: $resolvedSource"
    }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $tempPath, $true)
  } finally {
    $zip.Dispose()
  }
  [ordered]@{ Path = $tempPath; Temporary = $true }
}

function Test-InstalledLibMatches {
  param(
    [string]$SourceLibPath,
    $Context
  )
  $serial = $script:KssmaRuntimeConfig.PrimarySerial
  $remoteLibPath = Get-InstalledLibPath -Context $Context
  $pulledPath = Join-Path $env:TEMP "kssma-librooneyj-installed-$([guid]::NewGuid()).so"
  try {
    $pull = Invoke-Adb -Arguments @("-s", $serial, "pull", $remoteLibPath, $pulledPath) -TimeoutSeconds 60 -AllowFailure
    if ($Context) { Add-Stage $Context "pull-installed-lib" $pull }
    if ($pull.timedOut) {
      return [ordered]@{ ok = $false; unknown = $true; failureClass = "patch-verify-timeout"; details = "Timed out pulling installed librooneyj.so for hash verification."; remoteLib = $remoteLibPath }
    }
    if (-not (Test-Path -LiteralPath $pulledPath)) {
      return [ordered]@{ ok = $false; unknown = $false; failureClass = "patch-verify-missing-pull"; details = "Installed librooneyj.so pull did not create a local file."; remoteLib = $remoteLibPath }
    }
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceLibPath).Hash
    $pulledHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $pulledPath).Hash
    $matches = ($sourceHash -eq $pulledHash)
    $failure = if ($matches) { "" } else { "patch-verify-hash-mismatch" }
    return [ordered]@{ ok = $matches; unknown = $false; failureClass = $failure; sourceHash = $sourceHash; installedHash = $pulledHash; remoteLib = $remoteLibPath }
  } finally {
    Remove-Item -LiteralPath $pulledPath -Force -ErrorAction SilentlyContinue
  }
}

function Assert-ExpectedLibHash {
  param(
    [string]$SourceLibPath,
    [string]$ExpectedSha256,
    [string]$Name
  )
  if (-not $ExpectedSha256) {
    return
  }
  $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceLibPath).Hash
  if ($actual -ne $ExpectedSha256) {
    throw "$Name hash mismatch: got $actual, expected $ExpectedSha256"
  }
}

function Invoke-EnsureExplorationBaseline {
  $ctx = New-RuntimeContext "ensure-exploration-baseline"
  $runtime = Invoke-EnsureRuntime
  $ctx.stages += $runtime.stages
  if (-not $runtime.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $runtime.failureClass -RestartAllowed:$runtime.restartAllowed -RecommendedCommand $runtime.recommendedCommand
  }
  try {
    if (-not (Test-Path -LiteralPath $script:ExplorationAcceptedLibPath)) {
      throw "Missing accepted exploration native baseline: $($script:ExplorationAcceptedLibPath)"
    }
    Assert-ExpectedLibHash -SourceLibPath $script:ExplorationAcceptedLibPath -ExpectedSha256 $script:ExplorationAcceptedLibSha256 -Name "accepted exploration native baseline"
    $verify = Test-InstalledLibMatches -SourceLibPath $script:ExplorationAcceptedLibPath -Context $ctx
    if ($verify.ok) {
      return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{
          source = $script:ExplorationAcceptedLibPath
          status = "already-matched"
          verify = $verify
        })
    }
    Add-Stage $ctx "force-stop-before-exploration-patch" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "am", "force-stop", $script:KssmaRuntimeConfig.Package) -TimeoutSeconds 10 -AllowFailure)
    $remoteLibPath = Get-InstalledLibPath -Context $ctx
    Add-Stage $ctx "push-accepted-exploration-librooneyj" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "push", $script:ExplorationAcceptedLibPath, $remoteLibPath) -TimeoutSeconds 120 -AllowFailure)
    Add-Stage $ctx "chmod-librooneyj" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "chmod", "644", $remoteLibPath) -TimeoutSeconds 10 -AllowFailure)
    Add-Stage $ctx "chown-librooneyj" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "chown", "system:system", $remoteLibPath) -TimeoutSeconds 10 -AllowFailure)
    $postVerify = Test-InstalledLibMatches -SourceLibPath $script:ExplorationAcceptedLibPath -Context $ctx
    if (-not $postVerify.ok) {
      return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $postVerify.failureClass -RecommendedCommand "Do not continue gameplay validation; installed librooneyj.so still does not match the accepted exploration baseline." -Data ([ordered]@{
          source = $script:ExplorationAcceptedLibPath
          expectedHash = $script:ExplorationAcceptedLibSha256
          before = $verify
          after = $postVerify
        })
    }
    Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{
        source = $script:ExplorationAcceptedLibPath
        status = "patched-accepted-exploration-librooneyj"
        before = $verify
        verify = $postVerify
      })
  } catch {
    Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "ensure-exploration-baseline-failed" -RecommendedCommand "Inspect data.error; do not run generic patch-lib or install-apk without an explicit -ApkPath." -Data ([ordered]@{ error = $_.Exception.Message })
  }
}

function Invoke-PatchLib {
  param([string]$ApkPath)
  $ctx = New-RuntimeContext "patch-lib"
  try {
    $sourcePath = Resolve-ApkPath -ApkPath $ApkPath
    $sourceLib = Get-LibrooneySource -SourcePath $sourcePath
  } catch {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "source-required" -RecommendedCommand "Pass an explicit -ApkPath pointing to the intended APK or .so; this command no longer guesses a latest signed APK." -Data ([ordered]@{ error = $_.Exception.Message })
  }
  $runtime = Invoke-EnsureRuntime
  $ctx.stages += $runtime.stages
  if (-not $runtime.ok) {
    if ($sourceLib -and $sourceLib.Temporary) {
      Remove-Item -LiteralPath $sourceLib.Path -Force -ErrorAction SilentlyContinue
    }
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $runtime.failureClass -RestartAllowed:$runtime.restartAllowed -RecommendedCommand $runtime.recommendedCommand
  }
  try {
    $remoteLibPath = Get-InstalledLibPath -Context $ctx
    $preVerify = Test-InstalledLibMatches -SourceLibPath $sourceLib.Path -Context $ctx
    if ($preVerify.ok) {
      return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ source = $sourcePath; remoteLib = $remoteLibPath; status = "already-matched"; verify = $preVerify })
    }
    Add-Stage $ctx "force-stop-before-patch" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "am", "force-stop", $script:KssmaRuntimeConfig.Package) -TimeoutSeconds 10 -AllowFailure)
    Add-Stage $ctx "push-librooneyj" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "push", $sourceLib.Path, $remoteLibPath) -TimeoutSeconds 120 -AllowFailure)
    Add-Stage $ctx "chmod-librooneyj" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "chmod", "644", $remoteLibPath) -TimeoutSeconds 10 -AllowFailure)
    Add-Stage $ctx "chown-librooneyj" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "chown", "system:system", $remoteLibPath) -TimeoutSeconds 10 -AllowFailure)
    $verify = Test-InstalledLibMatches -SourceLibPath $sourceLib.Path -Context $ctx
    if (-not $verify.ok) {
      return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $verify.failureClass -RecommendedCommand "Do not reinstall blindly; run diagnose or rerun patch-lib after ADB settles." -Data ([ordered]@{ source = $sourcePath; remoteLib = $remoteLibPath; verify = $verify })
    }
    Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ source = $sourcePath; remoteLib = $remoteLibPath; status = "patched-librooneyj"; before = $preVerify; verify = $verify })
  } catch {
    $failure = if ($_.Exception.Message -match "pm path timed out") { "patch-verify-timeout" } elseif ($_.Exception.Message -match "not installed") { "package-missing" } else { "patch-lib-failed" }
    Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $failure -RecommendedCommand "If package is missing, use install-apk; otherwise run diagnose instead of retrying full install blindly." -Data ([ordered]@{ error = $_.Exception.Message })
  } finally {
    if ($sourceLib -and $sourceLib.Temporary) {
      Remove-Item -LiteralPath $sourceLib.Path -Force -ErrorAction SilentlyContinue
    }
  }
}

function Clear-InstallScratch {
  param($Context)
  $serial = $script:KssmaRuntimeConfig.PrimarySerial
  Add-Stage $Context "clean-install-tmp-apks" (Invoke-Adb -Arguments @("-s", $serial, "shell", "rm", "-f", "/data/local/tmp/*.apk", "/data/local/tmp/kssma-*.apk", "/data/local/tmp/million-cn-*") -TimeoutSeconds 20 -AllowFailure)
  Add-Stage $Context "clean-install-vmdl" (Invoke-Adb -Arguments @("-s", $serial, "shell", "rm", "-rf", "/data/app/vmdl-*", "/data/app-lib/vmdl-*") -TimeoutSeconds 20 -AllowFailure)
}

function Convert-DeviceSizeToBytes {
  param([string]$Value)
  $text = ($Value -replace "`r|`n", "").Trim()
  if ($text -notmatch "^([0-9]+(?:\.[0-9]+)?)([KMG])?$") { return 0 }
  $number = [double]$Matches[1]
  switch ($Matches[2]) {
    "G" { return [int64]($number * 1024 * 1024 * 1024) }
    "M" { return [int64]($number * 1024 * 1024) }
    "K" { return [int64]($number * 1024) }
    default { return [int64]$number }
  }
}

function Get-DataPartitionInfo {
  param($Context)
  $df = Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "df", "/data") -TimeoutSeconds 10 -AllowFailure
  if ($Context) { Add-Stage $Context "df-data" $df }
  $line = Get-OutputLines $df.stdout | Where-Object { $_ -match "\s/data\s*$|^/data\s+" } | Select-Object -Last 1
  if (-not $line) { return $null }
  $parts = @($line -split "\s+" | Where-Object { $_ -ne "" })
  if ($parts.Count -lt 4) { return $null }
  [ordered]@{
    raw = $line
    sizeBytes = Convert-DeviceSizeToBytes $parts[1]
    usedBytes = Convert-DeviceSizeToBytes $parts[2]
    freeBytes = Convert-DeviceSizeToBytes $parts[3]
  }
}

function Invoke-InstallApk {
  param([string]$ApkPath)
  $ctx = New-RuntimeContext "install-apk"
  try {
    $resolvedApkPath = Resolve-ApkPath -ApkPath $ApkPath
  } catch {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "source-required" -RecommendedCommand "Pass an explicit -ApkPath pointing to the APK to install; this command no longer guesses a latest signed APK." -Data ([ordered]@{ error = $_.Exception.Message })
  }
  $runtime = Invoke-EnsureRuntime
  $ctx.stages += $runtime.stages
  if (-not $runtime.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $runtime.failureClass -RestartAllowed:$runtime.restartAllowed -RecommendedCommand $runtime.recommendedCommand
  }
  try {
    Clear-InstallScratch -Context $ctx
    $dataInfo = Get-DataPartitionInfo -Context $ctx
    if ($dataInfo) {
      $apkBytes = (Get-Item -LiteralPath $resolvedApkPath).Length
      $requiredBytes = $apkBytes + 256MB
      if ($dataInfo.freeBytes -lt $requiredBytes) {
        return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "insufficient-data-space" -RecommendedCommand "Free /data space or enlarge disk.dataPartition.size before install-apk." -Data ([ordered]@{ data = $dataInfo; apkBytes = $apkBytes; requiredBytes = $requiredBytes })
      }
    }
    $install = Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "install", "-r", "-f", $resolvedApkPath) -TimeoutSeconds 900 -AllowFailure
    Add-Stage $ctx "adb-install" $install
    if ($install.ok -and -not $install.timedOut -and $install.stdout -match "Success") {
      return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ apk = $resolvedApkPath; install = $install.stdout })
    }

    $sourceLib = Get-LibrooneySource -SourcePath $resolvedApkPath
    $verify = Test-InstalledLibMatches -SourceLibPath $sourceLib.Path -Context $ctx
    if ($verify.ok) {
      return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ apk = $resolvedApkPath; install = $install.stdout; note = "adb install did not report clean Success, but installed librooneyj.so matches" })
    }
    $failure = if ($verify.unknown) { $verify.failureClass } else { "install-failed" }
    Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $failure -RecommendedCommand "Inspect install stages; do not restart emulator or retry full install blindly." -Data ([ordered]@{ apk = $resolvedApkPath; stdout = $install.stdout; stderr = $install.stderr; data = $dataInfo; verify = $verify })
  } catch {
    Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "install-failed" -RecommendedCommand "Run diagnose and inspect /data/install logs before retrying." -Data ([ordered]@{ error = $_.Exception.Message })
  } finally {
    if ($sourceLib -and $sourceLib.Temporary) {
      Remove-Item -LiteralPath $sourceLib.Path -Force -ErrorAction SilentlyContinue
    }
  }
}

function Invoke-InstallCheck {
  param([string]$ApkPath)
  $ctx = New-RuntimeContext "install-check"
  $runtime = Invoke-EnsureRuntime
  $ctx.stages += $runtime.stages
  if (-not $runtime.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $runtime.failureClass -RestartAllowed:$runtime.restartAllowed -RecommendedCommand $runtime.recommendedCommand
  }
  try {
    $pmPath = Get-InstalledApkPath -Context $ctx
    $verify = $null
    if ($ApkPath) {
      $sourcePath = Resolve-ApkPath -ApkPath $ApkPath
      $sourceLib = Get-LibrooneySource -SourcePath $sourcePath
      $verify = Test-InstalledLibMatches -SourceLibPath $sourceLib.Path -Context $ctx
    }
    Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ packagePath = $pmPath; libMatchesSource = if ($verify) { $verify.ok } else { $null }; verify = $verify })
  } catch {
    $failure = if ($_.Exception.Message -match "pm path timed out") { "install-check-timeout" } elseif ($_.Exception.Message -match "not installed") { "package-missing" } else { "install-check-failed" }
    Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $failure -RecommendedCommand "Use install-apk if package is missing; otherwise inspect package path." -Data ([ordered]@{ error = $_.Exception.Message })
  } finally {
    if ($sourceLib -and $sourceLib.Temporary) {
      Remove-Item -LiteralPath $sourceLib.Path -Force -ErrorAction SilentlyContinue
    }
  }
}

function Invoke-LaunchGame {
  $ctx = New-RuntimeContext "launch"
  $health = Get-PrimaryHealthData -Context $ctx -TimeoutSeconds 2
  if (-not $health.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "runtime-not-ready" -RestartAllowed $false -RecommendedCommand "powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-runtime"
  }
  Add-Stage $ctx "dismiss-keyguard-enter" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "input", "keyevent", "66") -TimeoutSeconds 10 -AllowFailure)
  Add-Stage $ctx "force-stop-game" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "am", "force-stop", $script:KssmaRuntimeConfig.Package) -TimeoutSeconds 10 -AllowFailure)
  $start = Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "am", "start", "-n", "$($script:KssmaRuntimeConfig.Package)/$($script:KssmaRuntimeConfig.Activity)") -TimeoutSeconds 20 -AllowFailure
  Add-Stage $ctx "am-start-game" $start
  Complete-RuntimeResult -Context $ctx -Ok ($start.ok -and -not $start.timedOut) -FailureClass $(if ($start.ok) { "" } else { "launch-failed" }) -RecommendedCommand $(if ($start.ok) { "" } else { "Run diagnose." }) -Data ([ordered]@{ start = $start.stdout })
}

function Invoke-Observe {
  param(
    [string[]]$Observe = @("Requests", "Activity", "Logcat", "Screenshot"),
    [string]$Tag = ""
  )
  $ctx = New-RuntimeContext "observe"
  $health = Get-PrimaryHealthData -Context $ctx -TimeoutSeconds 2
  if (-not $health.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "runtime-not-ready" -RecommendedCommand "powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-runtime"
  }
  if ($Observe -contains "Full") {
    $Observe = @("Requests", "Activity", "Logcat", "Screenshot", "Processes")
  }
  $stamp = if ($Tag) { $Tag } else { Get-Date -Format "yyyyMMdd-HHmmss" }
  $prefix = Join-Path $PSScriptRoot "kssma-runtime-$stamp"
  $artifacts = [ordered]@{}
  if ($Observe -contains "Requests") {
    $out = "$prefix-requests.txt"
    $serverLog = Join-Path $PSScriptRoot "kssma-server.out.log"
    if (Test-Path -LiteralPath $serverLog) {
      Select-String -Path $serverLog -Pattern "world_list|add_user|check_inspection|connect_app|contents_|connect_web|miss" -SimpleMatch:$false -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Line } |
        Set-Content -LiteralPath $out
    } else {
      "server log not found: $serverLog" | Set-Content -LiteralPath $out
    }
    Add-Stage $ctx "observe-requests" ([ordered]@{ ok = $true; elapsedMs = 0; details = $out })
    $artifacts.requests = $out
  }
  if ($Observe -contains "Activity") {
    $out = "$prefix-activity.txt"
    $stage = Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "dumpsys", "activity", "activities") -TimeoutSeconds 15 -AllowFailure
    $stage.stdout | Set-Content -LiteralPath $out
    Add-Stage $ctx "observe-activity" $stage
    $artifacts.activity = $out
  }
  if ($Observe -contains "Processes") {
    $out = "$prefix-processes.txt"
    $stage = Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "dumpsys", "activity", "processes") -TimeoutSeconds 15 -AllowFailure
    $stage.stdout | Set-Content -LiteralPath $out
    Add-Stage $ctx "observe-processes" $stage
    $artifacts.processes = $out
  }
  if ($Observe -contains "Logcat") {
    $out = "$prefix-logcat.txt"
    $stage = Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "logcat", "-d", "-v", "time") -TimeoutSeconds 30 -AllowFailure
    $stage.stdout | Set-Content -LiteralPath $out
    Add-Stage $ctx "observe-logcat" $stage
    $artifacts.logcat = $out
  }
  if ($Observe -contains "Screenshot") {
    $remote = "/data/local/tmp/kssma-runtime-observe.png"
    $out = "$prefix.png"
    Add-Stage $ctx "observe-screencap" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "screencap", "-p", $remote) -TimeoutSeconds 20 -AllowFailure)
    Add-Stage $ctx "observe-pull-screenshot" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "pull", $remote, $out) -TimeoutSeconds 30 -AllowFailure)
    $artifacts.screenshot = $out
  }
  Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ artifacts = $artifacts })
}

function Invoke-Diagnose {
  $ctx = New-RuntimeContext "diagnose"
  $health = Get-PrimaryHealthData -Context $ctx -TimeoutSeconds 2 -IncludeTransport
  $devices = $health.transport.devices
  $emulators = $health.transport.emulatorProcesses
  $data = [ordered]@{
    health = $health
    devices = $devices
    emulatorProcesses = $emulators
    transport = $health.transport
    adbExe = $script:AdbExe
    emulatorExe = $script:EmulatorExe
    statePath = $script:StatePath
    state = Read-RuntimeState
  }
  if ($health.ok) {
    $data.hosts = Get-HostsOk -Serial $script:KssmaRuntimeConfig.PrimarySerial
    Add-Stage $ctx "diagnose-hosts" $data.hosts.stage
    $data.mount = Get-MountOk -Serial $script:KssmaRuntimeConfig.PrimarySerial
    Add-Stage $ctx "diagnose-mount" $data.mount.stage
    $data.display = Ensure-Display -Context $ctx
    $data.package = Ensure-PackageInstalled -Context $ctx
    $data.data = Get-DataPartitionInfo -Context $ctx
    $obs = Invoke-Observe -Observe @("Full") -Tag ("diagnose-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    $ctx.stages += $obs.stages
    $data.artifacts = $obs.data.artifacts
  }
  Complete-RuntimeResult -Context $ctx -Ok $health.ok -FailureClass $(if ($health.ok) { "" } else { $health.transport.class }) -RestartAllowed:$health.transport.restartAllowed -RecommendedCommand $(if ($health.ok) { "" } else { "powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 repair-adb" }) -Data $data
}

function Invoke-RestartRuntime {
  param(
    [switch]$Force,
    [string]$Reason,
    [switch]$WipeData
  )
  $ctx = New-RuntimeContext "restart-runtime"
  if (-not $Force -or [string]::IsNullOrWhiteSpace($Reason)) {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "restart-requires-force-reason" -RestartAllowed $true -RecommendedCommand "powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 restart-runtime -Force -Reason `"short concrete reason`""
  }
  Add-Stage $ctx "adb-emu-kill-primary" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "emu", "kill") -TimeoutSeconds 5 -AllowFailure)
  Add-Stage $ctx "adb-emu-kill-legacy" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.LegacySerial, "emu", "kill") -TimeoutSeconds 5 -AllowFailure)
  Start-Sleep -Seconds 2
  $killed = @()
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  foreach ($proc in @(Get-EmulatorProcesses)) {
    Stop-Process -Id $proc.processId -Force -ErrorAction SilentlyContinue
    $killed += $proc
  }
  Add-Stage $ctx "kill-classic-emulator-processes" ([ordered]@{ ok = $true; elapsedMs = [int]$sw.ElapsedMilliseconds; details = "killed=$($killed.Count)" })
  Start-Sleep -Seconds 2
  Start-ClassicEmulator -Context $ctx -WipeData:$WipeData
  $bootOk = Wait-PrimaryBoot -Context $ctx -TimeoutSeconds 240
  if ($bootOk) {
    $boot = Get-DeviceBootFingerprint -Serial $script:KssmaRuntimeConfig.PrimarySerial
    Add-Stage $ctx "boot-fingerprint" $boot.stage
    Reset-BaselineStateValues ([ordered]@{ fastHealthOk = $true; bootCompleted = $true; bootUptimeSeconds = $boot.uptimeSeconds; lastRestartReason = $Reason })
    return Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ reason = $Reason; killed = $killed })
  } else {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "restart-boot-timeout" -RestartAllowed $false -RecommendedCommand "Run diagnose and inspect emulator stdout/stderr logs." -Data ([ordered]@{ reason = $Reason; killed = $killed; stdoutLog = $script:StdoutLog; stderrLog = $script:StderrLog })
  }
}

function Invoke-StopRuntime {
  param([string]$Reason = "legacy stop command")
  $ctx = New-RuntimeContext "stop-runtime"
  Add-Stage $ctx "adb-emu-kill-primary" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "emu", "kill") -TimeoutSeconds 5 -AllowFailure)
  Add-Stage $ctx "adb-emu-kill-legacy" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.LegacySerial, "emu", "kill") -TimeoutSeconds 5 -AllowFailure)
  Start-Sleep -Seconds 2
  $killed = @()
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  foreach ($proc in @(Get-EmulatorProcesses)) {
    Stop-Process -Id $proc.processId -Force -ErrorAction SilentlyContinue
    $killed += $proc
  }
  Add-Stage $ctx "kill-classic-emulator-processes" ([ordered]@{ ok = $true; elapsedMs = [int]$sw.ElapsedMilliseconds; details = "killed=$($killed.Count)" })
  Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ reason = $Reason; killed = $killed })
}

function Invoke-RunRuntime {
  param(
    [switch]$DriveLogin,
    [string[]]$Observe = @("Requests", "Activity", "Logcat"),
    [int]$WaitSeconds = 35,
    [string]$Tag = ""
  )
  $ctx = New-RuntimeContext "run"
  if ($DriveLogin) {
    $ctx.warnings += "run -DriveLogin is legacy debug plumbing; use `flow -Scenario <name>` for gameplay acceptance so login, server ownership, route waits, screenshots, and summaries stay in one artifact."
    $skillCheck = Join-Path $env:USERPROFILE ".codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1"
    if (-not (Test-Path -LiteralPath $skillCheck)) {
      return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "drive-login-harness-missing" -RecommendedCommand "Use the kssma-re-runtime skill or restore scripts\kssma_runtime_check.ps1."
    }
    $runTag = if ($Tag) { $Tag } else { "runtime-run-" + (Get-Date -Format "yyyyMMdd-HHmmss") }
    $args = @(
      "-NoProfile", "-ExecutionPolicy", "Bypass",
      "-File", $skillCheck,
      "-Repo", $script:RepoRoot,
      "-DriveLogin",
      "-DismissNoticeWebView",
      "-WaitSeconds", "$WaitSeconds",
      "-Tag", $runTag
    )
    $timeout = [Math]::Max(300, $WaitSeconds + 240)
    $stage = Invoke-RuntimeProcess -FilePath "powershell" -ArgumentList $args -TimeoutSeconds $timeout -AllowFailure
    Add-Stage $ctx "drive-login-harness" $stage
    $prefix = Join-Path $PSScriptRoot "kssma-runtime-$runTag"
    $artifacts = [ordered]@{
      summary = "$prefix-summary.txt"
      requests = "$prefix-requests.txt"
      activity = "$prefix-activity.txt"
      logcat = "$prefix-logcat.txt"
      screenshot = "$prefix.png"
      loginDriver = "$prefix-login-driver.txt"
    }
    $ok = $stage.ok -and -not $stage.timedOut
    return Complete-RuntimeResult -Context $ctx -Ok $ok -FailureClass $(if ($ok) { "" } else { "drive-login-failed" }) -RecommendedCommand $(if ($ok) { "" } else { "Read the summary artifact before changing APK or protocol." }) -Data ([ordered]@{
        delegated = "kssma_runtime_check.ps1"
        observeRequested = $Observe
        artifacts = $artifacts
        stdout = $stage.stdout
        stderr = $stage.stderr
      })
  }
  $baseline = Invoke-EnsureBaseline
  $ctx.stages += $baseline.stages
  if (-not $baseline.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $baseline.failureClass -RestartAllowed:$baseline.restartAllowed -RecommendedCommand $baseline.recommendedCommand -Data ([ordered]@{ baseline = $baseline.data })
  }
  Add-Stage $ctx "clear-logcat" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "logcat", "-c") -TimeoutSeconds 10 -AllowFailure)
  $launch = Invoke-LaunchGame
  $ctx.stages += $launch.stages
  if (-not $launch.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $launch.failureClass -RecommendedCommand $launch.recommendedCommand
  }

  Start-Sleep -Seconds $WaitSeconds
  $obs = Invoke-Observe -Observe $Observe -Tag $Tag
  $ctx.stages += $obs.stages
  Complete-RuntimeResult -Context $ctx -Ok $obs.ok -FailureClass $obs.failureClass -RecommendedCommand $obs.recommendedCommand -Data ([ordered]@{ artifacts = $obs.data.artifacts; driveLoginDelegated = [bool]$DriveLogin })
}

function Assert-LocalChildPath {
  param([string]$Child, [string]$Parent)
  $childFull = [System.IO.Path]::GetFullPath($Child)
  $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
  if (-not $childFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to modify path outside ${parentFull}: $childFull"
  }
}

function Restore-SampleSaveDump {
  Require-File $script:ResourceZipPath
  $sampleRoot = Join-Path $PSScriptRoot "million_cn"
  Assert-LocalChildPath $script:SampleDumpRoot $sampleRoot
  # ponytail: resource corruption is cheaper to fix by restoring the original 140330 save dump than by auditing every file.
  if (Test-Path -LiteralPath $script:SampleDumpRoot) {
    Remove-Item -LiteralPath $script:SampleDumpRoot -Recurse -Force
  }
  New-Item -ItemType Directory -Path $script:SampleDumpRoot | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($script:ResourceZipPath, $script:SampleDumpRoot)
  Require-File $script:SampleSaveDir
}

function Preload-SaveFile {
  param([string]$RelativePath, $Context)
  $sourcePath = Join-Path $script:SampleSaveDir $RelativePath
  Require-File $sourcePath
  $devicePath = "$script:DeviceSaveDir/$($RelativePath -replace '\\', '/')"
  if (Get-DeviceFileExists -Serial $script:KssmaRuntimeConfig.PrimarySerial -Path $devicePath) {
    return [ordered]@{ file = $RelativePath; status = "already-present" }
  }
  $deviceParent = $devicePath -replace "/[^/]+$", ""
  Add-Stage $Context "mkdir-$RelativePath" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "mkdir", "-p", $deviceParent) -TimeoutSeconds 10 -AllowFailure)
  Add-Stage $Context "push-$RelativePath" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "push", $sourcePath, $devicePath) -TimeoutSeconds 120 -AllowFailure)
  [ordered]@{ file = $RelativePath; status = "pushed" }
}

function Preload-DownloadDir {
  param([string]$Name, [string]$Sentinel, $Context)
  if ($Sentinel -and (Get-DeviceFileExists -Serial $script:KssmaRuntimeConfig.PrimarySerial -Path "$script:DeviceSaveDir/download/$Name/$Sentinel")) {
    return [ordered]@{ directory = "download/$Name"; files = 0; status = "already-present" }
  }
  $sourceDir = Join-Path $script:SampleSaveDir "download\$Name"
  Require-File $sourceDir
  Add-Stage $Context "mkdir-download-$Name" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "mkdir", "-p", "$script:DeviceSaveDir/download/$Name") -TimeoutSeconds 10 -AllowFailure)
  $files = Get-ChildItem -LiteralPath $sourceDir -Recurse -File
  foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($sourceDir.Length).TrimStart("\", "/") -replace "\\", "/"
    $devicePath = "$script:DeviceSaveDir/download/$Name/$relativePath"
    $deviceParent = $devicePath -replace "/[^/]+$", ""
    Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "mkdir", "-p", $deviceParent) -TimeoutSeconds 10 -AllowFailure | Out-Null
    Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "push", $file.FullName, $devicePath) -TimeoutSeconds 120 -AllowFailure | Out-Null
  }
  [ordered]@{ directory = "download/$Name"; files = $files.Count; status = "pushed" }
}

function Invoke-PreloadResources {
  param([ValidateSet("rest", "small", "full")] [string]$Mode)
  $ctx = New-RuntimeContext "preload-$Mode"
  $runtime = Invoke-EnsureRuntime
  $ctx.stages += $runtime.stages
  if (-not $runtime.ok) {
    return Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $runtime.failureClass -RestartAllowed:$runtime.restartAllowed -RecommendedCommand $runtime.recommendedCommand
  }
  $items = @()
  try {
    if ($Mode -eq "full") {
      Restore-SampleSaveDump
      Add-Stage $ctx "adb-root-for-full-preload" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "root") -TimeoutSeconds 10 -AllowFailure)
      Add-Stage $ctx "clear-internal-save-stash" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "rm", "-rf", $script:InternalSaveDir) -TimeoutSeconds 120 -AllowFailure)
      Add-Stage $ctx "mkdir-internal-save-stash" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "mkdir", "-p", $script:InternalSaveDir) -TimeoutSeconds 10 -AllowFailure)
      Add-Stage $ctx "push-full-save-stash" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "push", "$script:SampleSaveDir\.", $script:InternalSaveDir) -TimeoutSeconds 3600 -AllowFailure)
      Add-Stage $ctx "chmod-full-save-stash" (Invoke-Adb -Arguments @("-s", $script:KssmaRuntimeConfig.PrimarySerial, "shell", "chmod", "-R", "755", $script:InternalSaveDir) -TimeoutSeconds 120 -AllowFailure)
      $mount = Ensure-Mount -Context $ctx
      return Complete-RuntimeResult -Context $ctx -Ok $mount.ok -FailureClass $(if ($mount.ok) { "" } else { "mount-failed" }) -Data ([ordered]@{ mode = $Mode; mount = $mount })
    }
    if ($Mode -eq "rest") {
      $items += Preload-DownloadDir -Name "rest" -Sentinel "que_adv" -Context $ctx
    } else {
      foreach ($file in @(
          "appdata/save_version",
          "database/master_card",
          "database/master_item",
          "database/master_cardcategory",
          "database/master_boss",
          "database/master_scol",
          "database/master_combo",
          "download/image/adv/adv_chara111",
          "download/sound/bgm_common1.ogg"
        )) {
        $items += Preload-SaveFile -RelativePath $file -Context $ctx
      }
      $items += Preload-DownloadDir -Name "rest" -Sentinel "que_adv" -Context $ctx
      $items += Preload-DownloadDir -Name "scenario" -Sentinel "scsc_1010101" -Context $ctx
      $items += Preload-DownloadDir -Name "pack" -Sentinel "mainbg/mainbg_an_0_0" -Context $ctx
    }
    Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ mode = $Mode; items = $items })
  } catch {
    Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "preload-failed" -RecommendedCommand "Check sample save dump and device storage before retrying." -Data ([ordered]@{ error = $_.Exception.Message; items = $items })
  }
}

function Invoke-Status {
  $ctx = New-RuntimeContext "status"
  $health = Get-PrimaryHealthData -Context $ctx -TimeoutSeconds 2 -IncludeTransport
  $devices = $health.transport.devices
  $data = [ordered]@{
    abi = $health.abi
    release = $health.release
    bootCompleted = $health.bootCompleted
    devices = $devices
    emulatorProcesses = $health.transport.emulatorProcesses
    transport = $health.transport
    state = Read-RuntimeState
  }
  if ($health.ok) {
    $hosts = Get-HostsOk -Serial $script:KssmaRuntimeConfig.PrimarySerial
    Add-Stage $ctx "status-hosts" $hosts.stage
    $mount = Get-MountOk -Serial $script:KssmaRuntimeConfig.PrimarySerial
    Add-Stage $ctx "status-mount" $mount.stage
    $package = Ensure-PackageInstalled -Context $ctx
    $data.hostsOk = $hosts.ok
    $data.mountOk = $mount.ok
    $data.package = $package
  }
  Complete-RuntimeResult -Context $ctx -Ok $health.ok -FailureClass $(if ($health.ok) { "" } else { $health.transport.class }) -RestartAllowed:$health.transport.restartAllowed -RecommendedCommand $(if ($health.ok) { "" } else { "repair-adb" }) -Data $data
}

function New-FakeHealth {
  param(
    [string]$Serial,
    [bool]$Ok = $false,
    [bool]$TransportOk = $false,
    [string]$Abi = "",
    [string]$Release = "",
    [string]$Boot = ""
  )
  [ordered]@{
    serial = $Serial
    connect = ""
    abi = $Abi
    release = $Release
    bootCompleted = $Boot
    transportOk = $TransportOk
    ok = $Ok
  }
}

function New-FakeDevices {
  param([string[]]$Rows)
  $primary = Get-AdbRowState -Rows $Rows -Serial "127.0.0.1:5583"
  $legacy = Get-AdbRowState -Rows $Rows -Serial "emulator-5582"
  [ordered]@{
    rows = $Rows
    primary = $primary
    legacy = $legacy
    otherDevices = @($Rows | Where-Object {
        $_ -notmatch "^127\.0\.0\.1:5583\s+" -and $_ -notmatch "^emulator-5582\s+"
      })
    legacyOffline = $legacy.state -eq "offline"
    primaryDevice = $primary.state -eq "device"
  }
}

function Invoke-TransportSelfCheck {
  $ctx = New-RuntimeContext "self-check-transport"
  $ports = [ordered]@{
    console5582 = [ordered]@{ port = 5582; open = $true; error = "" }
    adb5583 = [ordered]@{ port = 5583; open = $false; error = "actively refused" }
  }
  $emulators = @([ordered]@{ processId = 1; name = "emulator-arm.exe"; commandLine = "emulator-arm.exe -avd kssma_arm19 -ports 5582,5583" })
  $cases = @(
    [ordered]@{
      name = "healthy-primary"
      expected = "healthy-arm19"
      primary = New-FakeHealth -Serial "127.0.0.1:5583" -Ok $true -TransportOk $true -Abi "armeabi-v7a" -Release "4.4.2" -Boot "1"
      legacy = New-FakeHealth -Serial "emulator-5582"
      devices = New-FakeDevices -Rows @("127.0.0.1:5583 device product:sdk model:sdk device:generic")
      emulators = $emulators
    },
    [ordered]@{
      name = "healthy-legacy"
      expected = "healthy-arm19"
      primary = New-FakeHealth -Serial "127.0.0.1:5583"
      legacy = New-FakeHealth -Serial "emulator-5582" -Ok $true -TransportOk $true -Abi "armeabi-v7a" -Release "4.4.2" -Boot "1"
      devices = New-FakeDevices -Rows @("emulator-5582 device product:sdk model:sdk device:generic")
      emulators = $emulators
    },
    [ordered]@{
      name = "detached-arm19"
      expected = "detached-arm19"
      primary = New-FakeHealth -Serial "127.0.0.1:5583"
      legacy = New-FakeHealth -Serial "emulator-5582"
      devices = New-FakeDevices -Rows @("emulator-5554 device product:MI model:MI device:MI")
      emulators = $emulators
    },
    [ordered]@{
      name = "wrong-runtime-only"
      expected = "wrong-runtime-only"
      primary = New-FakeHealth -Serial "127.0.0.1:5583"
      legacy = New-FakeHealth -Serial "emulator-5582"
      devices = New-FakeDevices -Rows @("emulator-5554 device product:MI model:MI device:MI")
      emulators = @()
    },
    [ordered]@{
      name = "adb-offline"
      expected = "adb-offline"
      primary = New-FakeHealth -Serial "127.0.0.1:5583"
      legacy = New-FakeHealth -Serial "emulator-5582"
      devices = New-FakeDevices -Rows @("emulator-5582 offline")
      emulators = $emulators
    },
    [ordered]@{
      name = "wrong-runtime"
      expected = "wrong-runtime"
      primary = New-FakeHealth -Serial "127.0.0.1:5583" -TransportOk $true -Abi "x86_64" -Release "12" -Boot "1"
      legacy = New-FakeHealth -Serial "emulator-5582"
      devices = New-FakeDevices -Rows @("127.0.0.1:5583 device product:MI model:MI device:MI")
      emulators = $emulators
    }
  )

  $results = @()
  foreach ($case in $cases) {
    $actual = Get-TransportClassification -PrimaryHealth $case.primary -LegacyHealth $case.legacy -Devices $case.devices -EmulatorProcesses $case.emulators -Ports $ports
    $pass = $actual.class -eq $case.expected
    $results += [ordered]@{ name = $case.name; expected = $case.expected; actual = $actual.class; ok = $pass }
  }
  $ok = -not ($results | Where-Object { -not $_.ok })
  Add-Stage $ctx "transport-classifier-cases" ([ordered]@{ ok = $ok; elapsedMs = 0; details = "$(($results | Where-Object { $_.ok }).Count)/$($results.Count) passed" })
  Complete-RuntimeResult -Context $ctx -Ok $ok -FailureClass $(if ($ok) { "" } else { "transport-self-check-failed" }) -Data ([ordered]@{ cases = $results })
}
