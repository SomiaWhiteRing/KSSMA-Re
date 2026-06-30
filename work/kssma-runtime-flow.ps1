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
    playerSave = Join-Path $artifactDir "player-save.json"
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

function Get-FlowObjectPropertyCount {
  param($Object)

  if ($null -eq $Object) {
    return 0
  }
  if ($Object -is [System.Collections.IDictionary]) {
    return $Object.Count
  }
  return @($Object.PSObject.Properties).Count
}

function Read-FlowPlayerSave {
  param(
    $Context,
    [string]$Step
  )

  if (-not (Test-Path -LiteralPath $Context.playerSave)) {
    Stop-FlowWithFailure -Context $Context -FailureClass "player-save-missing" -Step $Step -Message "Artifact player save is missing: $($Context.playerSave)"
  }
  try {
    return [System.IO.File]::ReadAllText($Context.playerSave, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  } catch {
    Stop-FlowWithFailure -Context $Context -FailureClass "player-save-invalid" -Step $Step -Message "Artifact player save is not valid JSON: $($_.Exception.Message)"
  }
}

function Set-FlowApShortagePlayerSave {
  param($Context)

  $defaultSavePath = Join-Path $script:RepoRoot "server\data\player\default-save.json"
  try {
    $save = [System.IO.File]::ReadAllText($defaultSavePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  } catch {
    Stop-FlowWithFailure -Context $Context -FailureClass "player-save-invalid" -Step "ap-shortage-save-setup" -Message "Cannot read default player save: $($_.Exception.Message)"
  }

  $save.resources.ap.current = 0
  $json = $save | ConvertTo-Json -Depth 40
  $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($Context.playerSave, $json + [Environment]::NewLine, $utf8NoBom)
  Add-FlowEvent -Context $Context -Type "player-save-seeded" -Data ([ordered]@{
      scenario = "exploration-ap-shortage-smoke"
      source = $defaultSavePath
      path = $Context.playerSave
      apCurrent = [int]$save.resources.ap.current
      profileExp = [int]$save.profile.exp
      gold = [int]$save.currencies.gold
      movesByFloorCount = Get-FlowObjectPropertyCount -Object $save.exploration.movesByFloor
    })
}

function Set-FlowLevelUpPlayerSave {
  param($Context)

  $defaultSavePath = Join-Path $script:RepoRoot "server\data\player\default-save.json"
  try {
    $save = [System.IO.File]::ReadAllText($defaultSavePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  } catch {
    Stop-FlowWithFailure -Context $Context -FailureClass "player-save-invalid" -Step "levelup-save-setup" -Message "Cannot read default player save: $($_.Exception.Message)"
  }

  $save.profile.level = 17
  $save.profile.exp = 1997
  $save.profile.nextExp = 2000
  $save.profile | Add-Member -NotePropertyName "percentage" -NotePropertyValue 99 -Force
  $save.resources.ap.current = 1
  $save.resources.ap.max = 25
  $save.resources.bc.current = 7
  $save.resources.bc.max = 25
  $save.progression.abilityPoints.unspent = 0
  $save.progression.abilityPoints.fromLevels = 0
  $json = $save | ConvertTo-Json -Depth 40
  $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($Context.playerSave, $json + [Environment]::NewLine, $utf8NoBom)
  Add-FlowEvent -Context $Context -Type "player-save-seeded" -Data ([ordered]@{
      scenario = "exploration-levelup-smoke"
      source = $defaultSavePath
      path = $Context.playerSave
      level = [int]$save.profile.level
      profileExp = [int]$save.profile.exp
      nextExp = [int]$save.profile.nextExp
      apCurrent = [int]$save.resources.ap.current
      bcCurrent = [int]$save.resources.bc.current
    })
}

function Set-FlowMainmenuFactionPlayerSave {
  param($Context)

  $defaultSavePath = Join-Path $script:RepoRoot "server\data\player\default-save.json"
  try {
    $save = [System.IO.File]::ReadAllText($defaultSavePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  } catch {
    Stop-FlowWithFailure -Context $Context -FailureClass "player-save-invalid" -Step "mainmenu-faction-save-setup" -Message "Cannot read default player save: $($_.Exception.Message)"
  }

  $save.profile.faction = "technique"
  $json = $save | ConvertTo-Json -Depth 40
  $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($Context.playerSave, $json + [Environment]::NewLine, $utf8NoBom)
  Add-FlowEvent -Context $Context -Type "player-save-seeded" -Data ([ordered]@{
      scenario = "mainmenu-faction-smoke"
      source = $defaultSavePath
      path = $Context.playerSave
      faction = $save.profile.faction
      expectedCountryId = 2
      expectedFairyCharacterId = 120
      expectedFairyPose = 1
      expectedFairyFace = 8
    })
}

function Assert-FlowLevelUpPlayerSave {
  param($Context)

  $actual = Read-FlowPlayerSave -Context $Context -Step "levelup-save-after"
  $level = [int]$actual.profile.level
  $exp = [int]$actual.profile.exp
  $nextExp = [int]$actual.profile.nextExp
  $ap = [int]$actual.resources.ap.current
  $bc = [int]$actual.resources.bc.current
  $abilityPoints = [int]$actual.progression.abilityPoints.unspent
  $fromLevels = [int]$actual.progression.abilityPoints.fromLevels
  $moves = [int]$actual.exploration.movesByFloor.'0:2'
  if ($level -ne 18 -or $exp -ne 0 -or $nextExp -ne 2100 -or $ap -ne 25 -or $bc -ne 25 -or $abilityPoints -ne 3 -or $fromLevels -ne 3 -or $moves -ne 1) {
    Stop-FlowWithFailure -Context $Context -FailureClass "levelup-save-mismatch" -Step "levelup-save-after" -Message "Level-up save mismatch: level=$level exp=$exp nextExp=$nextExp ap=$ap bc=$bc ability=$abilityPoints fromLevels=$fromLevels moves=$moves."
  }

  Add-FlowEvent -Context $Context -Type "levelup-save-ok" -Data ([ordered]@{
      level = $level
      profileExp = $exp
      nextExp = $nextExp
      apCurrent = $ap
      bcCurrent = $bc
      abilityPoints = $abilityPoints
      movesByFloor0x2 = $moves
    })
}

function Assert-FlowLevelUpPointsettingPlayerSave {
  param($Context)

  $actual = Read-FlowPlayerSave -Context $Context -Step "levelup-pointsetting-save-after"
  $level = [int]$actual.profile.level
  $exp = [int]$actual.profile.exp
  $nextExp = [int]$actual.profile.nextExp
  $apCurrent = [int]$actual.resources.ap.current
  $apMax = [int]$actual.resources.ap.max
  $bcCurrent = [int]$actual.resources.bc.current
  $bcMax = [int]$actual.resources.bc.max
  $abilityPoints = [int]$actual.progression.abilityPoints.unspent
  $fromLevels = [int]$actual.progression.abilityPoints.fromLevels
  $apAllocated = [int]$actual.progression.abilityPoints.apAllocated
  $bcAllocated = [int]$actual.progression.abilityPoints.bcAllocated
  $moves = [int]$actual.exploration.movesByFloor.'0:2'
  if (
    $level -ne 18 -or $exp -ne 0 -or $nextExp -ne 2100 -or
    $apCurrent -ne 28 -or $apMax -ne 28 -or
    $bcCurrent -ne 25 -or $bcMax -ne 25 -or
    $abilityPoints -ne 0 -or $fromLevels -ne 3 -or
    $apAllocated -ne 3 -or $bcAllocated -ne 0 -or $moves -ne 1
  ) {
    Stop-FlowWithFailure -Context $Context -FailureClass "levelup-pointsetting-save-mismatch" -Step "levelup-pointsetting-save-after" -Message "Pointsetting save mismatch: level=$level exp=$exp nextExp=$nextExp ap=$apCurrent/$apMax bc=$bcCurrent/$bcMax ability=$abilityPoints fromLevels=$fromLevels apAllocated=$apAllocated bcAllocated=$bcAllocated moves=$moves."
  }

  Add-FlowEvent -Context $Context -Type "levelup-pointsetting-save-ok" -Data ([ordered]@{
      level = $level
      profileExp = $exp
      nextExp = $nextExp
      apCurrent = $apCurrent
      apMax = $apMax
      bcCurrent = $bcCurrent
      bcMax = $bcMax
      abilityPoints = $abilityPoints
      apAllocated = $apAllocated
      bcAllocated = $bcAllocated
      movesByFloor0x2 = $moves
    })
}

function Assert-FlowApShortagePlayerSaveUnchanged {
  param(
    $Context,
    $InitialSave
  )

  $actual = Read-FlowPlayerSave -Context $Context -Step "ap-shortage-save-after"
  $initialMoves = Get-FlowObjectPropertyCount -Object $InitialSave.exploration.movesByFloor
  $actualMoves = Get-FlowObjectPropertyCount -Object $actual.exploration.movesByFloor
  $initialExp = [int]$InitialSave.profile.exp
  $actualExp = [int]$actual.profile.exp
  $initialGold = [int]$InitialSave.currencies.gold
  $actualGold = [int]$actual.currencies.gold
  $actualAp = [int]$actual.resources.ap.current

  if ($actualAp -ne 0 -or $actualMoves -ne 0 -or $actualMoves -ne $initialMoves -or $actualExp -ne $initialExp -or $actualGold -ne $initialGold) {
    Stop-FlowWithFailure -Context $Context -FailureClass "ap-shortage-save-mutated" -Step "ap-shortage-save-after" -Message "AP shortage explore mutated player save: ap=$actualAp moves=$actualMoves exp=$actualExp gold=$actualGold."
  }

  Add-FlowEvent -Context $Context -Type "ap-shortage-save-ok" -Data ([ordered]@{
      apCurrent = $actualAp
      movesByFloorCount = $actualMoves
      profileExp = $actualExp
      gold = $actualGold
    })
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

function Wait-FlowServerEventOptional {
  param(
    $Context,
    [string]$Step,
    [string]$Tag,
    [string]$Path,
    [hashtable]$Params = @{},
    [hashtable]$Fields = @{},
    [int]$TimeoutSeconds = 8
  )

  Add-FlowEvent -Context $Context -Type "wait-optional-start" -Data ([ordered]@{
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
    $newEvents = @($events | Where-Object { [int]$_.index -ge $startCursor })
    foreach ($event in $newEvents) {
      if ((-not $Tag -or $event.tag -eq $Tag) -and (-not $Path -or $event.path -eq $Path)) {
        if (Test-FlowServerEventMatch -Event $event -Tag $Tag -Path $Path -Params $Params -Fields $Fields) {
          $Context.requestCursor = [int]$event.index + 1
          Add-FlowEvent -Context $Context -Type "wait-optional-ok" -Data ([ordered]@{
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

  if ($samePathMismatch) {
    Add-FlowEvent -Context $Context -Type "wait-optional-mismatch" -Data ([ordered]@{
        step = $Step
        path = $samePathMismatch.path
        decryptedParams = $samePathMismatch.decryptedParams
        payload = $samePathMismatch.payload
      })
    return $samePathMismatch
  }
  Add-FlowEvent -Context $Context -Type "wait-optional-timeout" -Data ([ordered]@{
      step = $Step
      tag = $Tag
      path = $Path
    })
  return $null
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
  $activityLine = Get-FlowCurrentActivity -Serial $Context.serial
  $Context.lastActivity = $activityLine
  if (-not (Test-FlowGameActivity $activityLine)) {
    Stop-FlowWithFailure -Context $Context -FailureClass "client-crash" -Step $Step -Message "Game activity is no longer resumed: $activityLine"
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
  param(
    $Context,
    [hashtable]$ExtraEnvironment = @{}
  )

  Stop-FlowServerProcesses -Context $Context
  $env:CHECK_INSPECTION_KEY = "rBwj1MIAivVN222b"
  $env:CONNECT_APP_KEY = "rBwj1MIAivVN222b"
  $env:LOGIN_RESPONSE = "sample"
  $env:PORTS = "50005,10001"
  $oldEnvironment = @{}
  $environmentKeys = @("KSSMA_PLAYER_SAVE_PATH") + @($ExtraEnvironment.Keys)
  foreach ($key in $environmentKeys) {
    $oldEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
  }
  [Environment]::SetEnvironmentVariable("KSSMA_PLAYER_SAVE_PATH", $Context.playerSave, "Process")
  foreach ($key in $ExtraEnvironment.Keys) {
    [Environment]::SetEnvironmentVariable($key, [string]$ExtraEnvironment[$key], "Process")
  }
  try {
    $process = Start-Process -FilePath "node" -ArgumentList @(".\server\bootstrap-server.js") -WorkingDirectory $script:RepoRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $Context.serverOut -RedirectStandardError $Context.serverErr
  } finally {
    foreach ($key in $environmentKeys) {
      [Environment]::SetEnvironmentVariable($key, $oldEnvironment[$key], "Process")
    }
  }
  $Context.serverProcess = $process
  Set-Content -LiteralPath (Join-Path $PSScriptRoot "kssma-server.pid") -Value ([string]$process.Id) -Encoding ASCII
  Start-Sleep -Seconds 2
  if ($process.HasExited) {
    Stop-FlowWithFailure -Context $Context -FailureClass "server-start-failed" -Step "start-server" -Message "bootstrap server exited early; see $($Context.serverErr)"
  }
  Add-FlowEvent -Context $Context -Type "server-started" -Data ([ordered]@{ pid = $process.Id; stdout = $Context.serverOut; stderr = $Context.serverErr; playerSave = $Context.playerSave; extraEnvironment = $environmentKeys })
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
    if ($repair.data.transport.selectedSerial) {
      $script:KssmaRuntimeConfig.PrimarySerial = $repair.data.transport.selectedSerial
      $Context.serial = $script:KssmaRuntimeConfig.PrimarySerial
      Add-FlowEvent -Context $Context -Type "runtime-selected-serial" -Data ([ordered]@{ serial = $Context.serial; source = "repair-adb" })
    } else {
      $fast = Invoke-FastHealth
      Add-FlowEvent -Context $Context -Type "runtime-fast-health-after-repair" -Data ([ordered]@{ ok = $fast.ok; failureClass = $fast.failureClass; data = $fast.data })
      if (-not $fast.ok) {
        Stop-FlowWithFailure -Context $Context -FailureClass "runtime-not-ready" -Step "fast-health-after-repair" -Message "runtime still unhealthy after repair-adb: $($fast.failureClass)"
      }
    }
  }

  $baseline = Invoke-EnsureBaseline
  Add-FlowEvent -Context $Context -Type "runtime-ensure-baseline" -Data ([ordered]@{ ok = $baseline.ok; failureClass = $baseline.failureClass; data = $baseline.data })
  if (-not $baseline.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "runtime-not-ready" -Step "ensure-baseline" -Message "ensure-baseline failed: $($baseline.failureClass)"
  }

  $native = Invoke-EnsureClientBaseline
  Add-FlowEvent -Context $Context -Type "runtime-ensure-client-baseline" -Data ([ordered]@{ ok = $native.ok; failureClass = $native.failureClass; data = $native.data })
  if (-not $native.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "client-baseline-mismatch" -Step "ensure-client-baseline" -Message "ensure-client-baseline failed: $($native.failureClass)"
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
        Invoke-FlowDismissNoticeIfPresent -Context $Context | Out-Null
        $dismissTried = $true
        $deadline = (Get-Date).AddSeconds(45)
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
        Invoke-FlowDismissNoticeIfPresent -Context $Context | Out-Null
        $dismissTried = $true
        $deadline = (Get-Date).AddSeconds(45)
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

function Invoke-FlowMainmenuFactionSmoke {
  param($Context)

  Sync-FlowServerEvents -Context $Context | Out-Null
  $mainmenuResponse = @(
    $Context.requestEvents |
      Where-Object {
        $_.tag -eq "connect_app_response" -and
        ($_.path -eq "/connect/app/login" -or $_.path -eq "/connect/app/mainmenu/update" -or $_.path -eq "/connect/app/mainmenu")
      } |
      Select-Object -First 1
  )
  if ($mainmenuResponse.Count -eq 0) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-timeout" -Step "mainmenu-faction-response" -Message "No login/mainmenu response was observed."
  }

  $mainmenu = Get-FlowProperty -Object $mainmenuResponse[0].payload -Name "mainmenu"
  $countryId = Get-FlowProperty -Object $mainmenu -Name "countryId"
  $fairyCharacterId = Get-FlowProperty -Object $mainmenu -Name "fairyCharacterId"
  $fairyPose = Get-FlowProperty -Object $mainmenu -Name "fairyPose"
  $fairyFace = Get-FlowProperty -Object $mainmenu -Name "fairyFace"
  if ("$countryId" -ne "2" -or "$fairyCharacterId" -ne "120" -or "$fairyPose" -ne "1" -or "$fairyFace" -ne "8") {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step "mainmenu-faction-response" -Message "Unexpected mainmenu faction mapping: countryId=$countryId fairyCharacterId=$fairyCharacterId fairyPose=$fairyPose fairyFace=$fairyFace."
  }

  Add-FlowEvent -Context $Context -Type "mainmenu-faction-ok" -Data ([ordered]@{
      responsePath = $mainmenuResponse[0].path
      countryId = $countryId
      fairyCharacterId = $fairyCharacterId
      fairyPose = $fairyPose
      fairyFace = $fairyFace
    })
  Capture-FlowScreenshot -Context $Context -Name "mainmenu-technique" | Out-Null
}

function Get-FlowMainmenuRouteCoords {
  @{
    gacha = @{ x = 1090; y = 95 }
    battle = @{ x = 1090; y = 400 }
    compound = @{ x = 1090; y = 555 }
    shop = @{ x = 1090; y = 690 }
    menu = @{ x = 990; y = 675 }
    menuPlayerInfo = @{ x = 525; y = 115 }
    return = @{ x = 1090; y = 585 }
  }
}

function Move-FlowRequestCursorToEnd {
  param($Context)

  $events = @(Sync-FlowServerEvents -Context $Context)
  if ($events.Count -gt 0) {
    $Context.requestCursor = [int]$events[-1].index + 1
  }
}

function Invoke-FlowReturnToMainmenu {
  param(
    $Context,
    [string]$Name
  )

  $coords = Get-FlowMainmenuRouteCoords
  Invoke-FlowTap -Context $Context -Name $Name -X $coords.return.x -Y $coords.return.y
  $mainmenuProbe = Wait-FlowServerEventOptional -Context $Context -Step "$Name-mainmenu-probe" -Tag "connect_app_probe" -Path "/connect/app/mainmenu" -TimeoutSeconds 8
  if ($mainmenuProbe) {
    Wait-FlowServerEvent -Context $Context -Step "$Name-mainmenu-response" -Tag "connect_app_response" -Path "/connect/app/mainmenu" -TimeoutSeconds 10 | Out-Null
  } else {
    Wait-FlowServerQuiet -Context $Context -Step "$Name-local-back-settle" -QuietSeconds 3 -TimeoutSeconds 12
    Move-FlowRequestCursorToEnd -Context $Context
  }
  Start-Sleep -Seconds 3
  Assert-FlowClientAlive -Context $Context -Step "$Name-after-return"
  Capture-FlowScreenshot -Context $Context -Name "$Name-mainmenu" | Out-Null
}

function Invoke-FlowReturnToMenuList {
  param(
    $Context,
    [string]$Name
  )

  $coords = Get-FlowMainmenuRouteCoords
  Invoke-FlowTap -Context $Context -Name $Name -X $coords.return.x -Y $coords.return.y
  Wait-FlowServerEvent -Context $Context -Step "$Name-menu-probe" -Tag "connect_app_probe" -Path "/connect/app/menu/menulist" -TimeoutSeconds 10 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "$Name-menu-response" -Tag "connect_app_response" -Path "/connect/app/menu/menulist" -Fields @{ command = "menu"; nextScene = 20100 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Assert-FlowClientAlive -Context $Context -Step "$Name-after-return"
  Capture-FlowScreenshot -Context $Context -Name "$Name-menu" | Out-Null
}

function Invoke-FlowOpenMainmenuRoute {
  param(
    $Context,
    [string]$Name,
    [int]$X,
    [int]$Y,
    [string]$Path,
    [hashtable]$Params = @{},
    [hashtable]$Fields
  )

  Invoke-FlowTapThenWaitProbe -Context $Context -Name $Name -X $X -Y $Y -Path $Path -Params $Params -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "$Name-response" -Tag "connect_app_response" -Path $Path -Fields $Fields -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Assert-FlowClientAlive -Context $Context -Step "$Name-after-response"
  Capture-FlowScreenshot -Context $Context -Name $Name | Out-Null
}

function Invoke-FlowMainmenuButtonsRouteSmoke {
  param($Context)

  $coords = Get-FlowMainmenuRouteCoords
  $entries = @(
    @{ name = "open-mainmenu-gacha"; coord = $coords.gacha; path = "/connect/app/gacha/select/getcontents"; fields = @{ command = "gacha"; nextScene = 9100 } },
    @{ name = "open-mainmenu-battle"; coord = $coords.battle; path = "/connect/app/battle/area"; fields = @{ command = "battle"; nextScene = 5100 } },
    @{ name = "open-mainmenu-compound"; coord = $coords.compound; path = "/connect/app/card/exchange"; params = @{ mode = "1" }; fields = @{ command = "card_exchange"; nextScene = 7200 } },
    @{ name = "open-mainmenu-shop"; coord = $coords.shop; path = "/connect/app/shop/shop"; fields = @{ command = "shop"; nextScene = 8100 } }
  )

  foreach ($entry in $entries) {
    $params = if ($entry.ContainsKey("params")) { $entry.params } else { @{} }
    Invoke-FlowOpenMainmenuRoute -Context $Context -Name $entry.name -X $entry.coord.x -Y $entry.coord.y -Path $entry.path -Params $params -Fields $entry.fields
    Invoke-FlowReturnToMainmenu -Context $Context -Name "return-from-$($entry.name)"
  }

  Invoke-FlowOpenMainmenuRoute -Context $Context -Name "open-mainmenu-menu" -X $coords.menu.x -Y $coords.menu.y -Path "/connect/app/menu/menulist" -Fields @{ command = "menu"; nextScene = 20100 }
  Invoke-FlowOpenMainmenuRoute -Context $Context -Name "open-menu-playerinfo" -X $coords.menuPlayerInfo.x -Y $coords.menuPlayerInfo.y -Path "/connect/app/menu/playerinfo" -Fields @{ command = "p_info"; nextScene = 26100 }
  Invoke-FlowReturnToMenuList -Context $Context -Name "return-from-open-menu-playerinfo"
}

function Invoke-FlowFastTapThenWaitProbe {
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
  Add-FlowEvent -Context $Context -Type "tap" -Data ([ordered]@{ name = $Name; x = $X; y = $Y; fast = $true })
  $stage = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "tap", "$X", "$Y") -TimeoutSeconds 10 -AllowFailure
  if (-not $stage.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "runtime-not-ready" -Step $Name -Message "ADB fast tap failed: $($stage.failureClass) $($stage.stderr) $($stage.stdout)"
  }
  return Wait-FlowServerEvent -Context $Context -Step $Name -Tag "connect_app_probe" -Path $Path -Params $Params -TimeoutSeconds $TimeoutSeconds -NoEventFailureClass "tap-no-effect"
}

function Get-FlowExplorationCoords {
  @{
    mainmenuExplore = @{ x = 1090; y = 250 }
    areaRow0 = @{ x = 760; y = 260 }
    areaRow1Select = @{ x = 650; y = 395 }
    floorTopRow = @{ x = 760; y = 260 }
    floorSecondRow = @{ x = 760; y = 395 }
    explorationForward = @{ x = 1090; y = 95 }
    explorationNextFloor = @{ x = 1090; y = 95 }
    explorationReturn = @{ x = 1090; y = 585 }
    apShortageBuy = @{ x = 775; y = 340 }
    apShortageReturn = @{ x = 1090; y = 585 }
    shopReturn = @{ x = 1090; y = 585 }
    lvupApAll = @{ x = 1000; y = 465 }
    lvupOk = @{ x = 1090; y = 100 }
  }
}

function Enter-FlowExplorationArea0FloorList {
  param($Context)

  $coords = Get-FlowExplorationCoords

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
  Wait-FlowServerEvent -Context $Context -Step "open-exploration-response" -Tag "connect_app_response" -Path "/connect/app/exploration/area" -Fields @{ areaCount = 1 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "area-list" | Out-Null

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "tap-area-0" -X $coords.areaRow0.x -Y $coords.areaRow0.y -Path "/connect/app/exploration/floor" -Params @{ area_id = "0" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "tap-area-0-response" -Tag "connect_app_response" -Path "/connect/app/exploration/floor" -Fields @{ regionId = 0 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "area0-floor-list" | Out-Null
  return $coords
}

function Enter-FlowExplorationArea0Main {
  param($Context)

  $coords = Enter-FlowExplorationArea0FloorList -Context $Context

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "tap-area-0-floor" -X $coords.floorTopRow.x -Y $coords.floorTopRow.y -Path "/connect/app/exploration/get_floor" -Params @{ area_id = "0" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "tap-area-0-floor-response" -Tag "connect_app_response" -Path "/connect/app/exploration/get_floor" -Fields @{ regionId = 0; floorId = 2; areaNo = 1; bg = "adv_bg14" } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 5
  Capture-FlowScreenshot -Context $Context -Name "area0-main" | Out-Null
  return $coords
}

function Invoke-FlowExplorationSmoke {
  param($Context)

  $coords = Enter-FlowExplorationArea0Main -Context $Context

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "return-to-area-list" -X $coords.explorationReturn.x -Y $coords.explorationReturn.y -Path "/connect/app/exploration/area" -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "return-to-area-list-response" -Tag "connect_app_response" -Path "/connect/app/exploration/area" -Fields @{ areaCount = 1 } -TimeoutSeconds 10 | Out-Null
  Wait-FlowServerQuiet -Context $Context -Step "return-to-area-list-settle" -QuietSeconds 4 -TimeoutSeconds 20
  Start-Sleep -Seconds 4

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "tap-area-0-after-return" -X $coords.areaRow0.x -Y $coords.areaRow0.y -Path "/connect/app/exploration/floor" -Params @{ area_id = "0" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "tap-area-0-after-return-response" -Tag "connect_app_response" -Path "/connect/app/exploration/floor" -Fields @{ regionId = 0; unlocked = $true } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "area0-floor-list-after-return" | Out-Null
}

function Invoke-FlowExplorationWalkSmoke {
  param($Context)

  $coords = Enter-FlowExplorationArea0Main -Context $Context

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "area0-forward-1" -X $coords.explorationForward.x -Y $coords.explorationForward.y -Path "/connect/app/exploration/explore" -Params @{ area_id = "0"; floor_id = "1" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "area0-forward-1-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{ regionId = 0; floorId = 2; areaNo = 1; movesDone = 1; progress = 10; gold = 18; getExp = 3; remainingAp = 24 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "area0-after-forward-1" | Out-Null

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "area0-forward-2" -X $coords.explorationForward.x -Y $coords.explorationForward.y -Path "/connect/app/exploration/explore" -Params @{ area_id = "0"; floor_id = "1" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "area0-forward-2-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{ regionId = 0; floorId = 2; areaNo = 1; movesDone = 2; progress = 20; gold = 18; getExp = 3; remainingAp = 23 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "area0-after-forward-2" | Out-Null

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "walk-return-to-area-list" -X $coords.explorationReturn.x -Y $coords.explorationReturn.y -Path "/connect/app/exploration/area" -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "walk-return-area-response" -Tag "connect_app_response" -Path "/connect/app/exploration/area" -Fields @{ areaCount = 1 } -TimeoutSeconds 10 | Out-Null
  Wait-FlowServerQuiet -Context $Context -Step "walk-return-area-settle" -QuietSeconds 4 -TimeoutSeconds 20
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "walk-area-list-after-return" | Out-Null

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "walk-tap-area-0-again" -X $coords.areaRow0.x -Y $coords.areaRow0.y -Path "/connect/app/exploration/floor" -Params @{ area_id = "0" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "walk-area-0-floor-progress-response" -Tag "connect_app_response" -Path "/connect/app/exploration/floor" -Fields @{ regionId = 0; maxProgress = 20; maxProgressFloorId = 2 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "walk-area0-floor-list-progress" | Out-Null
}

function Invoke-FlowExplorationForwardVisualSmoke {
  param($Context)

  $coords = Enter-FlowExplorationArea0Main -Context $Context
  Capture-FlowScreenshot -Context $Context -Name "before-forward-progress-50" | Out-Null

  Invoke-FlowFastTapThenWaitProbe -Context $Context -Name "visual-forward" -X $coords.explorationForward.x -Y $coords.explorationForward.y -Path "/connect/app/exploration/explore" -Params @{ area_id = "0"; floor_id = "1" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "visual-forward-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{ regionId = 0; floorId = 2; areaNo = 1; movesDone = 6; progress = 60; gold = 18; getExp = 3; remainingAp = 24 } -TimeoutSeconds 10 | Out-Null

  Start-Sleep -Milliseconds 200
  Capture-FlowScreenshot -Context $Context -Name "after-forward-0200ms" | Out-Null
  Start-Sleep -Milliseconds 600
  Capture-FlowScreenshot -Context $Context -Name "after-forward-0800ms" | Out-Null
  Start-Sleep -Milliseconds 1000
  Capture-FlowScreenshot -Context $Context -Name "after-forward-1800ms" | Out-Null
  Start-Sleep -Milliseconds 1200
  Capture-FlowScreenshot -Context $Context -Name "after-forward-3000ms" | Out-Null
}

function Invoke-FlowExplorationFloorClearSmoke {
  param($Context)

  $coords = Enter-FlowExplorationArea0FloorList -Context $Context

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "tap-area-0-floor-area5" -X $coords.floorTopRow.x -Y $coords.floorTopRow.y -Path "/connect/app/exploration/get_floor" -Params @{ area_id = "0"; floor_id = "6" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "tap-area-0-floor-area5-response" -Tag "connect_app_response" -Path "/connect/app/exploration/get_floor" -Fields @{ regionId = 0; floorId = 6; areaNo = 5; bg = "adv_bg14"; movesDone = 15; progress = 93; hasNextFloor = $true; nextFloorId = 7; nextAreaNo = 6; nextRouteAreaId = 5 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 5
  Capture-FlowScreenshot -Context $Context -Name "area0-area5-main-before-clear" | Out-Null

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "area0-area5-final-forward" -X $coords.explorationForward.x -Y $coords.explorationForward.y -Path "/connect/app/exploration/explore" -Params @{ area_id = "4"; floor_id = "5" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "area0-area5-final-forward-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{ regionId = 0; floorId = 6; areaNo = 5; movesDone = 16; progress = 100; gold = 55; getExp = 9 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 2
  Capture-FlowScreenshot -Context $Context -Name "area0-area5-clear-early" | Out-Null
  Start-Sleep -Seconds 6
  Capture-FlowScreenshot -Context $Context -Name "area0-area5-clear-after-animation" | Out-Null

  $nextProbe = Invoke-FlowTapThenWaitProbe -Context $Context -Name "tap-next-floor-after-clear" -X $coords.explorationNextFloor.x -Y $coords.explorationNextFloor.y -Path "" -TimeoutSeconds 25
  if ($nextProbe.path -eq "/connect/app/exploration/explore") {
    Stop-FlowWithFailure -Context $Context -FailureClass "floor-clear-ui-not-triggered" -Step "tap-next-floor-after-clear" -Message "Tapping the expected next-floor button emitted /exploration/explore, so the client still appears to be on the normal forward UI."
  }
  if ($nextProbe.path -ne "/connect/app/exploration/get_floor") {
    Stop-FlowWithFailure -Context $Context -FailureClass "unknown-next-floor-route" -Step "tap-next-floor-after-clear" -Message "Tapping the expected next-floor button emitted $($nextProbe.path); preserve requests.jsonl before implementing a handler."
  }
  Wait-FlowServerEvent -Context $Context -Step "tap-next-floor-after-clear-response" -Tag "connect_app_response" -Path "/connect/app/exploration/get_floor" -Fields @{ regionId = 0; floorId = 7; areaNo = 6; bg = "adv_bg14"; movesDone = 0; progress = 0; hasNextFloor = $false } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 5
  Capture-FlowScreenshot -Context $Context -Name "area0-area6-main-after-next-floor" | Out-Null
}

function Invoke-FlowExplorationApShortageSmoke {
  param($Context)

  $coords = Enter-FlowExplorationArea0Main -Context $Context
  $initialSave = Read-FlowPlayerSave -Context $Context -Step "ap-shortage-save-before"

  Invoke-FlowTap -Context $Context -Name "ap-shortage-forward" -X $coords.explorationForward.x -Y $coords.explorationForward.y
  $probe = Wait-FlowServerEventOptional -Context $Context -Step "ap-shortage-forward-optional-probe" -Tag "connect_app_probe" -Path "/connect/app/exploration/explore" -Params @{ area_id = "0"; floor_id = "1" } -TimeoutSeconds 8
  if ($probe) {
    Wait-FlowServerEvent -Context $Context -Step "ap-shortage-forward-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{ source = "exploration ap fail"; nextScene = 81100; saved = $false; currentAp = 0 } -TimeoutSeconds 10 | Out-Null
    Add-FlowEvent -Context $Context -Type "ap-shortage-mode" -Data ([ordered]@{
        mode = "server-response"
        observable = "explore request reached server and returned AP shortage branch"
      })
  } else {
    Assert-FlowClientAlive -Context $Context -Step "ap-shortage-local-page"
    Add-FlowEvent -Context $Context -Type "ap-shortage-mode" -Data ([ordered]@{
        mode = "client-local"
        observable = "AP=0 was blocked by the client before /exploration/explore"
      })
  }
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "ap-shortage-page" | Out-Null
  Assert-FlowApShortagePlayerSaveUnchanged -Context $Context -InitialSave $initialSave

  Invoke-FlowTap -Context $Context -Name "ap-shortage-return" -X $coords.apShortageReturn.x -Y $coords.apShortageReturn.y
  Wait-FlowServerQuiet -Context $Context -Step "ap-shortage-return-settle" -QuietSeconds 3 -TimeoutSeconds 12
  Start-Sleep -Seconds 2
  Capture-FlowScreenshot -Context $Context -Name "ap-shortage-after-return" | Out-Null

  Invoke-FlowTap -Context $Context -Name "ap-shortage-forward-after-return" -X $coords.explorationForward.x -Y $coords.explorationForward.y
  $returnProbe = Wait-FlowServerEventOptional -Context $Context -Step "ap-shortage-forward-after-return-probe" -Tag "connect_app_probe" -Path "/connect/app/exploration/explore" -Params @{ area_id = "0"; floor_id = "1" } -TimeoutSeconds 8
  if (-not $returnProbe) {
    Stop-FlowWithFailure -Context $Context -FailureClass "ap-shortage-return-stuck" -Step "ap-shortage-forward-after-return" -Message "After tapping the AP shortage back button, tapping the stage forward button did not emit /exploration/explore. The client is probably still on the AP shortage scene or focused on the wrong layer."
  }
  Wait-FlowServerEvent -Context $Context -Step "ap-shortage-forward-after-return-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{ source = "exploration ap fail"; nextScene = 81100; saved = $false; currentAp = 0 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 2
  Capture-FlowScreenshot -Context $Context -Name "ap-shortage-page-after-return-forward" | Out-Null
  Assert-FlowApShortagePlayerSaveUnchanged -Context $Context -InitialSave $initialSave

  Invoke-FlowTap -Context $Context -Name "ap-shortage-buy" -X $coords.apShortageBuy.x -Y $coords.apShortageBuy.y
  $buyProbe = Wait-FlowServerEventOptional -Context $Context -Step "ap-shortage-buy-route" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 8
  if ($buyProbe) {
    Add-FlowEvent -Context $Context -Type "ap-shortage-buy-route" -Data ([ordered]@{
        path = $buyProbe.path
        decryptedParams = $buyProbe.decryptedParams
      })
    $buyResponse = Wait-FlowServerEventOptional -Context $Context -Step "ap-shortage-buy-response" -Tag "connect_app_response" -Path $buyProbe.path -TimeoutSeconds 10
    if ($buyResponse -and "$(Get-FlowProperty -Object $buyResponse.payload -Name 'status')" -eq "501") {
      Start-Sleep -Seconds 2
      Capture-FlowScreenshot -Context $Context -Name "ap-shortage-buy-unimplemented-route" | Out-Null
      Stop-FlowWithFailure -Context $Context -FailureClass "shop-route-unimplemented" -Step "ap-shortage-buy" -Message "AP shortage buy button emitted $($buyProbe.path), but the local server returned the generic 501 response. Implement the smallest shop response before judging the buy-page back button."
    }
  } else {
    Assert-FlowClientAlive -Context $Context -Step "ap-shortage-buy-local-page"
    Add-FlowEvent -Context $Context -Type "ap-shortage-buy-route" -Data ([ordered]@{
        path = ""
        observable = "buy button did not emit a server route before the screenshot"
      })
  }
  Start-Sleep -Seconds 3
  Capture-FlowScreenshot -Context $Context -Name "ap-shortage-buy-page" | Out-Null

  Invoke-FlowTap -Context $Context -Name "ap-shortage-buy-return" -X $coords.shopReturn.x -Y $coords.shopReturn.y
  Wait-FlowServerQuiet -Context $Context -Step "ap-shortage-buy-return-settle" -QuietSeconds 3 -TimeoutSeconds 12
  Start-Sleep -Seconds 2
  Capture-FlowScreenshot -Context $Context -Name "ap-shortage-after-buy-return" | Out-Null

  Invoke-FlowTap -Context $Context -Name "ap-shortage-forward-after-buy-return" -X $coords.explorationForward.x -Y $coords.explorationForward.y
  $buyReturnProbe = Wait-FlowServerEventOptional -Context $Context -Step "ap-shortage-forward-after-buy-return-probe" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 8
  if ($buyReturnProbe -and $buyReturnProbe.path -eq "/connect/app/exploration/get_floor") {
    Add-FlowEvent -Context $Context -Type "ap-shortage-buy-return-stage-reload" -Data ([ordered]@{
        path = $buyReturnProbe.path
        decryptedParams = $buyReturnProbe.decryptedParams
      })
    Wait-FlowServerEvent -Context $Context -Step "ap-shortage-buy-return-get-floor-response" -Tag "connect_app_response" -Path "/connect/app/exploration/get_floor" -Fields @{ regionId = 0; floorId = 2; areaNo = 1 } -TimeoutSeconds 10 | Out-Null
    Start-Sleep -Seconds 4
    Capture-FlowScreenshot -Context $Context -Name "ap-shortage-stage-after-buy-return-reload" | Out-Null
    Invoke-FlowTap -Context $Context -Name "ap-shortage-forward-after-buy-return-reload" -X $coords.explorationForward.x -Y $coords.explorationForward.y
    $buyReturnProbe = Wait-FlowServerEventOptional -Context $Context -Step "ap-shortage-forward-after-buy-return-reload-probe" -Tag "connect_app_probe" -Path "/connect/app/exploration/explore" -Params @{ area_id = "0"; floor_id = "1" } -TimeoutSeconds 8
  } elseif ($buyReturnProbe -and $buyReturnProbe.path -ne "/connect/app/exploration/explore") {
    Stop-FlowWithFailure -Context $Context -FailureClass "ap-shortage-buy-return-wrong-route" -Step "ap-shortage-forward-after-buy-return" -Message "After returning from the AP purchase page, tapping the stage forward coordinate emitted $($buyReturnProbe.path), not /exploration/explore."
  }
  if (-not $buyReturnProbe) {
    Invoke-FlowTap -Context $Context -Name "ap-shortage-return-after-buy-return" -X $coords.apShortageReturn.x -Y $coords.apShortageReturn.y
    Wait-FlowServerQuiet -Context $Context -Step "ap-shortage-return-after-buy-return-settle" -QuietSeconds 3 -TimeoutSeconds 12
    Start-Sleep -Seconds 2
    Capture-FlowScreenshot -Context $Context -Name "ap-shortage-stage-after-buy-return" | Out-Null
    Invoke-FlowTap -Context $Context -Name "ap-shortage-forward-after-buy-return-and-ap-return" -X $coords.explorationForward.x -Y $coords.explorationForward.y
    $buyReturnProbe = Wait-FlowServerEventOptional -Context $Context -Step "ap-shortage-forward-after-buy-return-and-ap-return-probe" -Tag "connect_app_probe" -Path "/connect/app/exploration/explore" -Params @{ area_id = "0"; floor_id = "1" } -TimeoutSeconds 8
  }
  if (-not $buyReturnProbe) {
    Stop-FlowWithFailure -Context $Context -FailureClass "ap-shortage-buy-return-stuck" -Step "ap-shortage-buy-return" -Message "After returning from the AP purchase page, neither the stage forward button nor the AP shortage back button restored a usable exploration stage."
  }
  Wait-FlowServerEvent -Context $Context -Step "ap-shortage-forward-after-buy-return-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{ source = "exploration ap fail"; nextScene = 81100; saved = $false; currentAp = 0 } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 2
  Capture-FlowScreenshot -Context $Context -Name "ap-shortage-page-after-buy-return-forward" | Out-Null
  Assert-FlowApShortagePlayerSaveUnchanged -Context $Context -InitialSave $initialSave
}

function Invoke-FlowExplorationLevelUpSmoke {
  param($Context)

  $coords = Enter-FlowExplorationArea0Main -Context $Context

  Invoke-FlowTapThenWaitProbe -Context $Context -Name "levelup-forward" -X $coords.explorationForward.x -Y $coords.explorationForward.y -Path "/connect/app/exploration/explore" -Params @{ area_id = "0"; floor_id = "1" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "levelup-forward-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{
    regionId = 0
    floorId = 2
    areaNo = 1
    movesDone = 1
    progress = 10
    gold = 18
    getExp = 3
    levelUp = $true
    isLimit = $false
    beforeLevel = 17
    level = 18
    profileExp = 0
    nextExp = 2100
    remainingAp = 25
    abilityPoints = 3
    abilityPointsGranted = 3
  } -TimeoutSeconds 10 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "levelup-status-probe" -Tag "connect_app_probe" -Path "/connect/app/town/lvup_status" -TimeoutSeconds 20 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "levelup-status-response" -Tag "connect_app_response" -Path "/connect/app/town/lvup_status" -Fields @{
    source = "minimal town lvup status"
    nextScene = 84100
    level = 18
    profileExp = 0
    nextExp = 2100
    apCurrent = 25
    apMax = 25
    bcCurrent = 25
    bcMax = 25
    abilityPoints = 3
  } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 5
  Capture-FlowScreenshot -Context $Context -Name "levelup-after-forward" | Out-Null
  Assert-FlowLevelUpPlayerSave -Context $Context

  Invoke-FlowTap -Context $Context -Name "levelup-ap-all" -X $coords.lvupApAll.x -Y $coords.lvupApAll.y
  Wait-FlowServerQuiet -Context $Context -Step "levelup-ap-all-local-settle" -QuietSeconds 2 -TimeoutSeconds 8
  Capture-FlowScreenshot -Context $Context -Name "levelup-after-ap-all" | Out-Null
  Invoke-FlowTapThenWaitProbe -Context $Context -Name "levelup-ok" -X $coords.lvupOk.x -Y $coords.lvupOk.y -Path "/connect/app/town/pointsetting" -Params @{ ap = "3"; bc = "0" } -TimeoutSeconds 20 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "levelup-pointsetting-response" -Tag "connect_app_response" -Path "/connect/app/town/pointsetting" -Fields @{
    source = "minimal town pointsetting"
    nextScene = 2100
    requestedAp = 3
    requestedBc = 0
    apAllocated = 3
    bcAllocated = 0
    remainingAbilityPoints = 0
    apCurrent = 28
    apMax = 28
    bcCurrent = 25
    bcMax = 25
    abilityPoints = 0
    saved = $true
  } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 5
  Capture-FlowScreenshot -Context $Context -Name "levelup-after-pointsetting" | Out-Null
  Assert-FlowLevelUpPointsettingPlayerSave -Context $Context
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
    playerSave = $Context.playerSave
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
    "player_save=$($Context.playerSave)",
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
      '[2026-01-01T00:00:00.100Z] connect_app_response {"path":"/connect/app/exploration/floor","regionId":0,"maxProgress":10,"maxProgressFloorId":7}',
      '[2026-01-01T00:00:01.000Z] connect_app_probe {"path":"/connect/app/exploration/get_floor","decryptedParams":{"area_id":"0","floor_id":"7","check":"1"}}',
      '[2026-01-01T00:00:01.100Z] connect_app_response {"path":"/connect/app/exploration/get_floor","regionId":0,"floorId":7,"areaNo":6,"bg":"adv_bg14"}',
      '[2026-01-01T00:00:02.000Z] connect_app_probe {"path":"/connect/app/exploration/explore","decryptedParams":{"area_id":"5","floor_id":"6","auto_build":"1"}}',
      '[2026-01-01T00:00:02.100Z] connect_app_response {"path":"/connect/app/exploration/explore","regionId":0,"floorId":7,"areaNo":6,"movesDone":2,"progress":10,"gold":55,"getExp":9}',
      '[2026-01-01T00:00:03.000Z] connect_app_probe {"path":"/connect/app/exploration/get_floor","decryptedParams":{"area_id":"0","floor_id":"6","check":"1"}}',
      '[2026-01-01T00:00:03.100Z] connect_app_response {"path":"/connect/app/exploration/get_floor","regionId":0,"floorId":6,"areaNo":5,"movesDone":15,"progress":93,"hasNextFloor":true,"nextFloorId":7,"nextAreaNo":6,"nextRouteAreaId":5,"bg":"adv_bg14"}',
      '[2026-01-01T00:00:04.000Z] connect_app_probe {"path":"/connect/app/exploration/explore","decryptedParams":{"area_id":"4","floor_id":"5","auto_build":"1"}}',
      '[2026-01-01T00:00:04.100Z] connect_app_response {"path":"/connect/app/exploration/explore","regionId":0,"floorId":6,"areaNo":5,"movesDone":16,"progress":100,"gold":55,"getExp":9}',
      '[2026-01-01T00:00:05.000Z] connect_app_probe {"path":"/connect/app/exploration/get_floor","decryptedParams":{"area_id":"5","floor_id":"6","check":"1"}}',
      '[2026-01-01T00:00:05.100Z] connect_app_response {"path":"/connect/app/exploration/get_floor","regionId":0,"floorId":7,"areaNo":6,"movesDone":0,"progress":0,"hasNextFloor":false,"bg":"adv_bg14"}',
      '[2026-01-01T00:00:06.000Z] connect_app_probe {"path":"/connect/app/exploration/explore","decryptedParams":{"area_id":"0","floor_id":"1","auto_build":"1"}}',
      '[2026-01-01T00:00:06.100Z] connect_app_response {"path":"/connect/app/exploration/explore","source":"exploration ap fail","nextScene":81100,"saved":false,"currentAp":0,"floorKey":"0:2","regionId":0,"floorId":2,"areaNo":1}',
      '[2026-01-01T00:00:07.000Z] connect_app_probe {"path":"/connect/app/exploration/explore","decryptedParams":{"area_id":"0","floor_id":"1","auto_build":"1"}}',
      '[2026-01-01T00:00:07.100Z] connect_app_response {"path":"/connect/app/exploration/explore","regionId":0,"floorId":2,"areaNo":1,"movesDone":1,"progress":10,"gold":18,"getExp":3,"levelUp":true,"isLimit":false,"beforeLevel":17,"level":18,"profileExp":0,"nextExp":2100,"remainingAp":25,"abilityPoints":3,"abilityPointsGranted":3}',
      '[2026-01-01T00:00:08.000Z] connect_app_probe {"path":"/connect/app/town/lvup_status","decryptedParams":{}}',
      '[2026-01-01T00:00:08.100Z] connect_app_response {"path":"/connect/app/town/lvup_status","source":"minimal town lvup status","nextScene":84100,"level":18,"profileExp":0,"nextExp":2100,"apCurrent":25,"apMax":25,"bcCurrent":25,"bcMax":25,"abilityPoints":3}',
      '[2026-01-01T00:00:09.000Z] connect_app_probe {"path":"/connect/app/town/pointsetting","decryptedParams":{"ap":"3","bc":"0"}}',
      '[2026-01-01T00:00:09.100Z] connect_app_response {"path":"/connect/app/town/pointsetting","source":"minimal town pointsetting","nextScene":2100,"requestedAp":3,"requestedBc":0,"apAllocated":3,"bcAllocated":0,"remainingAbilityPoints":0,"apCurrent":28,"apMax":28,"bcCurrent":25,"bcMax":25,"abilityPoints":0,"saved":true}'
    ) | Set-Content -LiteralPath $ctx.serverOut -Encoding UTF8
    Set-FlowApShortagePlayerSave -Context $ctx
    $initialApShortageSave = Read-FlowPlayerSave -Context $ctx -Step "self-ap-shortage-save-before"
    Assert-FlowApShortagePlayerSaveUnchanged -Context $ctx -InitialSave $initialApShortageSave
    Set-FlowLevelUpPlayerSave -Context $ctx
    $levelUpSave = Read-FlowPlayerSave -Context $ctx -Step "self-levelup-save-before"
    $levelUpSave.profile.level = 18
    $levelUpSave.profile.exp = 0
    $levelUpSave.profile.nextExp = 2100
    $levelUpSave.resources.ap.current = 25
    $levelUpSave.resources.bc.current = 25
    $levelUpSave.progression.abilityPoints.unspent = 3
    $levelUpSave.progression.abilityPoints.fromLevels = 3
    $levelUpSave.exploration.movesByFloor | Add-Member -NotePropertyName "0:2" -NotePropertyValue 1 -Force
    $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($ctx.playerSave, ($levelUpSave | ConvertTo-Json -Depth 40) + [Environment]::NewLine, $utf8NoBom)
    Assert-FlowLevelUpPlayerSave -Context $ctx
    $levelUpSave.resources.ap.current = 28
    $levelUpSave.resources.ap.max = 28
    $levelUpSave.resources.bc.current = 25
    $levelUpSave.resources.bc.max = 25
    $levelUpSave.progression.abilityPoints.unspent = 0
    $levelUpSave.progression.abilityPoints.apAllocated = 3
    $levelUpSave.progression.abilityPoints.bcAllocated = 0
    [System.IO.File]::WriteAllText($ctx.playerSave, ($levelUpSave | ConvertTo-Json -Depth 40) + [Environment]::NewLine, $utf8NoBom)
    Assert-FlowLevelUpPointsettingPlayerSave -Context $ctx
    Wait-FlowServerEvent -Context $ctx -Step "self-floor" -Tag "connect_app_probe" -Path "/connect/app/exploration/floor" -Params @{ area_id = "0" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-floor-response" -Tag "connect_app_response" -Path "/connect/app/exploration/floor" -Fields @{ regionId = 0; maxProgress = 10; maxProgressFloorId = 7 } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-get-floor" -Tag "connect_app_probe" -Path "/connect/app/exploration/get_floor" -Params @{ area_id = "0"; check = "1" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-get-floor-response" -Tag "connect_app_response" -Path "/connect/app/exploration/get_floor" -Fields @{ bg = "adv_bg14"; floorId = 7; areaNo = 6 } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-explore" -Tag "connect_app_probe" -Path "/connect/app/exploration/explore" -Params @{ area_id = "5"; floor_id = "6" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-explore-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{ floorId = 7; areaNo = 6; progress = 10; gold = 55; getExp = 9 } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-clear-get-floor" -Tag "connect_app_probe" -Path "/connect/app/exploration/get_floor" -Params @{ area_id = "0"; floor_id = "6" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-clear-get-floor-response" -Tag "connect_app_response" -Path "/connect/app/exploration/get_floor" -Fields @{ floorId = 6; areaNo = 5; movesDone = 15; progress = 93; hasNextFloor = $true; nextFloorId = 7; nextAreaNo = 6 } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-clear-explore" -Tag "connect_app_probe" -Path "/connect/app/exploration/explore" -Params @{ area_id = "4"; floor_id = "5" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-clear-explore-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{ floorId = 6; areaNo = 5; progress = 100 } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-next-floor-get-floor" -Tag "connect_app_probe" -Path "/connect/app/exploration/get_floor" -Params @{ area_id = "5"; floor_id = "6" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-next-floor-get-floor-response" -Tag "connect_app_response" -Path "/connect/app/exploration/get_floor" -Fields @{ floorId = 7; areaNo = 6; progress = 0; hasNextFloor = $false } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-ap-shortage-explore" -Tag "connect_app_probe" -Path "/connect/app/exploration/explore" -Params @{ area_id = "0"; floor_id = "1" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-ap-shortage-explore-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{ source = "exploration ap fail"; nextScene = 81100; saved = $false; currentAp = 0 } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-levelup-explore" -Tag "connect_app_probe" -Path "/connect/app/exploration/explore" -Params @{ area_id = "0"; floor_id = "1" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-levelup-explore-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{ levelUp = $true; isLimit = $false; beforeLevel = 17; level = 18; profileExp = 0; nextExp = 2100; remainingAp = 25; abilityPoints = 3; abilityPointsGranted = 3 } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-levelup-status-probe" -Tag "connect_app_probe" -Path "/connect/app/town/lvup_status" -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-levelup-status-response" -Tag "connect_app_response" -Path "/connect/app/town/lvup_status" -Fields @{ source = "minimal town lvup status"; nextScene = 84100; level = 18; profileExp = 0; nextExp = 2100; apCurrent = 25; apMax = 25; bcCurrent = 25; bcMax = 25; abilityPoints = 3 } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-levelup-pointsetting-probe" -Tag "connect_app_probe" -Path "/connect/app/town/pointsetting" -Params @{ ap = "3"; bc = "0" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-levelup-pointsetting-response" -Tag "connect_app_response" -Path "/connect/app/town/pointsetting" -Fields @{ source = "minimal town pointsetting"; nextScene = 2100; requestedAp = 3; requestedBc = 0; apAllocated = 3; bcAllocated = 0; remainingAbilityPoints = 0; apCurrent = 28; apMax = 28; bcCurrent = 25; bcMax = 25; abilityPoints = 0; saved = $true } -TimeoutSeconds 2 | Out-Null
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
        playerSave = $ctx.playerSave
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
      name = "mainmenu-faction-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Login with a technique-faction artifact save and verify the main-menu fairy selector and screenshot."
    },
    [ordered]@{
      name = "mainmenu-buttons-route-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Login to main menu, tap representative main/menu entries, verify their first route, screenshot pages, and return to main menu."
    },
    [ordered]@{
      name = "exploration-smoke"
      default = $true
      startsRuntime = $true
      ownsServer = $true
      description = "Login to main menu, run the accepted exploration area/floor/stage smoke path, and collect structured artifacts."
    },
    [ordered]@{
      name = "exploration-walk-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Login to main menu, enter the first exploration stage, advance twice, and verify progress/rewards plus floor-list progress."
    },
    [ordered]@{
      name = "exploration-forward-visual-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Login to main menu, enter the first exploration stage with seeded progress, advance once, and capture early post-forward frames."
    },
    [ordered]@{
      name = "exploration-floor-clear-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Login to main menu, enter region 0 area 5 with a flow-only near-clear seed, verify floor-clear, then enter area 6."
    },
    [ordered]@{
      name = "exploration-ap-shortage-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Login with an artifact-local AP=0 save, verify AP shortage, AP shortage back, AP purchase page back, and unchanged save."
    },
    [ordered]@{
      name = "exploration-levelup-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Login with a Lv17 artifact-local save at 1997/2000 EXP, advance once, and verify Lv18/AP-BC recovery/ability-point save state."
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
  $supportedRuntimeScenarios = @("mainmenu-faction-smoke", "mainmenu-buttons-route-smoke", "exploration-smoke", "exploration-walk-smoke", "exploration-forward-visual-smoke", "exploration-floor-clear-smoke", "exploration-ap-shortage-smoke", "exploration-levelup-smoke")
  if ($Scenario -notin $supportedRuntimeScenarios) {
    $ctx = New-FlowContext -Scenario $Scenario -Tag $Tag
    $supported = (@(Get-FlowScenarioCatalog).name -join ", ")
    return Complete-FlowResult -Context $ctx -Ok $false -FailureClass "unsupported-scenario" -FailureStep "scenario" -FailureMessage "Unsupported flow scenario: $Scenario. Supported scenarios: $supported"
  }

  $ctx = New-FlowContext -Scenario $Scenario -Tag $Tag
  try {
    Add-FlowEvent -Context $ctx -Type "flow-start" -Data ([ordered]@{ scenario = $Scenario })
    $serverEnvironment = @{}
    if ($Scenario -eq "exploration-ap-shortage-smoke") {
      Set-FlowApShortagePlayerSave -Context $ctx
    }
    if ($Scenario -eq "exploration-levelup-smoke") {
      Set-FlowLevelUpPlayerSave -Context $ctx
    }
    if ($Scenario -eq "mainmenu-faction-smoke") {
      Set-FlowMainmenuFactionPlayerSave -Context $ctx
    }
    if ($Scenario -eq "exploration-floor-clear-smoke") {
      $serverEnvironment["KSSMA_EXPLORATION_MOVES_SEED"] = '{"4:6":15}'
    }
    if ($Scenario -eq "exploration-forward-visual-smoke") {
      $serverEnvironment["KSSMA_EXPLORATION_MOVES_SEED"] = '{"0:2":5}'
    }
    Start-FlowServer -Context $ctx -ExtraEnvironment $serverEnvironment
    Invoke-FlowRuntimeGate -Context $ctx
    Invoke-FlowLaunchAndLogin -Context $ctx
    switch ($Scenario) {
      "mainmenu-faction-smoke" { Invoke-FlowMainmenuFactionSmoke -Context $ctx }
      "mainmenu-buttons-route-smoke" { Invoke-FlowMainmenuButtonsRouteSmoke -Context $ctx }
      "exploration-smoke" { Invoke-FlowExplorationSmoke -Context $ctx }
      "exploration-walk-smoke" { Invoke-FlowExplorationWalkSmoke -Context $ctx }
      "exploration-forward-visual-smoke" { Invoke-FlowExplorationForwardVisualSmoke -Context $ctx }
      "exploration-floor-clear-smoke" { Invoke-FlowExplorationFloorClearSmoke -Context $ctx }
      "exploration-ap-shortage-smoke" { Invoke-FlowExplorationApShortageSmoke -Context $ctx }
      "exploration-levelup-smoke" { Invoke-FlowExplorationLevelUpSmoke -Context $ctx }
    }
    Add-FlowEvent -Context $ctx -Type "flow-pass" -Data ([ordered]@{ scenario = $Scenario })
    return Complete-FlowResult -Context $ctx -Ok $true
  } catch {
    $failureClass = if ($_.Exception.Data["FlowFailureClass"]) { $_.Exception.Data["FlowFailureClass"] } else { "script-error" }
    $failureStep = if ($_.Exception.Data["FlowFailureStep"]) { $_.Exception.Data["FlowFailureStep"] } else { "flow" }
    return Complete-FlowResult -Context $ctx -Ok $false -FailureClass $failureClass -FailureStep $failureStep -FailureMessage $_.Exception.Message
  } finally {
    Stop-FlowServer -Context $ctx | Out-Null
  }
}
