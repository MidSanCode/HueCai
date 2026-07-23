param(
  [ValidateSet('windows','android','linux','macos','web')][string]$Platform = 'windows',
  [ValidateSet('release','debug','profile')][string]$Mode = 'release',
  [switch]$Clean = $true,
  [switch]$Zip = $true
)

$ErrorActionPreference = 'Stop'

Write-Host "=== 绘彩 (HueCai) Build Script ===" -ForegroundColor Cyan
Write-Host "Platform: $Platform" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Cyan

# Read version from pubspec.yaml
$pubspec = Get-Content -Path "pubspec.yaml" -Raw
$verMatch = [regex]::Match($pubspec, '^version:\s*([\d\.]+\+\d+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $verMatch.Success) {
  Write-Error "Cannot find version in pubspec.yaml"
  exit 1
}
$versionString = $verMatch.Groups[1].Value
$parts = $versionString.Split('+')
$buildName = $parts[0]
$buildNumber = $parts[1]

Write-Host "Version: $buildName+$buildNumber" -ForegroundColor Green

# Read config.json for dart-define
$configPath = "config.json"
$dartDefineArgs = @()
if (Test-Path $configPath) {
  Write-Host "Using config.json for dart-define-from-file" -ForegroundColor Yellow
  $dartDefineArgs += "--dart-define-from-file=$configPath"
}

if ($Clean) {
  Write-Host "Cleaning..." -ForegroundColor Yellow
  flutter clean
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Getting dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Building for $Platform ($Mode)..." -ForegroundColor Yellow
$buildArgs = @(
  "build", $Platform,
  "--$Mode",
  "--build-name=$buildName",
  "--build-number=$buildNumber"
)
$buildArgs += $dartDefineArgs

flutter $buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Zip) {
  Write-Host "Packaging output..." -ForegroundColor Yellow
  $outputPath = ""
  switch ($Platform) {
    "windows" {
      $outputPath = "build\windows\x64\runner\$Mode"
    }
    "android" {
      $outputPath = "build\app\outputs\flutter-apk"
    }
    "linux" {
      $outputPath = "build\linux\x64\$Mode\bundle"
    }
    "macos" {
      $outputPath = "build\macos\Build\Products\$Mode"
    }
    "web" {
      $outputPath = "build\web"
    }
  }

  if (Test-Path $outputPath) {
    $zipName = "huecai-$Platform-$buildName+$buildNumber.zip"
    Write-Host "Creating $zipName..." -ForegroundColor Yellow
    Compress-Archive -Path "$outputPath\*" -DestinationPath $zipName -Force
    Write-Host "Package created: $zipName" -ForegroundColor Green
  } else {
    Write-Warning "Output path not found: $outputPath"
  }
}

Write-Host "=== Build Complete ===" -ForegroundColor Cyan
