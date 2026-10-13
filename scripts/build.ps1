<#
.SYNOPSIS
  Builds My Brief with the Supabase credentials baked in.

.DESCRIPTION
  The app reads SUPABASE_URL / SUPABASE_ANON_KEY at compile time via
  String.fromEnvironment (lib/core/supabase/supabase_service.dart). A build
  without them compiles to "unconfigured" mode and only shows the Setup
  screen - no sign-in, no sync. This wrapper always passes
  --dart-define-from-file, so that cannot happen by accident.

.PARAMETER Target
  windows    -> build\windows\x64\runner\Release\mybrief.exe
  apk        -> build\app\outputs\flutter-apk\app-release.apk
  appbundle  -> build\app\outputs\bundle\release\app-release.aab

.PARAMETER Config
  Path to the dart-define JSON. Defaults to config\dev.json. Relative paths
  are resolved against the repo root.

.PARAMETER NoConfig
  Build deliberately without credentials (a Setup-screen build, e.g. to check
  that an unconfigured install works).

.EXAMPLE
  .\scripts\build.ps1 windows
.EXAMPLE
  .\scripts\build.ps1 apk
.EXAMPLE
  .\scripts\build.ps1 windows -Config config\staging.json
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('windows', 'apk', 'appbundle')]
  [string]$Target = 'windows',

  [string]$Config = 'config\dev.json',

  [switch]$NoConfig
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifacts = [ordered]@{
  windows   = 'build\windows\x64\runner\Release\mybrief.exe'
  apk       = 'build\app\outputs\flutter-apk\app-release.apk'
  appbundle = 'build\app\outputs\bundle\release\app-release.aab'
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host 'flutter is not on PATH. Install it (or add its bin directory) and re-run.' -ForegroundColor Red
  exit 1
}

Push-Location $repoRoot
try {
  $flutterArgs = @('build', $Target)

  if ($NoConfig) {
    Write-Warning 'Building WITHOUT Supabase credentials - the app will open on the Setup screen.'
  }
  else {
    $configPath = if ([System.IO.Path]::IsPathRooted($Config)) {
      $Config
    }
    else {
      Join-Path $repoRoot $Config
    }

    if (-not (Test-Path -LiteralPath $configPath)) {
      Write-Host "Missing dart-define file: $configPath" -ForegroundColor Red
      Write-Host '  copy config\dev.example.json config\dev.json   # then fill in your values' -ForegroundColor Yellow
      exit 1
    }
    $flutterArgs += "--dart-define-from-file=$configPath"
  }

  Write-Host "flutter $($flutterArgs -join ' ')" -ForegroundColor Cyan
  & flutter @flutterArgs
  if ($LASTEXITCODE -ne 0) {
    Write-Host "flutter build $Target failed (exit code $LASTEXITCODE)." -ForegroundColor Red
    exit 1
  }

  $out = $artifacts[$Target]
  Write-Host "`nBuilt: $out" -ForegroundColor Green

  if ($Target -eq 'apk') {
    Write-Host "`nInstall on a connected device:`n  adb install -r `"$out`""
  }
}
finally {
  Pop-Location
}
