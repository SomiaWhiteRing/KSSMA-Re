param(
  [ValidateSet(
    "self-check",
    "prepare",
    "deploy",
    "status",
    "install-client",
    "ensure-hosts",
    "restore-hosts",
    "install-resources",
    "launch"
  )]
  [string]$Command = "deploy",
  [string]$Serial = "127.0.0.1:7555",
  [string]$GuestHost = "10.0.2.2",
  [switch]$Rebuild,
  [switch]$StartServer,
  [switch]$Launch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "kssma-runtime-lib.ps1")

$script:MumuConfig = [ordered]@{
  Package = "com.square_enix.million_cn"
  Activity = "com.test.enter.LogoActivity"
  ExpectedRelease = "12"
  ExpectedSdk = @("31", "32")
  DeviceSaveDir = "/storage/emulated/0/Android/data/com.square_enix.million_cn/files/save"
  RemoteResourcePack = "/data/local/tmp/kssma-mumu-a12-resources.tar"
  RemoteChecksums = "/data/local/tmp/kssma-mumu-a12-resources.sha256"
  RemoteVerifyScript = "/data/local/tmp/kssma-mumu-a12-verify.sh"
  RemoteVerifyLog = "/data/local/tmp/kssma-mumu-a12-verify.log"
  HostsPath = "/system/etc/hosts"
  HostsBackupPath = "/system/etc/hosts.kssma-re-original"
  LegacyHostsBackupPath = "/system/etc/hosts.kssma-re-backup-20260817"
  Domains = @("game.ma.mobimon.com.tw", "dlc.game-CBT.ma.sdo.com")
}

$script:PrepareAssetsPath = Join-Path $PSScriptRoot "prepare-assets.py"
$script:ExtractGachaResourcesPath = Join-Path $PSScriptRoot "extract-gacha-pack-resources.py"
$script:BuildClientPath = Join-Path $PSScriptRoot "build-client-baseline.py"
$script:BuildResourcePackPath = Join-Path $PSScriptRoot "build-mumu-a12-resource-pack.py"
$script:ClientManifestPath = Join-Path $PSScriptRoot "client-baseline\client-baseline.json"
$script:ResourceManifestPath = Join-Path $PSScriptRoot "mumu-a12-package\resource-pack.json"
$script:LastLaunchScreenshot = Join-Path $PSScriptRoot "kssma-mumu-a12-last-launch.png"

function New-MumuContext {
  param([string]$Name)
  [ordered]@{
    command = $Name
    serial = $Serial
    guestHost = $GuestHost
    ok = $false
    startedAt = Get-Date
    stages = @()
    warnings = @()
    data = [ordered]@{}
  }
}

function Add-MumuStage {
  param($Context, [string]$Name, $Stage)
  $item = [ordered]@{
    name = $Name
    ok = [bool]$Stage.ok
    elapsedMs = [int]$Stage.elapsedMs
  }
  foreach ($key in @("exitCode", "timedOut", "stdout", "stderr", "failureClass", "details", "skipped")) {
    if ($Stage.Contains($key)) {
      $value = $Stage[$key]
      if ($key -in @("stdout", "stderr") -and ($value -as [string]).Length -gt 4000) {
        $value = ($value -as [string]).Substring(0, 4000) + "`n[truncated by kssma-mumu-a12.ps1]"
      }
      $item[$key] = $value
    }
  }
  $Context.stages += $item
}

function Complete-MumuResult {
  param($Context, [bool]$Ok, [string]$FailureClass = "", [string]$Message = "")
  $Context.ok = $Ok
  [ordered]@{
    ok = $Ok
    command = $Context.command
    serial = $Context.serial
    guestHost = $Context.guestHost
    elapsedMs = [int]((Get-Date) - $Context.startedAt).TotalMilliseconds
    failureClass = $FailureClass
    message = $Message
    stages = $Context.stages
    warnings = $Context.warnings
    data = $Context.data
  }
}

function Test-MumuIpv4Literal {
  param([string]$Value)
  $parsed = $null
  if (-not [System.Net.IPAddress]::TryParse($Value, [ref]$parsed)) {
    return $false
  }
  return $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
}

function Resolve-MumuRepoPath {
  param([string]$RelativePath)
  if ([string]::IsNullOrWhiteSpace($RelativePath)) {
    throw "Artifact manifest contains an empty path."
  }
  $root = [System.IO.Path]::GetFullPath($script:RepoRoot).TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
  $candidate = [System.IO.Path]::GetFullPath((Join-Path $script:RepoRoot $RelativePath))
  if (-not $candidate.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Artifact manifest path escapes the repository: $RelativePath"
  }
  $candidate
}

function Resolve-KssmaConda {
  $candidates = @()
  foreach ($name in @("conda.exe", "conda")) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
  }
  $candidates += @(
    (Join-Path $env:USERPROFILE "miniconda3\Scripts\conda.exe"),
    (Join-Path $env:USERPROFILE "anaconda3\Scripts\conda.exe")
  )
  $resolved = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
  if (-not $resolved) {
    throw "Conda was not found. Create the dedicated environment with: conda env create --override-channels -c conda-forge -f .\environment.yml"
  }
  $resolved
}

function Invoke-MumuPython {
  param($Context, [string]$Name, [string]$ScriptPath, [int]$TimeoutSeconds)
  Require-File $ScriptPath
  $conda = Resolve-KssmaConda
  $stage = Invoke-RuntimeProcess -FilePath $conda -ArgumentList @("run", "-n", "KSSMA-Re", "python", $ScriptPath) -TimeoutSeconds $TimeoutSeconds -AllowFailure
  Add-MumuStage $Context $Name $stage
  if (-not $stage.ok) {
    throw "$Name failed in the KSSMA-Re conda environment: $($stage.stderr) $($stage.stdout)"
  }
  $stage
}

function Invoke-MumuPrepare {
  param($Context)
  Invoke-MumuPython -Context $Context -Name "prepare-assets" -ScriptPath $script:PrepareAssetsPath -TimeoutSeconds 900 | Out-Null
  Invoke-MumuPython -Context $Context -Name "extract-original-gacha-resources" -ScriptPath $script:ExtractGachaResourcesPath -TimeoutSeconds 300 | Out-Null
  Invoke-MumuPython -Context $Context -Name "build-client-baseline" -ScriptPath $script:BuildClientPath -TimeoutSeconds 600 | Out-Null
  Invoke-MumuPython -Context $Context -Name "build-mumu-resource-pack" -ScriptPath $script:BuildResourcePackPath -TimeoutSeconds 1800 | Out-Null
  Get-MumuArtifacts -Context $Context
}

function Get-MumuArtifacts {
  param($Context)
  Require-File $script:ClientManifestPath
  Require-File $script:ResourceManifestPath
  $client = Get-Content -Raw -Encoding UTF8 -LiteralPath $script:ClientManifestPath | ConvertFrom-Json
  $resources = Get-Content -Raw -Encoding UTF8 -LiteralPath $script:ResourceManifestPath | ConvertFrom-Json

  $apkPath = Resolve-MumuRepoPath ($client.baselineApk.path -as [string])
  $nativePath = Resolve-MumuRepoPath ($client.nativeLib.path -as [string])
  $packPath = Resolve-MumuRepoPath ($resources.resourcePack.path -as [string])
  $checksumsPath = Resolve-MumuRepoPath ($resources.checksums.path -as [string])
  foreach ($path in @($apkPath, $nativePath, $packPath, $checksumsPath)) { Require-File $path }

  $checks = @(
    @{ name = "client APK"; path = $apkPath; expected = ($client.baselineApk.sha256 -as [string]) },
    @{ name = "accepted native library"; path = $nativePath; expected = ($client.nativeLib.sha256 -as [string]) },
    @{ name = "resource pack"; path = $packPath; expected = ($resources.resourcePack.sha256 -as [string]) },
    @{ name = "resource checksum list"; path = $checksumsPath; expected = ($resources.checksums.sha256 -as [string]) }
  )
  foreach ($check in $checks) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $check.path).Hash
    $ok = $actual -eq $check.expected
    Add-MumuStage $Context ("verify-artifact-" + ($check.name -replace "\s+", "-")) ([ordered]@{
        ok = $ok
        elapsedMs = 0
        details = "path=$($check.path); sha256=$actual"
      })
    if (-not $ok) { throw "$($check.name) hash mismatch: got $actual, expected $($check.expected)" }
  }
  if (@($resources.excludedMutable) -notcontains "appdata/save_appdata") {
    throw "Resource pack must explicitly exclude mutable appdata/save_appdata."
  }
  [ordered]@{
    clientManifest = $client
    resourceManifest = $resources
    apkPath = $apkPath
    nativePath = $nativePath
    packPath = $packPath
    checksumsPath = $checksumsPath
  }
}

function Ensure-MumuArtifacts {
  param($Context, [switch]$ForceRebuild)
  $missing = (-not (Test-Path -LiteralPath $script:ClientManifestPath)) -or (-not (Test-Path -LiteralPath $script:ResourceManifestPath))
  if ($ForceRebuild -or $missing) {
    return Invoke-MumuPrepare -Context $Context
  }
  Get-MumuArtifacts -Context $Context
}

function Invoke-MumuAdbStage {
  param(
    $Context,
    [string]$Name,
    [string[]]$Arguments,
    [int]$TimeoutSeconds = 30,
    [switch]$AllowFailure,
    [switch]$WithoutSerial
  )
  $adbArguments = if ($WithoutSerial) { $Arguments } else { @("-s", $Serial) + $Arguments }
  $stage = Invoke-Adb -Arguments $adbArguments -TimeoutSeconds $TimeoutSeconds -AllowFailure
  Add-MumuStage $Context $Name $stage
  if ((-not $AllowFailure) -and (-not $stage.ok)) {
    throw "$Name failed: $($stage.failureClass) $($stage.stderr) $($stage.stdout)"
  }
  $stage
}

function Wait-MumuDevice {
  param($Context, [string]$Name, [int]$TimeoutSeconds = 30)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $last = $null
  while ((Get-Date) -lt $deadline) {
    $last = Invoke-Adb -Arguments @("-s", $Serial, "get-state") -TimeoutSeconds 3 -AllowFailure
    if ($last.ok -and $last.stdout.Trim() -eq "device") {
      Add-MumuStage $Context $Name $last
      return
    }
    Start-Sleep -Milliseconds 750
  }
  if ($last) { Add-MumuStage $Context $Name $last }
  throw "Timed out waiting for ADB device $Serial."
}

function Get-MumuProp {
  param($Context, [string]$Property)
  $stage = Invoke-MumuAdbStage -Context $Context -Name ("getprop-" + ($Property -replace "[^A-Za-z0-9]+", "-")) -Arguments @("shell", "getprop", $Property) -TimeoutSeconds 5
  $stage.stdout.Trim()
}

function Invoke-MumuDeviceGate {
  param($Context)
  if (-not (Test-MumuIpv4Literal $GuestHost)) { throw "-GuestHost must be an IPv4 literal, got: $GuestHost" }
  if ($Serial -notmatch "^(127\.0\.0\.1|localhost):[0-9]+$") {
    throw "This installer only accepts an explicit loopback TCP ADB serial, got: $Serial"
  }
  Invoke-MumuAdbStage -Context $Context -Name "adb-connect" -Arguments @("connect", $Serial) -TimeoutSeconds 10 -WithoutSerial | Out-Null
  Wait-MumuDevice -Context $Context -Name "adb-device-ready" -TimeoutSeconds 30

  $release = Get-MumuProp -Context $Context -Property "ro.build.version.release"
  $sdk = Get-MumuProp -Context $Context -Property "ro.build.version.sdk"
  $abi = Get-MumuProp -Context $Context -Property "ro.product.cpu.abi"
  $abiList32 = Get-MumuProp -Context $Context -Property "ro.product.cpu.abilist32"
  $nativeBridge = Get-MumuProp -Context $Context -Property "ro.dalvik.vm.native.bridge"
  $boot = Get-MumuProp -Context $Context -Property "sys.boot_completed"
  if ($release -ne $script:MumuConfig.ExpectedRelease -or $sdk -notin $script:MumuConfig.ExpectedSdk) {
    throw "Wrong Android runtime: expected Android 12/API 31-32, got release=$release sdk=$sdk."
  }
  if ($boot -ne "1") { throw "MuMu has not completed boot: sys.boot_completed=$boot" }
  if ($abiList32 -notmatch "(^|,)(armeabi-v7a|armeabi)(,|$)") {
    throw "MuMu does not expose a usable 32-bit ARM ABI: abilist32=$abiList32"
  }
  if ([string]::IsNullOrWhiteSpace($nativeBridge)) {
    throw "MuMu does not report a native bridge for the ARM-only client."
  }
  [ordered]@{ release = $release; sdk = $sdk; abi = $abi; abiList32 = $abiList32; nativeBridge = $nativeBridge; bootCompleted = $boot }
}

function Invoke-MumuRoot {
  param($Context)
  $root = Invoke-MumuAdbStage -Context $Context -Name "adb-root" -Arguments @("root") -TimeoutSeconds 15 -AllowFailure
  if ((-not $root.ok) -or "$($root.stdout) $($root.stderr)" -match "cannot run as root") {
    throw "This MuMu instance did not allow adb root; hosts and installed-native verification cannot continue."
  }
  Wait-MumuDevice -Context $Context -Name "adb-ready-after-root" -TimeoutSeconds 30
  $uid = Invoke-MumuAdbStage -Context $Context -Name "verify-root-uid" -Arguments @("shell", "id", "-u") -TimeoutSeconds 5
  if ($uid.stdout.Trim() -ne "0") { throw "adb root returned, but shell uid is $($uid.stdout.Trim()) instead of 0." }
}

function Invoke-MumuUnroot {
  param($Context)
  Invoke-MumuAdbStage -Context $Context -Name "adb-unroot" -Arguments @("unroot") -TimeoutSeconds 15 -AllowFailure | Out-Null
  Wait-MumuDevice -Context $Context -Name "adb-ready-after-unroot" -TimeoutSeconds 30
}

function Test-MumuRemoteFile {
  param($Context, [string]$Path)
  $stage = Invoke-MumuAdbStage -Context $Context -Name ("test-remote-" + ([System.IO.Path]::GetFileName($Path))) -Arguments @("shell", "ls", $Path) -TimeoutSeconds 5 -AllowFailure
  $stage.ok -and $stage.stdout.Trim() -eq $Path
}

function Merge-MumuHostsText {
  param([string]$Current, [string]$Address)
  $domains = @($script:MumuConfig.Domains | ForEach-Object { $_.ToLowerInvariant() })
  $output = New-Object System.Collections.Generic.List[string]
  foreach ($line in @($Current -split "\r?\n")) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) {
      $output.Add($line)
      continue
    }
    $comment = ""
    $body = $line
    $commentIndex = $line.IndexOf("#")
    if ($commentIndex -ge 0) {
      $body = $line.Substring(0, $commentIndex)
      $comment = $line.Substring($commentIndex).TrimEnd()
    }
    $parts = @($body.Trim() -split "\s+" | Where-Object { $_ -ne "" })
    if ($parts.Count -lt 2) {
      $output.Add($line)
      continue
    }
    $aliases = @($parts[1..($parts.Count - 1)] | Where-Object { $_.ToLowerInvariant() -notin $domains })
    if ($aliases.Count -gt 0) {
      $rebuilt = "$($parts[0])`t$($aliases -join ' ')"
      if ($comment) { $rebuilt += " $comment" }
      $output.Add($rebuilt)
    } elseif ($comment) {
      $output.Add($comment)
    }
  }
  while ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
    $output.RemoveAt($output.Count - 1)
  }
  foreach ($domain in $script:MumuConfig.Domains) { $output.Add("$Address`t$domain") }
  ($output -join "`n") + "`n"
}

function Invoke-MumuEnsureHosts {
  param($Context)
  Invoke-MumuRoot -Context $Context
  $tempHosts = [System.IO.Path]::GetTempFileName()
  $remoteTemp = "/data/local/tmp/kssma-mumu-a12-hosts"
  try {
    if (-not (Test-MumuRemoteFile -Context $Context -Path $script:MumuConfig.HostsBackupPath)) {
      $backupSource = $script:MumuConfig.HostsPath
      if (Test-MumuRemoteFile -Context $Context -Path $script:MumuConfig.LegacyHostsBackupPath) {
        $backupSource = $script:MumuConfig.LegacyHostsBackupPath
      }
      Invoke-MumuAdbStage -Context $Context -Name "backup-original-hosts" -Arguments @("shell", "cp", $backupSource, $script:MumuConfig.HostsBackupPath) -TimeoutSeconds 10 | Out-Null
      Invoke-MumuAdbStage -Context $Context -Name "chmod-hosts-backup" -Arguments @("shell", "chmod", "600", $script:MumuConfig.HostsBackupPath) -TimeoutSeconds 10 | Out-Null
    }
    Invoke-MumuAdbStage -Context $Context -Name "pull-current-hosts" -Arguments @("pull", $script:MumuConfig.HostsPath, $tempHosts) -TimeoutSeconds 20 | Out-Null
    $current = Get-Content -Raw -LiteralPath $tempHosts
    $merged = Merge-MumuHostsText -Current $current -Address $GuestHost
    [System.IO.File]::WriteAllText($tempHosts, $merged, [System.Text.UTF8Encoding]::new($false))

    Invoke-MumuAdbStage -Context $Context -Name "remount-system" -Arguments @("remount") -TimeoutSeconds 30 -AllowFailure | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "push-merged-hosts" -Arguments @("push", $tempHosts, $remoteTemp) -TimeoutSeconds 20 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "install-merged-hosts" -Arguments @("shell", "cp", $remoteTemp, $script:MumuConfig.HostsPath) -TimeoutSeconds 10 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "chmod-hosts" -Arguments @("shell", "chmod", "644", $script:MumuConfig.HostsPath) -TimeoutSeconds 10 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "chown-hosts" -Arguments @("shell", "chown", "0:0", $script:MumuConfig.HostsPath) -TimeoutSeconds 10 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "remove-hosts-temp" -Arguments @("shell", "rm", "-f", $remoteTemp) -TimeoutSeconds 10 -AllowFailure | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "flush-netd-dns" -Arguments @("shell", "cmd", "netd", "resolver", "flushdefaultif") -TimeoutSeconds 10 -AllowFailure | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "force-stop-after-hosts" -Arguments @("shell", "am", "force-stop", $script:MumuConfig.Package) -TimeoutSeconds 10 -AllowFailure | Out-Null

    $verify = Invoke-MumuAdbStage -Context $Context -Name "verify-hosts" -Arguments @("shell", "cat", $script:MumuConfig.HostsPath) -TimeoutSeconds 10
    foreach ($domain in $script:MumuConfig.Domains) {
      if ($verify.stdout -notmatch "(?m)^$([regex]::Escape($GuestHost))\s+$([regex]::Escape($domain))\s*$") {
        throw "Installed hosts file does not map $domain to $GuestHost."
      }
      $ping = Invoke-MumuAdbStage -Context $Context -Name ("resolve-" + ($domain -replace "[^A-Za-z0-9]+", "-")) -Arguments @("shell", "ping", "-c", "1", "-W", "2", $domain) -TimeoutSeconds 8 -AllowFailure
      if ((-not $ping.ok) -or "$($ping.stdout) $($ping.stderr)" -notmatch [regex]::Escape($GuestHost)) {
        throw "Android did not resolve $domain to $GuestHost after hosts installation."
      }
    }
    [ordered]@{ changed = ($merged -ne $current); backup = $script:MumuConfig.HostsBackupPath; hosts = $merged }
  } finally {
    Remove-Item -LiteralPath $tempHosts -Force -ErrorAction SilentlyContinue
    Invoke-MumuUnroot -Context $Context
  }
}

function Invoke-MumuRestoreHosts {
  param($Context)
  Invoke-MumuRoot -Context $Context
  try {
    if (-not (Test-MumuRemoteFile -Context $Context -Path $script:MumuConfig.HostsBackupPath)) {
      throw "Hosts backup is missing: $($script:MumuConfig.HostsBackupPath)"
    }
    Invoke-MumuAdbStage -Context $Context -Name "remount-system-for-hosts-restore" -Arguments @("remount") -TimeoutSeconds 30 -AllowFailure | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "restore-original-hosts" -Arguments @("shell", "cp", $script:MumuConfig.HostsBackupPath, $script:MumuConfig.HostsPath) -TimeoutSeconds 10 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "chmod-restored-hosts" -Arguments @("shell", "chmod", "644", $script:MumuConfig.HostsPath) -TimeoutSeconds 10 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "chown-restored-hosts" -Arguments @("shell", "chown", "0:0", $script:MumuConfig.HostsPath) -TimeoutSeconds 10 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "force-stop-after-hosts-restore" -Arguments @("shell", "am", "force-stop", $script:MumuConfig.Package) -TimeoutSeconds 10 -AllowFailure | Out-Null
    $restored = Invoke-MumuAdbStage -Context $Context -Name "read-restored-hosts" -Arguments @("shell", "cat", $script:MumuConfig.HostsPath) -TimeoutSeconds 10
    [ordered]@{ restored = $true; hosts = $restored.stdout }
  } finally {
    Invoke-MumuUnroot -Context $Context
  }
}

function Invoke-MumuGrantLegacyPermissions {
  param($Context)
  foreach ($permission in @(
      "android.permission.READ_PHONE_STATE",
      "android.permission.READ_EXTERNAL_STORAGE",
      "android.permission.WRITE_EXTERNAL_STORAGE"
    )) {
    Invoke-MumuAdbStage -Context $Context -Name ("grant-" + ($permission -replace ".*\.", "")) -Arguments @("shell", "pm", "grant", $script:MumuConfig.Package, $permission) -TimeoutSeconds 10 -AllowFailure | Out-Null
  }
  Invoke-MumuAdbStage -Context $Context -Name "allow-legacy-storage-appop" -Arguments @("shell", "cmd", "appops", "set", $script:MumuConfig.Package, "LEGACY_STORAGE", "allow") -TimeoutSeconds 10 -AllowFailure | Out-Null
  $dump = Invoke-MumuAdbStage -Context $Context -Name "verify-client-permissions" -Arguments @("shell", "dumpsys", "package", $script:MumuConfig.Package) -TimeoutSeconds 20
  foreach ($permission in @("READ_PHONE_STATE", "READ_EXTERNAL_STORAGE", "WRITE_EXTERNAL_STORAGE")) {
    if ($dump.stdout -notmatch "android\.permission\.$permission`: granted=true") {
      throw "Required legacy permission was not granted: $permission"
    }
  }
}

function Invoke-MumuVerifyInstalledClient {
  param($Context, $Artifacts)
  $dump = Invoke-MumuAdbStage -Context $Context -Name "dumpsys-installed-client" -Arguments @("shell", "dumpsys", "package", $script:MumuConfig.Package) -TimeoutSeconds 20
  if ($dump.stdout -notmatch "primaryCpuAbi=armeabi") {
    throw "PackageManager did not select the expected armeabi client ABI."
  }
  if ($dump.stdout -notmatch "legacyNativeLibraryDir=([^\r\n]+)") {
    throw "Cannot locate the Android 12 native library directory."
  }
  $nativeDir = $Matches[1].Trim()
  $remoteLib = "$nativeDir/arm/librooneyj.so"
  Invoke-MumuRoot -Context $Context
  try {
    $hash = Invoke-MumuAdbStage -Context $Context -Name "hash-installed-librooneyj" -Arguments @("shell", "sha256sum", $remoteLib) -TimeoutSeconds 60
    $installedHash = @($hash.stdout -split "\s+")[0].ToUpperInvariant()
    $expectedHash = ($Artifacts.clientManifest.nativeLib.sha256 -as [string]).ToUpperInvariant()
    if ($installedHash -ne $expectedHash) {
      throw "Installed librooneyj.so hash mismatch: got $installedHash, expected $expectedHash"
    }
    [ordered]@{ primaryCpuAbi = "armeabi"; remoteLib = $remoteLib; installedLibSha256 = $installedHash }
  } finally {
    Invoke-MumuUnroot -Context $Context
  }
}

function Invoke-MumuInstallClient {
  param($Context, $Artifacts)
  Invoke-MumuAdbStage -Context $Context -Name "force-stop-before-install" -Arguments @("shell", "am", "force-stop", $script:MumuConfig.Package) -TimeoutSeconds 10 -AllowFailure | Out-Null
  $install = Invoke-MumuAdbStage -Context $Context -Name "install-client-baseline" -Arguments @("-s", $Serial, "install", "-r", $Artifacts.apkPath) -TimeoutSeconds 900 -WithoutSerial -AllowFailure
  if ((-not $install.ok) -or "$($install.stdout) $($install.stderr)" -notmatch "Success") {
    throw "Android 12 client install failed: $($install.stderr) $($install.stdout)"
  }
  Invoke-MumuGrantLegacyPermissions -Context $Context
  Invoke-MumuVerifyInstalledClient -Context $Context -Artifacts $Artifacts
}

function New-MumuVerifyScript {
  $path = [System.IO.Path]::GetTempFileName()
  $content = @'
#!/system/bin/sh
cd "$1" || exit 2
sha256sum -c "$2" >"$3" 2>&1
'@
  [System.IO.File]::WriteAllText($path, ($content -replace "`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
  $path
}

function Invoke-MumuInstallResources {
  param($Context, $Artifacts)
  $manifest = $Artifacts.resourceManifest
  $expectedFiles = [int]$manifest.resourcePack.fileCount
  if ($expectedFiles -lt 6000) { throw "Refusing incomplete resource pack with only $expectedFiles files." }
  $verifyScript = New-MumuVerifyScript
  try {
    Invoke-MumuAdbStage -Context $Context -Name "force-stop-before-resource-install" -Arguments @("shell", "am", "force-stop", $script:MumuConfig.Package) -TimeoutSeconds 10 -AllowFailure | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "mkdir-device-save" -Arguments @("shell", "mkdir", "-p", $script:MumuConfig.DeviceSaveDir) -TimeoutSeconds 10 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "device-storage-before-resource-install" -Arguments @("shell", "df", "-k", "/storage/emulated/0") -TimeoutSeconds 10 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "push-resource-pack" -Arguments @("push", $Artifacts.packPath, $script:MumuConfig.RemoteResourcePack) -TimeoutSeconds 1800 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "push-resource-checksums" -Arguments @("push", $Artifacts.checksumsPath, $script:MumuConfig.RemoteChecksums) -TimeoutSeconds 120 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "push-resource-verifier" -Arguments @("push", $verifyScript, $script:MumuConfig.RemoteVerifyScript) -TimeoutSeconds 30 | Out-Null
    Invoke-MumuAdbStage -Context $Context -Name "extract-resource-pack" -Arguments @("shell", "tar", "-xf", $script:MumuConfig.RemoteResourcePack, "-C", $script:MumuConfig.DeviceSaveDir) -TimeoutSeconds 1200 | Out-Null
    $verify = Invoke-MumuAdbStage -Context $Context -Name "verify-all-static-resources" -Arguments @("shell", "sh", $script:MumuConfig.RemoteVerifyScript, $script:MumuConfig.DeviceSaveDir, $script:MumuConfig.RemoteChecksums, $script:MumuConfig.RemoteVerifyLog) -TimeoutSeconds 1200 -AllowFailure
    if (-not $verify.ok) {
      $tail = Invoke-MumuAdbStage -Context $Context -Name "resource-verification-failure-tail" -Arguments @("shell", "tail", "-n", "40", $script:MumuConfig.RemoteVerifyLog) -TimeoutSeconds 20 -AllowFailure
      throw "Static resource checksum verification failed: $($tail.stdout) $($tail.stderr)"
    }
    [ordered]@{
      fileCount = $expectedFiles
      payloadBytes = [int64]$manifest.resourcePack.payloadBytes
      packSha256 = ($manifest.resourcePack.sha256 -as [string])
      mutableSavePreserved = "appdata/save_appdata"
      deviceSaveDir = $script:MumuConfig.DeviceSaveDir
    }
  } finally {
    Remove-Item -LiteralPath $verifyScript -Force -ErrorAction SilentlyContinue
    foreach ($remote in @($script:MumuConfig.RemoteResourcePack, $script:MumuConfig.RemoteChecksums, $script:MumuConfig.RemoteVerifyScript, $script:MumuConfig.RemoteVerifyLog)) {
      Invoke-MumuAdbStage -Context $Context -Name ("cleanup-" + [System.IO.Path]::GetFileName($remote)) -Arguments @("shell", "rm", "-f", $remote) -TimeoutSeconds 30 -AllowFailure | Out-Null
    }
  }
}

function Get-MumuStatus {
  param($Context, $Artifacts, $Device)
  $package = Invoke-MumuAdbStage -Context $Context -Name "status-package" -Arguments @("shell", "pm", "path", $script:MumuConfig.Package) -TimeoutSeconds 10 -AllowFailure
  $hosts = Invoke-MumuAdbStage -Context $Context -Name "status-hosts" -Arguments @("shell", "cat", $script:MumuConfig.HostsPath) -TimeoutSeconds 10 -AllowFailure
  $hostsOk = $hosts.ok
  foreach ($domain in $script:MumuConfig.Domains) {
    $hostsOk = $hostsOk -and ($hosts.stdout -match "(?m)^$([regex]::Escape($GuestHost))\s+$([regex]::Escape($domain))\s*$")
  }
  $sentinels = @()
  $resourcesOk = $true
  if ($Artifacts) {
    foreach ($sentinel in @($Artifacts.resourceManifest.sentinels)) {
      $remotePath = "$($script:MumuConfig.DeviceSaveDir)/$($sentinel.path)"
      $hash = Invoke-MumuAdbStage -Context $Context -Name ("status-resource-" + (($sentinel.path -as [string]) -replace "[^A-Za-z0-9]+", "-")) -Arguments @("shell", "sha256sum", $remotePath) -TimeoutSeconds 60 -AllowFailure
      $actual = if ($hash.ok) { @($hash.stdout -split "\s+")[0].ToUpperInvariant() } else { "" }
      $matches = $actual -eq (($sentinel.sha256 -as [string]).ToUpperInvariant())
      $resourcesOk = $resourcesOk -and $matches
      $sentinels += [ordered]@{ path = $sentinel.path; ok = $matches; expected = $sentinel.sha256; actual = $actual }
    }
  } else {
    $resourcesOk = $false
  }
  $tcp50005 = Invoke-MumuAdbStage -Context $Context -Name "status-server-50005" -Arguments @("shell", "curl", "-fsS", "--max-time", "3", "http://${GuestHost}:50005/healthz") -TimeoutSeconds 6 -AllowFailure
  $tcp10001 = Invoke-MumuAdbStage -Context $Context -Name "status-server-10001" -Arguments @("shell", "curl", "-fsS", "--max-time", "3", "http://${GuestHost}:10001/healthz") -TimeoutSeconds 6 -AllowFailure
  [ordered]@{
    device = $Device
    packageInstalled = ($package.ok -and $package.stdout -match "^package:")
    hostsOk = $hostsOk
    resourcesOk = $resourcesOk
    resourceSentinels = $sentinels
    server50005Reachable = ($tcp50005.ok -and $tcp50005.stdout -match '"ok"\s*:\s*true')
    server10001Reachable = ($tcp10001.ok -and $tcp10001.stdout -match '"ok"\s*:\s*true')
  }
}

function Invoke-MumuStartServer {
  param($Context)
  $serverScript = Join-Path $PSScriptRoot "kssma-server.ps1"
  $stage = Invoke-RuntimeProcess -FilePath "powershell" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $serverScript, "start") -TimeoutSeconds 30 -AllowFailure
  Add-MumuStage $Context "start-local-server" $stage
  if (-not $stage.ok) { throw "Local server start failed: $($stage.stderr) $($stage.stdout)" }
}

function Invoke-MumuLaunch {
  param($Context)
  Invoke-MumuAdbStage -Context $Context -Name "clear-logcat-before-launch" -Arguments @("logcat", "-c") -TimeoutSeconds 10 -AllowFailure | Out-Null
  Invoke-MumuAdbStage -Context $Context -Name "force-stop-before-launch" -Arguments @("shell", "am", "force-stop", $script:MumuConfig.Package) -TimeoutSeconds 10 -AllowFailure | Out-Null
  $start = Invoke-MumuAdbStage -Context $Context -Name "start-logo-activity" -Arguments @("shell", "am", "start", "-n", "$($script:MumuConfig.Package)/$($script:MumuConfig.Activity)") -TimeoutSeconds 20
  Start-Sleep -Seconds 10
  $gamePid = Invoke-MumuAdbStage -Context $Context -Name "launch-pid" -Arguments @("shell", "pidof", $script:MumuConfig.Package) -TimeoutSeconds 10 -AllowFailure
  $activity = Invoke-MumuAdbStage -Context $Context -Name "launch-top-activity" -Arguments @("shell", "dumpsys", "activity", "activities") -TimeoutSeconds 20 -AllowFailure
  Invoke-MumuAdbStage -Context $Context -Name "capture-launch-screenshot" -Arguments @("shell", "screencap", "-p", "/sdcard/Download/kssma-mumu-a12-last-launch.png") -TimeoutSeconds 30 | Out-Null
  Invoke-MumuAdbStage -Context $Context -Name "pull-launch-screenshot" -Arguments @("pull", "/sdcard/Download/kssma-mumu-a12-last-launch.png", $script:LastLaunchScreenshot) -TimeoutSeconds 60 | Out-Null
  $logcat = Invoke-MumuAdbStage -Context $Context -Name "launch-logcat" -Arguments @("logcat", "-d", "-v", "brief") -TimeoutSeconds 30 -AllowFailure
  $fatal = "$($logcat.stdout) $($logcat.stderr)" -match "FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGABRT"
  $top = @($activity.stdout -split "\r?\n" | Where-Object { $_ -match "topResumedActivity" } | Select-Object -First 1)
  if ((-not $gamePid.ok) -or [string]::IsNullOrWhiteSpace($gamePid.stdout) -or $fatal) {
    throw "Client did not survive the ten-second post-launch gate. pid=$($gamePid.stdout); fatal=$fatal"
  }
  [ordered]@{ pid = $gamePid.stdout.Trim(); topActivity = ($top -join ""); screenshot = $script:LastLaunchScreenshot; fatal = $fatal; start = $start.stdout }
}

function Invoke-MumuSelfCheck {
  param($Context)
  if (-not (Test-MumuIpv4Literal "10.0.2.2")) { throw "IPv4 classifier rejected the default guest host." }
  if (Test-MumuIpv4Literal "game.ma.mobimon.com.tw") { throw "IPv4 classifier accepted a hostname." }
  $fixture = "127.0.0.1 localhost`n::1 ip6-localhost`n192.0.2.1 keep.example game.ma.mobimon.com.tw # keep alias`n10.0.2.3 dlc.game-CBT.ma.sdo.com`n"
  $merged = Merge-MumuHostsText -Current $fixture -Address "10.0.2.2"
  $mergedTwice = Merge-MumuHostsText -Current $merged -Address "10.0.2.2"
  if ($merged -ne $mergedTwice) { throw "Hosts merge is not idempotent." }
  if ($merged -notmatch "192\.0\.2\.1\s+keep\.example") { throw "Hosts merge removed an unrelated alias." }
  foreach ($domain in $script:MumuConfig.Domains) {
    if (@([regex]::Matches($merged, "(?m)^10\.0\.2\.2\s+$([regex]::Escape($domain))$")).Count -ne 1) {
      throw "Hosts merge did not produce exactly one mapping for $domain."
    }
  }
  foreach ($path in @($script:MumuConfig.DeviceSaveDir, $script:MumuConfig.RemoteResourcePack, $script:MumuConfig.HostsBackupPath)) {
    if (-not $path.StartsWith("/storage/emulated/0/Android/data/com.square_enix.million_cn/") -and -not $path.StartsWith("/data/local/tmp/kssma-") -and -not $path.StartsWith("/system/etc/hosts.kssma-")) {
      throw "Unsafe device mutation path in MuMu config: $path"
    }
  }
  Add-MumuStage $Context "self-check" ([ordered]@{ ok = $true; elapsedMs = 0; details = "IPv4, hosts idempotence, alias preservation, and exact mutation paths passed." })
  [ordered]@{ checks = 7; hosts = $merged }
}

$ctx = New-MumuContext -Name $Command
try {
  $resultData = switch ($Command) {
    "self-check" { Invoke-MumuSelfCheck -Context $ctx }
    "prepare" {
      $artifacts = Invoke-MumuPrepare -Context $ctx
      [ordered]@{ apk = $artifacts.apkPath; resourcePack = $artifacts.packPath; fileCount = [int]$artifacts.resourceManifest.resourcePack.fileCount }
    }
    "deploy" {
      $artifacts = Ensure-MumuArtifacts -Context $ctx -ForceRebuild:$Rebuild
      $device = Invoke-MumuDeviceGate -Context $ctx
      $client = Invoke-MumuInstallClient -Context $ctx -Artifacts $artifacts
      $hosts = Invoke-MumuEnsureHosts -Context $ctx
      $resources = Invoke-MumuInstallResources -Context $ctx -Artifacts $artifacts
      if ($StartServer) { Invoke-MumuStartServer -Context $ctx }
      $launchData = $null
      if ($Launch) { $launchData = Invoke-MumuLaunch -Context $ctx }
      $status = Get-MumuStatus -Context $ctx -Artifacts $artifacts -Device $device
      if (-not $status.packageInstalled -or -not $status.hostsOk -or -not $status.resourcesOk) {
        throw "Final deployment status failed: package=$($status.packageInstalled); hosts=$($status.hostsOk); resources=$($status.resourcesOk)"
      }
      if (($StartServer -or $Launch) -and (-not $status.server50005Reachable -or -not $status.server10001Reachable)) {
        throw "Final guest-to-server health failed: port50005=$($status.server50005Reachable); port10001=$($status.server10001Reachable)"
      }
      [ordered]@{ client = $client; hosts = $hosts; resources = $resources; launch = $launchData; status = $status }
    }
    "status" {
      $artifacts = $null
      try { $artifacts = Get-MumuArtifacts -Context $ctx } catch { $ctx.warnings += $_.Exception.Message }
      $device = Invoke-MumuDeviceGate -Context $ctx
      Get-MumuStatus -Context $ctx -Artifacts $artifacts -Device $device
    }
    "install-client" {
      $artifacts = Ensure-MumuArtifacts -Context $ctx -ForceRebuild:$Rebuild
      $device = Invoke-MumuDeviceGate -Context $ctx
      $client = Invoke-MumuInstallClient -Context $ctx -Artifacts $artifacts
      [ordered]@{ device = $device; client = $client; apk = $artifacts.apkPath }
    }
    "ensure-hosts" {
      $device = Invoke-MumuDeviceGate -Context $ctx
      [ordered]@{ device = $device; hosts = (Invoke-MumuEnsureHosts -Context $ctx) }
    }
    "restore-hosts" {
      $device = Invoke-MumuDeviceGate -Context $ctx
      [ordered]@{ device = $device; hosts = (Invoke-MumuRestoreHosts -Context $ctx) }
    }
    "install-resources" {
      $artifacts = Ensure-MumuArtifacts -Context $ctx -ForceRebuild:$Rebuild
      $device = Invoke-MumuDeviceGate -Context $ctx
      [ordered]@{ device = $device; resources = (Invoke-MumuInstallResources -Context $ctx -Artifacts $artifacts) }
    }
    "launch" {
      $device = Invoke-MumuDeviceGate -Context $ctx
      if ($StartServer) { Invoke-MumuStartServer -Context $ctx }
      [ordered]@{ device = $device; launch = (Invoke-MumuLaunch -Context $ctx) }
    }
  }
  foreach ($key in $resultData.Keys) { $ctx.data[$key] = $resultData[$key] }
  $result = Complete-MumuResult -Context $ctx -Ok $true
} catch {
  $ctx.data["error"] = $_.Exception.Message
  $result = Complete-MumuResult -Context $ctx -Ok $false -FailureClass "mumu-a12-deploy-failed" -Message $_.Exception.Message
}

ConvertTo-Json -InputObject $result -Depth 15
if (-not $result.ok) { exit 1 }
