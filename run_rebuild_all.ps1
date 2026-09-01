# run_rebuild_all.ps1 [-Areas a,b,c] [-Tag all]
#
# Step 1 of doc/replan_connectivity_fix.md: purge the cached network artefacts and
# rebuild network + OD for every area on BOTH sides, under the landbody-connectivity
# fix (79cb58b) and the 20.19 MMD read-holder contract.
#
# Sweeps are NOT run here -- this step only produces the inputs and the evidence
# needed to decide which areas actually moved.
#
# Writes  scratch\rebuild_all_<Tag>.csv   (per area x side: exit code, seconds, bytes)
#         logs\rebuild_all_<Tag>.log      (progress)
param(
  [string]$Areas = "",
  [string]$Tag   = "all"
)
$ErrorActionPreference = "Continue"
$env:NoDefaultCurrentDirectoryInExePath = $null
Set-Location 'E:\prj\JRC\NetworkModel_EU'

$prog = "logs\rebuild_all_$Tag.log"
$csv  = "scratch\rebuild_all_$Tag.csv"
function Log($m) { "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m | Tee-Object -FilePath $prog -Append }

if ($Areas -ne "") { $list = $Areas -split ',' }
else { $list = (Get-Content doc\deck_data.json -Raw | ConvertFrom-Json) | ForEach-Object { $_.region } }

Log "===== rebuild-all $Tag START ($($list.Count) areas) ====="
$results = @()
$n = 0
foreach ($a in $list) {
  $n++
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Log "----- [$n/$($list.Count)] $a -----"

  # 1. purge the cached network artefacts on BOTH sides. The pattern catches both
  #    FinalSet_O-1km*.mmd/.xml and Linkset_O-1km*.mmd/.xml; the .mmd are DIRECTORIES.
  foreach ($side in 'ExistingPharmacies', 'NewPharmacies') {
    $dir = "C:\LocalData\networkmodel_eu\$side\$a"
    if (Test-Path $dir) {
      Get-ChildItem $dir -Filter "*set_O-1km*" -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Recurse -Force -Confirm:$false -ErrorAction Stop }
        catch { Log "  [warn] purge $($_.Name): $_" }
      }
    }
  }

  $row = [ordered]@{ area = $a }
  foreach ($pair in @(@('ExistingPharmacies', 'run_pharmacy_pipeline.bat'),
                      @('NewPharmacies', 'run_new_pharmacy_pipeline.bat'))) {
    $side = $pair[0]; $bat = $pair[1]
    $ssw = [Diagnostics.Stopwatch]::StartNew()
    $env:STEPS = "network1 network2 alloc"
    & cmd /c "$bat $a 2>&1" | Out-Null
    $ec = $LASTEXITCODE
    $od = "C:\LocalData\networkmodel_eu\$side\${a}_od.arrow"
    $ib = "C:\LocalData\networkmodel_eu\$side\${a}_i.arrow"
    # NB: PowerShell variables are case-INsensitive, so this must not be named $tag
    $sideTag = if ($side -eq 'ExistingPharmacies') { 'ex' } else { 'nw' }
    $row["${sideTag}_exit"]  = $ec
    $row["${sideTag}_secs"]  = [int]$ssw.Elapsed.TotalSeconds
    $row["${sideTag}_od"]    = if (Test-Path $od) { (Get-Item $od).Length } else { 0 }
    $row["${sideTag}_i"]     = if (Test-Path $ib) { (Get-Item $ib).Length } else { 0 }
    Log ("  {0,-18} exit={1} {2,4}s od={3:n0}" -f $side, $ec, [int]$ssw.Elapsed.TotalSeconds, $row["${sideTag}_od"])
  }
  $row["total_secs"] = [int]$sw.Elapsed.TotalSeconds
  $results += [pscustomobject]$row
  $results | Export-Csv -NoTypeInformation -Encoding UTF8 $csv   # incremental: survives a kill
  Log ("  DONE $a ({0}s)" -f [int]$sw.Elapsed.TotalSeconds)
}

$ok   = ($results | Where-Object { $_.ex_exit -eq 0 -and $_.nw_exit -eq 0 }).Count
$fail = $results.Count - $ok
Log "===== rebuild-all $Tag FINISHED: $ok ok, $fail failed -> $csv ====="
