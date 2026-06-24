param(
  [ValidateSet("start", "stop", "restart", "status", "log")]
  [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

$repo = Split-Path $PSScriptRoot -Parent
$serverScript = Join-Path $repo "server\bootstrap-server.js"
$pidFile = Join-Path $PSScriptRoot "kssma-server.pid"
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

function Test-Port {
  param([int]$Port)

  $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1
  return [bool]$connection
}

function Show-Status {
  $process = Get-ServerProcess
  $health = $false
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:50005/healthz" -TimeoutSec 2
    $health = $response.StatusCode -eq 200
  } catch {
    $health = $false
  }

  [pscustomobject]@{
    Running      = [bool]$process
    Pid          = if ($process) { $process.ProcessId } else { $null }
    Port50005    = Test-Port 50005
    Port10001    = Test-Port 10001
    Health50005  = $health
    StdoutLog    = $stdoutLog
    StderrLog    = $stderrLog
  } | Format-List
}

function Start-Server {
  if (Get-ServerProcess) {
    Write-Host "kssma server already running"
    Show-Status
    return
  }

  if (-not (Test-Path -LiteralPath $serverScript)) {
    throw "Missing server script: $serverScript"
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
  Remove-Item -LiteralPath $pidFile -ErrorAction SilentlyContinue
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
