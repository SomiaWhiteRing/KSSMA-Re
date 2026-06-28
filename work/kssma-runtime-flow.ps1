function New-FlowContext {
  param(
    [string]$Scenario,
    [string]$Tag
  )

  $stamp = if ($Tag) { $Tag } else { Get-Date -Format "yyyyMMdd-HHmmss" }
  $safeScenario = $Scenario -replace "[^A-Za-z0-9_.-]", "-"
  $artifactDir = Join-Path $PSScriptRoot "kssma-flow-$safeScenario-$stamp"
  $screenshotsDir = Join-Path $artifactDir "screenshots"
  New-Item -ItemType Directory -Force -Path $screenshotsDir | Out-Null

  [ordered]@{
    scenario = $Scenario
    artifactDir = $artifactDir
    screenshotsDir = $screenshotsDir
    eventsJsonl = Join-Path $artifactDir "events.jsonl"
    requestsJsonl = Join-Path $artifactDir "requests.jsonl"
    summaryTxt = Join-Path $artifactDir "summary.txt"
    summaryJson = Join-Path $artifactDir "summary.json"
    serverOut = Join-Path $artifactDir "server.out.log"
    serverErr = Join-Path $artifactDir "server.err.log"
    logcat = Join-Path $artifactDir "logcat.txt"
    activity = Join-Path $artifactDir "activity.txt"
    loginDriver = Join-Path $artifactDir "login-driver.txt"
    startedAt = Get-Date
    serverProcess = $null
    serial = $script:KssmaRuntimeConfig.PrimarySerial
    requestCursor = 0
    normalizedLineCount = 0
    requestEvents = @()
    steps = @()
    warnings = @()
    failureClass = ""
    failureStep = ""
    failureMessage = ""
    lastActivity = ""
    lastUiDumpStatus = "not-run"
  }
}

function Write-FlowJsonLine {
  param(
    [string]$Path,
    $Value
  )

  ($Value | ConvertTo-Json -Depth 20 -Compress) | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Add-FlowEvent {
  param(
    $Context,
    [string]$Type,
    $Data = $null
  )

  $event = [ordered]@{
    ts = (Get-Date).ToString("o")
    type = $Type
  }
  if ($Data) {
    foreach ($key in $Data.Keys) {
      $event[$key] = $Data[$key]
    }
  }
  Write-FlowJsonLine -Path $Context.eventsJsonl -Value $event
}

function Stop-FlowWithFailure {
  param(
    $Context,
    [string]$FailureClass,
    [string]$Step,
    [string]$Message
  )

  $Context.failureClass = $FailureClass
  $Context.failureStep = $Step
  $Context.failureMessage = $Message
  Add-FlowEvent -Context $Context -Type "failure" -Data ([ordered]@{
      failureClass = $FailureClass
      step = $Step
      message = $Message
    })
  $ex = [System.Exception]::new($Message)
  $ex.Data["FlowFailureClass"] = $FailureClass
  $ex.Data["FlowFailureStep"] = $Step
  throw $ex
}

function Get-FlowProperty {
  param(
    $Object,
    [string]$Name
  )

  if ($null -eq $Object) {
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($property) {
    return $property.Value
  }
  return $null
}

function ConvertTo-FlowHashtable {
  param($Object)

  $table = @{}
  if ($null -eq $Object) {
    return $table
  }
  foreach ($property in $Object.PSObject.Properties) {
    $table[$property.Name] = $property.Value
  }
  return $table
}

function Parse-FlowServerLine {
  param(
    [string]$Line,
    [int]$Index
  )

  if ($Line -notmatch "^\[(?<ts>[^\]]+)\]\s+(?<tag>\S+)\s+(?<payload>.*)$") {
    return $null
  }
  $payloadText = $Matches["payload"]
  $payload = $payloadText
  try {
    $payload = $payloadText | ConvertFrom-Json
  } catch {}

  $path = Get-FlowProperty -Object $payload -Name "path"
  $decryptedParams = ConvertTo-FlowHashtable (Get-FlowProperty -Object $payload -Name "decryptedParams")
  $rawParams = ConvertTo-FlowHashtable (Get-FlowProperty -Object $payload -Name "rawParams")

  [ordered]@{
    index = $Index
    ts = $Matches["ts"]
    tag = $Matches["tag"]
    path = ($path -as [string])
    decryptedParams = $decryptedParams
    rawParams = $rawParams
    payload = $payload
    raw = $Line
  }
}

function Sync-FlowServerEvents {
  param($Context)

  if (-not (Test-Path -LiteralPath $Context.serverOut)) {
    return @()
  }
  $lines = @(Get-Content -LiteralPath $Context.serverOut -ErrorAction SilentlyContinue)
  $events = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $event = Parse-FlowServerLine -Line $lines[$i] -Index $i
    if ($event) {
      $events += $event
      if ($i -ge [int]$Context.normalizedLineCount) {
        Write-FlowJsonLine -Path $Context.requestsJsonl -Value $event
      }
    }
  }
  if ($lines.Count -gt [int]$Context.normalizedLineCount) {
    $Context.normalizedLineCount = $lines.Count
  }
  $Context.requestEvents = $events
  return $events
}

function Test-FlowExpectedMap {
  param(
    $Actual,
    [hashtable]$Expected
  )

  foreach ($key in $Expected.Keys) {
    $value = $null
    if ($Actual -is [hashtable]) {
      $value = $Actual[$key]
    } else {
      $value = Get-FlowProperty -Object $Actual -Name $key
    }
    if ("$value" -ne "$($Expected[$key])") {
      return $false
    }
  }
  return $true
}

function Test-FlowServerEventMatch {
  param(
    $Event,
    [string]$Tag,
    [string]$Path,
    [hashtable]$Params = @{},
    [hashtable]$Fields = @{}
  )

  if ($Tag -and $Event.tag -ne $Tag) {
    return $false
  }
  if ($Path -and $Event.path -ne $Path) {
    return $false
  }
  if ($Params.Count -gt 0 -and -not (Test-FlowExpectedMap -Actual $Event.decryptedParams -Expected $Params)) {
    return $false
  }
  if ($Fields.Count -gt 0 -and -not (Test-FlowExpectedMap -Actual $Event.payload -Expected $Fields)) {
    return $false
  }
  return $true
}

function Wait-FlowServerEvent {
  param(
    $Context,
    [string]$Step,
    [string]$Tag,
    [string]$Path,
    [hashtable]$Params = @{},
    [hashtable]$Fields = @{},
    [int]$TimeoutSeconds = 25,
    [string]$NoEventFailureClass = "route-timeout"
  )

  Add-FlowEvent -Context $Context -Type "wait-start" -Data ([ordered]@{
      step = $Step
      tag = $Tag
      path = $Path
      params = $Params
      fields = $Fields
      timeoutSeconds = $TimeoutSeconds
    })
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $startCursor = [int]$Context.requestCursor
  $samePathMismatch = $null
  while ((Get-Date) -lt $deadline) {
    $events = @(Sync-FlowServerEvents -Context $Context)
    $newEvents = @($events | Where-Object { [int]$_.index -ge [int]$Context.requestCursor })
    foreach ($event in $newEvents) {
      if ((-not $Tag -or $event.tag -eq $Tag) -and (-not $Path -or $event.path -eq $Path)) {
        if (Test-FlowServerEventMatch -Event $event -Tag $Tag -Path $Path -Params $Params -Fields $Fields) {
          $Context.requestCursor = [int]$event.index + 1
          Add-FlowEvent -Context $Context -Type "wait-ok" -Data ([ordered]@{
              step = $Step
              index = $event.index
              tag = $event.tag
              path = $event.path
              decryptedParams = $event.decryptedParams
              payload = $event.payload
            })
          return $event
        }
        if (-not $samePathMismatch) {
          $samePathMismatch = $event
        }
      }
    }
    Start-Sleep -Milliseconds 500
  }

  $eventsAfterStart = @($Context.requestEvents | Where-Object { [int]$_.index -ge $startCursor })
  if ($samePathMismatch) {
    Add-FlowEvent -Context $Context -Type "route-param-mismatch-detail" -Data ([ordered]@{
        step = $Step
        path = $samePathMismatch.path
        decryptedParams = $samePathMismatch.decryptedParams
        payload = $samePathMismatch.payload
      })
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step $Step -Message "Saw $Tag $Path, but parameters or response fields did not match."
  }
  $failure = if ($eventsAfterStart.Count -eq 0) { $NoEventFailureClass } else { "route-timeout" }
  Stop-FlowWithFailure -Context $Context -FailureClass $failure -Step $Step -Message "Timed out waiting for $Tag $Path."
}

function Wait-FlowServerQuiet {
  param(
    $Context,
    [string]$Step,
    [int]$QuietSeconds = 3,
    [int]$TimeoutSeconds = 20
  )

  Add-FlowEvent -Context $Context -Type "wait-quiet-start" -Data ([ordered]@{
      step = $Step
      quietSeconds = $QuietSeconds
      timeoutSeconds = $TimeoutSeconds
    })
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $lastCount = @(Sync-FlowServerEvents -Context $Context).Count
  $quietSince = Get-Date
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    $count = @(Sync-FlowServerEvents -Context $Context).Count
    if ($count -ne $lastCount) {
      $lastCount = $count
      $quietSince = Get-Date
      continue
    }
    if (((Get-Date) - $quietSince).TotalSeconds -ge $QuietSeconds) {
      Add-FlowEvent -Context $Context -Type "wait-quiet-ok" -Data ([ordered]@{
          step = $Step
          requestCount = $count
        })
      return
    }
  }
  Add-FlowEvent -Context $Context -Type "wait-quiet-timeout" -Data ([ordered]@{
      step = $Step
      requestCount = $lastCount
    })
}

function Get-FlowCurrentActivity {
  param([string]$Serial)

  $stage = Invoke-Adb -Arguments @("-s", $Serial, "shell", "dumpsys", "activity", "activities") -TimeoutSeconds 10 -AllowFailure
  $line = (Get-OutputLines $stage.stdout | Where-Object {
      $_ -match "mFocusedActivity|mResumedActivity|mCurrentFocus"
    } | Select-Object -First 1)
  if (-not $line) {
    $line = (Get-OutputLines $stage.stdout | Where-Object { $_ -match "com\.test\.|Launcher" } | Select-Object -First 1)
  }
  return (($line -as [string]).Trim())
}

function Get-FlowUiDump {
  param(
    $Context,
    [string]$Serial,
    [string]$Name
  )

  $localPath = Join-Path $Context.artifactDir "$Name-ui.xml"
  $Context.lastUiDumpStatus = "dumping"
  Invoke-Adb -Arguments @("-s", $Serial, "shell", "uiautomator", "dump", "/data/local/tmp/kssma-flow-window.xml") -TimeoutSeconds 20 -AllowFailure | Out-Null
  Invoke-Adb -Arguments @("-s", $Serial, "pull", "/data/local/tmp/kssma-flow-window.xml", $localPath) -TimeoutSeconds 20 -AllowFailure | Out-Null
  if (-not (Test-Path -LiteralPath $localPath)) {
    $Context.lastUiDumpStatus = "missing"
    return $null
  }
  try {
    $Context.lastUiDumpStatus = "ok"
    return [xml](Get-Content -Raw -LiteralPath $localPath)
  } catch {
    $Context.lastUiDumpStatus = "parse-failed"
    return $null
  }
}

function Find-FlowUiNode {
  param(
    [xml]$Ui,
    [string]$ResourceId,
    [string]$Text
  )

  if ($null -eq $Ui) {
    return $null
  }
  if ($ResourceId) {
    $node = $Ui.SelectSingleNode("//*[@resource-id='$ResourceId']")
    if ($node) {
      return $node
    }
  }
  if ($Text) {
    return $Ui.SelectSingleNode("//*[@text='$Text']")
  }
  return $null
}

function Test-FlowCrashDialog {
  param(
    $Context,
    [string]$Name = "crash"
  )

  $ui = Get-FlowUiDump -Context $Context -Serial $Context.serial -Name $Name
  if ($null -eq $ui) {
    return $false
  }
  $message = $ui.SelectSingleNode("//*[@resource-id='android:id/message']")
  if ($null -eq $message) {
    return $false
  }
  $text = $message.GetAttribute("text")
  return $text -match "has stopped|Unfortunately"
}

function Assert-FlowClientAlive {
  param(
    $Context,
    [string]$Step
  )

  if (Test-FlowCrashDialog -Context $Context -Name "crash-$Step") {
    Stop-FlowWithFailure -Context $Context -FailureClass "client-crash" -Step $Step -Message "Android crash dialog is visible."
  }
}

function Assert-FlowRuntimeReady {
  param(
    $Context,
    [string]$Step
  )

  $boot = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "getprop", "sys.boot_completed") -TimeoutSeconds 5 -AllowFailure
  if (-not $boot.ok -or -not (($boot.stdout -as [string]).Trim())) {
    Add-FlowEvent -Context $Context -Type "runtime-not-ready" -Data ([ordered]@{
        step = $Step
        ok = $boot.ok
        timedOut = $boot.timedOut
        stdout = $boot.stdout
        stderr = $boot.stderr
        failureClass = $boot.failureClass
      })
    Stop-FlowWithFailure -Context $Context -FailureClass "runtime-not-ready" -Step $Step -Message "ADB transport stopped answering during flow."
  }
}

function Test-FlowExitConfirmDialog {
  param(
    $Context,
    [string]$Name = "exit-confirm"
  )

  $ui = Get-FlowUiDump -Context $Context -Serial $Context.serial -Name $Name
  if ($null -eq $ui) {
    return $false
  }
  $message = $ui.SelectSingleNode("//*[@resource-id='android:id/message']")
  $yes = $ui.SelectSingleNode("//*[@resource-id='android:id/button1' and @text='Yes']")
  $no = $ui.SelectSingleNode("//*[@resource-id='android:id/button2' and @text='No']")
  return ($null -ne $message -and $null -ne $yes -and $null -ne $no)
}

function Invoke-FlowCancelExitConfirmIfPresent {
  param($Context)

  $ui = Get-FlowUiDump -Context $Context -Serial $Context.serial -Name "exit-confirm"
  if ($null -eq $ui) {
    return $false
  }
  $no = $ui.SelectSingleNode("//*[@resource-id='android:id/button2' and @text='No']")
  if ($null -eq $no) {
    return $false
  }
  Add-FlowEvent -Context $Context -Type "exit-confirm-cancel" -Data ([ordered]@{ method = "tap-no" })
  Invoke-FlowTapNode -Context $Context -Serial $Context.serial -Name "exit-confirm-no" -Node $no | Out-Null
  Start-Sleep -Seconds 2
  return $true
}

function Invoke-FlowDismissUnexpectedNetworkDialog {
  param(
    $Context,
    [string]$Step
  )

  Sync-FlowServerEvents -Context $Context | Out-Null
  $unexpected = @($Context.requestEvents | Where-Object {
      $_.tag -eq "connect_app_probe" -and $_.path -match "^/connect/app/gacha/"
    })
  if ($unexpected.Count -eq 0) {
    return $false
  }
  $Context.warnings += "Unexpected gacha route appeared before exploration smoke; dismissing likely native network retry dialog."
  Add-FlowEvent -Context $Context -Type "dismiss-network-dialog" -Data ([ordered]@{
      step = $Step
      routeCount = $unexpected.Count
      lastRoute = $unexpected[-1].path
    })
  Invoke-FlowTap -Context $Context -Name "dismiss-network-dialog-touch-screen" -X 640 -Y 650
  Start-Sleep -Seconds 4
  return $true
}

function Get-FlowUiNodeCenter {
  param($Node)

  $bounds = $Node.GetAttribute("bounds")
  if ($bounds -notmatch "^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$") {
    return $null
  }
  [ordered]@{
    x = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
    y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
  }
}

function Invoke-FlowTap {
  param(
    $Context,
    [string]$Name,
    [int]$X,
    [int]$Y
  )

  Add-FlowEvent -Context $Context -Type "tap" -Data ([ordered]@{ name = $Name; x = $X; y = $Y })
  $stage = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "tap", "$X", "$Y") -TimeoutSeconds 10 -AllowFailure
  if (-not $stage.ok) {
    if ($stage.timedOut -or $stage.failureClass -match "adb|transport|offline|device") {
      $probe = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "getprop", "sys.boot_completed") -TimeoutSeconds 5 -AllowFailure
      if ($probe.ok -and (($probe.stdout -as [string]).Trim())) {
        Add-FlowEvent -Context $Context -Type "tap-retry" -Data ([ordered]@{
            name = $Name
            reason = "first tap failed but transport probe recovered"
            firstTimedOut = $stage.timedOut
            firstFailureClass = $stage.failureClass
          })
        Start-Sleep -Seconds 1
        $stage = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "tap", "$X", "$Y") -TimeoutSeconds 10 -AllowFailure
        if ($stage.ok) {
          Start-Sleep -Milliseconds 800
          return
        }
      }
      Add-FlowEvent -Context $Context -Type "tap-runtime-not-ready" -Data ([ordered]@{
          name = $Name
          failureClass = $stage.failureClass
          timedOut = $stage.timedOut
          stdout = $stage.stdout
          stderr = $stage.stderr
        })
      Stop-FlowWithFailure -Context $Context -FailureClass "runtime-not-ready" -Step $Name -Message "ADB tap failed because runtime transport is not ready."
    }
    $Context.warnings += "tap command for $Name returned non-ok; continuing to route wait: $($stage.failureClass) $($stage.stderr) $($stage.stdout)"
    Add-FlowEvent -Context $Context -Type "tap-warning" -Data ([ordered]@{
        name = $Name
        failureClass = $stage.failureClass
        timedOut = $stage.timedOut
        stdout = $stage.stdout
        stderr = $stage.stderr
      })
  }
  Start-Sleep -Milliseconds 800
}

function Invoke-FlowTapNode {
  param(
    $Context,
    [string]$Serial,
    [string]$Name,
    $Node
  )

  $center = Get-FlowUiNodeCenter -Node $Node
  if (-not $center) {
    return $false
  }
  Invoke-FlowTap -Context $Context -Name $Name -X $center.x -Y $center.y
  return $true
}

function Set-FlowUiText {
  param(
    $Context,
    [string]$Serial,
    $Node,
    [string]$Value
  )

  if (-not (Invoke-FlowTapNode -Context $Context -Serial $Serial -Name "focus-text" -Node $Node)) {
    return $false
  }
  Start-Sleep -Milliseconds 300
  Invoke-Adb -Arguments @("-s", $Serial, "shell", "input", "keyevent", "123") -TimeoutSeconds 3 -AllowFailure | Out-Null
  for ($i = 0; $i -lt 24; $i++) {
    Invoke-Adb -Arguments @("-s", $Serial, "shell", "input", "keyevent", "67") -TimeoutSeconds 3 -AllowFailure | Out-Null
  }
  Invoke-Adb -Arguments @("-s", $Serial, "shell", "input", "text", $Value) -TimeoutSeconds 5 -AllowFailure | Out-Null
  return $true
}

function Capture-FlowScreenshot {
  param(
    $Context,
    [string]$Name
  )

  $safeName = $Name -replace "[^A-Za-z0-9_.-]", "-"
  $remote = "/data/local/tmp/kssma-flow-$safeName.png"
  $local = Join-Path $Context.screenshotsDir "$safeName.png"
  Add-FlowEvent -Context $Context -Type "screenshot-start" -Data ([ordered]@{ name = $Name; path = $local })
  Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "screencap", "-p", $remote) -TimeoutSeconds 20 -AllowFailure | Out-Null
  $pull = Invoke-Adb -Arguments @("-s", $Context.serial, "pull", $remote, $local) -TimeoutSeconds 30 -AllowFailure
  Add-FlowEvent -Context $Context -Type "screenshot" -Data ([ordered]@{ name = $Name; path = $local; ok = [bool](Test-Path -LiteralPath $local); adbOk = $pull.ok })
  return $local
}

function Stop-FlowServerProcesses {
  param($Context)

  $helper = Join-Path $PSScriptRoot "kssma-server.ps1"
  if (Test-Path -LiteralPath $helper) {
    Invoke-RuntimeProcess -FilePath "powershell" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $helper, "stop") -TimeoutSeconds 20 -AllowFailure | Out-Null
  }

  $repoFull = [System.IO.Path]::GetFullPath($script:RepoRoot)
  Get-CimInstance Win32_Process |
    Where-Object {
      $_.Name -match "node" -and
      $_.CommandLine -like "*server*bootstrap-server.js*" -and
      $_.CommandLine -like "*$repoFull*"
    } |
    ForEach-Object {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Start-FlowServer {
  param($Context)

  Stop-FlowServerProcesses -Context $Context
  $env:CHECK_INSPECTION_KEY = "rBwj1MIAivVN222b"
  $env:CONNECT_APP_KEY = "rBwj1MIAivVN222b"
  $env:LOGIN_RESPONSE = "sample"
  $env:PORTS = "50005,10001"
  $process = Start-Process -FilePath "node" -ArgumentList @(".\server\bootstrap-server.js") -WorkingDirectory $script:RepoRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $Context.serverOut -RedirectStandardError $Context.serverErr
  $Context.serverProcess = $process
  Set-Content -LiteralPath (Join-Path $PSScriptRoot "kssma-server.pid") -Value ([string]$process.Id) -Encoding ASCII
  Start-Sleep -Seconds 2
  if ($process.HasExited) {
    Stop-FlowWithFailure -Context $Context -FailureClass "server-start-failed" -Step "start-server" -Message "bootstrap server exited early; see $($Context.serverErr)"
  }
  Add-FlowEvent -Context $Context -Type "server-started" -Data ([ordered]@{ pid = $process.Id; stdout = $Context.serverOut; stderr = $Context.serverErr })
}

function Stop-FlowServer {
  param($Context)

  if ($Context.serverProcess) {
    Stop-Process -Id $Context.serverProcess.Id -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $PSScriptRoot "kssma-server.pid") -ErrorAction SilentlyContinue
    Add-FlowEvent -Context $Context -Type "server-stopped" -Data ([ordered]@{ pid = $Context.serverProcess.Id })
  }
}

function Invoke-FlowRuntimeGate {
  param($Context)

  $fast = Invoke-FastHealth
  Add-FlowEvent -Context $Context -Type "runtime-fast-health" -Data ([ordered]@{ ok = $fast.ok; failureClass = $fast.failureClass; data = $fast.data })
  if (-not $fast.ok) {
    $repair = Invoke-RepairAdb
    Add-FlowEvent -Context $Context -Type "runtime-repair-adb" -Data ([ordered]@{ ok = $repair.ok; failureClass = $repair.failureClass; data = $repair.data })
    if (-not $repair.ok) {
      Stop-FlowWithFailure -Context $Context -FailureClass "runtime-not-ready" -Step "repair-adb" -Message "fast-health and repair-adb failed: $($repair.failureClass)"
    }
    $fast = Invoke-FastHealth
    Add-FlowEvent -Context $Context -Type "runtime-fast-health-after-repair" -Data ([ordered]@{ ok = $fast.ok; failureClass = $fast.failureClass; data = $fast.data })
    if (-not $fast.ok) {
      Stop-FlowWithFailure -Context $Context -FailureClass "runtime-not-ready" -Step "fast-health-after-repair" -Message "runtime still unhealthy after repair-adb: $($fast.failureClass)"
    }
  }

  $baseline = Invoke-EnsureBaseline
  Add-FlowEvent -Context $Context -Type "runtime-ensure-baseline" -Data ([ordered]@{ ok = $baseline.ok; failureClass = $baseline.failureClass; data = $baseline.data })
  if (-not $baseline.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "runtime-not-ready" -Step "ensure-baseline" -Message "ensure-baseline failed: $($baseline.failureClass)"
  }

  $native = Invoke-EnsureExplorationBaseline
  Add-FlowEvent -Context $Context -Type "runtime-ensure-exploration-baseline" -Data ([ordered]@{ ok = $native.ok; failureClass = $native.failureClass; data = $native.data })
  if (-not $native.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "native-baseline-mismatch" -Step "ensure-exploration-baseline" -Message "ensure-exploration-baseline failed: $($native.failureClass)"
  }
  $Context.serial = $script:KssmaRuntimeConfig.PrimarySerial
}

function Test-FlowGameActivity {
  param([string]$ActivityLine)
  return $ActivityLine -match "com\.test\.|com\.square_enix\.million_cn"
}

function Test-FlowLauncherActivity {
  param([string]$ActivityLine)
  return $ActivityLine -match "Launcher|launcher"
}

function Invoke-FlowOriginalLogin {
  param(
    $Context,
    [string]$LoginId = "13800138000",
    [string]$Password = "testpass1",
    [int]$TimeoutSeconds = 120
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $lastHeartbeat = (Get-Date).AddSeconds(-30)
  $lastActionAt = (Get-Date).AddSeconds(-30)
  $modeAttempts = 0
  $worldAttempts = 0
  $loginAttempts = 0
  $popupAttempts = 0
  $nativeTitleAttempts = 0
  Add-FlowEvent -Context $Context -Type "login-start" -Data ([ordered]@{ timeoutSeconds = $TimeoutSeconds })

  while ((Get-Date) -lt $deadline) {
    $now = Get-Date
    $activityLine = Get-FlowCurrentActivity -Serial $Context.serial
    $Context.lastActivity = $activityLine
    if (-not $activityLine) {
      Assert-FlowRuntimeReady -Context $Context -Step "login-activity"
    }
    Sync-FlowServerEvents -Context $Context | Out-Null
    $connectAppSeen = [bool](@($Context.requestEvents | Where-Object { $_.tag -eq "connect_app_probe" }).Count)
    $connectWebSeen = [bool](@($Context.requestEvents | Where-Object { $_.tag -eq "connect_web_stub" }).Count)
    if ($connectAppSeen -or $connectWebSeen) {
      Add-FlowEvent -Context $Context -Type "login-request-chain-seen" -Data ([ordered]@{ activity = $activityLine; connectAppSeen = $connectAppSeen; connectWebSeen = $connectWebSeen })
      return
    }
    if ($activityLine -match "com\.test\.RooneyJActivity") {
      if (($now - $lastActionAt).TotalSeconds -ge 6) {
        Add-FlowEvent -Context $Context -Type "login-rooney-title-without-connect-app" -Data ([ordered]@{ activity = $activityLine; attempt = $nativeTitleAttempts + 1 })
        Invoke-FlowTap -Context $Context -Name "login-native-title-touch-screen" -X 640 -Y 650
        $nativeTitleAttempts++
        $lastActionAt = Get-Date
        Start-Sleep -Seconds 5
        continue
      }
    }

    $ui = Get-FlowUiDump -Context $Context -Serial $Context.serial -Name "login"
    $now = Get-Date
    if (($now - $lastHeartbeat).TotalSeconds -ge 5) {
      Add-FlowEvent -Context $Context -Type "login-heartbeat" -Data ([ordered]@{
          activity = $activityLine
          uiDump = $Context.lastUiDumpStatus
          modeAttempts = $modeAttempts
          worldAttempts = $worldAttempts
          loginAttempts = $loginAttempts
          popupAttempts = $popupAttempts
          nativeTitleAttempts = $nativeTitleAttempts
        })
      $lastHeartbeat = $now
    }

    if ((Test-FlowLauncherActivity $activityLine) -and -not (Test-FlowGameActivity $activityLine) -and (($now - $lastActionAt).TotalSeconds -ge 10)) {
      Stop-FlowWithFailure -Context $Context -FailureClass "login-failed" -Step "login-launcher" -Message "launch did not keep focus on the game; activity=$activityLine"
    }

    if ($activityLine -match "ModeSelectActivity" -and (($now - $lastActionAt).TotalSeconds -ge 4)) {
      $modeContinue = Find-FlowUiNode -Ui $ui -ResourceId "com.square_enix.million_cn:id/enter_modeselect_btn_continue"
      if ($modeContinue) {
        Invoke-FlowTapNode -Context $Context -Serial $Context.serial -Name "login-mode-continue" -Node $modeContinue | Out-Null
      } else {
        # ponytail: retry the known-good saved-login entry first; fresh account
        # setup can become a separate branch if a clean install needs it.
        Invoke-FlowTap -Context $Context -Name "login-mode-continue-fallback" -X 640 -Y 280
      }
      $modeAttempts++
      $lastActionAt = Get-Date
      Start-Sleep -Seconds 5
      continue
    }

    $world = Find-FlowUiNode -Ui $ui -ResourceId "" -Text "Local Dev World"
    if (-not $world) {
      $world = Find-FlowUiNode -Ui $ui -ResourceId "com.square_enix.million_cn:id/enter_worldselect_lst_worlds"
    }
    if ($world -and (($now - $lastActionAt).TotalSeconds -ge 4)) {
      # ponytail: the local bootstrap exposes one world; multi-world matching can wait.
      Invoke-FlowTapNode -Context $Context -Serial $Context.serial -Name "login-world-local" -Node $world | Out-Null
      $worldAttempts++
      $lastActionAt = Get-Date
      Start-Sleep -Seconds 5
      continue
    }

    $phone = Find-FlowUiNode -Ui $ui -ResourceId "com.square_enix.million_cn:id/enter_login_edt_phonenumber"
    $pass = Find-FlowUiNode -Ui $ui -ResourceId "com.square_enix.million_cn:id/enter_login_edt_password"
    $loginButton = Find-FlowUiNode -Ui $ui -ResourceId "com.square_enix.million_cn:id/enter_login_btn_login"
    if ($phone -and $pass -and $loginButton -and (($now - $lastActionAt).TotalSeconds -ge 4)) {
      Set-FlowUiText -Context $Context -Serial $Context.serial -Node $phone -Value $LoginId | Out-Null
      Set-FlowUiText -Context $Context -Serial $Context.serial -Node $pass -Value $Password | Out-Null
      Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "keyevent", "4") -TimeoutSeconds 10 -AllowFailure | Out-Null
      Start-Sleep -Milliseconds 500
      Invoke-FlowTapNode -Context $Context -Serial $Context.serial -Name "login-submit" -Node $loginButton | Out-Null
      $loginAttempts++
      $lastActionAt = Get-Date
      Start-Sleep -Seconds 4
      continue
    }

    $popupOk = Find-FlowUiNode -Ui $ui -ResourceId "com.square_enix.million_cn:id/button_ok"
    if ($popupOk -and (($now - $lastActionAt).TotalSeconds -ge 4)) {
      Invoke-FlowTapNode -Context $Context -Serial $Context.serial -Name "login-popup-ok" -Node $popupOk | Out-Null
      $popupAttempts++
      $lastActionAt = Get-Date
      Start-Sleep -Seconds 8
      continue
    }

    Start-Sleep -Seconds 2
  }

  Stop-FlowWithFailure -Context $Context -FailureClass "login-failed" -Step "drive-login" -Message "login driver timed out"
}

function Test-FlowNoticeWebView {
  param($Context)

  $ui = Get-FlowUiDump -Context $Context -Serial $Context.serial -Name "notice"
  return Test-FlowUiHasWebView -Ui $ui
}

function Test-FlowUiHasWebView {
  param([xml]$Ui)

  if ($null -eq $ui) {
    return $false
  }
  return $null -ne $ui.SelectSingleNode("//*[contains(@class,'WebView')]")
}

function Invoke-FlowDismissNoticeIfPresent {
  param($Context)

  Sync-FlowServerEvents -Context $Context | Out-Null
  $connectWebSeen = [bool](@($Context.requestEvents | Where-Object { $_.tag -eq "connect_web_stub" -or $_.path -like "/connect/web/*" }).Count)
  $webViewVisible = Test-FlowNoticeWebView -Context $Context
  if (-not $connectWebSeen -and -not $webViewVisible) {
    Add-FlowEvent -Context $Context -Type "notice-skip" -Data ([ordered]@{ connectWebSeen = $connectWebSeen; webViewVisible = $webViewVisible })
    return $false
  }

  Capture-FlowScreenshot -Context $Context -Name "notice-before" | Out-Null
  $webViewVisible = Test-FlowNoticeWebView -Context $Context
  if (-not $webViewVisible) {
    Add-FlowEvent -Context $Context -Type "notice-skip-after-screenshot" -Data ([ordered]@{
        connectWebSeen = $connectWebSeen
        webViewVisible = $webViewVisible
      })
    return $false
  }
  Add-FlowEvent -Context $Context -Type "notice-dismiss" -Data ([ordered]@{ connectWebSeen = $connectWebSeen; webViewVisible = $webViewVisible; method = "back-first" })
  foreach ($tap in @(
      # ponytail: native WebView notices are full-screen and Back is the least
      # layout-dependent close action. If a future notice ignores Back, add a
      # screenshot-proven close coordinate for that notice shape only.
      @{ name = "notice-back"; keyevent = "4" },
      @{ name = "notice-top-right"; x = 1080; y = 90 },
      @{ name = "notice-center"; x = 640; y = 360 },
      @{ name = "notice-bottom-confirm"; x = 640; y = 650 }
    )) {
    if ($tap.keyevent) {
      Add-FlowEvent -Context $Context -Type "keyevent" -Data ([ordered]@{ name = $tap.name; keyevent = $tap.keyevent })
      Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "keyevent", "$($tap.keyevent)") -TimeoutSeconds 10 -AllowFailure | Out-Null
    } else {
      Invoke-FlowTap -Context $Context -Name $tap.name -X $tap.x -Y $tap.y
    }
    Start-Sleep -Seconds 4
    Invoke-FlowCancelExitConfirmIfPresent -Context $Context | Out-Null
    Sync-FlowServerEvents -Context $Context | Out-Null
    if (@($Context.requestEvents | Where-Object { $_.tag -eq "connect_app_probe" -and ($_.path -eq "/connect/app/mainmenu/update" -or $_.path -eq "/connect/app/mainmenu") }).Count -gt 0) {
      return $true
    }
    if (-not (Test-FlowNoticeWebView -Context $Context)) {
      Add-FlowEvent -Context $Context -Type "notice-dismissed" -Data ([ordered]@{ method = $tap.name })
      return $true
    }
  }
  return $false
}

function Wait-FlowMainMenuReady {
  param($Context)

  $deadline = (Get-Date).AddSeconds(60)
  $dismissTried = $false
  while ((Get-Date) -lt $deadline) {
    Sync-FlowServerEvents -Context $Context | Out-Null
    $mainmenu = @($Context.requestEvents | Where-Object { $_.tag -eq "connect_app_probe" -and ($_.path -eq "/connect/app/mainmenu/update" -or $_.path -eq "/connect/app/mainmenu") } | Select-Object -First 1)
    if ($mainmenu.Count -gt 0) {
      Add-FlowEvent -Context $Context -Type "mainmenu-ready" -Data ([ordered]@{ path = $mainmenu[0].path })
      return
    }
    $loginSeed = @($Context.requestEvents | Where-Object { $_.tag -eq "connect_app_response" -and $_.path -eq "/connect/app/login" } | Select-Object -First 1)
    $connectWeb = @($Context.requestEvents | Where-Object { $_.tag -eq "connect_web_stub" } | Select-Object -First 1)
    if ($loginSeed.Count -gt 0 -or $connectWeb.Count -gt 0) {
      if (Test-FlowExitConfirmDialog -Context $Context -Name "mainmenu-exit-confirm") {
        Invoke-FlowCancelExitConfirmIfPresent -Context $Context | Out-Null
      }
      if ((Test-FlowNoticeWebView -Context $Context) -and -not $dismissTried) {
        Invoke-FlowDismissNoticeIfPresent -Context $Context
        $dismissTried = $true
        continue
      }
      if (-not (Test-FlowNoticeWebView -Context $Context)) {
        Add-FlowEvent -Context $Context -Type "mainmenu-ready" -Data ([ordered]@{
            path = if ($loginSeed.Count -gt 0) { "/connect/app/login" } else { "/connect/web/" }
            source = if ($loginSeed.Count -gt 0) { (Get-FlowProperty -Object $loginSeed[0].payload -Name "source") } else { "connect-web-stub" }
          })
        return
      }
    }
    if (-not $dismissTried) {
      $connectWebSeen = [bool](@($Context.requestEvents | Where-Object { $_.tag -eq "connect_web_stub" }).Count)
      if ($connectWebSeen -or (Test-FlowNoticeWebView -Context $Context)) {
        Invoke-FlowDismissNoticeIfPresent -Context $Context
        $dismissTried = $true
      }
    }
    Start-Sleep -Seconds 1
  }
  Stop-FlowWithFailure -Context $Context -FailureClass "login-failed" -Step "mainmenu-ready" -Message "mainmenu route was not observed after login"
}

function Invoke-FlowLaunchAndLogin {
  param($Context)

  Add-FlowEvent -Context $Context -Type "clear-logcat" -Data ([ordered]@{})
  Invoke-Adb -Arguments @("-s", $Context.serial, "logcat", "-c") -TimeoutSeconds 10 -AllowFailure | Out-Null
  $launch = Invoke-LaunchGame
  Add-FlowEvent -Context $Context -Type "launch-game" -Data ([ordered]@{ ok = $launch.ok; failureClass = $launch.failureClass; data = $launch.data })
  if (-not $launch.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "login-failed" -Step "launch-game" -Message "launch failed: $($launch.failureClass)"
  }

  $enteredGame = $false
  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $deadline) {
    $activityLine = Get-FlowCurrentActivity -Serial $Context.serial
    $Context.lastActivity = $activityLine
    Add-FlowEvent -Context $Context -Type "post-launch-activity" -Data ([ordered]@{ activity = $activityLine })
    if (Test-FlowGameActivity $activityLine) {
      $enteredGame = $true
      break
    }
    Start-Sleep -Seconds 2
  }
  if (-not $enteredGame) {
    Stop-FlowWithFailure -Context $Context -FailureClass "login-failed" -Step "post-launch-activity" -Message "game activity did not receive focus"
  }

  Invoke-FlowOriginalLogin -Context $Context
  Wait-FlowMainMenuReady -Context $Context
  Start-Sleep -Seconds 4
  Assert-FlowClientAlive -Context $Context -Step "mainmenu-ready"
  Capture-FlowScreenshot -Context $Context -Name "mainmenu" | Out-Null
}

function Invoke-FlowTapThenWaitProbe {
  param(
    $Context,
    [string]$Name,
    [int]$X,
    [int]$Y,
    [string]$Path,
    [hashtable]$Params = @{},
    [int]$TimeoutSeconds = 25
  )

  Assert-FlowClientAlive -Context $Context -Step "$Name-before-tap"
  Invoke-FlowTap -Context $Context -Name $Name -X $X -Y $Y
  return Wait-FlowServerEvent -Context $Context -Step $Name -Tag "connect_app_probe" -Path $Path -Params $Params -TimeoutSeconds $TimeoutSeconds -NoEventFailureClass "tap-no-effect"
}

function Invoke-FlowExplorationSmoke {
  param($Context)

  $coords = @{
    mainmenuExplore = @{ x = 1090; y = 250 }
    areaRow0 = @{ x = 760; y = 260 }
    areaRow1Select = @{ x = 650; y = 395 }
    floorTopRow = @{ x = 760; y = 260 }
    explorationReturn = @{ x = 1090; y = 585 }
  }

  try {
    Invoke-FlowTapThenWaitProbe -Context $Context -Name "open-exploration" -X $coords.mainmenuExplore.x -Y $coords.mainmenuExplore.y -Path "/connect/app/exploration/area" -TimeoutSeconds 25 | Out-Null
  } catch {
    if ($_.Exception.Data["FlowFailureStep"] -ne "open-exploration" -or -not (Invoke-FlowDismissUnexpectedNetworkDialog -Context $Context -Step "open-exploration")) {
      throw
    }
    $Context.failureClass = ""
    $Context.failureStep = ""
    $Context.failureMessage = ""
    Add-FlowEvent -Context $Context -Type "retry-step" -Data ([ordered]@{ step = "open-exploration" })
    Invoke-FlowTapThenWaitProbe -Context $Context -Name "open-exploration-retry" -X $coords.mainmenuExplore.x -Y $coords.mainmenuExplore.y -Path "/connect/app/exploration/area" -TimeoutSeconds 25 | Out-Null
  }
  Wait-FlowServerEvent -Context $Context -Step "open-exploration-response" -Tag "connect_app_response" -Path "/connect/app/exploration/area" -Fields @{ areaCount = 6 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "area-list" | Out-Null

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "tap-area-0" -X $coords.areaRow0.x -Y $coords.areaRow0.y -Path "/connect/app/exploration/floor" -Params @{ area_id = "0" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "tap-area-0-response" -Tag "connect_app_response" -Path "/connect/app/exploration/floor" -Fields @{ regionId = 0 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "area0-floor-list" | Out-Null

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "tap-area-0-floor" -X $coords.floorTopRow.x -Y $coords.floorTopRow.y -Path "/connect/app/exploration/get_floor" -Params @{ area_id = "0" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "tap-area-0-floor-response" -Tag "connect_app_response" -Path "/connect/app/exploration/get_floor" -Fields @{ regionId = 0; bg = "adv_bg14" } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 5
  Capture-FlowScreenshot -Context $Context -Name "area0-main" | Out-Null

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "return-to-area-list" -X $coords.explorationReturn.x -Y $coords.explorationReturn.y -Path "/connect/app/exploration/area" -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "return-to-area-list-response" -Tag "connect_app_response" -Path "/connect/app/exploration/area" -Fields @{ areaCount = 6 } -TimeoutSeconds 10 | Out-Null
  Wait-FlowServerQuiet -Context $Context -Step "return-to-area-list-settle" -QuietSeconds 4 -TimeoutSeconds 20
  Start-Sleep -Seconds 4
  Capture-FlowScreenshot -Context $Context -Name "area-list-after-return" | Out-Null

  Invoke-FlowTap -Context $Context -Name "select-area-1" -X $coords.areaRow1Select.x -Y $coords.areaRow1Select.y
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "area1-selected" | Out-Null

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "tap-area-1" -X $coords.areaRow0.x -Y $coords.areaRow0.y -Path "/connect/app/exploration/floor" -Params @{ area_id = "1" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "tap-area-1-response" -Tag "connect_app_response" -Path "/connect/app/exploration/floor" -Fields @{ regionId = 1 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "area1-floor-list" | Out-Null

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "tap-area-1-floor" -X $coords.floorTopRow.x -Y $coords.floorTopRow.y -Path "/connect/app/exploration/get_floor" -Params @{ area_id = "1" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "tap-area-1-floor-response" -Tag "connect_app_response" -Path "/connect/app/exploration/get_floor" -Fields @{ regionId = 1; bg = "adv_bg11" } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 5
  Capture-FlowScreenshot -Context $Context -Name "area1-main" | Out-Null
}

function Collect-FlowArtifacts {
  param($Context)

  try {
    Sync-FlowServerEvents -Context $Context | Out-Null
    $activity = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "dumpsys", "activity", "activities") -TimeoutSeconds 15 -AllowFailure
    $activity.stdout | Set-Content -LiteralPath $Context.activity -Encoding UTF8
    $logcat = Invoke-Adb -Arguments @("-s", $Context.serial, "logcat", "-d", "-v", "time") -TimeoutSeconds 30 -AllowFailure
    $logcat.stdout | Set-Content -LiteralPath $Context.logcat -Encoding UTF8
  } catch {
    $Context.warnings += "artifact collection failed: $($_.Exception.Message)"
  }
}

function Get-FlowRouteSequence {
  param($Context)

  @($Context.requestEvents |
    Where-Object { $_.tag -eq "connect_app_probe" -and $_.path } |
    ForEach-Object {
      [ordered]@{
        path = $_.path
        decryptedParams = $_.decryptedParams
      }
    })
}

function Complete-FlowResult {
  param(
    $Context,
    [bool]$Ok,
    [string]$FailureClass = "",
    [string]$FailureStep = "",
    [string]$FailureMessage = ""
  )

  Collect-FlowArtifacts -Context $Context
  $elapsed = [int]((Get-Date) - $Context.startedAt).TotalMilliseconds
  $routeSequence = Get-FlowRouteSequence -Context $Context
  $fatal = $false
  if (Test-Path -LiteralPath $Context.logcat) {
    $fatal = [bool](Select-String -LiteralPath $Context.logcat -Pattern "Fatal signal|SIGSEGV" -Quiet -ErrorAction SilentlyContinue)
  }
  $contentsMiss = @($Context.requestEvents | Where-Object { $_.tag -eq "contents_miss" })
  if ($Ok -and $fatal) {
    $Ok = $false
    $FailureClass = "client-crash"
    $FailureStep = "final-logcat"
    $FailureMessage = "fatal native crash was present in logcat"
  }
  if ($Ok -and $contentsMiss.Count -gt 0) {
    $Context.warnings += "server logged $($contentsMiss.Count) contents_miss events"
  }
  if (-not $Ok) {
    try {
      Capture-FlowScreenshot -Context $Context -Name "failure" | Out-Null
    } catch {
      $Context.warnings += "failure screenshot failed: $($_.Exception.Message)"
    }
  }

  $artifacts = [ordered]@{
    dir = $Context.artifactDir
    events = $Context.eventsJsonl
    requests = $Context.requestsJsonl
    summary = $Context.summaryTxt
    summaryJson = $Context.summaryJson
    serverOut = $Context.serverOut
    serverErr = $Context.serverErr
    logcat = $Context.logcat
    activity = $Context.activity
    screenshots = $Context.screenshotsDir
  }
  $summary = [ordered]@{
    status = if ($Ok) { "pass" } else { "fail" }
    scenario = $Context.scenario
    elapsedMs = $elapsed
    failureClass = $FailureClass
    failureStep = $FailureStep
    failureMessage = $FailureMessage
    serial = $Context.serial
    warnings = $Context.warnings
    routeSequence = $routeSequence
    artifacts = $artifacts
  }
  $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Context.summaryJson -Encoding UTF8

  $lines = @(
    "status=$($summary.status)",
    "scenario=$($Context.scenario)",
    "elapsed_ms=$elapsed",
    "failure_class=$FailureClass",
    "failure_step=$FailureStep",
    "failure_message=$FailureMessage",
    "artifact_dir=$($Context.artifactDir)",
    "requests=$($Context.requestsJsonl)",
    "logcat=$($Context.logcat)",
    "activity=$($Context.activity)",
    "screenshots=$($Context.screenshotsDir)",
    "",
    "route_sequence:"
  )
  foreach ($route in $routeSequence) {
    $lines += "  $($route.path) $($route.decryptedParams | ConvertTo-Json -Compress)"
  }
  if ($Context.warnings.Count -gt 0) {
    $lines += ""
    $lines += "warnings:"
    foreach ($warning in $Context.warnings) {
      $lines += "  $warning"
    }
  }
  $lines | Set-Content -LiteralPath $Context.summaryTxt -Encoding UTF8

  [ordered]@{
    ok = $Ok
    command = "flow"
    serial = $Context.serial
    elapsedMs = $elapsed
    failureClass = if ($Ok) { "" } else { $FailureClass }
    restartAllowed = $false
    recommendedCommand = if ($Ok) { "" } else { "Read $($Context.summaryTxt), then inspect the failing step in events.jsonl before changing server/native code." }
    stages = @()
    warnings = $Context.warnings
    data = [ordered]@{
      scenario = $Context.scenario
      artifacts = $artifacts
      routeSequence = $routeSequence
      failureStep = $FailureStep
      failureMessage = $FailureMessage
    }
  }
}

function Invoke-FlowSelfCheck {
  param(
    [string]$Scenario,
    [string]$Tag
  )

  $ctx = New-FlowContext -Scenario $Scenario -Tag $Tag
  try {
    @(
      '[2026-01-01T00:00:00.000Z] connect_app_probe {"path":"/connect/app/exploration/floor","decryptedParams":{"area_id":"0"}}',
      '[2026-01-01T00:00:00.100Z] connect_app_response {"path":"/connect/app/exploration/floor","regionId":0}',
      '[2026-01-01T00:00:01.000Z] connect_app_probe {"path":"/connect/app/exploration/get_floor","decryptedParams":{"area_id":"0","floor_id":"7","check":"1"}}',
      '[2026-01-01T00:00:01.100Z] connect_app_response {"path":"/connect/app/exploration/get_floor","regionId":0,"floorId":7,"bg":"adv_bg14"}'
    ) | Set-Content -LiteralPath $ctx.serverOut -Encoding UTF8
    Wait-FlowServerEvent -Context $ctx -Step "self-floor" -Tag "connect_app_probe" -Path "/connect/app/exploration/floor" -Params @{ area_id = "0" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-floor-response" -Tag "connect_app_response" -Path "/connect/app/exploration/floor" -Fields @{ regionId = 0 } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-get-floor" -Tag "connect_app_probe" -Path "/connect/app/exploration/get_floor" -Params @{ area_id = "0"; check = "1" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-get-floor-response" -Tag "connect_app_response" -Path "/connect/app/exploration/get_floor" -Fields @{ bg = "adv_bg14"; floorId = 7 } -TimeoutSeconds 2 | Out-Null
    $plainUi = [xml]"<?xml version='1.0'?><hierarchy><node class='android.view.View' /></hierarchy>"
    $webUi = [xml]"<?xml version='1.0'?><hierarchy><node class='android.webkit.WebView' /></hierarchy>"
    if (Test-FlowUiHasWebView -Ui $plainUi) {
      throw "plain native view was misclassified as a notice WebView"
    }
    if (-not (Test-FlowUiHasWebView -Ui $webUi)) {
      throw "WebView notice classifier failed"
    }
    $elapsed = [int]((Get-Date) - $ctx.startedAt).TotalMilliseconds
    $summary = [ordered]@{
      status = "pass"
      scenario = $Scenario
      elapsedMs = $elapsed
      failureClass = ""
      failureStep = ""
      failureMessage = ""
      serial = ""
      warnings = @()
      routeSequence = Get-FlowRouteSequence -Context $ctx
      artifacts = [ordered]@{
        dir = $ctx.artifactDir
        events = $ctx.eventsJsonl
        requests = $ctx.requestsJsonl
        summary = $ctx.summaryTxt
        summaryJson = $ctx.summaryJson
        serverOut = $ctx.serverOut
      }
    }
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ctx.summaryJson -Encoding UTF8
    @(
      "status=pass",
      "scenario=$Scenario",
      "elapsed_ms=$elapsed",
      "artifact_dir=$($ctx.artifactDir)",
      "requests=$($ctx.requestsJsonl)"
    ) | Set-Content -LiteralPath $ctx.summaryTxt -Encoding UTF8
    return [ordered]@{
      ok = $true
      command = "flow"
      serial = ""
      elapsedMs = $elapsed
      failureClass = ""
      restartAllowed = $false
      recommendedCommand = ""
      stages = @()
      warnings = @()
      data = [ordered]@{
        scenario = $Scenario
        artifacts = $summary.artifacts
        routeSequence = $summary.routeSequence
      }
    }
  } catch {
    $failureClass = if ($_.Exception.Data["FlowFailureClass"]) { $_.Exception.Data["FlowFailureClass"] } else { "script-error" }
    $failureStep = if ($_.Exception.Data["FlowFailureStep"]) { $_.Exception.Data["FlowFailureStep"] } else { "self-check" }
    $elapsed = [int]((Get-Date) - $ctx.startedAt).TotalMilliseconds
    return [ordered]@{
      ok = $false
      command = "flow"
      serial = ""
      elapsedMs = $elapsed
      failureClass = $failureClass
      restartAllowed = $false
      recommendedCommand = "Inspect $($ctx.eventsJsonl)."
      stages = @()
      warnings = @()
      data = [ordered]@{
        scenario = $Scenario
        artifacts = [ordered]@{ dir = $ctx.artifactDir; events = $ctx.eventsJsonl; requests = $ctx.requestsJsonl }
        failureStep = $failureStep
        failureMessage = $_.Exception.Message
      }
    }
  }
}

function Get-FlowScenarioCatalog {
  @(
    [ordered]@{
      name = "exploration-smoke"
      default = $true
      startsRuntime = $true
      ownsServer = $true
      description = "Login to main menu, run the accepted exploration area/floor/stage smoke path, and collect structured artifacts."
    },
    [ordered]@{
      name = "self-check"
      default = $false
      startsRuntime = $false
      ownsServer = $false
      description = "Exercise flow log parsing, route/field matching, and notice WebView classification without touching ARM19."
    },
    [ordered]@{
      name = "list"
      default = $false
      startsRuntime = $false
      ownsServer = $false
      description = "List supported flow scenarios and the shared stages future gameplay scenarios should reuse."
    }
  )
}

function Invoke-FlowScenarioList {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $scenarios = @(Get-FlowScenarioCatalog)
  $sw.Stop()
  [ordered]@{
    ok = $true
    command = "flow"
    serial = ""
    elapsedMs = [int]$sw.ElapsedMilliseconds
    failureClass = ""
    restartAllowed = $false
    recommendedCommand = ""
    stages = @()
    warnings = @()
    data = [ordered]@{
      defaultScenario = "exploration-smoke"
      scenarios = $scenarios
      reusableStages = @(
        "Start-FlowServer",
        "Invoke-FlowRuntimeGate",
        "Invoke-FlowLaunchAndLogin",
        "Wait-FlowServerEvent",
        "Capture-FlowScreenshot",
        "Complete-FlowResult"
      )
    }
  }
}

function Invoke-Play {
  param([string]$Tag = "")

  $ctx = New-FlowContext -Scenario "play" -Tag $(if ($Tag) { $Tag } else { "human-entry-" + (Get-Date -Format "yyyyMMdd-HHmmss") })
  try {
    Add-FlowEvent -Context $ctx -Type "play-start" -Data ([ordered]@{
        goal = "start local server, prepare ARM19, login to main menu, then leave the game ready for manual play"
      })
    Start-FlowServer -Context $ctx
    Invoke-FlowRuntimeGate -Context $ctx
    Invoke-FlowLaunchAndLogin -Context $ctx
    Capture-FlowScreenshot -Context $ctx -Name "ready-mainmenu" | Out-Null
    Add-FlowEvent -Context $ctx -Type "play-ready" -Data ([ordered]@{
        message = "Game is ready at the main menu. The local bootstrap server remains running for manual play."
      })
    $result = Complete-FlowResult -Context $ctx -Ok $true
    $result.command = "play"
    $result.data["message"] = "Ready: play in the ARM19 emulator. Stop the server later with .\stop.cmd or .\work\kssma-server.ps1 stop."
    return $result
  } catch {
    $failureClass = if ($_.Exception.Data["FlowFailureClass"]) { $_.Exception.Data["FlowFailureClass"] } else { "script-error" }
    $failureStep = if ($_.Exception.Data["FlowFailureStep"]) { $_.Exception.Data["FlowFailureStep"] } else { "play" }
    $result = Complete-FlowResult -Context $ctx -Ok $false -FailureClass $failureClass -FailureStep $failureStep -FailureMessage $_.Exception.Message
    $result.command = "play"
    return $result
  }
}

function Invoke-Flow {
  param(
    [string]$Scenario = "exploration-smoke",
    [string]$Tag = ""
  )

  if ($Scenario -eq "list") {
    return Invoke-FlowScenarioList
  }
  if ($Scenario -eq "self-check") {
    return Invoke-FlowSelfCheck -Scenario $Scenario -Tag $Tag
  }
  if ($Scenario -ne "exploration-smoke") {
    $ctx = New-FlowContext -Scenario $Scenario -Tag $Tag
    $supported = (@(Get-FlowScenarioCatalog).name -join ", ")
    return Complete-FlowResult -Context $ctx -Ok $false -FailureClass "unsupported-scenario" -FailureStep "scenario" -FailureMessage "Unsupported flow scenario: $Scenario. Supported scenarios: $supported"
  }

  $ctx = New-FlowContext -Scenario $Scenario -Tag $Tag
  try {
    Add-FlowEvent -Context $ctx -Type "flow-start" -Data ([ordered]@{ scenario = $Scenario })
    Start-FlowServer -Context $ctx
    Invoke-FlowRuntimeGate -Context $ctx
    Invoke-FlowLaunchAndLogin -Context $ctx
    Invoke-FlowExplorationSmoke -Context $ctx
    Add-FlowEvent -Context $ctx -Type "flow-pass" -Data ([ordered]@{ scenario = $Scenario })
    return Complete-FlowResult -Context $ctx -Ok $true
  } catch {
    $failureClass = if ($_.Exception.Data["FlowFailureClass"]) { $_.Exception.Data["FlowFailureClass"] } else { "script-error" }
    $failureStep = if ($_.Exception.Data["FlowFailureStep"]) { $_.Exception.Data["FlowFailureStep"] } else { "flow" }
    return Complete-FlowResult -Context $ctx -Ok $false -FailureClass $failureClass -FailureStep $failureStep -FailureMessage $_.Exception.Message
  } finally {
    Stop-FlowServer -Context $ctx
  }
}
