#Requires -Version 5.1
<#
.SYNOPSIS
    真机验收脚本：构建 -> 启动真实应用 -> 注入文件 -> 截屏 -> 关闭。

.DESCRIPTION
    把媒体文件通过环境变量 MEDIA_INFO_OPEN_FILES 注入应用（应用启动时读取，
    逐个开成标签页），然后用 screenshot.ps1 抓真实窗口的画面。

    这是"自己点一遍"的自动化版本：真实 exe、真实文件、真实渲染。

.PARAMETER Files
    要打开的媒体文件路径。多个用分号分隔（应用侧用 ; 分隔）。

.PARAMETER ScreenshotName
    截图文件名（不含扩展名），输出到 build/screenshots/ 下。

.PARAMETER ScreenshotWidth
    截图时的窗口宽度。0 = 保持应用默认尺寸。

.PARAMETER ScreenshotHeight
    截图时的窗口高度。0 = 保持应用默认尺寸。

.PARAMETER SettleSeconds
    启动后等待应用完成解析的秒数。

.EXAMPLE
    pwsh tool/acceptance.ps1 -Files "test\fixtures\mp4_h264_aac_320x240.normal.mp4" -ScreenshotName main

.EXAMPLE
    pwsh tool/acceptance.ps1 -Files "a.mp4;b.wav" -ScreenshotName multi -Width 1600 -Height 1000
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Files,

    [string] $ScreenshotName = 'acceptance',

    [int] $ScreenshotWidth = 1600,

    [int] $ScreenshotHeight = 1000,

    [int] $SettleSeconds = 6,

    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$exe = Join-Path $repoRoot 'build\windows\x64\runner\Release\media_info.exe'
$screenshotDir = Join-Path $repoRoot 'build\screenshots'

function Write-Step {
    param([string] $Message)
    Write-Host "==> $Message"
}

if (-not $SkipBuild) {
    Write-Step 'flutter build windows --release'
    Push-Location $repoRoot
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
    }
    finally { Pop-Location }
}
elseif (-not (Test-Path $exe)) {
    throw "找不到 $exe（先构建，或去掉 -SkipBuild）"
}

# Normalise the file list to absolute paths and check they exist.
$paths = @()
foreach ($raw in ($Files -split ';')) {
    $trimmed = $raw.Trim()
    if (-not $trimmed) { continue }
    $full = if ([System.IO.Path]::IsPathRooted($trimmed)) { $trimmed } else { Join-Path $repoRoot $trimmed }
    if (-not (Test-Path $full)) { throw "文件不存在：$full" }
    $paths += (Resolve-Path $full).Path
}
if ($paths.Count -eq 0) { throw '没有要打开的文件' }

# Make sure no stale instance is holding the exe / the port.
Get-Process -Name 'media_info' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Write-Step "启动应用并注入 $($paths.Count) 个文件"
$env:MEDIA_INFO_OPEN_FILES = ($paths -join ';')
$process = Start-Process $exe -PassThru

try {
    Write-Step "等待应用解析（$SettleSeconds 秒）"
    Start-Sleep -Seconds $SettleSeconds

    if ($process.HasExited) {
        throw "应用启动后立刻退出了（exit code $($process.ExitCode)）。"
    }

    if (-not (Test-Path $screenshotDir)) { New-Item -ItemType Directory -Force -Path $screenshotDir | Out-Null }
    $out = Join-Path $screenshotDir "$ScreenshotName.png"

    Write-Step "截屏 -> $out"
    $shotArgs = @{
        ProcessName = 'media_info'
        OutputPath  = $out
    }
    if ($ScreenshotWidth -gt 0) { $shotArgs['Width'] = $ScreenshotWidth }
    if ($ScreenshotHeight -gt 0) { $shotArgs['Height'] = $ScreenshotHeight }
    & (Join-Path $repoRoot 'tool\screenshot.ps1') @shotArgs

    Write-Host ''
    Write-Host '==> 注入的文件'
    $paths | ForEach-Object { Write-Host "    $_" }
    Write-Host ''
    Write-Host "==> 截图: $out"
}
finally {
    Get-Process -Name 'media_info' -ErrorAction SilentlyContinue | Stop-Process -Force
    Remove-Item Env:\MEDIA_INFO_OPEN_FILES -ErrorAction SilentlyContinue
}
