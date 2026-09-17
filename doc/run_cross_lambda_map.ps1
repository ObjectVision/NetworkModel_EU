# Render the cross-lambda map with the installed GeoDMS GUI (cfg/cross_lambda_map.dms): one headless run per capture
# (viewport, then layer control), each driven by a /T script that copies to the clipboard and
# closes the app; the clipboard image is saved as PNG. Run unsandboxed (the GUI must be able to
# own the clipboard and draw). Output: doc\charts\cross_lambda_map_viewport.png and
# doc\charts\cross_lambda_map_legend.png.
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Name Win32 -Namespace '' -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
$gui = 'C:\Program Files\ObjectVision\GeoDms20.19.1.m\GeoDmsGuiQt.exe'
$cfg = 'E:\prj\JRC\NetworkModel_EU\cfg\cross_lambda_map.dms'
$out = 'E:\prj\JRC\NetworkModel_EU\doc\charts'
New-Item -ItemType Directory -Force $out | Out-Null

function Capture([string]$script, [string]$png) {
  $log = "E:\prj\JRC\NetworkModel_EU\logs\cross_lambda_map_$([IO.Path]::GetFileNameWithoutExtension($script)).log"
  if (Test-Path $log) { Remove-Item $log }
  [System.Windows.Forms.Clipboard]::Clear()
  $p = Start-Process -FilePath $gui -ArgumentList @("/L$log", "/TE:\prj\JRC\NetworkModel_EU\doc\$script", $cfg) -PassThru
  # maximise the main window before the script's DefaultView + TileSubWindows fire (10 + 6 s);
  # the handle seen at 4 s can still be the splash, so keep at it until the copy is due
  foreach ($t in 4, 3, 2, 2, 2) {
    Start-Sleep $t
    $p.Refresh()
    if ($p.MainWindowHandle -ne 0) { [Win32]::ShowWindowAsync($p.MainWindowHandle, 3) | Out-Null }
  }
  "  main window handle $($p.MainWindowHandle) maximised"
  $ok = $p.WaitForExit(120000)
  if (-not $ok) { "  timeout: killing GeoDmsGuiQt"; Stop-Process -Id $p.Id -Force }
  Start-Sleep 1
  $img = [System.Windows.Forms.Clipboard]::GetImage()
  if ($img) { $img.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); "  saved $png ($($img.Width)x$($img.Height))" }
  else { "  NO IMAGE on the clipboard after $script" }
  Select-String -Path $log -Pattern 'Execute|error|\[E\]' | Select-Object -First 6 | ForEach-Object { '  log: ' + $_.Line.Substring(0, [Math]::Min(160, $_.Line.Length)) }
}
"viewport:"; Capture 'cross_lambda_map_copy.dmsscript'   "$out\cross_lambda_map_viewport.png"
"legend:";   Capture 'cross_lambda_map_copylc.dmsscript' "$out\cross_lambda_map_legend.png"
