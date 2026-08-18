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
    coordinateScale = 1.0
    screenshotScale = 1.0
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
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) {
      return $Object[$Name]
    }
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

function Set-FlowGachaSettlementPlayerSave {
  param($Context)

  $defaultSavePath = Join-Path $script:RepoRoot "server\data\player\default-save.json"
  try {
    $save = [System.IO.File]::ReadAllText($defaultSavePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  } catch {
    Stop-FlowWithFailure -Context $Context -FailureClass "player-save-invalid" -Step "gacha-settlement-save-setup" -Message "Cannot read default player save: $($_.Exception.Message)"
  }

  $save.currencies.friendshipPoint = 400
  $save.stats.cardsDrawn = 0
  $save.gacha.history = @()
  $save.cards.count = @($save.cards.instances).Count
  $json = $save | ConvertTo-Json -Depth 40
  $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($Context.playerSave, $json + [Environment]::NewLine, $utf8NoBom)
  Add-FlowEvent -Context $Context -Type "player-save-seeded" -Data ([ordered]@{
      scenario = "gacha-settlement-deck-smoke"
      source = $defaultSavePath
      path = $Context.playerSave
      friendshipPoint = [int]$save.currencies.friendshipPoint
      cardCount = [int]$save.cards.count
      cardsDrawn = [int]$save.stats.cardsDrawn
    })
}

function Set-FlowGachaPaidSettlementPlayerSave {
  param(
    $Context,
    [int]$InitialMc = 300,
    [string]$ScenarioName = "gacha-paid-settlement-deck-smoke"
  )

  $defaultSavePath = Join-Path $script:RepoRoot "server\data\player\default-save.json"
  try {
    $save = [System.IO.File]::ReadAllText($defaultSavePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  } catch {
    Stop-FlowWithFailure -Context $Context -FailureClass "player-save-invalid" -Step "gacha-paid-settlement-save-setup" -Message "Cannot read default player save: $($_.Exception.Message)"
  }

  $save.currencies.friendshipPoint = 0
  $save.currencies.mc = $InitialMc
  $save.stats.cardsDrawn = 0
  $save.gacha.history = @()
  $save.cards.count = @($save.cards.instances).Count
  $json = $save | ConvertTo-Json -Depth 40
  $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($Context.playerSave, $json + [Environment]::NewLine, $utf8NoBom)
  Add-FlowEvent -Context $Context -Type "player-save-seeded" -Data ([ordered]@{
      scenario = $ScenarioName
      source = $defaultSavePath
      path = $Context.playerSave
      mc = [int]$save.currencies.mc
      friendshipPoint = [int]$save.currencies.friendshipPoint
      cardCount = [int]$save.cards.count
      cardsDrawn = [int]$save.stats.cardsDrawn
    })
}

function Set-FlowDeckBuilderEditPlayerSave {
  param(
    $Context,
    [string]$ScenarioName = "deck-builder-edit-smoke"
  )

  $defaultSavePath = Join-Path $script:RepoRoot "server\data\player\default-save.json"
  $gachaDataPath = Join-Path $script:RepoRoot "server\data\game\gacha.json"
  try {
    $save = [System.IO.File]::ReadAllText($defaultSavePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $gachaData = [System.IO.File]::ReadAllText($gachaDataPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  } catch {
    Stop-FlowWithFailure -Context $Context -FailureClass "player-save-invalid" -Step "deck-builder-edit-save-setup" -Message "Cannot read the deck-builder seed data: $($_.Exception.Message)"
  }

  $starter = @($save.cards.instances | Where-Object { [int]$_.serialId -eq 1 -and [int]$_.masterCardId -eq 22 } | Select-Object -First 1)
  $drawCard = $gachaData.buy.drawCard
  $activeDeck = @($save.cards.decks | Where-Object { $_.id -eq $save.cards.activeDeckId } | Select-Object -First 1)
  if ($starter.Count -ne 1 -or $null -eq $drawCard -or [int]$drawCard.serialId -ne 2 -or [int]$drawCard.masterCardId -ne 9 -or $activeDeck.Count -ne 1) {
    Stop-FlowWithFailure -Context $Context -FailureClass "player-save-invalid" -Step "deck-builder-edit-save-setup" -Message "Deck-builder seed requires starter 1/22, gacha draw 2/9, and one active deck."
  }

  $candidate = $drawCard.PSObject.Copy()
  $candidate | Add-Member -NotePropertyName "level" -NotePropertyValue ([int]$drawCard.buildLevel) -Force
  $candidate | Add-Member -NotePropertyName "exp" -NotePropertyValue ([int]$drawCard.buildExp) -Force
  $save.cards.instances = @($starter[0], $candidate)
  $save.cards.count = 2
  $activeDeck[0].cardInstanceIds = @(1)
  $save.profile.leaderSerialId = 1
  $json = $save | ConvertTo-Json -Depth 40
  $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($Context.playerSave, $json + [Environment]::NewLine, $utf8NoBom)
  Add-FlowEvent -Context $Context -Type "player-save-seeded" -Data ([ordered]@{
      scenario = $ScenarioName
      sources = @($defaultSavePath, $gachaDataPath)
      path = $Context.playerSave
      ownerCardSerialIds = @(1, 2)
      ownerCardMasterCardIds = @(22, 9)
      activeDeckCardInstanceIds = @(1)
      leaderSerialId = 1
      historyCount = @($save.gacha.history).Count
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

function Assert-FlowGachaSettlementPlayerSave {
  param($Context)

  $actual = Read-FlowPlayerSave -Context $Context -Step "gacha-settlement-save-after"
  $friendshipPoint = [int]$actual.currencies.friendshipPoint
  $instances = if ($actual.cards.instances) { @($actual.cards.instances) } else { @() }
  $gachaHistoryValue = Get-FlowProperty -Object $actual.gacha -Name "history"
  $gachaHistoryEntries = if ($gachaHistoryValue) { @($gachaHistoryValue) } else { @() }
  $drawnCards = @($instances | Where-Object { [int]$_.serialId -eq 2 -and [int]$_.masterCardId -eq 9 })
  $instanceCount = @($instances).Count
  $drawnCardCount = @($drawnCards).Count
  $historyCount = @($gachaHistoryEntries).Count
  $cardsDrawn = [int]$actual.stats.cardsDrawn
  $historyLast = if ($historyCount -gt 0) { @($gachaHistoryEntries)[-1] } else { $null }

  if (
    $friendshipPoint -ne 200 -or
    $instanceCount -ne 2 -or
    $drawnCardCount -ne 1 -or
    $cardsDrawn -ne 1 -or
    $historyCount -ne 1 -or
    $null -eq $historyLast -or
    [int]$historyLast.productId -ne 1 -or
    [int]$historyLast.bulk -ne 1 -or
    [int]$historyLast.serialId -ne 2 -or
    [int]$historyLast.masterCardId -ne 9
  ) {
    Stop-FlowWithFailure -Context $Context -FailureClass "gacha-settlement-save-mismatch" -Step "gacha-settlement-save-after" -Message "Gacha settlement save mismatch: friendship=$friendshipPoint cards=$instanceCount drawnCardMatches=$drawnCardCount cardsDrawn=$cardsDrawn history=$historyCount."
  }

  Add-FlowEvent -Context $Context -Type "gacha-settlement-save-ok" -Data ([ordered]@{
      friendshipPoint = $friendshipPoint
      cardCount = $instanceCount
      serialId = 2
      masterCardId = 9
      cardsDrawn = $cardsDrawn
      historyCount = $historyCount
    })
}

function Assert-FlowGachaPaidSettlementPlayerSave {
  param($Context)

  $actual = Read-FlowPlayerSave -Context $Context -Step "gacha-paid-settlement-save-after"
  $mc = [int]$actual.currencies.mc
  $friendshipPoint = [int]$actual.currencies.friendshipPoint
  $instances = if ($actual.cards.instances) { @($actual.cards.instances) } else { @() }
  $gachaHistoryValue = Get-FlowProperty -Object $actual.gacha -Name "history"
  $gachaHistoryEntries = if ($gachaHistoryValue) { @($gachaHistoryValue) } else { @() }
  $drawnCards = @($instances | Where-Object { [int]$_.serialId -eq 2 -and [int]$_.masterCardId -eq 9 })
  $instanceCount = @($instances).Count
  $drawnCardCount = @($drawnCards).Count
  $historyCount = @($gachaHistoryEntries).Count
  $cardsDrawn = [int]$actual.stats.cardsDrawn
  $historyLast = if ($historyCount -gt 0) { @($gachaHistoryEntries)[-1] } else { $null }

  if (
    $mc -ne 0 -or
    $friendshipPoint -ne 0 -or
    $instanceCount -ne 2 -or
    $drawnCardCount -ne 1 -or
    $cardsDrawn -ne 1 -or
    $historyCount -ne 1 -or
    $null -eq $historyLast -or
    [int]$historyLast.productId -ne 2 -or
    [int]$historyLast.bulk -ne 1 -or
    [int]$historyLast.serialId -ne 2 -or
    [int]$historyLast.masterCardId -ne 9
  ) {
    Stop-FlowWithFailure -Context $Context -FailureClass "gacha-paid-settlement-save-mismatch" -Step "gacha-paid-settlement-save-after" -Message "Paid gacha settlement save mismatch: mc=$mc friendship=$friendshipPoint cards=$instanceCount drawnCardMatches=$drawnCardCount cardsDrawn=$cardsDrawn history=$historyCount."
  }

  Add-FlowEvent -Context $Context -Type "gacha-paid-settlement-save-ok" -Data ([ordered]@{
      mc = $mc
      friendshipPoint = $friendshipPoint
      cardCount = $instanceCount
      serialId = 2
      masterCardId = 9
      cardsDrawn = $cardsDrawn
      historyCount = $historyCount
    })
}

function Assert-FlowGachaPaidRetryPlayerSave {
  param($Context)

  $actual = Read-FlowPlayerSave -Context $Context -Step "gacha-paid-retry-save-after"
  $mc = [int]$actual.currencies.mc
  $friendshipPoint = [int]$actual.currencies.friendshipPoint
  $instances = if ($actual.cards.instances) { @($actual.cards.instances) } else { @() }
  $historyValue = Get-FlowProperty -Object $actual.gacha -Name "history"
  $history = if ($historyValue) { @($historyValue) } else { @() }
  $serial2Cards = @($instances | Where-Object { [int]$_.serialId -eq 2 -and [int]$_.masterCardId -eq 9 })
  $serial3Cards = @($instances | Where-Object { [int]$_.serialId -eq 3 -and [int]$_.masterCardId -eq 9 })
  $historyFirst = if ($history.Count -gt 0) { $history[0] } else { $null }
  $historyLast = if ($history.Count -gt 1) { $history[1] } else { $null }
  if (
    $mc -ne 0 -or
    $friendshipPoint -ne 0 -or
    $instances.Count -ne 3 -or
    $serial2Cards.Count -ne 1 -or
    $serial3Cards.Count -ne 1 -or
    [int]$actual.cards.count -ne 3 -or
    [int]$actual.stats.cardsDrawn -ne 2 -or
    $history.Count -ne 2 -or
    $null -eq $historyFirst -or
    $null -eq $historyLast -or
    [int]$historyFirst.productId -ne 2 -or
    [int]$historyFirst.bulk -ne 1 -or
    [int]$historyFirst.serialId -ne 2 -or
    [int]$historyFirst.masterCardId -ne 9 -or
    [int]$historyLast.productId -ne 2 -or
    [int]$historyLast.bulk -ne 1 -or
    [int]$historyLast.serialId -ne 3 -or
    [int]$historyLast.masterCardId -ne 9
  ) {
    Stop-FlowWithFailure -Context $Context -FailureClass "gacha-paid-retry-save-mismatch" -Step "gacha-paid-retry-save-after" -Message "Paid retry save mismatch: mc=$mc friendship=$friendshipPoint cards=$($instances.Count) serial2Matches=$($serial2Cards.Count) serial3Matches=$($serial3Cards.Count) cardsDrawn=$($actual.stats.cardsDrawn) history=$($history.Count)."
  }

  Add-FlowEvent -Context $Context -Type "gacha-paid-retry-save-ok" -Data ([ordered]@{
      mc = $mc
      friendshipPoint = $friendshipPoint
      cardCount = $instances.Count
      serialIds = @(2, 3)
      masterCardId = 9
      cardsDrawn = [int]$actual.stats.cardsDrawn
      historyCount = $history.Count
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

function Test-FlowDeckBuilderSaveParams {
  param($Params)

  if ($null -eq $Params -or -not ($Params -is [System.Collections.IDictionary])) {
    return $false
  }
  $keys = @($Params.Keys | ForEach-Object { "$_" })
  if (
    $keys.Count -ne 2 -or
    @($keys | Where-Object { $_ -ceq "C" }).Count -ne 1 -or
    @($keys | Where-Object { $_ -ceq "lr" }).Count -ne 1
  ) {
    return $false
  }
  return (
    "$($Params["C"])" -ceq "1,2,empty,empty,empty,empty,empty,empty,empty,empty,empty,empty" -and
    "$($Params["lr"])" -ceq "1"
  )
}

function Test-FlowGachaBuyParams {
  param(
    $Params,
    [string]$ProductId,
    [string]$Bulk,
    [string]$AutoBuild
  )

  if ($null -eq $Params -or -not ($Params -is [System.Collections.IDictionary])) {
    return $false
  }
  $keys = @($Params.Keys | ForEach-Object { "$_" })
  if (
    $keys.Count -ne 3 -or
    @($keys | Where-Object { $_ -ceq "product_id" }).Count -ne 1 -or
    @($keys | Where-Object { $_ -ceq "bulk" }).Count -ne 1 -or
    @($keys | Where-Object { $_ -ceq "auto_build" }).Count -ne 1
  ) {
    return $false
  }
  return (
    "$($Params["product_id"])" -ceq $ProductId -and
    "$($Params["bulk"])" -ceq $Bulk -and
    "$($Params["auto_build"])" -ceq $AutoBuild
  )
}

function Get-FlowEventDecryptedParams {
  param($Event)

  $params = Get-FlowProperty -Object $Event -Name "decryptedParams"
  if (-not $params) {
    $payload = Get-FlowProperty -Object $Event -Name "payload"
    $params = Get-FlowProperty -Object $payload -Name "decryptedParams"
  }
  if ($params) {
    return $params
  }
  return @{}
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
  if ($Params.Count -gt 0 -and -not (Test-FlowExpectedMap -Actual (Get-FlowEventDecryptedParams -Event $Event) -Expected $Params)) {
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

function Invoke-FlowDismissStaleCrashDialog {
  param(
    $Context,
    [string]$Step
  )

  $ui = Get-FlowUiDump -Context $Context -Serial $Context.serial -Name "stale-crash-$Step"
  if ($null -eq $ui) {
    return $false
  }
  $message = $ui.SelectSingleNode("//*[@resource-id='android:id/message']")
  if ($null -eq $message) {
    return $false
  }
  $text = $message.GetAttribute("text")
  if ($text -notmatch "has stopped|Unfortunately") {
    return $false
  }
  $ok = $ui.SelectSingleNode("//*[@resource-id='android:id/button1' and @text='OK']")
  if ($null -eq $ok) {
    return $false
  }
  $center = Get-FlowUiNodeCenter -Node $ok
  if (-not $center) {
    return $false
  }
  Add-FlowEvent -Context $Context -Type "stale-crash-dismiss" -Data ([ordered]@{
      step = $Step
      message = $text
      x = $center.x
      y = $center.y
    })
  # ponytail: startup-only cleanup for Android crash dialogs left by a prior
  # flow run; new crashes inside a scenario are still handled by Assert-FlowClientAlive.
  Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "tap", "$($center.x)", "$($center.y)") -TimeoutSeconds 12 -AllowFailure | Out-Null
  Start-Sleep -Seconds 2
  return $true
}

function Find-FlowSystemAnrWaitButton {
  param([xml]$Ui)

  if ($null -eq $Ui) {
    return $null
  }
  $message = $Ui.SelectSingleNode("//*[@resource-id='android:id/message']")
  if ($null -eq $message) {
    return $null
  }
  $text = $message.GetAttribute("text")
  if ($text -notmatch "isn't responding|is not responding") {
    return $null
  }
  return $Ui.SelectSingleNode("//*[@resource-id='android:id/button2' and @text='Wait']")
}

function Invoke-FlowDismissSystemAnrIfPresent {
  param(
    $Context,
    [string]$Step
  )

  $ui = Get-FlowUiDump -Context $Context -Serial $Context.serial -Name "system-anr-$Step"
  $wait = Find-FlowSystemAnrWaitButton -Ui $ui
  if ($null -eq $wait) {
    return $false
  }

  # ponytail: ARM19 sometimes shows the host system ANR dialog over an alive game.
  # Tapping Wait is the narrow recovery; OK would kill the process and invalidate the flow.
  Add-FlowEvent -Context $Context -Type "system-anr-dismiss" -Data ([ordered]@{
      step = $Step
      action = "wait"
    })
  $center = Get-FlowUiNodeCenter -Node $wait
  if (-not $center) {
    Add-FlowEvent -Context $Context -Type "system-anr-dismiss-failed" -Data ([ordered]@{
        step = $Step
        reason = "button bounds unavailable"
      })
    return $false
  }
  Add-FlowEvent -Context $Context -Type "tap" -Data ([ordered]@{
      name = "system-anr-wait-$Step"
      x = $center.x
      y = $center.y
      raw = $true
    })
  Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "tap", "$($center.x)", "$($center.y)") -TimeoutSeconds 12 -AllowFailure | Out-Null
  Start-Sleep -Seconds 2
  return $true
}

function Ensure-FlowNoSystemAnr {
  param(
    $Context,
    [string]$Step
  )

  for ($attempt = 1; $attempt -le 2; $attempt++) {
    if (-not (Invoke-FlowDismissSystemAnrIfPresent -Context $Context -Step "$Step-$attempt")) {
      return
    }
  }
}

function Test-FlowUiShowsGamePackage {
  param([xml]$Ui)

  if ($null -eq $Ui) {
    return $false
  }
  return $null -ne $Ui.SelectSingleNode("//*[@package='com.square_enix.million_cn']")
}

function Assert-FlowClientAlive {
  param(
    $Context,
    [string]$Step
  )

  Ensure-FlowNoSystemAnr -Context $Context -Step $Step
  if (Test-FlowCrashDialog -Context $Context -Name "crash-$Step") {
    Stop-FlowWithFailure -Context $Context -FailureClass "client-crash" -Step $Step -Message "Android crash dialog is visible."
  }
  $lastActivityLine = ""
  $lastUiStatus = "not-run"
  $lastUiShowsGame = $false
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $activityLine = Get-FlowCurrentActivity -Serial $Context.serial
    $lastActivityLine = $activityLine
    $Context.lastActivity = $activityLine
    if (Test-FlowGameActivity $activityLine) {
      if ($attempt -gt 1) {
        Add-FlowEvent -Context $Context -Type "activity-check-recovered" -Data ([ordered]@{
            step = $Step
            attempt = $attempt
            activity = $activityLine
          })
      }
      return
    }

    # ponytail: old ARM19 sometimes returns an empty/partial dumpsys while the
    # game surface is still foreground; package-owned UI is enough to keep the
    # flow moving. If a real crash/launcher is foreground, this remains false.
    $ui = Get-FlowUiDump -Context $Context -Serial $Context.serial -Name "alive-$Step-$attempt"
    $lastUiStatus = $Context.lastUiDumpStatus
    $lastUiShowsGame = Test-FlowUiShowsGamePackage -Ui $ui
    Add-FlowEvent -Context $Context -Type "activity-check-retry" -Data ([ordered]@{
        step = $Step
        attempt = $attempt
        activity = $activityLine
        uiDump = $lastUiStatus
        uiShowsGame = $lastUiShowsGame
      })
    if ($lastUiShowsGame) {
      $Context.lastActivity = "ui:com.square_enix.million_cn"
      return
    }
    if ($attempt -lt 3) {
      Start-Sleep -Seconds 2
    }
  }
  Stop-FlowWithFailure -Context $Context -FailureClass "client-crash" -Step $Step -Message "Game activity is no longer resumed: $lastActivityLine; uiDump=$lastUiStatus; uiShowsGame=$lastUiShowsGame"
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
    [int]$Y,
    [switch]$DeviceCoordinates
  )

  $scale = if ($DeviceCoordinates) { 1.0 } else { [double]$Context.coordinateScale }
  $deviceX = [int][Math]::Round($X * $scale)
  $deviceY = [int][Math]::Round($Y * $scale)
  Ensure-FlowNoSystemAnr -Context $Context -Step "before-$Name"
  Add-FlowEvent -Context $Context -Type "tap" -Data ([ordered]@{
      name = $Name
      x = $X
      y = $Y
      deviceX = $deviceX
      deviceY = $deviceY
      coordinateScale = $scale
      deviceCoordinates = [bool]$DeviceCoordinates
    })
  $stage = $null
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $stage = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "tap", "$deviceX", "$deviceY") -TimeoutSeconds 30 -AllowFailure
    if ($stage.ok) {
      Start-Sleep -Milliseconds 800
      return
    }
    if (-not ($stage.timedOut -or $stage.failureClass -match "adb|transport|offline|device")) {
      break
    }

    $transportRecovered = $false
    for ($probeAttempt = 1; $probeAttempt -le 3; $probeAttempt++) {
      $probe = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "getprop", "sys.boot_completed") -TimeoutSeconds 5 -AllowFailure
      if ($probe.ok -and (($probe.stdout -as [string]).Trim())) {
        $transportRecovered = $true
        Add-FlowEvent -Context $Context -Type "tap-retry" -Data ([ordered]@{
            name = $Name
            reason = "tap failed but transport probe recovered"
            attempt = $attempt
            probeAttempt = $probeAttempt
            firstTimedOut = $stage.timedOut
            firstFailureClass = $stage.failureClass
          })
        break
      }
      Start-Sleep -Seconds 1
    }
    if (-not $transportRecovered) {
      continue
    }
    Start-Sleep -Seconds $attempt
  }

  if (-not $stage.ok) {
    if ($stage.timedOut -or $stage.failureClass -match "adb|transport|offline|device") {
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
  # UIAutomator bounds already use physical device pixels and must not be scaled.
  Invoke-FlowTap -Context $Context -Name $Name -X $center.x -Y $center.y -DeviceCoordinates
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

  Ensure-FlowNoSystemAnr -Context $Context -Step "screenshot-$Name"
  $safeName = $Name -replace "[^A-Za-z0-9_.-]", "-"
  $remote = "/data/local/tmp/kssma-flow-$safeName.png"
  $local = Join-Path $Context.screenshotsDir "$safeName.png"
  $scale = [double]$Context.screenshotScale
  $pulled = if ($scale -eq 1.0) { $local } else { Join-Path $Context.screenshotsDir "$safeName.native.png" }
  Add-FlowEvent -Context $Context -Type "screenshot-start" -Data ([ordered]@{ name = $Name; path = $local; nativePath = $pulled; screenshotScale = $scale })
  $pull = $null
  $size = 0
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    if (Test-Path -LiteralPath $pulled) {
      Remove-Item -LiteralPath $pulled -Force -ErrorAction SilentlyContinue
    }
    Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "screencap", "-p", $remote) -TimeoutSeconds 20 -AllowFailure | Out-Null
    $pull = Invoke-Adb -Arguments @("-s", $Context.serial, "pull", $remote, $pulled) -TimeoutSeconds 30 -AllowFailure
    $size = if (Test-Path -LiteralPath $pulled) { (Get-Item -LiteralPath $pulled).Length } else { 0 }
    Add-FlowEvent -Context $Context -Type "screenshot-attempt" -Data ([ordered]@{ name = $Name; attempt = $attempt; path = $pulled; bytes = $size; adbOk = $pull.ok })
    if ($size -gt 0) {
      break
    }
    # ponytail: classic ARM19 sometimes pulls a zero-byte PNG while the next
    # screencap succeeds; retry keeps visual gates from failing on capture noise.
    Start-Sleep -Seconds 2
  }
  if ($size -gt 0 -and $scale -ne 1.0) {
    Add-Type -AssemblyName System.Drawing
    $source = $null
    $target = $null
    $graphics = $null
    try {
      $source = [System.Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $pulled))
      $width = [int][Math]::Round($source.Width / $scale)
      $height = [int][Math]::Round($source.Height / $scale)
      $target = New-Object System.Drawing.Bitmap($width, $height)
      $graphics = [System.Drawing.Graphics]::FromImage($target)
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.DrawImage($source, 0, 0, $width, $height)
      $target.Save($local, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      if ($graphics) { $graphics.Dispose() }
      if ($target) { $target.Dispose() }
      if ($source) { $source.Dispose() }
    }
  }
  $normalizedSize = if (Test-Path -LiteralPath $local) { (Get-Item -LiteralPath $local).Length } else { 0 }
  Add-FlowEvent -Context $Context -Type "screenshot" -Data ([ordered]@{
      name = $Name
      path = $local
      nativePath = $pulled
      ok = [bool]($normalizedSize -gt 0)
      bytes = $normalizedSize
      nativeBytes = $size
      screenshotScale = $scale
      adbOk = $pull.ok
    })
  return $local
}

function Get-FlowScreenshotDiffScore {
  param(
    [string]$ExpectedPath,
    [string]$ActualPath
  )

  if (-not (Test-Path -LiteralPath $ExpectedPath) -or -not (Test-Path -LiteralPath $ActualPath)) {
    return $null
  }
  if ((Get-Item -LiteralPath $ExpectedPath).Length -le 0 -or (Get-Item -LiteralPath $ActualPath).Length -le 0) {
    return $null
  }

  Add-Type -AssemblyName System.Drawing
  $expected = $null
  $actual = $null
  try {
    $expected = [System.Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $ExpectedPath))
    $actual = [System.Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $ActualPath))
    $sum = 0.0
    $count = 0
    $width = [Math]::Min($expected.Width, $actual.Width)
    $height = [Math]::Min($expected.Height, $actual.Height)
    for ($y = 20; $y -lt $height; $y += 30) {
      for ($x = 20; $x -lt $width; $x += 30) {
        $left = $expected.GetPixel($x, $y)
        $right = $actual.GetPixel($x, $y)
        $sum += [Math]::Abs($left.R - $right.R) + [Math]::Abs($left.G - $right.G) + [Math]::Abs($left.B - $right.B)
        $count += 3
      }
    }
    if ($count -eq 0) {
      return $null
    }
    return [Math]::Round($sum / $count, 2)
  } catch {
    return $null
  } finally {
    if ($expected) { $expected.Dispose() }
    if ($actual) { $actual.Dispose() }
  }
}

function Get-FlowScreenshotRegionDiffScore {
  param(
    [string]$ExpectedPath,
    [string]$ActualPath,
    [int]$RegionX,
    [int]$RegionY,
    [int]$RegionWidth,
    [int]$RegionHeight,
    [int]$SampleStep = 8
  )

  if (
    $RegionX -lt 0 -or $RegionY -lt 0 -or $RegionWidth -le 0 -or $RegionHeight -le 0 -or $SampleStep -le 0 -or
    -not (Test-Path -LiteralPath $ExpectedPath) -or -not (Test-Path -LiteralPath $ActualPath)
  ) {
    return $null
  }

  Add-Type -AssemblyName System.Drawing
  $expected = $null
  $actual = $null
  try {
    $expected = [System.Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $ExpectedPath))
    $actual = [System.Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $ActualPath))
    $right = [Math]::Min([Math]::Min($expected.Width, $actual.Width), $RegionX + $RegionWidth)
    $bottom = [Math]::Min([Math]::Min($expected.Height, $actual.Height), $RegionY + $RegionHeight)
    $sum = 0.0
    $count = 0
    for ($y = $RegionY; $y -lt $bottom; $y += $SampleStep) {
      for ($x = $RegionX; $x -lt $right; $x += $SampleStep) {
        $leftPixel = $expected.GetPixel($x, $y)
        $rightPixel = $actual.GetPixel($x, $y)
        $sum += [Math]::Abs($leftPixel.R - $rightPixel.R) + [Math]::Abs($leftPixel.G - $rightPixel.G) + [Math]::Abs($leftPixel.B - $rightPixel.B)
        $count += 3
      }
    }
    if ($count -eq 0) {
      return $null
    }
    return [Math]::Round($sum / $count, 2)
  } catch {
    return $null
  } finally {
    if ($expected) { $expected.Dispose() }
    if ($actual) { $actual.Dispose() }
  }
}

function Assert-FlowScreenshotDiff {
  param(
    $Context,
    [string]$Step,
    [string]$ExpectedPath,
    [string]$ActualPath,
    [double]$MinDiff = -1,
    [double]$MaxDiff = -1
  )

  $score = Get-FlowScreenshotDiffScore -ExpectedPath $ExpectedPath -ActualPath $ActualPath
  Add-FlowEvent -Context $Context -Type "screenshot-diff" -Data ([ordered]@{
      step = $Step
      expected = $ExpectedPath
      actual = $ActualPath
      score = $score
      minDiff = $MinDiff
      maxDiff = $MaxDiff
    })
  if ($null -eq $score) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step $Step -Message "Could not compare screenshots."
  }
  if ($MinDiff -ge 0 -and $score -lt $MinDiff) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step $Step -Message "Screenshot did not leave the previous page. diff=$score min=$MinDiff"
  }
  if ($MaxDiff -ge 0 -and $score -gt $MaxDiff) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step $Step -Message "Screenshot did not return to expected page. diff=$score max=$MaxDiff"
  }
}

function Get-FlowDeckBuilderEntryVisualCheck {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -le 0) {
    return [pscustomobject][ordered]@{ ok = $false; reason = "missing-image"; samples = @{} }
  }

  Add-Type -AssemblyName System.Drawing
  $bitmap = $null
  try {
    $bitmap = [System.Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $Path))
    if ($bitmap.Width -lt 1180 -or $bitmap.Height -lt 660) {
      return [pscustomobject][ordered]@{ ok = $false; reason = "unexpected-size"; samples = @{} }
    }

    # ponytail: fixed-point colors cover the accepted 1280x720 DeckScene; replace
    # this with a scene-id hook or template classifier if the display/layout baseline changes.
    $decide = $bitmap.GetPixel(1040, 80)
    $leader = $bitmap.GetPixel(1040, 250)
    $create = $bitmap.GetPixel(1040, 400)
    $back = $bitmap.GetPixel(1040, 550)
    $deck = $bitmap.GetPixel(170, 200)
    $samples = [ordered]@{
      decide = "$($decide.R),$($decide.G),$($decide.B)"
      leader = "$($leader.R),$($leader.G),$($leader.B)"
      createDeck = "$($create.R),$($create.G),$($create.B)"
      back = "$($back.R),$($back.G),$($back.B)"
      deckRail = "$($deck.R),$($deck.G),$($deck.B)"
    }
    $ok = (
      $decide.R -ge 130 -and ($decide.R - $decide.G) -ge 80 -and ($decide.R - $decide.B) -ge 80 -and
      $leader.R -ge 150 -and $leader.G -ge 70 -and ($leader.R - $leader.G) -ge 40 -and ($leader.G - $leader.B) -ge 30 -and
      $create.R -ge 150 -and $create.G -ge 70 -and ($create.R - $create.G) -ge 40 -and ($create.G - $create.B) -ge 20 -and
      $back.R -ge 25 -and $back.R -le 100 -and [Math]::Abs($back.R - $back.G) -le 8 -and [Math]::Abs($back.G - $back.B) -le 8 -and
      $deck.B -ge 180 -and ($deck.B - $deck.R) -ge 100 -and ($deck.G - $deck.R) -ge 60
    )
    return [pscustomobject][ordered]@{ ok = [bool]$ok; reason = $(if ($ok) { "" } else { "signature-mismatch" }); samples = $samples }
  } catch {
    return [pscustomobject][ordered]@{ ok = $false; reason = $_.Exception.Message; samples = @{} }
  } finally {
    if ($bitmap) { $bitmap.Dispose() }
  }
}

function Assert-FlowDeckBuilderEntryVisual {
  param(
    $Context,
    [string]$Step,
    [string]$Path
  )

  $check = Get-FlowDeckBuilderEntryVisualCheck -Path $Path
  Add-FlowEvent -Context $Context -Type "deck-builder-visual-check" -Data ([ordered]@{
      step = $Step
      path = $Path
      ok = $check.ok
      reason = $check.reason
      samples = $check.samples
    })
  if (-not $check.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step $Step -Message "DeckScene visual signature was not present: $($check.reason)."
  }
}

function Get-FlowDeckBuilderLeaderModeVisualCheck {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -le 0) {
    return [pscustomobject][ordered]@{ ok = $false; reason = "missing-image"; samples = @{} }
  }

  Add-Type -AssemblyName System.Drawing
  $bitmap = $null
  try {
    $bitmap = [System.Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $Path))
    if ($bitmap.Width -lt 1180 -or $bitmap.Height -lt 660) {
      return [pscustomobject][ordered]@{ ok = $false; reason = "unexpected-size"; samples = @{} }
    }

    # ponytail: this fixed signature covers the accepted 1280x720 leader-select dimming;
    # replace it with a scene-mode hook or template classifier if the display/layout baseline changes.
    $decide = $bitmap.GetPixel(1040, 80)
    $leader = $bitmap.GetPixel(1040, 250)
    $create = $bitmap.GetPixel(1040, 400)
    $back = $bitmap.GetPixel(1040, 550)
    $deck = $bitmap.GetPixel(170, 200)
    $samples = [ordered]@{
      decide = "$($decide.R),$($decide.G),$($decide.B)"
      leader = "$($leader.R),$($leader.G),$($leader.B)"
      createDeck = "$($create.R),$($create.G),$($create.B)"
      back = "$($back.R),$($back.G),$($back.B)"
      deckRail = "$($deck.R),$($deck.G),$($deck.B)"
    }
    $ok = (
      $decide.R -le 80 -and [Math]::Abs($decide.R - $decide.G) -le 5 -and [Math]::Abs($decide.G - $decide.B) -le 5 -and
      $leader.R -le 80 -and [Math]::Abs($leader.R - $leader.G) -le 5 -and [Math]::Abs($leader.G - $leader.B) -le 5 -and
      $create.R -le 70 -and [Math]::Abs($create.R - $create.G) -le 5 -and [Math]::Abs($create.G - $create.B) -le 5 -and
      $back.R -le 40 -and [Math]::Abs($back.R - $back.G) -le 5 -and [Math]::Abs($back.G - $back.B) -le 5 -and
      $deck.B -ge 180 -and ($deck.B - $deck.R) -ge 100 -and ($deck.G - $deck.R) -ge 60
    )
    return [pscustomobject][ordered]@{ ok = [bool]$ok; reason = $(if ($ok) { "" } else { "signature-mismatch" }); samples = $samples }
  } catch {
    return [pscustomobject][ordered]@{ ok = $false; reason = $_.Exception.Message; samples = @{} }
  } finally {
    if ($bitmap) { $bitmap.Dispose() }
  }
}

function Assert-FlowDeckBuilderLeaderModeVisual {
  param(
    $Context,
    [string]$Step,
    [string]$Path
  )

  $check = Get-FlowDeckBuilderLeaderModeVisualCheck -Path $Path
  Add-FlowEvent -Context $Context -Type "deck-builder-leader-visual-check" -Data ([ordered]@{
      step = $Step
      path = $Path
      ok = $check.ok
      reason = $check.reason
      samples = $check.samples
    })
  if (-not $check.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step $Step -Message "DeckScene leader-select visual signature was not present: $($check.reason)."
  }
}

function New-FlowSolidPng {
  param(
    [string]$Path,
    [int]$Width,
    [int]$Height,
    [int]$Red,
    [int]$Green,
    [int]$Blue
  )

  Add-Type -AssemblyName System.Drawing
  $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($Red, $Green, $Blue))
    try {
      $graphics.FillRectangle($brush, 0, 0, $Width, $Height)
    } finally {
      $brush.Dispose()
    }
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
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

function Sync-FlowSaveFile {
  param(
    $Context,
    [string]$RelativePath
  )

  $sourcePath = Join-Path $script:SampleSaveDir $RelativePath
  if (-not (Test-Path -LiteralPath $sourcePath)) {
    Stop-FlowWithFailure -Context $Context -FailureClass "resource-miss" -Step "sync-save-file" -Message "Missing local save resource: $RelativePath"
  }

  $devicePath = "$script:DeviceSaveDir/$($RelativePath -replace '\\', '/')"
  $deviceParent = $devicePath -replace "/[^/]+$", ""
  Add-FlowEvent -Context $Context -Type "sync-save-file" -Data ([ordered]@{
      relativePath = $RelativePath
      source = $sourcePath
      devicePath = $devicePath
    })
  $mkdir = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "mkdir", "-p", $deviceParent) -TimeoutSeconds 10 -AllowFailure
  Add-FlowEvent -Context $Context -Type "sync-save-file-mkdir" -Data ([ordered]@{
      ok = $mkdir.ok
      timedOut = $mkdir.timedOut
      failureClass = $mkdir.failureClass
      stderr = $mkdir.stderr
    })
  if (-not $mkdir.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "resource-push-failed" -Step "mkdir-flow-save-file" -Message "Cannot create device parent for $RelativePath"
  }
  $push = Invoke-Adb -Arguments @("-s", $Context.serial, "push", $sourcePath, $devicePath) -TimeoutSeconds 120 -AllowFailure
  Add-FlowEvent -Context $Context -Type "sync-save-file-push" -Data ([ordered]@{
      ok = $push.ok
      timedOut = $push.timedOut
      failureClass = $push.failureClass
      stdout = $push.stdout
      stderr = $push.stderr
    })
  if (-not $push.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "resource-push-failed" -Step "push-flow-save-file" -Message "Cannot push device resource $RelativePath"
  }
  $chmod = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "chmod", "644", $devicePath) -TimeoutSeconds 10 -AllowFailure
  Add-FlowEvent -Context $Context -Type "sync-save-file-chmod" -Data ([ordered]@{
      ok = $chmod.ok
      timedOut = $chmod.timedOut
      failureClass = $chmod.failureClass
      stderr = $chmod.stderr
    })
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
        # ponytail: once RooneyJ is visible and no connect route exists, use a direct bounded tap.
        # The generic tap's UI-dialog inspection can take several seconds; automatic login may finish
        # during that delay and turn the intended title tap into an unrelated main-menu action.
        $titleX = [int][Math]::Round(640 * [double]$Context.coordinateScale)
        $titleY = [int][Math]::Round(650 * [double]$Context.coordinateScale)
        Add-FlowEvent -Context $Context -Type "tap" -Data ([ordered]@{ name = "login-native-title-touch-screen"; x = 640; y = 650; deviceX = $titleX; deviceY = $titleY; coordinateScale = $Context.coordinateScale; fast = $true })
        $titleTap = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "tap", "$titleX", "$titleY") -TimeoutSeconds 10 -AllowFailure
        if (-not $titleTap.ok) {
          Stop-FlowWithFailure -Context $Context -FailureClass "runtime-not-ready" -Step "login-native-title-touch-screen" -Message "ADB title tap failed: $($titleTap.failureClass) $($titleTap.stderr) $($titleTap.stdout)"
        }
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
  Invoke-FlowDismissStaleCrashDialog -Context $Context -Step "before-launch" | Out-Null
  Invoke-Adb -Arguments @("-s", $Context.serial, "logcat", "-c") -TimeoutSeconds 10 -AllowFailure | Out-Null
  $launch = Invoke-LaunchGame
  Add-FlowEvent -Context $Context -Type "launch-game" -Data ([ordered]@{ ok = $launch.ok; failureClass = $launch.failureClass; data = $launch.data })
  if (-not $launch.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "login-failed" -Step "launch-game" -Message "launch failed: $($launch.failureClass)"
  }
  Invoke-FlowDismissStaleCrashDialog -Context $Context -Step "after-launch" | Out-Null

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
    deck = @{ x = 640; y = 675 }
    friends = @{ x = 790; y = 675 }
    menu = @{ x = 990; y = 675 }
    menuPlayerInfo = @{ x = 525; y = 115 }
    return = @{ x = 1090; y = 585 }
  }
}

function Get-FlowMenuPageCoords {
  @{
    invite = @{ x = 300; y = 115 }
    playerInfo = @{ x = 525; y = 115 }
    story = @{ x = 755; y = 115 }
    townEvent = @{ x = 985; y = 115 }
    fairy = @{ x = 300; y = 300 }
    battleHistory = @{ x = 525; y = 300 }
    ranking = @{ x = 755; y = 300 }
    option = @{ x = 985; y = 300 }
    item = @{ x = 300; y = 485 }
    cardCollection = @{ x = 525; y = 485 }
    partsList = @{ x = 755; y = 485 }
    help = @{ x = 985; y = 485 }
    updateHistory = @{ x = 300; y = 635 }
  }
}

function Get-FlowGachaCoords {
  @{
      drawOne = @{ x = 650; y = 200 }
      paidOne = @{ x = 650; y = 405 }
      paidConfirm = @{ x = 440; y = 418 }
      touchResult = @{ x = 640; y = 650 }
    resultRetry = @{ x = 1090; y = 95 }
    resultBack = @{ x = 1090; y = 585 }
  }
}

function Invoke-FlowSwipe {
  param(
    $Context,
    [string]$Name,
    [int]$X1,
    [int]$Y1,
    [int]$X2,
    [int]$Y2,
    [int]$DurationMs = 450
  )

  $scale = [double]$Context.coordinateScale
  $deviceX1 = [int][Math]::Round($X1 * $scale)
  $deviceY1 = [int][Math]::Round($Y1 * $scale)
  $deviceX2 = [int][Math]::Round($X2 * $scale)
  $deviceY2 = [int][Math]::Round($Y2 * $scale)
  Ensure-FlowNoSystemAnr -Context $Context -Step "before-$Name"
  Add-FlowEvent -Context $Context -Type "swipe" -Data ([ordered]@{ name = $Name; x1 = $X1; y1 = $Y1; x2 = $X2; y2 = $Y2; deviceX1 = $deviceX1; deviceY1 = $deviceY1; deviceX2 = $deviceX2; deviceY2 = $deviceY2; coordinateScale = $scale; durationMs = $DurationMs })
  $stage = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "swipe", "$deviceX1", "$deviceY1", "$deviceX2", "$deviceY2", "$DurationMs") -TimeoutSeconds 30 -AllowFailure
  if (-not $stage.ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "tap-no-effect" -Step $Name -Message "ADB swipe failed: $($stage.failureClass)"
  }
  Start-Sleep -Milliseconds 1000
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
  return Capture-FlowScreenshot -Context $Context -Name "$Name-mainmenu"
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

function Invoke-FlowOpenMenuListFromMainmenu {
  param(
    $Context,
    [string]$Name = "open-menu-list"
  )

  $coords = Get-FlowMainmenuRouteCoords
  Invoke-FlowOpenMainmenuRoute -Context $Context -Name $Name -X $coords.menu.x -Y $coords.menu.y -Path "/connect/app/menu/menulist" -Fields @{ command = "menu"; nextScene = 20100 }
  $Context.menuBaselineScreenshot = Join-Path $Context.screenshotsDir "$Name.png"
}

function Ensure-FlowMenuListVisible {
  param(
    $Context,
    [string]$Name
  )

  $coords = Get-FlowMainmenuRouteCoords
  Invoke-FlowTap -Context $Context -Name $Name -X $coords.menu.x -Y $coords.menu.y
  $probe = Wait-FlowServerEventOptional -Context $Context -Step "$Name-probe" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 6
  if ($probe) {
    if ($probe.path -ne "/connect/app/menu/menulist") {
      Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step $Name -Message "Expected menu list or no route while ensuring menu visibility, saw $($probe.path)."
    }
    Wait-FlowServerEvent -Context $Context -Step "$Name-response" -Tag "connect_app_response" -Path "/connect/app/menu/menulist" -Fields @{ command = "menu"; nextScene = 20100 } -TimeoutSeconds 10 | Out-Null
  } else {
    Wait-FlowServerQuiet -Context $Context -Step "$Name-already-menu-settle" -QuietSeconds 2 -TimeoutSeconds 8
    Move-FlowRequestCursorToEnd -Context $Context
  }
  Start-Sleep -Seconds 2
  Assert-FlowClientAlive -Context $Context -Step "$Name-after"
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

  Invoke-FlowTap -Context $Context -Name $Name -X $X -Y $Y
  $probe = Wait-FlowServerEvent -Context $Context -Step $Name -Tag "connect_app_probe" -Path "" -TimeoutSeconds 25 -NoEventFailureClass "tap-no-effect"
  if ($probe.path -ne $Path) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step $Name -Message "Unexpected route for ${Name}: $($probe.path). Expected $Path."
  }
  if ($Params.Count -gt 0 -and -not (Test-FlowExpectedMap -Actual $probe.decryptedParams -Expected $Params)) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step $Name -Message "Unexpected params for $Name $($probe.path)."
  }
  Wait-FlowServerEvent -Context $Context -Step "$Name-response" -Tag "connect_app_response" -Path $Path -Fields $Fields -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Assert-FlowClientAlive -Context $Context -Step "$Name-after-response"
  Capture-FlowScreenshot -Context $Context -Name $Name | Out-Null
}

function Invoke-FlowReturnToMainmenuRetry {
  param(
    $Context,
    [string]$Name,
    [string]$BaselineScreenshot,
    [int]$MaxAttempts = 3,
    [double]$MaxDiff = 12,
    [string[]]$AllowedIntermediatePaths = @()
  )

  $coords = Get-FlowMainmenuRouteCoords
  $lastScreenshot = $null
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    Invoke-FlowTap -Context $Context -Name "$Name-attempt-$attempt" -X $coords.return.x -Y $coords.return.y
    $probe = Wait-FlowServerEventOptional -Context $Context -Step "$Name-attempt-$attempt-probe" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 8
    if ($probe) {
      if ($probe.path -eq "/connect/app/mainmenu") {
        Wait-FlowServerEvent -Context $Context -Step "$Name-attempt-$attempt-mainmenu-response" -Tag "connect_app_response" -Path "/connect/app/mainmenu" -TimeoutSeconds 10 | Out-Null
      } elseif ($probe.path -in $AllowedIntermediatePaths) {
        Wait-FlowServerEvent -Context $Context -Step "$Name-attempt-$attempt-intermediate-response" -Tag "connect_app_response" -Path $probe.path -TimeoutSeconds 10 | Out-Null
      } else {
        Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step $Name -Message "Unexpected return route from ${Name}: $($probe.path)."
      }
    } else {
      Wait-FlowServerQuiet -Context $Context -Step "$Name-attempt-$attempt-local-back-settle" -QuietSeconds 2 -TimeoutSeconds 10
      Move-FlowRequestCursorToEnd -Context $Context
    }
    Start-Sleep -Seconds 2
    Assert-FlowClientAlive -Context $Context -Step "$Name-attempt-$attempt-after-return"
    $lastScreenshot = Capture-FlowScreenshot -Context $Context -Name "$Name-attempt-$attempt-mainmenu"
    $score = Get-FlowScreenshotDiffScore -ExpectedPath $BaselineScreenshot -ActualPath $lastScreenshot
    Add-FlowEvent -Context $Context -Type "screenshot-diff" -Data ([ordered]@{
        step = "$Name-attempt-$attempt-visual-return"
        expected = $BaselineScreenshot
        actual = $lastScreenshot
        score = $score
        minDiff = -1
        maxDiff = $MaxDiff
      })
    if ($null -ne $score -and $score -le $MaxDiff) {
      Add-FlowEvent -Context $Context -Type "mainmenu-return-ok" -Data ([ordered]@{ name = $Name; attempts = $attempt; score = $score })
      return $lastScreenshot
    }
  }

  Assert-FlowScreenshotDiff -Context $Context -Step "$Name-visual-return" -ExpectedPath $BaselineScreenshot -ActualPath $lastScreenshot -MaxDiff $MaxDiff
  return $lastScreenshot
}

function Invoke-FlowOpenMenuNativeEntry {
  param(
    $Context,
    [hashtable]$Entry
  )

  $name = $Entry.name
  $coord = $Entry.coord
  Assert-FlowClientAlive -Context $Context -Step "$name-before-tap"
  Invoke-FlowTap -Context $Context -Name $name -X $coord.x -Y $coord.y
  $allowLocal = $Entry.ContainsKey("allowLocal") -and [bool]$Entry.allowLocal
  $probe = $null
  if ($allowLocal) {
    $probe = Wait-FlowServerEventOptional -Context $Context -Step "$name-probe" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 8
    if (-not $probe) {
      Wait-FlowServerQuiet -Context $Context -Step "$name-local-open-settle" -QuietSeconds 2 -TimeoutSeconds 10
      Move-FlowRequestCursorToEnd -Context $Context
      Start-Sleep -Seconds 2
      Assert-FlowClientAlive -Context $Context -Step "$name-after-local-open"
      $openedScreenshot = Capture-FlowScreenshot -Context $Context -Name $name
      if ($Context.Contains("menuBaselineScreenshot") -and $Context.menuBaselineScreenshot) {
        Assert-FlowScreenshotDiff -Context $Context -Step "$name-visual-open" -ExpectedPath $Context.menuBaselineScreenshot -ActualPath $openedScreenshot -MinDiff 20
      }
      Add-FlowEvent -Context $Context -Type "menu-native-entry-ok" -Data ([ordered]@{
          name = $name
          path = ""
          mode = "local"
          expectedPaths = @($Entry.paths)
        })
      return ""
    }
  } else {
    $probe = Wait-FlowServerEvent -Context $Context -Step "$name-probe" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 25 -NoEventFailureClass "tap-no-effect"
  }
  $allowedPaths = @($Entry.paths)
  if ($probe.path -notin $allowedPaths) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step $name -Message "Unexpected route for ${name}: $($probe.path). Expected one of: $($allowedPaths -join ', ')."
  }

  $expectedParams = @{}
  if ($Entry.ContainsKey("paramsByPath") -and $Entry.paramsByPath.ContainsKey($probe.path)) {
    $expectedParams = $Entry.paramsByPath[$probe.path]
  } elseif ($Entry.ContainsKey("params")) {
    $expectedParams = $Entry.params
  }
  if ($expectedParams.Count -gt 0 -and -not (Test-FlowExpectedMap -Actual $probe.decryptedParams -Expected $expectedParams)) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step $name -Message "Unexpected params for $name $($probe.path)."
  }

  $expectedFields = @{}
  if ($Entry.ContainsKey("fieldsByPath") -and $Entry.fieldsByPath.ContainsKey($probe.path)) {
    $expectedFields = $Entry.fieldsByPath[$probe.path]
  } elseif ($Entry.ContainsKey("fields")) {
    $expectedFields = $Entry.fields
  }
  Wait-FlowServerEvent -Context $Context -Step "$name-response" -Tag "connect_app_response" -Path $probe.path -Fields $expectedFields -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 3
  Assert-FlowClientAlive -Context $Context -Step "$name-after-response"
  $openedScreenshot = Capture-FlowScreenshot -Context $Context -Name $name
  if ($Context.Contains("menuBaselineScreenshot") -and $Context.menuBaselineScreenshot -and $name -in @("open-menu-parts-list", "open-menu-card-collection", "open-menu-fairy")) {
    Assert-FlowScreenshotDiff -Context $Context -Step "$name-visual-open" -ExpectedPath $Context.menuBaselineScreenshot -ActualPath $openedScreenshot -MinDiff 20
  }
  Add-FlowEvent -Context $Context -Type "menu-native-entry-ok" -Data ([ordered]@{
      name = $name
      path = $probe.path
      expectedPaths = $allowedPaths
    })
  return $probe.path
}

function Invoke-FlowReturnFromMenuEntry {
  param(
    $Context,
    [string]$Name
  )

  $coords = Get-FlowMainmenuRouteCoords
  Invoke-FlowTap -Context $Context -Name $Name -X $coords.return.x -Y $coords.return.y
  $probe = Wait-FlowServerEventOptional -Context $Context -Step "$Name-probe" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 8
  $location = "menu"
  if ($probe) {
    if ($probe.path -eq "/connect/app/menu/menulist") {
      Wait-FlowServerEvent -Context $Context -Step "$Name-menu-response" -Tag "connect_app_response" -Path "/connect/app/menu/menulist" -Fields @{ command = "menu"; nextScene = 20100 } -TimeoutSeconds 10 | Out-Null
      $location = "menu"
    } elseif ($probe.path -eq "/connect/app/mainmenu") {
      Wait-FlowServerEvent -Context $Context -Step "$Name-mainmenu-response" -Tag "connect_app_response" -Path "/connect/app/mainmenu" -TimeoutSeconds 10 | Out-Null
      $location = "mainmenu"
    } else {
      Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step $Name -Message "Unexpected return route from menu entry: $($probe.path)."
    }
  } else {
    Wait-FlowServerQuiet -Context $Context -Step "$Name-local-back-settle" -QuietSeconds 2 -TimeoutSeconds 10
    Move-FlowRequestCursorToEnd -Context $Context
  }
  Start-Sleep -Seconds 2
  Assert-FlowClientAlive -Context $Context -Step "$Name-after-return"
  $returnScreenshot = Capture-FlowScreenshot -Context $Context -Name "$Name-$location"
  if ($location -eq "menu" -and $Context.Contains("menuBaselineScreenshot") -and $Context.menuBaselineScreenshot) {
    Assert-FlowScreenshotDiff -Context $Context -Step "$Name-visual-return" -ExpectedPath $Context.menuBaselineScreenshot -ActualPath $returnScreenshot -MaxDiff 8
  }
  return $location
}

function Invoke-FlowOpenMenuWebEntry {
  param(
    $Context,
    [hashtable]$Entry
  )

  $name = $Entry.name
  $coord = $Entry.coord
  Assert-FlowClientAlive -Context $Context -Step "$name-before-tap"
  Invoke-FlowTap -Context $Context -Name $name -X $coord.x -Y $coord.y
  $web = Wait-FlowServerEvent -Context $Context -Step "$name-web" -Tag "connect_web_stub" -Path "" -TimeoutSeconds 20 -NoEventFailureClass "tap-no-effect"
  $allowedPaths = @($Entry.paths)
  if ($web.path -notin $allowedPaths) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step $name -Message "Unexpected web path for ${name}: $($web.path). Expected one of: $($allowedPaths -join ', ')."
  }
  Wait-FlowServerQuiet -Context $Context -Step "$name-web-settle" -QuietSeconds 2 -TimeoutSeconds 10
  Assert-FlowClientAlive -Context $Context -Step "$name-after-web"
  Capture-FlowScreenshot -Context $Context -Name $name | Out-Null
  Add-FlowEvent -Context $Context -Type "menu-web-entry-ok" -Data ([ordered]@{
      name = $name
      path = $web.path
    })
}

function Invoke-FlowReturnFromMenuWebEntry {
  param(
    $Context,
    [string]$Name
  )

  Add-FlowEvent -Context $Context -Type "keyevent" -Data ([ordered]@{ name = $Name; key = "BACK" })
  Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "keyevent", "4") -TimeoutSeconds 10 -AllowFailure | Out-Null
  Start-Sleep -Seconds 2
  Invoke-FlowCancelExitConfirmIfPresent -Context $Context | Out-Null
  Wait-FlowServerQuiet -Context $Context -Step "$Name-web-back-settle" -QuietSeconds 2 -TimeoutSeconds 10
  Move-FlowRequestCursorToEnd -Context $Context
  Assert-FlowClientAlive -Context $Context -Step "$Name-after-web-return"
  Capture-FlowScreenshot -Context $Context -Name "$Name-after-web-return" | Out-Null
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

function Invoke-FlowMainmenuBottomButtonsSmoke {
  param($Context)

  $coords = Get-FlowMainmenuRouteCoords
  Start-Sleep -Seconds 2
  Assert-FlowClientAlive -Context $Context -Step "mainmenu-bottom-ready"
  $baseline = Capture-FlowScreenshot -Context $Context -Name "mainmenu-bottom-baseline"
  Move-FlowRequestCursorToEnd -Context $Context

  $entries = @(
    @{ name = "open-mainmenu-deck"; coord = $coords.deck; path = "/connect/app/roundtable/edit"; params = @{ move = "1" }; fields = @{ command = "round_table"; nextScene = 83200 } },
    @{ name = "open-mainmenu-friends"; coord = $coords.friends; path = "/connect/app/menu/friendlist"; fields = @{ command = "friends"; nextScene = 17100 } }
  )

  foreach ($entry in $entries) {
    $params = if ($entry.ContainsKey("params")) { $entry.params } else { @{} }
    Invoke-FlowOpenMainmenuRoute -Context $Context -Name $entry.name -X $entry.coord.x -Y $entry.coord.y -Path $entry.path -Params $params -Fields $entry.fields
    $opened = Join-Path $Context.screenshotsDir "$($entry.name).png"
    Assert-FlowScreenshotDiff -Context $Context -Step "$($entry.name)-visual-open" -ExpectedPath $baseline -ActualPath $opened -MinDiff 20
    Invoke-FlowReturnToMainmenuRetry -Context $Context -Name "return-from-$($entry.name)" -BaselineScreenshot $baseline -AllowedIntermediatePaths @("/connect/app/cardselect/savedeckcard") | Out-Null
  }
}

function Invoke-FlowDeckBuilderEntrySmoke {
  param($Context)

  $coords = Get-FlowMainmenuRouteCoords
  Start-Sleep -Seconds 2
  Assert-FlowClientAlive -Context $Context -Step "deck-builder-entry-ready"
  $mainmenu = Capture-FlowScreenshot -Context $Context -Name "deck-builder-mainmenu"
  Move-FlowRequestCursorToEnd -Context $Context

  Invoke-FlowTap -Context $Context -Name "open-deck-builder" -X $coords.deck.x -Y $coords.deck.y
  $probe = Wait-FlowServerEvent -Context $Context -Step "open-deck-builder-probe" -Tag "connect_app_probe" -Path "/connect/app/roundtable/edit" -Params @{ move = "1" } -TimeoutSeconds 25 -NoEventFailureClass "tap-no-effect"
  $response = Wait-FlowServerEvent -Context $Context -Step "open-deck-builder-response" -Tag "connect_app_response" -Path "/connect/app/roundtable/edit" -Fields @{
    command = "round_table"
    nextScene = 83200
  } -TimeoutSeconds 10
  Start-Sleep -Seconds 3
  Assert-FlowClientAlive -Context $Context -Step "open-deck-builder-after-response"
  $entry = Capture-FlowScreenshot -Context $Context -Name "deck-builder-entry"
  Assert-FlowScreenshotDiff -Context $Context -Step "deck-builder-entry-visual-open" -ExpectedPath $mainmenu -ActualPath $entry -MinDiff 20
  Assert-FlowDeckBuilderEntryVisual -Context $Context -Step "deck-builder-entry-controls-visible" -Path $entry
  Add-FlowEvent -Context $Context -Type "deck-builder-entry-ok" -Data ([ordered]@{
      path = $probe.path
      decryptedParams = $probe.decryptedParams
      response = $response.payload
      nextTarget = [ordered]@{
        name = "leader"
        screen = [ordered]@{ x = 1090; y = 270 }
        expectedBehavior = "change_mode_leader_select"
        expectedRoute = ""
      }
    })
}

function Invoke-FlowDeckBuilderLeaderModeSmoke {
  param($Context)

  Invoke-FlowDeckBuilderEntrySmoke -Context $Context
  $before = Capture-FlowScreenshot -Context $Context -Name "deck-builder-leader-before"
  Move-FlowRequestCursorToEnd -Context $Context

  Invoke-FlowTap -Context $Context -Name "open-deck-builder-leader-mode" -X 1090 -Y 270
  $unexpectedProbe = Wait-FlowServerEventOptional -Context $Context -Step "deck-builder-leader-mode-no-route" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 3
  if ($unexpectedProbe) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step "deck-builder-leader-mode-no-route" -Message "Leader mode unexpectedly emitted $($unexpectedProbe.path)."
  }
  Assert-FlowClientAlive -Context $Context -Step "deck-builder-leader-mode-after-tap"
  $after = Capture-FlowScreenshot -Context $Context -Name "deck-builder-leader-after"
  Assert-FlowScreenshotDiff -Context $Context -Step "deck-builder-leader-mode-visual-change" -ExpectedPath $before -ActualPath $after -MinDiff 8
  Assert-FlowDeckBuilderLeaderModeVisual -Context $Context -Step "deck-builder-leader-mode-visible" -Path $after
  Add-FlowEvent -Context $Context -Type "deck-builder-leader-mode-ok" -Data ([ordered]@{
      target = "leader"
      screen = [ordered]@{ x = 1090; y = 270 }
      expectedBehavior = "change_mode_leader_select"
      expectedRoute = ""
      quietSeconds = 3
      before = $before
      after = $after
    })
}

function Invoke-FlowDeckBuilderEditSmoke {
  param($Context)

  $initialSaveText = [System.IO.File]::ReadAllText($Context.playerSave, [System.Text.Encoding]::UTF8)
  $initialSaveHash = (Get-FileHash -LiteralPath $Context.playerSave -Algorithm SHA256).Hash
  Invoke-FlowDeckBuilderEntrySmoke -Context $Context
  Sync-FlowServerEvents -Context $Context | Out-Null
  $entryResponse = @(
    $Context.requestEvents |
      Where-Object { $_.tag -eq "connect_app_response" -and $_.path -eq "/connect/app/roundtable/edit" } |
      Select-Object -Last 1
  )
  $serialIds = if ($entryResponse.Count -eq 1) { @(Get-FlowProperty -Object $entryResponse[0].payload -Name "ownerCardSerialIds") } else { @() }
  $masterCardIds = if ($entryResponse.Count -eq 1) { @(Get-FlowProperty -Object $entryResponse[0].payload -Name "ownerCardMasterCardIds") } else { @() }
  if (($serialIds -join ",") -ne "1,2" -or ($masterCardIds -join ",") -ne "22,9") {
    Stop-FlowWithFailure -Context $Context -FailureClass "deck-owned-card-mismatch" -Step "deck-builder-edit-fixture" -Message "Expected owned serials 1,2 and masters 22,9; saw serials=$($serialIds -join ',') masters=$($masterCardIds -join ',')."
  }

  $before = Capture-FlowScreenshot -Context $Context -Name "deck-builder-edit-before"

  Move-FlowRequestCursorToEnd -Context $Context
  Invoke-FlowTap -Context $Context -Name "open-deck-builder-card-selection" -X 127 -Y 360
  $openProbe = Wait-FlowServerEventOptional -Context $Context -Step "deck-builder-edit-open-no-route" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 3
  if ($openProbe) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step "deck-builder-edit-open-no-route" -Message "Opening card-selection mode unexpectedly emitted $($openProbe.path)."
  }
  Assert-FlowClientAlive -Context $Context -Step "deck-builder-edit-card-mode-alive"
  $cardMode = Capture-FlowScreenshot -Context $Context -Name "deck-builder-edit-card-mode"
  Assert-FlowScreenshotDiff -Context $Context -Step "deck-builder-edit-card-mode-visible" -ExpectedPath $before -ActualPath $cardMode -MinDiff 8
  if ((Get-FlowDeckBuilderEntryVisualCheck -Path $cardMode).ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step "deck-builder-edit-card-mode-visible" -Message "Card-selection mode still matched the normal DeckScene signature."
  }
  # ponytail: these fixed 1280x720 ROIs cover the closed D3 geometry; replace
  # them with scene-layout geometry if the accepted display baseline changes.
  $candidateEnterDiff = Get-FlowScreenshotRegionDiffScore -ExpectedPath $before -ActualPath $cardMode -RegionX 174 -RegionY 174 -RegionWidth 104 -RegionHeight 146
  if ($null -eq $candidateEnterDiff -or $candidateEnterDiff -lt 20) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step "deck-builder-edit-card-mode-candidate-visible" -Message "The sole serial-2 candidate did not visibly enter its card-mode ROI. diff=$candidateEnterDiff"
  }

  Move-FlowRequestCursorToEnd -Context $Context
  Invoke-FlowTap -Context $Context -Name "select-deck-builder-card-serial-2" -X 226 -Y 247
  $selectProbe = Wait-FlowServerEventOptional -Context $Context -Step "deck-builder-edit-select-no-route" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 3
  if ($selectProbe) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step "deck-builder-edit-select-no-route" -Message "Selecting serial 2 unexpectedly emitted $($selectProbe.path)."
  }
  Assert-FlowClientAlive -Context $Context -Step "deck-builder-edit-card-accepted-alive"
  $cardAccepted = Capture-FlowScreenshot -Context $Context -Name "deck-builder-edit-card-accepted"
  Assert-FlowScreenshotDiff -Context $Context -Step "deck-builder-edit-card-accepted-visible" -ExpectedPath $cardMode -ActualPath $cardAccepted -MinDiff 3
  if ((Get-FlowDeckBuilderEntryVisualCheck -Path $cardAccepted).ok) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step "deck-builder-edit-card-accepted-visible" -Message "Card selection returned to normal DeckScene before the explicit return action."
  }
  $candidateDiff = Get-FlowScreenshotRegionDiffScore -ExpectedPath $cardMode -ActualPath $cardAccepted -RegionX 174 -RegionY 174 -RegionWidth 104 -RegionHeight 146
  if ($null -eq $candidateDiff -or $candidateDiff -lt 20) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step "deck-builder-edit-card-accepted-visible" -Message "The sole serial-2 candidate did not visibly leave its card-mode ROI. diff=$candidateDiff"
  }
  $returnTabDiff = Get-FlowScreenshotRegionDiffScore -ExpectedPath $cardMode -ActualPath $cardAccepted -RegionX 1115 -RegionY 30 -RegionWidth 50 -RegionHeight 660
  if ($null -eq $returnTabDiff -or $returnTabDiff -gt 8) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step "deck-builder-edit-card-mode-retained" -Message "The mode-1 return tab changed before the explicit return action. diff=$returnTabDiff"
  }

  Move-FlowRequestCursorToEnd -Context $Context
  Invoke-FlowTap -Context $Context -Name "return-deck-builder-edit-mode" -X 1144 -Y 360
  $returnProbe = Wait-FlowServerEventOptional -Context $Context -Step "deck-builder-edit-return-no-route" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 3
  if ($returnProbe) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step "deck-builder-edit-return-no-route" -Message "Returning to deck-edit mode unexpectedly emitted $($returnProbe.path)."
  }
  Assert-FlowClientAlive -Context $Context -Step "deck-builder-edit-returned-alive"
  $returned = Capture-FlowScreenshot -Context $Context -Name "deck-builder-edit-returned"
  Assert-FlowScreenshotDiff -Context $Context -Step "deck-builder-edit-returned-visible" -ExpectedPath $cardAccepted -ActualPath $returned -MinDiff 8
  Assert-FlowDeckBuilderEntryVisual -Context $Context -Step "deck-builder-edit-normal-mode-restored" -Path $returned

  $slot0Diff = Get-FlowScreenshotRegionDiffScore -ExpectedPath $before -ActualPath $returned -RegionX 176 -RegionY 5 -RegionWidth 144 -RegionHeight 143
  $slot1Diff = Get-FlowScreenshotRegionDiffScore -ExpectedPath $before -ActualPath $returned -RegionX 335 -RegionY 5 -RegionWidth 144 -RegionHeight 143
  if ($null -eq $slot0Diff -or $slot0Diff -gt 8 -or $null -eq $slot1Diff -or $slot1Diff -lt 20) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step "deck-builder-edit-slot-state" -Message "Expected slot0 stable and slot1 changed. slot0Diff=$slot0Diff slot1Diff=$slot1Diff"
  }

  $finalSaveText = [System.IO.File]::ReadAllText($Context.playerSave, [System.Text.Encoding]::UTF8)
  $finalSaveHash = (Get-FileHash -LiteralPath $Context.playerSave -Algorithm SHA256).Hash
  if ($finalSaveText -cne $initialSaveText -or $finalSaveHash -ne $initialSaveHash) {
    Stop-FlowWithFailure -Context $Context -FailureClass "player-save-mismatch" -Step "deck-builder-edit-save-unchanged" -Message "The artifact player save changed during the client-local D4 edit. before=$initialSaveHash after=$finalSaveHash"
  }
  Add-FlowEvent -Context $Context -Type "deck-builder-edit-ok" -Data ([ordered]@{
      taps = @(
        [ordered]@{ x = 127; y = 360; action = "slider_right" },
        [ordered]@{ x = 226; y = 247; action = "select_serial_2" },
        [ordered]@{ x = 1144; y = 360; action = "slider_left" }
      )
      quietSecondsPerAction = 3
      candidateEnterDiff = $candidateEnterDiff
      candidateDiff = $candidateDiff
      returnTabDiff = $returnTabDiff
      slot0Diff = $slot0Diff
      slot1Diff = $slot1Diff
      playerSaveSha256 = $finalSaveHash
      persisted = $false
    })
}

function Invoke-FlowDeckBuilderSaveSmoke {
  param($Context)

  $initialSaveText = [System.IO.File]::ReadAllText($Context.playerSave, [System.Text.Encoding]::UTF8)
  $initialSaveHash = (Get-FileHash -LiteralPath $Context.playerSave -Algorithm SHA256).Hash
  Invoke-FlowDeckBuilderEditSmoke -Context $Context

  $beforeSave = Capture-FlowScreenshot -Context $Context -Name "deck-builder-save-before"
  Assert-FlowDeckBuilderEntryVisual -Context $Context -Step "deck-builder-save-before-visible" -Path $beforeSave
  Move-FlowRequestCursorToEnd -Context $Context
  $preTapCursor = [int]$Context.requestCursor

  Invoke-FlowTap -Context $Context -Name "decide-deck-builder-save" -X 1090 -Y 95
  $saveProbe = Wait-FlowServerEvent -Context $Context -Step "deck-builder-save-probe" -Tag "connect_app_probe" -Path "/connect/app/cardselect/savedeckcard" -TimeoutSeconds 25 -NoEventFailureClass "tap-no-effect"
  $saveParams = Get-FlowEventDecryptedParams -Event $saveProbe
  if (-not (Test-FlowDeckBuilderSaveParams -Params $saveParams)) {
    $actualParams = $saveParams | ConvertTo-Json -Compress
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step "deck-builder-save-probe" -Message "Expected exact case-sensitive C/lr deck-save params; saw $actualParams."
  }

  $duplicateProbe = Wait-FlowServerEventOptional -Context $Context -Step "deck-builder-save-no-duplicate" -Tag "connect_app_probe" -Path "/connect/app/cardselect/savedeckcard" -TimeoutSeconds 3
  if ($duplicateProbe) {
    Stop-FlowWithFailure -Context $Context -FailureClass "duplicate-route" -Step "deck-builder-save-no-duplicate" -Message "A duplicate deck-save probe was emitted at server line $($duplicateProbe.index)."
  }
  $saveResponse = Wait-FlowServerEvent -Context $Context -Step "deck-builder-save-response" -Tag "connect_app_response" -Path "/connect/app/cardselect/savedeckcard" -TimeoutSeconds 10

  Assert-FlowClientAlive -Context $Context -Step "deck-builder-save-response-alive"
  $afterResponse = Capture-FlowScreenshot -Context $Context -Name "deck-builder-save-response"
  $responseDiff = Get-FlowScreenshotDiffScore -ExpectedPath $beforeSave -ActualPath $afterResponse
  if ($null -eq $responseDiff) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step "deck-builder-save-response-capture" -Message "Could not score the diagnostic post-response screenshot."
  }
  $deckSceneCheck = Get-FlowDeckBuilderEntryVisualCheck -Path $afterResponse

  $events = @(Sync-FlowServerEvents -Context $Context)
  $saveProbes = @($events | Where-Object {
      [int]$_.index -ge $preTapCursor -and
      $_.tag -eq "connect_app_probe" -and
      $_.path -eq "/connect/app/cardselect/savedeckcard"
    })
  if ($saveProbes.Count -ne 1) {
    Stop-FlowWithFailure -Context $Context -FailureClass "duplicate-route" -Step "deck-builder-save-probe-count" -Message "Expected exactly one deck-save probe after the decide cursor; saw $($saveProbes.Count)."
  }
  $followupRequests = @($events | Where-Object {
      [int]$_.index -gt [int]$saveResponse.index -and $_.tag -eq "connect_app_probe" -and $_.path
    } | ForEach-Object {
      [ordered]@{ path = $_.path; decryptedParams = $_.decryptedParams }
    })

  $finalSaveText = [System.IO.File]::ReadAllText($Context.playerSave, [System.Text.Encoding]::UTF8)
  $finalSaveHash = (Get-FileHash -LiteralPath $Context.playerSave -Algorithm SHA256).Hash
  if ($finalSaveText -cne $initialSaveText -or $finalSaveHash -ne $initialSaveHash) {
    Stop-FlowWithFailure -Context $Context -FailureClass "player-save-mismatch" -Step "deck-builder-save-unchanged" -Message "The capture-only D5 request changed the artifact save. before=$initialSaveHash after=$finalSaveHash"
  }

  Add-FlowEvent -Context $Context -Type "deck-builder-save-captured" -Data ([ordered]@{
      request = [ordered]@{
        path = $saveProbe.path
        decryptedParams = $saveParams
        preTapCursor = $preTapCursor
        probeIndex = $saveProbe.index
        countFromPreTapCursor = $saveProbes.Count
      }
      response = $saveResponse.payload
      responseClaim = "diagnostic-only"
      responseScreenshot = $afterResponse
      responseDiff = $responseDiff
      deckSceneClassifier = $deckSceneCheck
      followupRequests = $followupRequests
      playerSaveBeforeSha256 = $initialSaveHash
      playerSaveAfterSha256 = $finalSaveHash
      playerSaveBytesUnchanged = $true
      persisted = $false
    })
}

function Invoke-FlowGachaDrawSmoke {
  param(
    $Context,
    [string]$DrawKind = "friendship"
  )

  $mainmenuCoords = Get-FlowMainmenuRouteCoords
  $gachaCoords = Get-FlowGachaCoords
  Start-Sleep -Seconds 2
  Assert-FlowClientAlive -Context $Context -Step "gacha-draw-ready"
  $baseline = Capture-FlowScreenshot -Context $Context -Name "gacha-draw-mainmenu-baseline"
  Move-FlowRequestCursorToEnd -Context $Context

  $expectedPage = "main"
  Invoke-FlowOpenMainmenuRoute -Context $Context -Name "open-gacha-select" -X $mainmenuCoords.gacha.x -Y $mainmenuCoords.gacha.y -Path "/connect/app/gacha/select/getcontents" -Fields @{ command = "gacha"; nextScene = 9100; gachaPage = $expectedPage }
  $selectScreenshot = Join-Path $Context.screenshotsDir "open-gacha-select.png"
  Assert-FlowScreenshotDiff -Context $Context -Step "open-gacha-select-visual-open" -ExpectedPath $baseline -ActualPath $selectScreenshot -MinDiff 20
  Move-FlowRequestCursorToEnd -Context $Context

  if ($DrawKind -eq "paid") {
    Capture-FlowScreenshot -Context $Context -Name "gacha-main-paid-entry" | Out-Null
  }
  $drawCoord = if ($DrawKind -eq "paid") { $gachaCoords.paidOne } else { $gachaCoords.drawOne }
  $expectedProductId = if ($DrawKind -eq "paid") { "2" } else { "1" }
  $expectedBulk = if ($DrawKind -eq "paid") { "0" } else { "1" }
  $expectedAutoBuild = if ($DrawKind -eq "paid") { "0" } else { "1" }
  Invoke-FlowTap -Context $Context -Name "tap-gacha-$DrawKind-draw-one" -X $drawCoord.x -Y $drawCoord.y
  if ($DrawKind -eq "paid") {
    Start-Sleep -Seconds 1
    Capture-FlowScreenshot -Context $Context -Name "gacha-paid-confirm" | Out-Null
    Invoke-FlowTap -Context $Context -Name "tap-gacha-paid-confirm" -X $gachaCoords.paidConfirm.x -Y $gachaCoords.paidConfirm.y
  }
  $probe = Wait-FlowServerEventOptional -Context $Context -Step "tap-gacha-$DrawKind-draw-one-probe" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 12
  if (-not $probe) {
    Capture-FlowScreenshot -Context $Context -Name "gacha-draw-no-route" | Out-Null
    Stop-FlowWithFailure -Context $Context -FailureClass "tap-no-effect" -Step "tap-gacha-$DrawKind-draw-one" -Message "Tapping the gacha $DrawKind draw candidate did not emit a route."
  }
  if ($probe.path -notmatch "^/connect/app/gacha/") {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step "tap-gacha-$DrawKind-draw-one" -Message "Unexpected route after gacha draw tap: $($probe.path)."
  }
  $probeParams = Get-FlowEventDecryptedParams -Event $probe
  if (-not (Test-FlowGachaBuyParams -Params $probeParams -ProductId $expectedProductId -Bulk $expectedBulk -AutoBuild $expectedAutoBuild)) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step "tap-gacha-$DrawKind-draw-one" -Message "Expected exact gacha params product_id=$expectedProductId, bulk=$expectedBulk, auto_build=$expectedAutoBuild after $DrawKind draw."
  }
  $response = Wait-FlowServerEventOptional -Context $Context -Step "tap-gacha-$DrawKind-draw-one-response" -Tag "connect_app_response" -Path $probe.path -TimeoutSeconds 10
  if (-not $response) {
    Capture-FlowScreenshot -Context $Context -Name "gacha-draw-route-no-response" | Out-Null
    Stop-FlowWithFailure -Context $Context -FailureClass "route-timeout" -Step "tap-gacha-$DrawKind-draw-one-response" -Message "Gacha draw route $($probe.path) emitted but no response log was captured."
  }
  Start-Sleep -Seconds 4
  Assert-FlowClientAlive -Context $Context -Step "tap-gacha-$DrawKind-draw-one-after-response"
  Capture-FlowScreenshot -Context $Context -Name "gacha-draw-after-route" | Out-Null
  Add-FlowEvent -Context $Context -Type "gacha-draw-route-captured" -Data ([ordered]@{
      drawKind = $DrawKind
      path = $probe.path
      decryptedParams = $probeParams
      response = $response.payload
    })
}

function Invoke-FlowGachaResultSmoke {
  param(
    $Context,
    [string]$DrawKind = "friendship"
  )

  $gachaCoords = Get-FlowGachaCoords
  Invoke-FlowGachaDrawSmoke -Context $Context -DrawKind $DrawKind
  $drawScene = Join-Path $Context.screenshotsDir "gacha-draw-after-route.png"
  Move-FlowRequestCursorToEnd -Context $Context

  Invoke-FlowTap -Context $Context -Name "tap-gacha-draw-touch-screen" -X $gachaCoords.touchResult.x -Y $gachaCoords.touchResult.y
  $probe = Wait-FlowServerEventOptional -Context $Context -Step "tap-gacha-draw-touch-screen-probe" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 15
  $response = $null
  if ($probe) {
    if ($probe.path -notmatch "^/connect/app/gacha/") {
      Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step "tap-gacha-draw-touch-screen" -Message "Unexpected route after gacha draw touch: $($probe.path)."
    }
    $response = Wait-FlowServerEventOptional -Context $Context -Step "tap-gacha-draw-touch-screen-response" -Tag "connect_app_response" -Path $probe.path -TimeoutSeconds 10
  }

  Start-Sleep -Seconds 4
  Assert-FlowClientAlive -Context $Context -Step "tap-gacha-draw-touch-screen-after"
  $afterTouch = Capture-FlowScreenshot -Context $Context -Name "gacha-result-after-touch"
  Assert-FlowScreenshotDiff -Context $Context -Step "gacha-result-visual-transition" -ExpectedPath $drawScene -ActualPath $afterTouch -MinDiff 8
  Add-FlowEvent -Context $Context -Type "gacha-result-edge-captured" -Data ([ordered]@{
      route = if ($probe) { $probe.path } else { "" }
      decryptedParams = if ($probe) { $probe.decryptedParams } else { @{} }
      response = if ($response) { $response.payload } else { @{} }
      localTransition = [bool](-not $probe)
    })
}

function Invoke-FlowGachaResultBackSmoke {
  param(
    $Context,
    [string]$DrawKind = "friendship"
  )

  $gachaCoords = Get-FlowGachaCoords
  Invoke-FlowGachaResultSmoke -Context $Context -DrawKind $DrawKind
  $resultScreenshot = Join-Path $Context.screenshotsDir "gacha-result-after-touch.png"
  Move-FlowRequestCursorToEnd -Context $Context

  Invoke-FlowTap -Context $Context -Name "tap-gacha-result-back" -X $gachaCoords.resultBack.x -Y $gachaCoords.resultBack.y
  $probe = Wait-FlowServerEventOptional -Context $Context -Step "tap-gacha-result-back-probe" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 12
  $mode = "local"
  $response = $null
  if ($probe) {
    if ($probe.path -eq "/connect/app/gacha/select/getcontents") {
      $mode = "gacha-select"
      $response = Wait-FlowServerEvent -Context $Context -Step "tap-gacha-result-back-select-response" -Tag "connect_app_response" -Path $probe.path -Fields @{ command = "gacha"; nextScene = 9100 } -TimeoutSeconds 10
    } elseif ($probe.path -eq "/connect/app/mainmenu") {
      $mode = "mainmenu"
      $response = Wait-FlowServerEvent -Context $Context -Step "tap-gacha-result-back-mainmenu-response" -Tag "connect_app_response" -Path $probe.path -TimeoutSeconds 10
    } else {
      Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step "tap-gacha-result-back" -Message "Unexpected route after gacha result back: $($probe.path)."
    }
  } else {
    Wait-FlowServerQuiet -Context $Context -Step "tap-gacha-result-back-local-settle" -QuietSeconds 2 -TimeoutSeconds 10
    Move-FlowRequestCursorToEnd -Context $Context
  }

  Start-Sleep -Seconds 3
  Assert-FlowClientAlive -Context $Context -Step "tap-gacha-result-back-after"
  $afterBack = Capture-FlowScreenshot -Context $Context -Name "gacha-result-after-back"
  Assert-FlowScreenshotDiff -Context $Context -Step "gacha-result-back-visual-transition" -ExpectedPath $resultScreenshot -ActualPath $afterBack -MinDiff 8
  Add-FlowEvent -Context $Context -Type "gacha-result-back-captured" -Data ([ordered]@{
      mode = $mode
      route = if ($probe) { $probe.path } else { "" }
      decryptedParams = if ($probe) { $probe.decryptedParams } else { @{} }
      response = if ($response) { $response.payload } else { @{} }
    })
}

function Invoke-FlowGachaPaidRetrySmoke {
  param($Context)

  $gachaCoords = Get-FlowGachaCoords
  Invoke-FlowGachaResultSmoke -Context $Context -DrawKind "paid"
  $firstResult = Join-Path $Context.screenshotsDir "gacha-result-after-touch.png"
  Move-FlowRequestCursorToEnd -Context $Context

  Invoke-FlowTap -Context $Context -Name "tap-gacha-paid-result-retry" -X $gachaCoords.resultRetry.x -Y $gachaCoords.resultRetry.y
  Start-Sleep -Seconds 1
  $retryConfirm = Capture-FlowScreenshot -Context $Context -Name "gacha-paid-retry-confirm"
  Assert-FlowScreenshotDiff -Context $Context -Step "gacha-paid-retry-confirm-visible" -ExpectedPath $firstResult -ActualPath $retryConfirm -MinDiff 8

  Invoke-FlowTap -Context $Context -Name "tap-gacha-paid-retry-confirm" -X $gachaCoords.paidConfirm.x -Y $gachaCoords.paidConfirm.y
  $retryProbe = Wait-FlowServerEvent -Context $Context -Step "gacha-paid-retry-probe" -Tag "connect_app_probe" -Path "/connect/app/gacha/buy" -Params @{
    product_id = "2"
    bulk = "0"
    auto_build = "0"
  } -TimeoutSeconds 15 -NoEventFailureClass "tap-no-effect"
  $retryResponse = Wait-FlowServerEvent -Context $Context -Step "gacha-paid-retry-response" -Tag "connect_app_response" -Path "/connect/app/gacha/buy" -Fields @{
    source = "gacha buy settlement"
    command = "gacha_buy"
    nextScene = 9200
    productId = 2
    bulk = 1
    friendshipBefore = 0
    friendshipCost = 0
    friendshipAfter = 0
    mcBefore = 300
    mcCost = 300
    mcAfter = 0
    drawnSerialId = 3
    drawnMasterCardId = 9
    ownerCardCount = 3
    cardsDrawn = 2
    saved = $true
  } -TimeoutSeconds 10

  Start-Sleep -Seconds 4
  Assert-FlowClientAlive -Context $Context -Step "gacha-paid-retry-after-response"
  $retryDraw = Capture-FlowScreenshot -Context $Context -Name "gacha-paid-retry-draw-after-route"
  Assert-FlowScreenshotDiff -Context $Context -Step "gacha-paid-retry-draw-transition" -ExpectedPath $firstResult -ActualPath $retryDraw -MinDiff 8
  Move-FlowRequestCursorToEnd -Context $Context

  Invoke-FlowTap -Context $Context -Name "tap-gacha-paid-retry-draw-touch-screen" -X $gachaCoords.touchResult.x -Y $gachaCoords.touchResult.y
  $resultProbe = Wait-FlowServerEventOptional -Context $Context -Step "gacha-paid-retry-result-probe" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 15
  if ($resultProbe) {
    Stop-FlowWithFailure -Context $Context -FailureClass "route-param-mismatch" -Step "gacha-paid-retry-result" -Message "The accepted draw-to-result edge is local, but retry emitted route $($resultProbe.path)."
  }

  Start-Sleep -Seconds 4
  Assert-FlowClientAlive -Context $Context -Step "gacha-paid-retry-result-after"
  $secondResult = Capture-FlowScreenshot -Context $Context -Name "gacha-paid-retry-result"
  Assert-FlowScreenshotDiff -Context $Context -Step "gacha-paid-retry-result-transition" -ExpectedPath $retryDraw -ActualPath $secondResult -MinDiff 8
  Assert-FlowGachaPaidRetryPlayerSave -Context $Context
  Add-FlowEvent -Context $Context -Type "gacha-paid-retry-edge-ok" -Data ([ordered]@{
      route = $retryProbe.path
      decryptedParams = $retryProbe.decryptedParams
      response = $retryResponse.payload
      resultRoute = ""
      localResultTransition = $true
    })
}

function Invoke-FlowGachaSettlementDeckSmoke {
  param($Context)

  $mainmenuCoords = Get-FlowMainmenuRouteCoords
  Invoke-FlowGachaResultBackSmoke -Context $Context
  Sync-FlowServerEvents -Context $Context | Out-Null
  $buyResponse = @(
    $Context.requestEvents |
      Where-Object { $_.tag -eq "connect_app_response" -and $_.path -eq "/connect/app/gacha/buy" } |
      Select-Object -Last 1
  )
  $expectedBuyFields = @{
    source = "gacha buy settlement"
    command = "gacha_buy"
    nextScene = 9200
    productId = 1
    bulk = 1
    friendshipBefore = 400
    friendshipCost = 200
    friendshipAfter = 200
    drawnSerialId = 2
    drawnMasterCardId = 9
    ownerCardCount = 2
    cardsDrawn = 1
    saved = $true
  }
  if ($buyResponse.Count -eq 0 -or -not (Test-FlowExpectedMap -Actual $buyResponse[0].payload -Expected $expectedBuyFields)) {
    Stop-FlowWithFailure -Context $Context -FailureClass "gacha-settlement-response-mismatch" -Step "gacha-settlement-buy-response" -Message "Gacha buy settlement response was missing or did not match expected settlement fields."
  }
  Assert-FlowGachaSettlementPlayerSave -Context $Context

  $mainmenuBaseline = Join-Path $Context.screenshotsDir "gacha-draw-mainmenu-baseline.png"
  $returnedMainmenu = Invoke-FlowReturnToMainmenuRetry -Context $Context -Name "return-from-gacha-select-after-settlement" -BaselineScreenshot $mainmenuBaseline
  Move-FlowRequestCursorToEnd -Context $Context

  Invoke-FlowTap -Context $Context -Name "open-deck-after-gacha-settlement" -X $mainmenuCoords.deck.x -Y $mainmenuCoords.deck.y
  $deckProbe = Wait-FlowServerEvent -Context $Context -Step "open-deck-after-gacha-settlement-probe" -Tag "connect_app_probe" -Path "/connect/app/roundtable/edit" -Params @{ move = "1" } -TimeoutSeconds 25 -NoEventFailureClass "tap-no-effect"
  $deckResponse = Wait-FlowServerEvent -Context $Context -Step "open-deck-after-gacha-settlement-response" -Tag "connect_app_response" -Path "/connect/app/roundtable/edit" -Fields @{
    command = "round_table"
    nextScene = 83200
    ownerCardCount = 2
  } -TimeoutSeconds 10
  Start-Sleep -Seconds 3
  Assert-FlowClientAlive -Context $Context -Step "open-deck-after-gacha-settlement-after-response"
  Capture-FlowScreenshot -Context $Context -Name "open-deck-after-gacha-settlement" | Out-Null
  Add-FlowEvent -Context $Context -Type "deck-route-after-gacha-settlement" -Data ([ordered]@{
      path = $deckProbe.path
      decryptedParams = $deckProbe.decryptedParams
      response = $deckResponse.payload
    })
  $serialIds = @(Get-FlowProperty -Object $deckResponse.payload -Name "ownerCardSerialIds")
  $masterCardIds = @(Get-FlowProperty -Object $deckResponse.payload -Name "ownerCardMasterCardIds")
  if (-not ($serialIds -contains 2) -or -not ($masterCardIds -contains 9)) {
    Stop-FlowWithFailure -Context $Context -FailureClass "deck-owned-card-mismatch" -Step "deck-after-gacha-settlement-response" -Message "Deck entry did not report the drawn card. serialIds=$($serialIds -join ',') masterCardIds=$($masterCardIds -join ',')."
  }
  $deckScreenshot = Join-Path $Context.screenshotsDir "open-deck-after-gacha-settlement.png"
  Assert-FlowScreenshotDiff -Context $Context -Step "open-deck-after-gacha-settlement-visual-open" -ExpectedPath $returnedMainmenu -ActualPath $deckScreenshot -MinDiff 20
  Add-FlowEvent -Context $Context -Type "gacha-settlement-deck-ok" -Data ([ordered]@{
      serialId = 2
      masterCardId = 9
      friendshipPoint = 200
      ownerCardSerialIds = $serialIds
      ownerCardMasterCardIds = $masterCardIds
    })
}

function Invoke-FlowGachaPaidSettlementDeckSmoke {
  param($Context)

  $mainmenuCoords = Get-FlowMainmenuRouteCoords
  Invoke-FlowGachaResultBackSmoke -Context $Context -DrawKind "paid"
  Sync-FlowServerEvents -Context $Context | Out-Null
  $buyResponse = @(
    $Context.requestEvents |
      Where-Object { $_.tag -eq "connect_app_response" -and $_.path -eq "/connect/app/gacha/buy" } |
      Select-Object -Last 1
  )
  $expectedBuyFields = @{
    source = "gacha buy settlement"
    command = "gacha_buy"
    nextScene = 9200
    productId = 2
    bulk = 1
    friendshipBefore = 0
    friendshipCost = 0
    friendshipAfter = 0
    mcBefore = 300
    mcCost = 300
    mcAfter = 0
    drawnSerialId = 2
    drawnMasterCardId = 9
    ownerCardCount = 2
    cardsDrawn = 1
    saved = $true
  }
  if ($buyResponse.Count -eq 0 -or -not (Test-FlowExpectedMap -Actual $buyResponse[0].payload -Expected $expectedBuyFields)) {
    Stop-FlowWithFailure -Context $Context -FailureClass "gacha-paid-settlement-response-mismatch" -Step "gacha-paid-settlement-buy-response" -Message "Paid gacha buy settlement response was missing or did not match expected settlement fields."
  }
  Assert-FlowGachaPaidSettlementPlayerSave -Context $Context

  $mainmenuBaseline = Join-Path $Context.screenshotsDir "gacha-draw-mainmenu-baseline.png"
  $returnedMainmenu = Invoke-FlowReturnToMainmenuRetry -Context $Context -Name "return-from-paid-gacha-select-after-settlement" -BaselineScreenshot $mainmenuBaseline
  Move-FlowRequestCursorToEnd -Context $Context

  Invoke-FlowTap -Context $Context -Name "open-deck-after-paid-gacha-settlement" -X $mainmenuCoords.deck.x -Y $mainmenuCoords.deck.y
  $deckProbe = Wait-FlowServerEvent -Context $Context -Step "open-deck-after-paid-gacha-settlement-probe" -Tag "connect_app_probe" -Path "/connect/app/roundtable/edit" -Params @{ move = "1" } -TimeoutSeconds 25 -NoEventFailureClass "tap-no-effect"
  $deckResponse = Wait-FlowServerEvent -Context $Context -Step "open-deck-after-paid-gacha-settlement-response" -Tag "connect_app_response" -Path "/connect/app/roundtable/edit" -Fields @{
    command = "round_table"
    nextScene = 83200
    ownerCardCount = 2
  } -TimeoutSeconds 10
  Start-Sleep -Seconds 3
  Assert-FlowClientAlive -Context $Context -Step "open-deck-after-paid-gacha-settlement-after-response"
  Capture-FlowScreenshot -Context $Context -Name "open-deck-after-paid-gacha-settlement" | Out-Null
  Add-FlowEvent -Context $Context -Type "deck-route-after-paid-gacha-settlement" -Data ([ordered]@{
      path = $deckProbe.path
      decryptedParams = $deckProbe.decryptedParams
      response = $deckResponse.payload
    })
  $serialIds = @(Get-FlowProperty -Object $deckResponse.payload -Name "ownerCardSerialIds")
  $masterCardIds = @(Get-FlowProperty -Object $deckResponse.payload -Name "ownerCardMasterCardIds")
  if (-not ($serialIds -contains 2) -or -not ($masterCardIds -contains 9)) {
    Stop-FlowWithFailure -Context $Context -FailureClass "deck-owned-card-mismatch" -Step "deck-after-paid-gacha-settlement-response" -Message "Deck entry did not report the paid drawn card. serialIds=$($serialIds -join ',') masterCardIds=$($masterCardIds -join ',')."
  }
  $deckScreenshot = Join-Path $Context.screenshotsDir "open-deck-after-paid-gacha-settlement.png"
  Assert-FlowScreenshotDiff -Context $Context -Step "open-deck-after-paid-gacha-settlement-visual-open" -ExpectedPath $returnedMainmenu -ActualPath $deckScreenshot -MinDiff 20
  Add-FlowEvent -Context $Context -Type "gacha-paid-settlement-deck-ok" -Data ([ordered]@{
      serialId = 2
      masterCardId = 9
      mc = 0
      friendshipPoint = 0
      ownerCardSerialIds = $serialIds
      ownerCardMasterCardIds = $masterCardIds
    })
}

function Invoke-FlowMenuButtonsRouteSmoke {
  param(
    $Context,
    [string[]]$EntryNames = @()
  )

  $coords = Get-FlowMenuPageCoords
  Invoke-FlowOpenMenuListFromMainmenu -Context $Context -Name "open-menu-buttons-menu"

  $nativeEntries = @(
    @{ name = "open-menu-invite"; coord = $coords.invite; paths = @("/connect/app/menu/other_list", "/connect/app/menu/invite_friend", "/connect/app/menu/player_search"); fieldsByPath = @{ "/connect/app/menu/other_list" = @{ command = "other_list"; nextScene = 20100 }; "/connect/app/menu/invite_friend" = @{ command = "invide"; nextScene = 32100 }; "/connect/app/menu/player_search" = @{ command = "friend_search"; nextScene = 22300 } } },
    @{ name = "open-menu-playerinfo"; coord = $coords.playerInfo; paths = @("/connect/app/menu/playerinfo"); fields = @{ command = "p_info"; nextScene = 26100 } },
    @{ name = "open-menu-story"; coord = $coords.story; paths = @("/connect/app/story/getoutline"); fields = @{ command = "story"; nextScene = 3100 } },
    @{ name = "open-menu-town-event"; coord = $coords.townEvent; paths = @("/connect/app/menu/gettownevent", "/connect/app/menu/towneventlist"); fieldsByPath = @{ "/connect/app/menu/gettownevent" = @{ command = "town_event"; nextScene = 28100 }; "/connect/app/menu/towneventlist" = @{ command = "town_event"; nextScene = 28100 } } },
    @{ name = "open-menu-battle-history"; coord = $coords.battleHistory; paths = @("/connect/app/menu/battlehistory"); fields = @{ command = "b_history"; nextScene = 25100 } },
    @{ name = "open-menu-ranking"; coord = $coords.ranking; paths = @("/connect/app/menu/ranking/ranking_arena", "/connect/app/menu/ranking/rankingevent", "/connect/app/ranking/ranking"); fieldsByPath = @{ "/connect/app/menu/ranking/ranking_arena" = @{ command = "ranking"; nextScene = 27100 }; "/connect/app/menu/ranking/rankingevent" = @{ command = "ranking"; nextScene = 27100 }; "/connect/app/ranking/ranking" = @{ command = "ranking"; nextScene = 27100 } } },
    @{ name = "open-menu-option"; coord = $coords.option; paths = @("/connect/app/menu/chksnd"); fields = @{ command = "option"; nextScene = 33000 }; allowLocal = $true },
    @{ name = "open-menu-item"; coord = $coords.item; paths = @("/connect/app/item/havelist"); fields = @{ command = "item"; nextScene = 30100 }; allowLocal = $true },
    @{ name = "open-menu-card-collection"; coord = $coords.cardCollection; paths = @("/connect/app/menu/cardcollection"); fields = @{ command = "c_collection"; nextScene = 23100 } },
    @{ name = "open-menu-parts-list"; coord = $coords.partsList; paths = @("/connect/app/menu/haveparts"); fields = @{ command = "partslist"; nextScene = 31100 } },
    @{ name = "open-menu-fairy"; coord = $coords.fairy; paths = @("/connect/app/menu/fairyselect"); fields = @{ command = "fairy"; nextScene = 29200 } }
  )

  $selectedNativeEntries = $nativeEntries
  if ($EntryNames.Count -gt 0) {
    $selectedNativeEntries = @($nativeEntries | Where-Object { $_.name -in $EntryNames })
  }

  foreach ($entry in $selectedNativeEntries) {
    Invoke-FlowOpenMenuNativeEntry -Context $Context -Entry $entry | Out-Null
    $location = Invoke-FlowReturnFromMenuEntry -Context $Context -Name "return-from-$($entry.name)"
    if ($location -eq "mainmenu") {
      Invoke-FlowOpenMenuListFromMainmenu -Context $Context -Name "reopen-menu-after-$($entry.name)"
    }
  }

  $webEntries = @(
    @{ name = "open-menu-update-history"; coord = $coords.updateHistory; paths = @("/connect/web/") },
    @{ name = "open-menu-help"; coord = $coords.help; paths = @("/connect/web/help") }
  )

  $selectedWebEntries = $webEntries
  if ($EntryNames.Count -gt 0) {
    $selectedWebEntries = @($webEntries | Where-Object { $_.name -in $EntryNames })
  }

  foreach ($entry in $selectedWebEntries) {
    Invoke-FlowOpenMenuWebEntry -Context $Context -Entry $entry
    Invoke-FlowReturnFromMenuWebEntry -Context $Context -Name "return-from-$($entry.name)"
    Ensure-FlowMenuListVisible -Context $Context -Name "ensure-menu-after-$($entry.name)"
  }
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
  $scale = [double]$Context.coordinateScale
  $deviceX = [int][Math]::Round($X * $scale)
  $deviceY = [int][Math]::Round($Y * $scale)
  Add-FlowEvent -Context $Context -Type "tap" -Data ([ordered]@{ name = $Name; x = $X; y = $Y; deviceX = $deviceX; deviceY = $deviceY; coordinateScale = $scale; fast = $true })
  $stage = Invoke-Adb -Arguments @("-s", $Context.serial, "shell", "input", "tap", "$deviceX", "$deviceY") -TimeoutSeconds 10 -AllowFailure
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
    fairyChallenge = @{ x = 1090; y = 95 }
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

function Invoke-FlowFairyBattleSmoke {
  param($Context)

  $coords = Enter-FlowExplorationArea0Main -Context $Context
  Move-FlowRequestCursorToEnd -Context $Context

  Invoke-FlowFastTapThenWaitProbe -Context $Context -Name "fairy-encounter-forward" -X $coords.explorationForward.x -Y $coords.explorationForward.y -Path "/connect/app/exploration/explore" -Params @{ area_id = "0"; floor_id = "1" } -TimeoutSeconds 25 | Out-Null
  Wait-FlowServerEvent -Context $Context -Step "fairy-encounter-forward-response" -Tag "connect_app_response" -Path "/connect/app/exploration/explore" -Fields @{
    regionId = 0
    floorId = 2
    areaNo = 1
    movesDone = 6
    progress = 60
    fairyEncounter = $true
    fairyEncounterRate = 100
    fairySerialId = "100001"
    fairyMasterBossId = 30024
    fairyLevel = 18
    fairyMaxHp = 6000
  } -TimeoutSeconds 10 | Out-Null
  Start-Sleep -Seconds 4
  Assert-FlowClientAlive -Context $Context -Step "fairy-encounter-visible"
  $fairyScreenshot = Capture-FlowScreenshot -Context $Context -Name "fairy-encounter"
  Move-FlowRequestCursorToEnd -Context $Context

  Invoke-FlowTap -Context $Context -Name "fairy-challenge" -X $coords.fairyChallenge.x -Y $coords.fairyChallenge.y
  $battleProbe = Wait-FlowServerEvent -Context $Context -Step "fairy-challenge-probe" -Tag "connect_app_probe" -Path "/connect/app/exploration/fairybattle" -Params @{
    user_id = "1"
    serial_id = "100001"
  } -TimeoutSeconds 25 -NoEventFailureClass "tap-no-effect"
  $battleResponse = Wait-FlowServerEvent -Context $Context -Step "fairy-challenge-response" -Tag "connect_app_response" -Path "/connect/app/exploration/fairybattle" -Fields @{
    source = "local fairy battle settlement"
    nextScene = 4100
    battleScene = 4301
    resultScene = 4420
    explorationEventType = 18
    requestedSerialId = "100001"
    fairyMasterBossId = 30024
    enemyBattleType = 30024
    enemyBossImageId = 600
    fairyLevel = 18
    fairyInitialHp = 6000
    fairyCurrentHp = 0
    fairyMaxHp = 6000
    fairyAttackPower = 1000
    playerMaxHp = 5620
    playerRemainingHp = 4620
    playerWon = $true
    winner = 1
    rounds = 2
    playerDamage = 6000
    fairyDamage = 1000
    goldBefore = 18
    goldReward = 777
    goldAfter = 795
    expBefore = 3
    expReward = 4
    expAfter = 7
    levelBefore = 1
    levelAfter = 1
    saved = $true
  } -TimeoutSeconds 10

  Start-Sleep -Milliseconds 200
  $battleEarly = Capture-FlowScreenshot -Context $Context -Name "fairy-battle-0200ms"
  Start-Sleep -Milliseconds 800
  Capture-FlowScreenshot -Context $Context -Name "fairy-battle-1000ms" | Out-Null
  Start-Sleep -Seconds 3
  $battleFourSeconds = Capture-FlowScreenshot -Context $Context -Name "fairy-battle-4000ms"
  Start-Sleep -Seconds 6
  $battleTenSeconds = Capture-FlowScreenshot -Context $Context -Name "fairy-battle-10000ms"
  Start-Sleep -Seconds 8
  $battleEighteenSeconds = Capture-FlowScreenshot -Context $Context -Name "fairy-battle-18000ms"
  Assert-FlowClientAlive -Context $Context -Step "fairy-battle-after-response"

  $settledSave = Read-FlowPlayerSave -Context $Context -Step "fairy-battle-settlement-save"
  $settledFairy = Get-FlowProperty -Object (Get-FlowProperty -Object (Get-FlowProperty -Object $settledSave -Name "battle") -Name "fairy") -Name "active"
  $history = @((Get-FlowProperty -Object (Get-FlowProperty -Object (Get-FlowProperty -Object $settledSave -Name "battle") -Name "fairy") -Name "history"))
  $historyTail = if ($history.Count -gt 0) { $history[-1] } else { $null }
  $saveChecks = [ordered]@{
    battleWins = Get-FlowProperty -Object (Get-FlowProperty -Object $settledSave -Name "battle") -Name "wins"
    activeFairy = $settledFairy
    gold = Get-FlowProperty -Object (Get-FlowProperty -Object $settledSave -Name "currencies") -Name "gold"
    exp = Get-FlowProperty -Object (Get-FlowProperty -Object $settledSave -Name "profile") -Name "exp"
    historyWon = Get-FlowProperty -Object $historyTail -Name "won"
    historyRewardGold = Get-FlowProperty -Object $historyTail -Name "rewardGold"
    historyRewardExp = Get-FlowProperty -Object $historyTail -Name "rewardExp"
  }
  if ([int]$saveChecks.battleWins -ne 1 -or $null -ne $saveChecks.activeFairy -or [int]$saveChecks.gold -ne 795 -or [int]$saveChecks.exp -ne 7 -or $saveChecks.historyWon -ne $true -or [int]$saveChecks.historyRewardGold -ne 777 -or [int]$saveChecks.historyRewardExp -ne 4) {
    Stop-FlowWithFailure -Context $Context -FailureClass "save-state-mismatch" -Step "fairy-battle-settlement-save" -Message "Fairy battle save did not match the logged settlement: $($saveChecks | ConvertTo-Json -Compress -Depth 5)"
  }

  $earlyDiff = Get-FlowScreenshotDiffScore -ExpectedPath $fairyScreenshot -ActualPath $battleEarly
  $fourSecondDiff = Get-FlowScreenshotDiffScore -ExpectedPath $fairyScreenshot -ActualPath $battleFourSeconds
  $tenSecondDiff = Get-FlowScreenshotDiffScore -ExpectedPath $fairyScreenshot -ActualPath $battleTenSeconds
  $diffValues = @($earlyDiff, $fourSecondDiff, $tenSecondDiff) | Where-Object { $null -ne $_ }
  $eighteenSecondDiff = Get-FlowScreenshotDiffScore -ExpectedPath $fairyScreenshot -ActualPath $battleEighteenSeconds
  $diffValues = (@($diffValues) + @($eighteenSecondDiff)) | Where-Object { $null -ne $_ }
  $maxDiff = if (@($diffValues).Count -gt 0) {
    ($diffValues | Measure-Object -Maximum).Maximum
  } else {
    $null
  }
  if ($null -eq $maxDiff -or [double]$maxDiff -lt 20) {
    Stop-FlowWithFailure -Context $Context -FailureClass "visual-state-mismatch" -Step "fairy-battle-visual-transition" -Message "The accepted fairybattle response did not visibly leave the fairy encounter page. maxDiff=$maxDiff"
  }
  if ($null -eq $eighteenSecondDiff -or [double]$eighteenSecondDiff -lt 5) {
    Stop-FlowWithFailure -Context $Context -FailureClass "stale-fairy-event" -Step "fairy-battle-post-result-state" -Message "The settled battle replayed or retained the pre-battle fairy encounter surface. eighteenSecondDiff=$eighteenSecondDiff"
  }
  Add-FlowEvent -Context $Context -Type "fairy-battle-edge-captured" -Data ([ordered]@{
      request = [ordered]@{ path = $battleProbe.path; decryptedParams = $battleProbe.decryptedParams }
      response = $battleResponse.payload
      scenePath = @(4100, 4301, 4420)
      screenshots = @($battleEarly, $battleFourSeconds, $battleTenSeconds, $battleEighteenSeconds)
      diffFromFairy = [ordered]@{ early = $earlyDiff; fourSeconds = $fourSecondDiff; tenSeconds = $tenSecondDiff; eighteenSeconds = $eighteenSecondDiff; maximum = $maxDiff }
      settlementSave = $saveChecks
      settlementClaim = "save-verified"
    })
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
      '[2026-01-01T00:00:09.100Z] connect_app_response {"path":"/connect/app/town/pointsetting","source":"minimal town pointsetting","nextScene":2100,"requestedAp":3,"requestedBc":0,"apAllocated":3,"bcAllocated":0,"remainingAbilityPoints":0,"apCurrent":28,"apMax":28,"bcCurrent":25,"bcMax":25,"abilityPoints":0,"saved":true}',
      '[2026-01-01T00:00:10.000Z] connect_app_response {"path":"/connect/app/gacha/buy","source":"gacha buy settlement","command":"gacha_buy","nextScene":9200,"productId":1,"bulk":1,"friendshipBefore":400,"friendshipCost":200,"friendshipAfter":200,"drawnSerialId":2,"drawnMasterCardId":9,"ownerCardCount":2,"cardsDrawn":1,"saved":true}',
      '[2026-01-01T00:00:10.900Z] connect_app_probe {"path":"/connect/app/roundtable/edit","decryptedParams":{"move":"1"}}',
      '[2026-01-01T00:00:11.000Z] connect_app_response {"path":"/connect/app/roundtable/edit","command":"round_table","nextScene":83200,"ownerCardCount":2,"ownerCardSerialIds":[1,2],"ownerCardMasterCardIds":[22,9]}',
      '[2026-01-01T00:00:12.000Z] connect_app_response {"path":"/connect/app/gacha/buy","source":"gacha buy settlement","command":"gacha_buy","nextScene":9200,"productId":2,"bulk":1,"friendshipBefore":0,"friendshipCost":0,"friendshipAfter":0,"mcBefore":300,"mcCost":300,"mcAfter":0,"drawnSerialId":2,"drawnMasterCardId":9,"ownerCardCount":2,"cardsDrawn":1,"saved":true}',
      '[2026-01-01T00:00:13.000Z] connect_app_probe {"path":"/connect/app/exploration/fairybattle","decryptedParams":{"user_id":"1","serial_id":"100001"}}',
      '[2026-01-01T00:00:13.100Z] connect_app_response {"path":"/connect/app/exploration/fairybattle","source":"local fairy battle settlement","nextScene":4100,"battleScene":4301,"resultScene":4420,"explorationEventType":18,"requestedSerialId":"100001","fairyMasterBossId":30024,"enemyBattleType":30024,"enemyBossImageId":600,"fairyLevel":18,"fairyInitialHp":6000,"fairyCurrentHp":0,"fairyMaxHp":6000,"fairyAttackPower":1000,"playerMaxHp":5620,"playerRemainingHp":4620,"playerWon":true,"winner":1,"rounds":2,"playerDamage":6000,"fairyDamage":1000,"goldBefore":18,"goldReward":777,"goldAfter":795,"expBefore":3,"expReward":4,"expAfter":7,"levelBefore":1,"levelAfter":1,"saved":true}'
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
    Set-FlowDeckBuilderEditPlayerSave -Context $ctx
    $deckEditSave = Read-FlowPlayerSave -Context $ctx -Step "self-deck-builder-edit-seed"
    $deckEditSerials = @($deckEditSave.cards.instances | ForEach-Object { [int]$_.serialId })
    $deckEditMasters = @($deckEditSave.cards.instances | ForEach-Object { [int]$_.masterCardId })
    $deckEditActiveDeck = @($deckEditSave.cards.decks | Where-Object { $_.id -eq $deckEditSave.cards.activeDeckId } | Select-Object -First 1)
    if (
      ($deckEditSerials -join ",") -ne "1,2" -or
      ($deckEditMasters -join ",") -ne "22,9" -or
      $deckEditActiveDeck.Count -ne 1 -or
      (@($deckEditActiveDeck[0].cardInstanceIds) -join ",") -ne "1" -or
      [int]$deckEditSave.profile.leaderSerialId -ne 1 -or
      [int]$deckEditSave.cards.count -ne 2 -or
      @($deckEditSave.gacha.history).Count -ne 0
    ) {
      throw "deck-builder edit seed does not preserve owned 1,2 / active deck 1 / leader 1 / untouched history"
    }
    $deckSaveCards = "1,2,empty,empty,empty,empty,empty,empty,empty,empty,empty,empty"
    $deckSaveValid = @{ C = $deckSaveCards; lr = "1" }
    $deckSaveExtra = @{ C = $deckSaveCards; lr = "1"; extra = "1" }
    $deckSaveWrongCase = @{ c = $deckSaveCards; lr = "1" }
    $deckSaveWrongValue = @{ C = $deckSaveCards; lr = "2" }
    if (-not (Test-FlowDeckBuilderSaveParams -Params $deckSaveValid)) {
      throw "deck-builder save param predicate rejected the valid exact fixture"
    }
    if (
      (Test-FlowDeckBuilderSaveParams -Params $deckSaveExtra) -or
      (Test-FlowDeckBuilderSaveParams -Params $deckSaveWrongCase) -or
      (Test-FlowDeckBuilderSaveParams -Params $deckSaveWrongValue)
    ) {
      throw "deck-builder save param predicate accepted an extra-key, wrong-case, or wrong-value fixture"
    }
    $gachaFriendshipParams = @{ product_id = "1"; bulk = "1"; auto_build = "1" }
    $gachaPaidParams = @{ product_id = "2"; bulk = "0"; auto_build = "0" }
    $gachaExtraParams = @{ product_id = "1"; bulk = "1"; auto_build = "1"; extra = "1" }
    if (
      -not (Test-FlowGachaBuyParams -Params $gachaFriendshipParams -ProductId "1" -Bulk "1" -AutoBuild "1") -or
      -not (Test-FlowGachaBuyParams -Params $gachaPaidParams -ProductId "2" -Bulk "0" -AutoBuild "0")
    ) {
      throw "gacha buy param predicate rejected an accepted friendship or paid fixture"
    }
    if (
      (Test-FlowGachaBuyParams -Params $gachaExtraParams -ProductId "1" -Bulk "1" -AutoBuild "1") -or
      (Test-FlowGachaBuyParams -Params $gachaPaidParams -ProductId "2" -Bulk "1" -AutoBuild "1")
    ) {
      throw "gacha buy param predicate accepted an extra-key or wrong-mode fixture"
    }
    Set-FlowGachaSettlementPlayerSave -Context $ctx
    $gachaSave = Read-FlowPlayerSave -Context $ctx -Step "self-gacha-settlement-before"
    $drawnCard = [pscustomobject]@{
      serialId = 2
      masterCardId = 9
      holography = 0
      hp = 450
      power = 520
      critical = 0
      level = 1
      maxLevel = 30
      exp = 0
      maxExp = 1800
      nextExp = 60
      expDiff = 0
      expPercent = 0
      salePrice = 120
      materialPrice = 80
      evolutionPrice = 100
      plusLimitCount = 0
      limitOver = 0
    }
    $gachaSave.currencies.friendshipPoint = 200
    $gachaSave.cards.instances += $drawnCard
    $gachaSave.cards.count = 2
    $gachaSave.stats.cardsDrawn = 1
    $gachaSave.gacha.history += [pscustomobject]@{ productId = 1; bulk = 1; serialId = 2; masterCardId = 9 }
    [System.IO.File]::WriteAllText($ctx.playerSave, ($gachaSave | ConvertTo-Json -Depth 40) + [Environment]::NewLine, $utf8NoBom)
    Assert-FlowGachaSettlementPlayerSave -Context $ctx
    Set-FlowGachaPaidSettlementPlayerSave -Context $ctx
    $paidGachaSave = Read-FlowPlayerSave -Context $ctx -Step "self-gacha-paid-settlement-before"
    $paidGachaSave.currencies.mc = 0
    $paidGachaSave.currencies.friendshipPoint = 0
    $paidGachaSave.cards.instances += $drawnCard
    $paidGachaSave.cards.count = 2
    $paidGachaSave.stats.cardsDrawn = 1
    $paidGachaSave.gacha.history += [pscustomobject]@{ productId = 2; bulk = 1; serialId = 2; masterCardId = 9 }
    [System.IO.File]::WriteAllText($ctx.playerSave, ($paidGachaSave | ConvertTo-Json -Depth 40) + [Environment]::NewLine, $utf8NoBom)
    Assert-FlowGachaPaidSettlementPlayerSave -Context $ctx
    Set-FlowGachaPaidSettlementPlayerSave -Context $ctx -InitialMc 600 -ScenarioName "gacha-paid-retry-smoke"
    $paidRetrySave = Read-FlowPlayerSave -Context $ctx -Step "self-gacha-paid-retry-before"
    $retryCard2 = $drawnCard.PSObject.Copy()
    $retryCard3 = $drawnCard.PSObject.Copy()
    $retryCard3.serialId = 3
    $paidRetrySave.currencies.mc = 0
    $paidRetrySave.cards.instances += @($retryCard2, $retryCard3)
    $paidRetrySave.cards.count = 3
    $paidRetrySave.stats.cardsDrawn = 2
    $paidRetrySave.gacha.history = @(
      [pscustomobject]@{ productId = 2; bulk = 1; serialId = 2; masterCardId = 9 },
      [pscustomobject]@{ productId = 2; bulk = 1; serialId = 3; masterCardId = 9 }
    )
    [System.IO.File]::WriteAllText($ctx.playerSave, ($paidRetrySave | ConvertTo-Json -Depth 40) + [Environment]::NewLine, $utf8NoBom)
    Assert-FlowGachaPaidRetryPlayerSave -Context $ctx
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
    Wait-FlowServerEvent -Context $ctx -Step "self-gacha-settlement-response" -Tag "connect_app_response" -Path "/connect/app/gacha/buy" -Fields @{ source = "gacha buy settlement"; command = "gacha_buy"; nextScene = 9200; productId = 1; bulk = 1; friendshipBefore = 400; friendshipCost = 200; friendshipAfter = 200; drawnSerialId = 2; drawnMasterCardId = 9; ownerCardCount = 2; cardsDrawn = 1; saved = $true } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-deck-entry-probe" -Tag "connect_app_probe" -Path "/connect/app/roundtable/edit" -Params @{ move = "1" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-gacha-deck-response" -Tag "connect_app_response" -Path "/connect/app/roundtable/edit" -Fields @{ command = "round_table"; nextScene = 83200; ownerCardCount = 2 } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-gacha-paid-settlement-response" -Tag "connect_app_response" -Path "/connect/app/gacha/buy" -Fields @{ source = "gacha buy settlement"; command = "gacha_buy"; nextScene = 9200; productId = 2; bulk = 1; friendshipBefore = 0; friendshipCost = 0; friendshipAfter = 0; mcBefore = 300; mcCost = 300; mcAfter = 0; drawnSerialId = 2; drawnMasterCardId = 9; ownerCardCount = 2; cardsDrawn = 1; saved = $true } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-fairy-battle-probe" -Tag "connect_app_probe" -Path "/connect/app/exploration/fairybattle" -Params @{ user_id = "1"; serial_id = "100001" } -TimeoutSeconds 2 | Out-Null
    Wait-FlowServerEvent -Context $ctx -Step "self-fairy-battle-response" -Tag "connect_app_response" -Path "/connect/app/exploration/fairybattle" -Fields @{ source = "local fairy battle settlement"; nextScene = 4100; battleScene = 4301; resultScene = 4420; explorationEventType = 18; requestedSerialId = "100001"; enemyBattleType = 30024; enemyBossImageId = 600; playerWon = $true; winner = 1; goldAfter = 795; expAfter = 7; saved = $true } -TimeoutSeconds 2 | Out-Null
    $unexpectedLeaderProbe = Wait-FlowServerEventOptional -Context $ctx -Step "self-deck-leader-no-route" -Tag "connect_app_probe" -Path "" -TimeoutSeconds 1
    if ($unexpectedLeaderProbe) {
      throw "leader-mode quiet-window fixture unexpectedly found $($unexpectedLeaderProbe.path)"
    }
    $scenarioNames = @((Get-FlowScenarioCatalog).name)
    foreach ($requiredScenario in @("deck-builder-leader-mode-smoke", "deck-builder-edit-smoke", "deck-builder-save-smoke", "fairy-battle-smoke")) {
      if ($scenarioNames -notcontains $requiredScenario) {
        throw "$requiredScenario is missing from the flow catalog"
      }
    }
    $plainUi = [xml]"<?xml version='1.0'?><hierarchy><node class='android.view.View' /></hierarchy>"
    $webUi = [xml]"<?xml version='1.0'?><hierarchy><node class='android.webkit.WebView' /></hierarchy>"
    if (Test-FlowUiHasWebView -Ui $plainUi) {
      throw "plain native view was misclassified as a notice WebView"
    }
    if (-not (Test-FlowUiHasWebView -Ui $webUi)) {
      throw "WebView notice classifier failed"
    }
    $gameUi = [xml]"<?xml version='1.0'?><hierarchy><node package='com.square_enix.million_cn' /></hierarchy>"
    $launcherUi = [xml]"<?xml version='1.0'?><hierarchy><node package='com.android.launcher' /></hierarchy>"
    if (-not (Test-FlowUiShowsGamePackage -Ui $gameUi)) {
      throw "game package UI classifier failed"
    }
    if (Test-FlowUiShowsGamePackage -Ui $launcherUi) {
      throw "launcher UI was misclassified as game foreground"
    }
    $anrUi = [xml]"<?xml version='1.0'?><hierarchy><node resource-id='android:id/message' text='Process system isn&apos;t responding.&#10;&#10;Do you want to close it?' /><node resource-id='android:id/button2' text='Wait' /></hierarchy>"
    $crashUi = [xml]"<?xml version='1.0'?><hierarchy><node resource-id='android:id/message' text='Unfortunately, KSSMA has stopped.' /><node resource-id='android:id/button1' text='OK' /></hierarchy>"
    if ($null -eq (Find-FlowSystemAnrWaitButton -Ui $anrUi)) {
      throw "system ANR Wait classifier failed"
    }
    if ($null -ne (Find-FlowSystemAnrWaitButton -Ui $crashUi)) {
      throw "crash dialog was misclassified as system ANR"
    }
    $crashOk = $crashUi.SelectSingleNode("//*[@resource-id='android:id/button1' and @text='OK']")
    if ($null -eq $crashOk) {
      throw "crash dialog OK classifier failed"
    }
    $sameA = Join-Path $ctx.artifactDir "self-diff-a.png"
    $sameB = Join-Path $ctx.artifactDir "self-diff-b.png"
    New-FlowSolidPng -Path $sameA -Width 90 -Height 90 -Red 20 -Green 40 -Blue 60
    New-FlowSolidPng -Path $sameB -Width 90 -Height 90 -Red 220 -Green 80 -Blue 30
    $sameScore = Get-FlowScreenshotDiffScore -ExpectedPath $sameA -ActualPath $sameA
    $changedScore = Get-FlowScreenshotDiffScore -ExpectedPath $sameA -ActualPath $sameB
    if ($sameScore -ne 0) {
      throw "same screenshot diff should be 0, got $sameScore"
    }
    if ($changedScore -lt 50) {
      throw "changed screenshot diff too small: $changedScore"
    }
    $sameRegionScore = Get-FlowScreenshotRegionDiffScore -ExpectedPath $sameA -ActualPath $sameA -RegionX 0 -RegionY 0 -RegionWidth 90 -RegionHeight 90
    $changedRegionScore = Get-FlowScreenshotRegionDiffScore -ExpectedPath $sameA -ActualPath $sameB -RegionX 0 -RegionY 0 -RegionWidth 90 -RegionHeight 90
    if ($sameRegionScore -ne 0 -or $changedRegionScore -lt 50) {
      throw "regional screenshot diff check failed: same=$sameRegionScore changed=$changedRegionScore"
    }
    $deckSignature = Join-Path $ctx.artifactDir "self-deck-builder-signature.png"
    Add-Type -AssemblyName System.Drawing
    $deckBitmap = New-Object System.Drawing.Bitmap 1280, 720
    try {
      $deckBitmap.SetPixel(1040, 80, [System.Drawing.Color]::FromArgb(235, 79, 79))
      $deckBitmap.SetPixel(1040, 250, [System.Drawing.Color]::FromArgb(205, 122, 64))
      $deckBitmap.SetPixel(1040, 400, [System.Drawing.Color]::FromArgb(184, 99, 39))
      $deckBitmap.SetPixel(1040, 550, [System.Drawing.Color]::FromArgb(54, 54, 54))
      $deckBitmap.SetPixel(170, 200, [System.Drawing.Color]::FromArgb(80, 168, 226))
      $deckBitmap.Save($deckSignature, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $deckBitmap.Dispose()
    }
    if (-not (Get-FlowDeckBuilderEntryVisualCheck -Path $deckSignature).ok) {
      throw "deck builder visual signature classifier rejected its positive fixture"
    }
    if ((Get-FlowDeckBuilderEntryVisualCheck -Path $sameA).ok) {
      throw "deck builder visual signature classifier accepted a non-DeckScene fixture"
    }
    $leaderModeSignature = Join-Path $ctx.artifactDir "self-deck-builder-leader-mode-signature.png"
    $leaderBitmap = New-Object System.Drawing.Bitmap 1280, 720
    try {
      $leaderBitmap.SetPixel(1040, 80, [System.Drawing.Color]::FromArgb(51, 51, 51))
      $leaderBitmap.SetPixel(1040, 250, [System.Drawing.Color]::FromArgb(50, 50, 50))
      $leaderBitmap.SetPixel(1040, 400, [System.Drawing.Color]::FromArgb(42, 42, 42))
      $leaderBitmap.SetPixel(1040, 550, [System.Drawing.Color]::FromArgb(23, 23, 23))
      $leaderBitmap.SetPixel(170, 200, [System.Drawing.Color]::FromArgb(80, 168, 226))
      $leaderBitmap.Save($leaderModeSignature, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $leaderBitmap.Dispose()
    }
    if (-not (Get-FlowDeckBuilderLeaderModeVisualCheck -Path $leaderModeSignature).ok) {
      throw "deck builder leader-mode visual signature classifier rejected its positive fixture"
    }
    if ((Get-FlowDeckBuilderLeaderModeVisualCheck -Path $deckSignature).ok) {
      throw "deck builder leader-mode visual signature classifier accepted the normal DeckScene fixture"
    }
    if ((Get-FlowDeckBuilderLeaderModeVisualCheck -Path $sameA).ok) {
      throw "deck builder leader-mode visual signature classifier accepted a non-DeckScene fixture"
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
      name = "mainmenu-bottom-buttons-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Focused main-menu smoke covering the bottom deck and friends entry/back visual gates."
    },
    [ordered]@{
      name = "deck-builder-entry-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Open the bottom deck entry, verify roundtable/edit move=1 enters DeckScene, capture it, and stop before the leader action."
    },
    [ordered]@{
      name = "deck-builder-leader-mode-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Reuse the accepted DeckScene entry, tap leader, verify a route-quiet local visual transition, and stop before card selection."
    },
    [ordered]@{
      name = "deck-builder-edit-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Use the closed local card-selector path to place owned serial 2 in slot 1, return to DeckScene, and prove no save occurred."
    },
    [ordered]@{
      name = "deck-builder-save-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Replay the accepted one-card edit, capture the exact decide request and diagnostic response state, and prove the save stayed unchanged."
    },
    [ordered]@{
      name = "gacha-draw-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Login to main menu, enter gacha select, tap the first draw candidate, and capture the next gacha route or scene."
    },
    [ordered]@{
      name = "gacha-result-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Run the accepted one-draw path, tap the draw-card touch screen, and capture result-page or next-route behavior."
    },
    [ordered]@{
      name = "gacha-result-back-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Run the accepted one-draw result path, tap the visible result-page back button, and verify route or local page transition."
    },
    [ordered]@{
      name = "gacha-paid-retry-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Run one paid draw, use the visible result-page retry action, and verify the second buy, result, and persisted settlement."
    },
    [ordered]@{
      name = "gacha-settlement-deck-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Run one friendship-point draw, verify persisted settlement, return to main menu, then verify deck entry sees the drawn card."
    },
    [ordered]@{
      name = "gacha-paid-settlement-deck-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Run one paid MC draw, verify persisted settlement, return to main menu, then verify deck entry sees the drawn card."
    },
    [ordered]@{
      name = "menu-buttons-route-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Login to main menu, open the Menu page, tap each visible Menu-page entry, verify its first route or WebView URL, screenshot pages, and return to Menu."
    },
    [ordered]@{
      name = "menu-buttons-tail-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Short menu tail smoke covering option, item, card collection, parts list, fairy, update history, help, and their back paths."
    },
    [ordered]@{
      name = "menu-item-parts-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Focused Menu-page smoke covering item and parts-list entry/back visual gates."
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
      name = "fairy-battle-smoke"
      default = $false
      startsRuntime = $true
      ownsServer = $true
      description = "Force one ordinary fairy encounter, tap its original challenge control, verify fairybattle params/scene metadata, and capture the original battle transition."
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
  $supportedRuntimeScenarios = @("mainmenu-faction-smoke", "mainmenu-buttons-route-smoke", "mainmenu-bottom-buttons-smoke", "deck-builder-entry-smoke", "deck-builder-leader-mode-smoke", "deck-builder-edit-smoke", "deck-builder-save-smoke", "gacha-draw-smoke", "gacha-result-smoke", "gacha-result-back-smoke", "gacha-paid-retry-smoke", "gacha-settlement-deck-smoke", "gacha-paid-settlement-deck-smoke", "menu-buttons-route-smoke", "menu-buttons-tail-smoke", "menu-item-parts-smoke", "exploration-smoke", "exploration-walk-smoke", "exploration-forward-visual-smoke", "fairy-battle-smoke", "exploration-floor-clear-smoke", "exploration-ap-shortage-smoke", "exploration-levelup-smoke")
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
    if ($Scenario -eq "gacha-settlement-deck-smoke") {
      Set-FlowGachaSettlementPlayerSave -Context $ctx
    }
    if ($Scenario -eq "gacha-paid-settlement-deck-smoke") {
      Set-FlowGachaPaidSettlementPlayerSave -Context $ctx
    }
    if ($Scenario -eq "gacha-paid-retry-smoke") {
      Set-FlowGachaPaidSettlementPlayerSave -Context $ctx -InitialMc 600 -ScenarioName $Scenario
    }
    if ($Scenario -in @("deck-builder-edit-smoke", "deck-builder-save-smoke")) {
      Set-FlowDeckBuilderEditPlayerSave -Context $ctx -ScenarioName $Scenario
    }
    if ($Scenario -eq "exploration-floor-clear-smoke") {
      $serverEnvironment["KSSMA_EXPLORATION_MOVES_SEED"] = '{"4:6":15}'
    }
    if ($Scenario -in @("exploration-forward-visual-smoke", "fairy-battle-smoke")) {
      $serverEnvironment["KSSMA_EXPLORATION_MOVES_SEED"] = '{"0:2":5}'
    }
    if ($Scenario -eq "fairy-battle-smoke") {
      $serverEnvironment["KSSMA_FAIRY_ENABLED"] = "1"
      $serverEnvironment["KSSMA_FAIRY_ENCOUNTER_RATE"] = "100"
      $serverEnvironment["KSSMA_FAIRY_LEVEL"] = "18"
      $serverEnvironment["KSSMA_FAIRY_MAX_HP"] = "6000"
      $serverEnvironment["KSSMA_FAIRY_ATTACK_POWER"] = "1000"
      $serverEnvironment["KSSMA_FAIRY_REWARD_GOLD"] = "777"
      $serverEnvironment["KSSMA_FAIRY_REWARD_EXP"] = "4"
      $serverEnvironment["KSSMA_FAIRY_TIME_LIMIT_SECONDS"] = "3600"
    }
    if ($Scenario -in @("exploration-smoke", "exploration-walk-smoke", "exploration-floor-clear-smoke", "exploration-ap-shortage-smoke", "exploration-levelup-smoke")) {
      # Flow saves and server processes are isolated; the adjustable admin
      # fairy switch must be isolated too or ordinary exploration ceases to
      # be a deterministic scenario.
      $serverEnvironment["KSSMA_FAIRY_ENABLED"] = "0"
    }
    Start-FlowServer -Context $ctx -ExtraEnvironment $serverEnvironment
    Invoke-FlowRuntimeGate -Context $ctx
    if ($Scenario -match "^gacha-") {
      foreach ($gachaResource in @("gacha_free_0", "gacha_cp_button")) {
        Sync-FlowSaveFile -Context $ctx -RelativePath "download\pack\gacha\$gachaResource"
      }
      foreach ($gachaResource in @("ae_gacha", "ae_gacha02", "rja_ae_gacha", "rja_ae_gacha.load")) {
        Sync-FlowSaveFile -Context $ctx -RelativePath "download\rest\$gachaResource"
      }
    }
    Invoke-FlowLaunchAndLogin -Context $ctx
    switch ($Scenario) {
      "mainmenu-faction-smoke" { Invoke-FlowMainmenuFactionSmoke -Context $ctx }
      "mainmenu-buttons-route-smoke" { Invoke-FlowMainmenuButtonsRouteSmoke -Context $ctx }
      "mainmenu-bottom-buttons-smoke" { Invoke-FlowMainmenuBottomButtonsSmoke -Context $ctx }
      "deck-builder-entry-smoke" { Invoke-FlowDeckBuilderEntrySmoke -Context $ctx }
      "deck-builder-leader-mode-smoke" { Invoke-FlowDeckBuilderLeaderModeSmoke -Context $ctx }
      "deck-builder-edit-smoke" { Invoke-FlowDeckBuilderEditSmoke -Context $ctx }
      "deck-builder-save-smoke" { Invoke-FlowDeckBuilderSaveSmoke -Context $ctx }
      "gacha-draw-smoke" { Invoke-FlowGachaDrawSmoke -Context $ctx }
      "gacha-result-smoke" { Invoke-FlowGachaResultSmoke -Context $ctx }
      "gacha-result-back-smoke" { Invoke-FlowGachaResultBackSmoke -Context $ctx }
      "gacha-paid-retry-smoke" { Invoke-FlowGachaPaidRetrySmoke -Context $ctx }
      "gacha-settlement-deck-smoke" { Invoke-FlowGachaSettlementDeckSmoke -Context $ctx }
      "gacha-paid-settlement-deck-smoke" { Invoke-FlowGachaPaidSettlementDeckSmoke -Context $ctx }
      "menu-buttons-route-smoke" { Invoke-FlowMenuButtonsRouteSmoke -Context $ctx }
      "menu-buttons-tail-smoke" { Invoke-FlowMenuButtonsRouteSmoke -Context $ctx -EntryNames @("open-menu-option", "open-menu-item", "open-menu-card-collection", "open-menu-parts-list", "open-menu-fairy", "open-menu-update-history", "open-menu-help") }
      "menu-item-parts-smoke" { Invoke-FlowMenuButtonsRouteSmoke -Context $ctx -EntryNames @("open-menu-item", "open-menu-parts-list") }
      "exploration-smoke" { Invoke-FlowExplorationSmoke -Context $ctx }
      "exploration-walk-smoke" { Invoke-FlowExplorationWalkSmoke -Context $ctx }
      "exploration-forward-visual-smoke" { Invoke-FlowExplorationForwardVisualSmoke -Context $ctx }
      "fairy-battle-smoke" { Invoke-FlowFairyBattleSmoke -Context $ctx }
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
