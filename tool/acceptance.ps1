#Requires -Version 5.1
<#
.SYNOPSIS
    真机验收：启动应用 -> 真实鼠标点击 -> 截图。

.DESCRIPTION
    把"自己点一遍"这件事脚本化：启动真实 exe（带 MEDIA_INFO_OPEN_FILES 注入文件），
    用真实的鼠标事件点击界面上的坐标，然后抓真实窗口的画面。

    坐标是**截图里的像素坐标**（相对窗口左上角），脚本自己换算成屏幕坐标并处理缩放。

.PARAMETER Files
    要打开的媒体文件，分号分隔。

.PARAMETER Click
    要依次点击的坐标，形如 "620,252"（多个用逗号分隔的组用分号隔开：
    "620,252;900,400"）。不填就只截图。

.PARAMETER ScreenshotName
    截图文件名（不含扩展名），落在 build/screenshots/ 下。

.EXAMPLE
    pwsh tool/acceptance.ps1 -Files "test\fixtures\mp4_h264_aac_320x240.normal.mp4" `
        -Click "620,252" -ScreenshotName "tree-selected"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Files,

    [string] $Click = '',

    [string] $ScreenshotName = 'acceptance',

    [int] $Width = 1600,

    [int] $Height = 1000,

    [int] $SettleSeconds = 6,

    [int] $ClickSettleMilliseconds = 700,

    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$exe = Join-Path $repoRoot 'build\windows\x64\runner\Release\media_info.exe'
$clicker = Join-Path $repoRoot 'tool\click.ps1'
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

$paths = @()
foreach ($raw in ($Files -split ';')) {
    $trimmed = $raw.Trim()
    if (-not $trimmed) { continue }
    $full = if ([System.IO.Path]::IsPathRooted($trimmed)) { $trimmed } else { Join-Path $repoRoot $trimmed }
    if (-not (Test-Path $full)) { throw "文件不存在：$full" }
    $paths += (Resolve-Path $full).Path
}
if ($paths.Count -eq 0) { throw '没有要打开的文件' }

Get-Process -Name 'media_info' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Write-Step "启动应用并注入 $($paths.Count) 个文件"
$env:MEDIA_INFO_OPEN_FILES = ($paths -join ';')
$process = Start-Process $exe -PassThru

try {
    Write-Step "等待应用解析（$SettleSeconds 秒）"
    Start-Sleep -Seconds $SettleSeconds
    if ($process.HasExited) { throw "应用启动后立刻退出了（exit $($process.ExitCode)）" }

    if ($Click) {
        foreach ($pair in ($Click -split ';')) {
            $coords = $pair.Trim() -split ','
            if ($coords.Count -lt 2) { continue }
            $x = [int]$coords[0]
            $y = [int]$coords[1]
            $right = $coords.Count -ge 3 -and $coords[2] -eq 'right'
            Write-Step "点击 ($x, $y)$(if ($right) { ' 右键' })"
            & $clicker -X $x -Y $y -ImageWidth $Width -ImageHeight $Height `
                -TargetWidth $Width -TargetHeight $Height -Right:$right | Out-Null
            Start-Sleep -Milliseconds $ClickSettleMilliseconds
        }
    }

    if (-not (Test-Path $screenshotDir)) {
        New-Item -ItemType Directory -Force -Path $screenshotDir | Out-Null
    }
    $out = Join-Path $screenshotDir "$ScreenshotName.png"

    Write-Step "截屏 -> $out"
    & (Join-Path $repoRoot 'tool\screenshot.ps1') `
        -ProcessName 'media_info' -OutputPath $out -Width $Width -Height $Height

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
