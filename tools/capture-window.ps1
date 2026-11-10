# Captures a real screenshot of a window (by title substring) via PrintWindow.
#   capture-window.ps1 -Title "InfluxDB" -Out shot.png
param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][string]$Out, [switch]$List, [switch]$Screen)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinCap {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[WinCap]::SetProcessDPIAware() | Out-Null

$found = New-Object System.Collections.ArrayList
$cb = [WinCap+EnumProc]{ param($h, $l)
  if ([WinCap]::IsWindowVisible($h)) {
    $sb = New-Object System.Text.StringBuilder 512
    [WinCap]::GetWindowText($h, $sb, 512) | Out-Null
    $t = $sb.ToString()
    if ($t) { [void]$found.Add([pscustomobject]@{H=$h; T=$t}) }
  }
  $true }
[WinCap]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
if ($List) { $found | ForEach-Object { $_.T }; return }

$w = $found | Where-Object { $_.T -eq $Title } | Select-Object -First 1
if (-not $w) { $w = $found | Where-Object { $_.T -like "*$Title*" } | Select-Object -First 1 }
if (-not $w) { throw "Window '$Title' not found" }

$r = New-Object WinCap+RECT
[WinCap]::GetWindowRect($w.H, [ref]$r) | Out-Null
if ($Screen) {   # copy the visible window area from the screen (for windows PrintWindow can't render)
  $v = New-Object WinCap+RECT
  [WinCap]::DwmGetWindowAttribute($w.H, 9, [ref]$v, 16) | Out-Null
  $bmp = New-Object System.Drawing.Bitmap ($v.R - $v.L), ($v.B - $v.T)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($v.L, $v.T, 0, 0, $bmp.Size); $g.Dispose()
  $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  "saved $Out ($($w.T), screen)"; return
}
$wd = $r.R - $r.L; $ht = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $wd, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[WinCap]::PrintWindow($w.H, $hdc, 2) | Out-Null   # PW_RENDERFULLCONTENT
$g.ReleaseHdc($hdc); $g.Dispose()

# crop the invisible DWM border
$v = New-Object WinCap+RECT
if ([WinCap]::DwmGetWindowAttribute($w.H, 9, [ref]$v, 16) -eq 0) {
  $cx = $v.L - $r.L; $cy = $v.T - $r.T; $cw = $v.R - $v.L; $ch = $v.B - $v.T
  if ($cw -gt 0 -and $ch -gt 0 -and ($cx -gt 0 -or $cy -gt 0 -or $cw -lt $wd)) {
    $crop = $bmp.Clone((New-Object System.Drawing.Rectangle $cx, $cy, $cw, $ch), $bmp.PixelFormat)
    $bmp.Dispose(); $bmp = $crop
  }
}
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
"saved $Out ($($w.T))"
