# Render the cross-lambda maps with the installed GeoDMS GUI (cfg/cross_lambda_map.dms): one
# headless run per travel-cost function, each driven by a /T script that opens the map,
# copies the viewport to the clipboard and closes the app; the clipboard image is saved as
# PNG. Run unsandboxed (the GUI must be able to own the clipboard and draw).
#   powershell -File doc\run_cross_lambda_map.ps1          -> doc\charts\cross_lambda_map_viewport_<FN>.png
# Then doc\cross_lambda_map_figure.py <FN> composes the figure with title and legend.
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Name Win32 -Namespace '' -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
$gui = 'C:\Program Files\ObjectVision\GeoDms20.19.1.m\GeoDmsGuiQt.exe'
$cfg = 'E:\prj\JRC\NetworkModel_EU\cfg\cross_lambda_map.dms'
$out = 'E:\prj\JRC\NetworkModel_EU\doc\charts'
New-Item -ItemType Directory -Force $out | Out-Null

function Capture([string]$script, [string]$png) {
  $log = "E:\prj\JRC\NetworkModel_EU\logs\cross_lambda_map_$([IO.Path]::GetFileNameWithoutExtension($script)).log"
  if (Test-Path $log) { [IO.File]::Delete($log) }
  [System.Windows.Forms.Clipboard]::Clear()
  $p = Start-Process -FilePath $gui -ArgumentList @("/L$log", "/TE:\prj\JRC\NetworkModel_EU\doc\$script", $cfg) -PassThru
  # maximise the main window before the script's DefaultView + TileSubWindows fire (10 + 6 s);
  # the handle seen at 4 s can still be the splash, so keep at it until the copy is due
  foreach ($t in 4, 3, 2, 2, 2) {
    Start-Sleep $t
    $p.Refresh()
    if ($p.MainWindowHandle -ne 0) { [Win32]::ShowWindowAsync($p.MainWindowHandle, 3) | Out-Null }
  }
  $ok = $p.WaitForExit(120000)
  if (-not $ok) { "  timeout: killing GeoDmsGuiQt"; Stop-Process -Id $p.Id -Force }
  Start-Sleep 1
  $img = [System.Windows.Forms.Clipboard]::GetImage()
  if ($img) { $img.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); "  saved $png ($($img.Width)x$($img.Height))" }
  else { "  NO IMAGE on the clipboard after $script" }
  Select-String -Path $log -Pattern 'error|\[E\]' | Select-Object -First 4 | ForEach-Object { '  log: ' + $_.Line.Substring(0, [Math]::Min(160, $_.Line.Length)) }
}
foreach ($fn in 'LINEAR', 'LOGISTIC') {
  "${fn}:"; Capture "cross_lambda_map_copy_$fn.dmsscript" "$out\cross_lambda_map_viewport_$fn.png"
}
