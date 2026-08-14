param(
  [switch]$AcceptAndroidSdkLicense,
  [switch]$Force,
  [switch]$SelfCheck,
  [string]$CacheDir = (Join-Path $env:LOCALAPPDATA "KSSMA-Re\downloads")
)

$ErrorActionPreference = "Stop"

$installRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk-classic-arm"
$repositoryRoot = "https://dl.google.com/android/repository"
$packages = @(
  [ordered]@{
    name = "tools_r25.2.5-windows.zip"
    url = "$repositoryRoot/tools_r25.2.5-windows.zip"
    bytes = 306785944L
    sha1 = "A7F7EBEAE1C8D8F62D3A8466E9C81BAEE7CC31CA"
    sha256 = "DA1A0BD9BB358CB52A8FC0A553A060428EFE11151E69B9EA7A5CBACB27CF1C7C"
    extractedRoot = "tools"
    destination = "tools"
  },
  [ordered]@{
    name = "armeabi-v7a-19_r05.zip"
    url = "$repositoryRoot/sys-img/android/armeabi-v7a-19_r05.zip"
    bytes = 159871567L
    sha1 = "D1A5FD4F2E1C013C3D3D9BFE7E9DB908C3ED56FA"
    sha256 = "CA7440CADE53D829A8CACE857CFAD9AFAA174C286D1B7A5D139E73CFCFDE45D7"
    extractedRoot = "armeabi-v7a"
    destination = "system-images\android-19\default\armeabi-v7a"
  }
)
$installedFiles = @(
  [ordered]@{ path = "tools\emulator.exe"; sha256 = "DCD619733884F2234790354E42643456D71557C307ED73F5E7E5C1E8A6F6F06D" },
  [ordered]@{ path = "tools\emulator-arm.exe"; sha256 = "3CA9CA373382B4998C81B72EF2EE3A2B8AA55B6DCFFC7806FDBD32FE4D65BA36" },
  [ordered]@{ path = "system-images\android-19\default\armeabi-v7a\system.img"; sha256 = "C7F65E9875455A07B5336DE67042FB83DACDB82FCF117D544EAB86D1782BF162" },
  [ordered]@{ path = "system-images\android-19\default\armeabi-v7a\userdata.img"; sha256 = "55C5283EB52440593C0AD06114DE8F3D9DFAD9D291F24413A4FD65A1E6571220" }
)

function Test-HexHash {
  param([string]$Value, [int]$Length)
  $Value -match "^[0-9A-F]{$Length}$"
}

function Test-InstalledRuntime {
  foreach ($file in $installedFiles) {
    $path = Join-Path $installRoot $file.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      return $false
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) {
      return $false
    }
  }
  return $true
}

function Assert-Archive {
  param($Package, [string]$Path)
  $item = Get-Item -LiteralPath $Path
  if ($item.Length -ne $Package.bytes) {
    throw "$($Package.name) size mismatch: got $($item.Length), expected $($Package.bytes)"
  }
  $sha1 = (Get-FileHash -LiteralPath $Path -Algorithm SHA1).Hash
  if ($sha1 -ne $Package.sha1) {
    throw "$($Package.name) SHA-1 mismatch: got $sha1, expected $($Package.sha1)"
  }
  $sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  if ($sha256 -ne $Package.sha256) {
    throw "$($Package.name) SHA-256 mismatch: got $sha256, expected $($Package.sha256)"
  }
}

function Expand-CheckedArchive {
  param($Package, [string]$ArchivePath, [string]$StageRoot)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $extractRoot = Join-Path $StageRoot ([System.IO.Path]::GetFileNameWithoutExtension($Package.name))
  New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
  $rootFull = [System.IO.Path]::GetFullPath($extractRoot).TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
  $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
  try {
    foreach ($entry in $zip.Entries) {
      $target = [System.IO.Path]::GetFullPath((Join-Path $extractRoot $entry.FullName))
      if (-not $target.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Archive entry escapes staging directory: $($entry.FullName)"
      }
    }
  } finally {
    $zip.Dispose()
  }
  [System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $extractRoot)
  $source = Join-Path $extractRoot $Package.extractedRoot
  if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "Archive root is missing after extraction: $source"
  }
  return $source
}

if ($SelfCheck) {
  if ($packages.Count -ne 2) { throw "expected two Android SDK packages" }
  foreach ($package in $packages) {
    if (-not $package.url.StartsWith("https://dl.google.com/android/repository/")) { throw "non-Google package URL: $($package.url)" }
    if ($package.bytes -le 0) { throw "invalid package size: $($package.name)" }
    if (-not (Test-HexHash $package.sha1 40)) { throw "invalid SHA-1: $($package.name)" }
    if (-not (Test-HexHash $package.sha256 64)) { throw "invalid SHA-256: $($package.name)" }
  }
  if ($installedFiles.Count -ne 4) { throw "expected four installed-file checks" }
  Write-Output "setup-android44-arm self-check passed"
  exit 0
}

if (-not $AcceptAndroidSdkLicense) {
  throw "Android SDK components require accepting Google's Android SDK License. Rerun with -AcceptAndroidSdkLicense after reviewing https://developer.android.com/studio/terms."
}

if ((Test-Path -LiteralPath $installRoot) -and (Test-InstalledRuntime) -and -not $Force) {
  Write-Output "Android 4.4 ARM runtime already matches the accepted hashes: $installRoot"
  exit 0
}
if ((Test-Path -LiteralPath $installRoot) -and -not $Force) {
  throw "Android runtime exists but does not match the accepted hashes: $installRoot. Inspect it or rerun with -Force to replace this project-specific directory."
}

New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
$stageRoot = Join-Path $env:TEMP "kssma-android44-arm-$([guid]::NewGuid())"
$newRoot = "$installRoot.new-$([guid]::NewGuid().ToString('N'))"
$backupRoot = "$installRoot.backup-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
try {
  New-Item -ItemType Directory -Path $stageRoot, $newRoot -Force | Out-Null
  foreach ($package in $packages) {
    $archivePath = Join-Path $CacheDir $package.name
    $valid = $false
    if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
      try {
        Assert-Archive -Package $package -Path $archivePath
        $valid = $true
      } catch {
        Remove-Item -LiteralPath $archivePath -Force
      }
    }
    if (-not $valid) {
      Write-Output "Downloading $($package.url)"
      Invoke-WebRequest -UseBasicParsing -Uri $package.url -OutFile $archivePath -TimeoutSec 3600
      Assert-Archive -Package $package -Path $archivePath
    }
    $source = Expand-CheckedArchive -Package $package -ArchivePath $archivePath -StageRoot $stageRoot
    $destination = Join-Path $newRoot $package.destination
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Move-Item -LiteralPath $source -Destination $destination
  }
  foreach ($file in $installedFiles) {
    $path = Join-Path $newRoot $file.path
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -ne $file.sha256) {
      throw "Installed file hash mismatch for $($file.path): got $actual, expected $($file.sha256)"
    }
  }
  if (Test-Path -LiteralPath $installRoot) {
    Move-Item -LiteralPath $installRoot -Destination $backupRoot
  }
  Move-Item -LiteralPath $newRoot -Destination $installRoot
  Write-Output "Android 4.4 ARM runtime installed: $installRoot"
  if (Test-Path -LiteralPath $backupRoot) {
    Write-Output "Previous runtime preserved at: $backupRoot"
  }
} finally {
  Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $newRoot -Recurse -Force -ErrorAction SilentlyContinue
}
