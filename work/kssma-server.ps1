param(
  [ValidateSet("start", "stop", "restart", "status", "log")]
  [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

$repo = Split-Path $PSScriptRoot -Parent
$serverScript = Join-Path $repo "server\bootstrap-server.js"
$pidFile = Join-Path $PSScriptRoot "kssma-server.pid"
$fingerprintFile = Join-Path $PSScriptRoot "kssma-server.fingerprint"
$stdoutLog = Join-Path $PSScriptRoot "kssma-server.out.log"
$stderrLog = Join-Path $PSScriptRoot "kssma-server.err.log"

function Get-ServerPid {
  if (-not (Test-Path -LiteralPath $pidFile)) {
    return $null
  }

  $raw = (Get-Content -Raw -LiteralPath $pidFile -ErrorAction SilentlyContinue).Trim()
  if ($raw -notmatch "^\d+$") {
    return $null
  }

  return [int]$raw
}

function Get-ServerProcess {
  $serverPid = Get-ServerPid
  if (-not $serverPid) {
    return $null
  }

  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $serverPid" -ErrorAction SilentlyContinue
  if (-not $process) {
    return $null
  }

  if ($process.CommandLine -notmatch "bootstrap-server\.js") {
    return $null
  }

  return $process
}

function Get-BootstrapServerProcesses {
  @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
      $_.Name -match "node" -and $_.CommandLine -match "bootstrap-server\.js"
    })
}

function Test-Port {
  param([int]$Port)

  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $async = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
    if (-not $async.AsyncWaitHandle.WaitOne(500, $false)) {
      return $false
    }
    $client.EndConnect($async)
    return $true
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

function Test-Health {
  try {
    $request = [System.Net.WebRequest]::Create("http://127.0.0.1:50005/healthz")
    $request.Timeout = 800
    $request.ReadWriteTimeout = 800
    $response = $request.GetResponse()
    try {
      return [int]$response.StatusCode -eq 200
    } finally {
      $response.Close()
    }
  } catch {
    return $false
  }
}

function Get-ServerFingerprint {
  $paths = @()
  $paths += Get-Item -LiteralPath $serverScript -ErrorAction Stop

  foreach ($relativeDir in @("server\data\game", "server\data\server")) {
    $dataDir = Join-Path $repo $relativeDir
    if (Test-Path -LiteralPath $dataDir) {
      $paths += Get-ChildItem -LiteralPath $dataDir -Recurse -File -Filter *.json
    }
  }

  $defaultSave = Join-Path $repo "server\data\player\default-save.json"
  if (Test-Path -LiteralPath $defaultSave) {
    $paths += Get-Item -LiteralPath $defaultSave
  }

  $lines = foreach ($path in ($paths | Sort-Object FullName)) {
    $repoFull = [System.IO.Path]::GetFullPath($repo).TrimEnd("\", "/")
    $pathFull = [System.IO.Path]::GetFullPath($path.FullName)
    $relative = if ($pathFull.StartsWith($repoFull, [System.StringComparison]::OrdinalIgnoreCase)) {
      $pathFull.Substring($repoFull.Length).TrimStart("\", "/")
    } else {
      $pathFull
    }
    $hash = (Get-FileHash -LiteralPath $path.FullName -Algorithm SHA256).Hash
    "$relative=$hash"
  }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "")
  } finally {
    $sha.Dispose()
  }
}

function Get-StoredServerFingerprint {
  if (-not (Test-Path -LiteralPath $fingerprintFile)) {
    return ""
  }
  return (Get-Content -Raw -LiteralPath $fingerprintFile -ErrorAction SilentlyContinue).Trim()
}

function Show-Status {
  $process = Get-ServerProcess
  $currentFingerprint = if (Test-Path -LiteralPath $serverScript) { Get-ServerFingerprint } else { "" }
  $storedFingerprint = Get-StoredServerFingerprint
  $health = Test-Health

  [pscustomobject]@{
    Running      = [bool]$process
    Pid          = if ($process) { $process.ProcessId } else { $null }
    Port50005    = Test-Port 50005
    Port10001    = Test-Port 10001
    Health50005  = $health
    FingerprintOk = [bool]($process -and $storedFingerprint -and $storedFingerprint -eq $currentFingerprint)
    StdoutLog    = $stdoutLog
    StderrLog    = $stderrLog
  } | Format-List
}

function Start-Server {
  if (-not (Test-Path -LiteralPath $serverScript)) {
    throw "Missing server script: $serverScript"
  }

  $currentFingerprint = Get-ServerFingerprint
  $process = Get-ServerProcess
  $bootstrapProcesses = @(Get-BootstrapServerProcesses)
  if ($process) {
    $storedFingerprint = Get-StoredServerFingerprint
    $orphanProcesses = @($bootstrapProcesses | Where-Object { $_.ProcessId -ne $process.ProcessId })
    if ($storedFingerprint -and $storedFingerprint -eq $currentFingerprint -and $orphanProcesses.Count -eq 0) {
      Write-Host "kssma server already running"
      Show-Status
      return
    }

    Write-Host "kssma server code/data changed; restarting"
  } elseif ($bootstrapProcesses.Count -gt 0) {
    Write-Host "kssma server process exists without current pid; restarting"
  }

  if ($process -or $bootstrapProcesses.Count -gt 0) {
    foreach ($candidate in $bootstrapProcesses) {
      Stop-Process -Id $candidate.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($process -and $process.ProcessId -notin @($bootstrapProcesses.ProcessId)) {
      Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $pidFile -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
  }

  Remove-Item -LiteralPath $stdoutLog, $stderrLog -ErrorAction SilentlyContinue

  $env:CHECK_INSPECTION_KEY = "rBwj1MIAivVN222b"
  $env:CONNECT_APP_KEY = "rBwj1MIAivVN222b"
  $env:LOGIN_RESPONSE = "sample"
  $env:PORTS = "50005,10001"

  $process = Start-Process `
    -FilePath "node" `
    -ArgumentList @(".\server\bootstrap-server.js") `
    -WorkingDirectory $repo `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog `
    -WindowStyle Hidden `
    -PassThru

  Set-Content -LiteralPath $pidFile -Value ([string]$process.Id)
  Set-Content -LiteralPath $fingerprintFile -Value $currentFingerprint
  Start-Sleep -Seconds 1
  Show-Status
}

function Stop-Server {
  $process = Get-ServerProcess
  if (-not $process) {
    Write-Host "kssma server is not running"
    Remove-Item -LiteralPath $pidFile -ErrorAction SilentlyContinue
    return
  }

  Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $pidFile, $fingerprintFile -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 300
  Show-Status
}

function Show-Log {
  if (Test-Path -LiteralPath $stdoutLog) {
    Get-Content -LiteralPath $stdoutLog -Tail 80
  } else {
    Write-Host "No stdout log yet: $stdoutLog"
  }

  if (Test-Path -LiteralPath $stderrLog) {
    $stderr = Get-Content -LiteralPath $stderrLog -Tail 40
    if ($stderr) {
      Write-Host ""
      Write-Host "stderr:"
      $stderr
    }
  }
}

switch ($Action) {
  "start" { Start-Server }
  "stop" { Stop-Server }
  "restart" { Stop-Server; Start-Server }
  "status" { Show-Status }
  "log" { Show-Log }
}
