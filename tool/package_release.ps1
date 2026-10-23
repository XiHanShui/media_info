#Requires -Version 5.1
<#
.SYNOPSIS
    Builds and packages media_info release artifacts locally, without CI.

.DESCRIPTION
    Produces exactly the same package shapes as .github/workflows/build.yml:
      Windows : dist/media_info-v<version>-windows-x64.zip
                 (the whole build/windows/x64/runner/Release directory)
      macOS   : dist/media_info-v<version>-macos-universal.tar.gz
                 (the build/macos/Build/Products/Release/<name>.app bundle)

    This is the Windows-friendly counterpart of tool/package_release.sh; it
    works with Windows PowerShell 5.1 and PowerShell 7+.

.EXAMPLE
    pwsh tool/package_release.ps1
    pwsh tool/package_release.ps1 -Platform windows -SkipBuild
#>
[CmdletBinding()]
param(
    # Which platform to build and package. 'auto' picks windows on Windows.
    [ValidateSet('auto', 'windows', 'macos')]
    [string] $Platform = 'auto',

    # Version string used in the artifact name. Defaults to the version
    # declared in pubspec.yaml (build number stripped).
    [string] $Version,

    # Package an existing build output instead of running flutter build first.
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    # The script lives in <repo>/tool, so the repo root is one level up.
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-PubspecVersion {
    param([string] $RepoRoot)
    $pubspec = Join-Path $RepoRoot 'pubspec.yaml'
    $match = Select-String -Path $pubspec -Pattern '^version:\s*([0-9][^ +]*)' | Select-Object -First 1
    if (-not $match) { throw "could not read version from $pubspec" }
    return $match.Matches[0].Groups[1].Value
}

function Invoke-FlutterBuild {
    param([string] $RepoRoot, [string] $Target)
    Write-Host "==> flutter build $Target --release"
    Push-Location $RepoRoot
    try {
        flutter build $Target --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build $Target --release failed (exit $LASTEXITCODE)" }
    }
    finally {
        Pop-Location
    }
}

function Get-ArchiveSize {
    param([string] $Path)
    $item = Get-Item $Path
    return ('{0:N0} bytes ({1:N2} MB)' -f $item.Length, ($item.Length / 1MB))
}

$repoRoot = Get-RepoRoot

$onWindows = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { $IsWindows }
if ($Platform -eq 'auto') {
    $Platform = if ($onWindows) { 'windows' } else { 'macos' }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-PubspecVersion -RepoRoot $repoRoot
}

Write-Host "==> media_info v$Version ($Platform)"

if (-not $SkipBuild) {
    Invoke-FlutterBuild -RepoRoot $repoRoot -Target $Platform
}

$outDir = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

switch ($Platform) {
    'windows' {
        $src = Join-Path $repoRoot 'build/windows/x64/runner/Release'
        $exe = Join-Path $src 'media_info.exe'
        if (-not (Test-Path $exe)) { throw "media_info.exe not found in $src" }
        $archive = Join-Path $outDir "media_info-v$Version-windows-x64.zip"
        Write-Host "==> zipping $src -> $archive"
        Compress-Archive -Path (Join-Path $src '*') -DestinationPath $archive -Force
    }
    'macos' {
        $products = Join-Path $repoRoot 'build/macos/Build/Products/Release'
        $app = Get-ChildItem -Path $products -Filter '*.app' -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $app) { throw "no .app bundle found under $products" }
        $archive = Join-Path $outDir "media_info-v$Version-macos-universal.tar.gz"
        Write-Host "==> tarring $($app.FullName) -> $archive"
        tar -czf $archive -C $products $app.Name
        if ($LASTEXITCODE -ne 0) { throw "tar failed (exit $LASTEXITCODE)" }
    }
}

Write-Host ''
Write-Host '==> artifacts'
Get-ChildItem -Path $outDir -Filter "media_info-v$Version-*" | ForEach-Object {
    Write-Host ("    {0}  ({1})" -f $_.Name, (Get-ArchiveSize -Path $_.FullName))
}
Write-Host ''
Write-Host "Done. Artifacts are in $outDir"
