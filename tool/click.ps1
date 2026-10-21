param(
    [int] $X,
    [int] $Y,
    [int] $ImageWidth = 1600,
    [int] $ImageHeight = 1000
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

$proc = Get-Process -Name 'media_info' -ErrorAction Stop | Select-Object -First 1
$handle = $proc.MainWindowHandle
$rect = New-Object TempClicker+RECT
[void][TempClicker]::GetWindowRect($handle, [ref]$rect)
$physWidth = $rect.Right - $rect.Left
$physHeight = $rect.Bottom - $rect.Top
$scale = $physWidth / $ImageWidth
Write-Host "window physical = ${physWidth}x${physHeight} scale=$scale"

[void][TempClicker]::SetForegroundWindow($handle)
Start-Sleep -Milliseconds 400

$px = [int]($X * $scale) + $rect.Left
$py = [int]($Y * $scale) + $rect.Top
[void][TempClicker]::SetCursorPos($px, $py)
Start-Sleep -Milliseconds 300
[TempClicker]::mouse_event(0x0002, 0, 0, 0, 0)
Start-Sleep -Milliseconds 80
[TempClicker]::mouse_event(0x0004, 0, 0, 0, 0)
Start-Sleep -Milliseconds 800
Write-Host "clicked image($X,$Y) -> screen($px,$py)"
