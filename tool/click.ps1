param(
    [int] $X,
    [int] $Y,
    [int] $ImageWidth = 1600,
    [int] $ImageHeight = 1000,
    [int] $TargetWidth = 0,
    [int] $TargetHeight = 0,
    [switch] $Right
)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class TempClicker {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr value);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

# Make this process per-monitor DPI aware so window rects are physical pixels.
[void][TempClicker]::SetProcessDpiAwarenessContext([IntPtr](-4))
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class TempClicker2 {
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
'@

$proc = Get-Process -Name 'media_info' -ErrorAction Stop | Select-Object -First 1
$handle = $proc.MainWindowHandle
$rect = New-Object TempClicker+RECT
[void][TempClicker]::GetWindowRect($handle, [ref]$rect)
$physWidth = $rect.Right - $rect.Left
$physHeight = $rect.Bottom - $rect.Top
$scale = $physWidth / $ImageWidth
Write-Host "window physical = ${physWidth}x${physHeight} scale=$scale"

# 把窗口移到 (0,0) 并**缩放到目标尺寸**——截图工具也是这么做的。
# 两边必须用同一套坐标与尺寸，否则"点的位置"和"截出来的位置"会对不上
# （窗口默认 1280x720，截图却是 1600x1000，坐标会整体错位）。
$targetW = if ($TargetWidth -gt 0) { $TargetWidth } else { $physWidth }
$targetH = if ($TargetHeight -gt 0) { $TargetHeight } else { $physHeight }
[void][TempClicker2]::SetWindowPos($handle, [IntPtr]::Zero, 0, 0, $targetW, $targetH, 0x0040)
Start-Sleep -Milliseconds 400
[void][TempClicker]::GetWindowRect($handle, [ref]$rect)
$physWidth = $rect.Right - $rect.Left
$physHeight = $rect.Bottom - $rect.Top
$scale = $physWidth / $ImageWidth
Write-Host "window now physical = ${physWidth}x${physHeight} scale=$scale"

[void][TempClicker]::SetForegroundWindow($handle)
Start-Sleep -Milliseconds 400

$px = [int]($X * $scale) + $rect.Left
$py = [int]($Y * $scale) + $rect.Top
[void][TempClicker]::SetCursorPos($px, $py)
Start-Sleep -Milliseconds 300
if ($Right) {
    # 右键：down(0x0008) / up(0x0010)
    [TempClicker]::mouse_event(0x0008, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 80
    [TempClicker]::mouse_event(0x0010, 0, 0, 0, 0)
}
else {
    [TempClicker]::mouse_event(0x0002, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 80
    [TempClicker]::mouse_event(0x0004, 0, 0, 0, 0)
}
Start-Sleep -Milliseconds 800
Write-Host "clicked image($X,$Y) -> screen($px,$py)$(if ($Right) { ' [right]' })"
