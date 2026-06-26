param(
  [ValidateSet("status", "configure", "repair-adb", "start", "wait", "clean-install", "install", "patch-lib", "hosts", "mount", "preload-rest", "preload-small", "preload-full", "launch", "run", "logcat", "stop")]
  [string]$Action = "status",
  [string]$ApkPath,
  [switch]$WipeData
)

$ErrorActionPreference = "Stop"

$runtimeEntry = Join-Path $PSScriptRoot "kssma-runtime.ps1"
if (-not (Test-Path -LiteralPath $runtimeEntry)) {
  throw "Missing runtime entry: $runtimeEntry"
}

$command = switch ($Action) {
  "status" { "status" }
  "configure" { "configure" }
  "repair-adb" { "repair-adb" }
  "start" { "ensure-runtime" }
  "wait" { "ensure-runtime" }
  "clean-install" { "clean-install" }
  "install" { "install-apk" }
  "patch-lib" { "patch-lib" }
  "hosts" { "hosts" }
  "mount" { "mount" }
  "preload-rest" { "preload-rest" }
  "preload-small" { "preload-small" }
  "preload-full" { "preload-full" }
  "launch" { "launch" }
  "run" { "run" }
  "logcat" { "observe" }
  "stop" { "stop-runtime" }
}

$arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runtimeEntry, $command)
if ($ApkPath) {
  $arguments += @("-ApkPath", $ApkPath)
}
if ($WipeData) {
  $arguments += "-WipeData"
}
if ($Action -eq "logcat") {
  $arguments += @("-Observe", "Full", "-Tag", "android44-arm19-last-run")
}
if ($Action -eq "stop") {
  $arguments += @("-Reason", "legacy android44-arm19 stop command")
}

& powershell @arguments
exit $LASTEXITCODE
