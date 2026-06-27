param(
  [ValidateSet(
    "fast-health",
    "self-check-transport",
    "connect",
    "repair-adb",
    "ensure-runtime",
    "ensure-baseline",
    "status",
    "launch",
    "run",
    "observe",
    "patch-lib",
    "install-apk",
    "install-check",
    "diagnose",
    "restart-runtime",
    "stop-runtime",
    "configure",
    "clean-install",
    "hosts",
    "mount",
    "display",
    "preload-rest",
    "preload-small",
    "preload-full"
  )]
  [string]$Command = "fast-health",
  [string]$ApkPath,
  [switch]$Force,
  [string]$Reason = "",
  [switch]$WipeData,
  [switch]$DriveLogin,
  [string[]]$Observe = @(),
  [int]$WaitSeconds = 35,
  [string]$Tag = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "kssma-runtime-lib.ps1")

function Normalize-ObserveList {
  param([string[]]$Values, [string[]]$Default)
  if (-not $Values -or $Values.Count -eq 0) {
    return $Default
  }
  @($Values | ForEach-Object { ($_ -split ",") } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
}

try {
  $result = switch ($Command) {
    "fast-health" { Invoke-FastHealth }
    "self-check-transport" { Invoke-TransportSelfCheck }
    "connect" { Invoke-ConnectRuntime }
    "repair-adb" { Invoke-RepairAdb }
    "ensure-runtime" { Invoke-EnsureRuntime -WipeData:$WipeData }
    "ensure-baseline" { Invoke-EnsureBaseline }
    "status" { Invoke-Status }
    "launch" { Invoke-LaunchGame }
    "run" {
      $observeList = Normalize-ObserveList -Values $Observe -Default @("Requests", "Activity", "Logcat")
      Invoke-RunRuntime -DriveLogin:$DriveLogin -Observe $observeList -WaitSeconds $WaitSeconds -Tag $Tag
    }
    "observe" {
      $observeList = Normalize-ObserveList -Values $Observe -Default @("Requests", "Activity", "Logcat", "Screenshot")
      Invoke-Observe -Observe $observeList -Tag $Tag
    }
    "patch-lib" { Invoke-PatchLib -ApkPath $ApkPath }
    "install-apk" { Invoke-InstallApk -ApkPath $ApkPath }
    "install-check" { Invoke-InstallCheck -ApkPath $ApkPath }
    "diagnose" { Invoke-Diagnose }
    "restart-runtime" { Invoke-RestartRuntime -Force:$Force -Reason $Reason -WipeData:$WipeData }
    "stop-runtime" { Invoke-StopRuntime -Reason $(if ($Reason) { $Reason } else { "explicit stop-runtime command" }) }
    "configure" { Invoke-ConfigureRuntime }
    "clean-install" {
      $ctx = New-RuntimeContext "clean-install"
      $runtime = Invoke-EnsureRuntime -WipeData:$WipeData
      $ctx.stages += $runtime.stages
      if ($runtime.ok) {
        Clear-InstallScratch -Context $ctx
        Complete-RuntimeResult -Context $ctx -Ok $true -Data ([ordered]@{ data = Get-DataPartitionInfo -Context $ctx })
      } else {
        Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass $runtime.failureClass -RestartAllowed:$runtime.restartAllowed -RecommendedCommand $runtime.recommendedCommand
      }
    }
    "hosts" { Invoke-EnsureBaseline -Only @("hosts") }
    "mount" { Invoke-EnsureBaseline -Only @("mount") }
    "display" { Invoke-EnsureBaseline -Only @("display") }
    "preload-rest" { Invoke-PreloadResources -Mode "rest" }
    "preload-small" { Invoke-PreloadResources -Mode "small" }
    "preload-full" { Invoke-PreloadResources -Mode "full" }
  }
} catch {
  $ctx = New-RuntimeContext $Command
  $result = Complete-RuntimeResult -Context $ctx -Ok $false -FailureClass "script-error" -RestartAllowed $false -RecommendedCommand "Inspect PowerShell error and command arguments." -Data ([ordered]@{ error = $_.Exception.Message })
}

ConvertTo-RuntimeJson $result
if (-not $result.ok) {
  exit 1
}
