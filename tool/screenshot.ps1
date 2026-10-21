#Requires -Version 5.1
<#
.SYNOPSIS
    截取 Windows 桌面应用窗口的画面，保存为 PNG。

.DESCRIPTION
    用于真机验收：把应用窗口的真实渲染结果抓下来，肉眼核对界面。
    按进程名找窗口（不是抓整个屏幕），抓到的是窗口矩形范围内的像素。

.PARAMETER ProcessName
    目标进程名（不含 .exe），例如 media_info。

.PARAMETER OutputPath
    输出 PNG 的路径。目录会自动创建。

.PARAMETER WindowTitle
    可选：按窗口标题做进一步匹配（子串，大小写不敏感）。

.PARAMETER TimeoutSeconds
    等窗口出现的超时秒数。默认 30。

.EXAMPLE
    pwsh tool/screenshot.ps1 -ProcessName media_info -OutputPath build/screenshots/main.png

.EXAMPLE
    pwsh tool/screenshot.ps1 -ProcessName media_info -OutputPath build/screenshots/main.png -WindowTitle media_info
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ProcessName,

    [Parameter(Mandatory = $true)]
    [string] $OutputPath,

    [string] $WindowTitle,

    [int] $TimeoutSeconds = 30,

    [int] $Width = 0,

    [int] $Height = 0
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

if (-not ('MediaInfoShot.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace MediaInfoShot
{
    public struct RECT { public int Left, Top, Right, Bottom; }

    public static class Native
    {
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref RECT lpPoint);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
        [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    }
}
'@
}

function Get-TargetProcessId {
    param([string] $Name)
    $procs = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return $null }
    return $procs[0].Id
}

function Find-Window {
    param([int] $ProcessId, [string] $TitleFilter)

    $found = [IntPtr]::Zero
    $callback = [MediaInfoShot.Native+EnumWindowsProc] {
        param([IntPtr] $hWnd, [IntPtr] $lParam)
        # NOTE: do not name this $pid - PowerShell's $PID is read-only and the
        # scriptblock runs in PowerShell, not in C#.
        $ownerPid = 0
        [void][MediaInfoShot.Native]::GetWindowThreadProcessId($hWnd, [ref] $ownerPid)
        if ($ownerPid -ne $ProcessId) { return $true }
        if (-not [MediaInfoShot.Native]::IsWindowVisible($hWnd)) { return $true }

        $len = [MediaInfoShot.Native]::GetWindowTextLength($hWnd)
        if ($len -le 0) { return $true }
        $sb = New-Object System.Text.StringBuilder ($len + 1)
        [void][MediaInfoShot.Native]::GetWindowText($hWnd, $sb, $sb.Capacity)
        $title = $sb.ToString()

        if ($TitleFilter -and ($title -notlike "*$TitleFilter*")) { return $true }

        $script:found = $hWnd
        $script:foundTitle = $title
        return $false
    }
    $script:found = [IntPtr]::Zero
    $script:foundTitle = ''
    [void][MediaInfoShot.Native]::EnumWindows($callback, [IntPtr]::Zero)
    return @{ Handle = $script:found; Title = $script:foundTitle }
}

$procId = Get-TargetProcessId -Name $ProcessName
if (-not $procId) {
    throw "找不到进程 '$ProcessName'。请先启动应用。"
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$window = $null
while ((Get-Date) -lt $deadline) {
    $window = Find-Window -ProcessId $procId -TitleFilter $WindowTitle
    if ($window.Handle -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 300
}
if (-not $window -or $window.Handle -eq [IntPtr]::Zero) {
    throw "进程 '$ProcessName' 存在，但找不到可见窗口（等了 $TimeoutSeconds 秒）。"
}

#  bring the window to the front so the capture is not occluded
[void][MediaInfoShot.Native]::ShowWindow($window.Handle, 9)   # SW_RESTORE
[void][MediaInfoShot.Native]::SetForegroundWindow($window.Handle)
Start-Sleep -Milliseconds 300

# Park the window at a known position/size so the capture is deterministic and
# does not include desktop chrome (the Flutter default window can open partly
# off-screen, which used to bleed a strip of wallpaper into the capture).
$pre = New-Object MediaInfoShot.RECT
[void][MediaInfoShot.Native]::GetWindowRect($window.Handle, [ref] $pre)
$targetWidth = if ($Width -gt 0) { $Width } else { $pre.Right - $pre.Left }
$targetHeight = if ($Height -gt 0) { $Height } else { $pre.Bottom - $pre.Top }
[void][MediaInfoShot.Native]::SetWindowPos(
    $window.Handle, [IntPtr]::Zero, 0, 0, $targetWidth, $targetHeight, 0x0040)  # SWP_NOZORDER
Start-Sleep -Milliseconds 500

$rect = New-Object MediaInfoShot.RECT
[void][MediaInfoShot.Native]::GetWindowRect($window.Handle, [ref] $rect)
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -le 0 -or $height -le 0) {
    throw "窗口尺寸异常：${width}x${height}"
}

$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$hdc = $graphics.GetHdc()
$printed = $false
try {
    # PW_RENDERFULLCONTENT (0x2) renders the window's own content even for
    # hardware-accelerated windows (Flutter draws through ANGLE/D3D), and is
    # immune to whatever else overlaps the window on screen.
    $printed = [MediaInfoShot.Native]::PrintWindow($window.Handle, $hdc, 0x00000002)
}
finally {
    $graphics.ReleaseHdc($hdc)
}

if (-not $printed) {
    # Fallback: copy from the screen. The window was moved to the top-left and
    # brought to the foreground, so this is usually fine.
    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
}

try {
    $dir = Split-Path -Parent $OutputPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

$info = Get-Item $OutputPath
Write-Host "已截图：$($info.FullName)  ($($info.Length) bytes, ${width}x${height})  窗口标题='$($window.Title)'"
