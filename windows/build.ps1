<#
.SYNOPSIS
  Build Snapline.exe and (optionally) the Inno Setup installer.

.DESCRIPTION
  Mirrors the spirit of the macOS build.sh — a single command that produces
  the shippable artifact in windows\dist\.

  Outputs:
    windows\build\Snapline.exe                    self-contained single-file
    windows\dist\Snapline-Setup-<version>.exe     installer (if Inno present)

.PARAMETER Configuration
  Release (default) or Debug.

.PARAMETER SkipInstaller
  Build the .exe only, don't run Inno Setup.

.PARAMETER SignCert
  Optional PFX file used to Authenticode-sign the .exe and the installer.

.PARAMETER SignPassword
  Optional password for the PFX file.

.EXAMPLE
  pwsh windows\build.ps1
  pwsh windows\build.ps1 -SkipInstaller
  pwsh windows\build.ps1 -SignCert C:\certs\snapline.pfx -SignPassword 'hunter2'
#>

param(
    [ValidateSet('Release','Debug')]
    [string]$Configuration = 'Release',
    [switch]$SkipInstaller,
    [string]$SignCert,
    [string]$SignPassword
)

$ErrorActionPreference = 'Stop'
$root        = $PSScriptRoot
$projectFile = Join-Path $root 'Snapline\Snapline.csproj'
$buildDir    = Join-Path $root 'build'
$distDir     = Join-Path $root 'dist'
$installerScript = Join-Path $root 'installer\Snapline.iss'

Write-Host "Snapline Windows build" -ForegroundColor Cyan
Write-Host "  Configuration : $Configuration"
Write-Host "  Build dir     : $buildDir"
Write-Host "  Dist dir      : $distDir"

if (Test-Path $buildDir) { Remove-Item $buildDir -Recurse -Force }
New-Item -ItemType Directory -Path $buildDir | Out-Null
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

dotnet publish $projectFile `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -o $buildDir

if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }

$exePath = Join-Path $buildDir 'Snapline.exe'
if (-not (Test-Path $exePath)) { throw "Snapline.exe not produced at $exePath" }

$exeSize = '{0:N1} MB' -f ((Get-Item $exePath).Length / 1MB)
Write-Host "Built Snapline.exe ($exeSize)" -ForegroundColor Green

if ($SignCert) {
    if (-not (Test-Path $SignCert)) { throw "Cert not found: $SignCert" }
    $signtool = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if (-not $signtool) { throw "signtool.exe not in PATH (install Windows SDK)" }
    Write-Host "Signing Snapline.exe…" -ForegroundColor Cyan
    $args = @('sign', '/fd', 'sha256', '/tr', 'http://timestamp.digicert.com', '/td', 'sha256', '/f', $SignCert)
    if ($SignPassword) { $args += @('/p', $SignPassword) }
    $args += $exePath
    & $signtool.Source @args
    if ($LASTEXITCODE -ne 0) { throw "signtool failed (exit $LASTEXITCODE)" }
}

if ($SkipInstaller) {
    Write-Host "Skipping installer (per -SkipInstaller)." -ForegroundColor Yellow
    return
}

$isccCandidates = @(
    (Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue).Source,
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $isccCandidates) {
    Write-Host "Inno Setup (ISCC.exe) not found. Skipping installer." -ForegroundColor Yellow
    Write-Host "  Install: winget install JRSoftware.InnoSetup" -ForegroundColor Yellow
    return
}
$iscc = $isccCandidates

Write-Host "Compiling installer with Inno Setup ($iscc)…" -ForegroundColor Cyan
& $iscc $installerScript
if ($LASTEXITCODE -ne 0) { throw "ISCC failed (exit $LASTEXITCODE)" }

if ($SignCert) {
    $installerExe = Get-ChildItem $distDir -Filter 'Snapline-Setup-*.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($installerExe) {
        Write-Host "Signing installer…" -ForegroundColor Cyan
        $args = @('sign', '/fd', 'sha256', '/tr', 'http://timestamp.digicert.com', '/td', 'sha256', '/f', $SignCert)
        if ($SignPassword) { $args += @('/p', $SignPassword) }
        $args += $installerExe.FullName
        & $signtool.Source @args
        if ($LASTEXITCODE -ne 0) { throw "signtool (installer) failed (exit $LASTEXITCODE)" }
    }
}

Write-Host "Done. Installer in: $distDir" -ForegroundColor Green
Get-ChildItem $distDir -Filter 'Snapline-Setup-*.exe' | Format-Table Name, Length, LastWriteTime
