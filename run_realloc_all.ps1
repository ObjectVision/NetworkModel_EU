# run_realloc_all.ps1 [-Tag nuts] [-Skip Norway,SE2,SE3]
#
# Re-run ONLY the `alloc` step, on BOTH pipeline sides, for every area. The networks and
# ODs are already rebuilt (step 1); this just regenerates the client/facility exports so
# they carry the new NUTS column that the region-exclusion rule (issue #49) reads.
#
# The rule takes its verdict from the EXISTING client table, so BOTH sides must be
# re-exported before it can judge an area.
#
# Skips the areas that cannot be rebuilt at all (issue #50) and any area handled elsewhere.
param(
  [string]$Tag  = "nuts",
  [string]$Skip = "Norway,SE2,SE3"
)
$ErrorActionPreference = "Continue"
$env:NoDefaultCurrentDirectoryInExePath = $null
Set-Location 'E:\prj\JRC\NetworkModel_EU'

$prog = "logs\realloc_$Tag.log"
$csv  = "scratch\realloc_$Tag.csv"
function Log($m) { "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m | Tee-Object -FilePath $prog -Append }

# NB: build the skip set explicitly and filter with an inline test. An earlier version
# used `$skip -notcontains $_` after a ForEach-Object and silently kept ALL 42 areas,
# which would have collided with work running on the skipped ones.
# NB: $skipSet, NOT $skip -- PowerShell variables are case-INsensitive, so $skip would
# silently overwrite the $Skip parameter (this bit once already, and again with $Tag).
$skipSet = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($s in ($Skip -split ',')) { [void]$skipSet.Add($s.Trim()) }
$all  = @((Get-Content doc\deck_data.json -Raw | ConvertFrom-Json) | ForEach-Object { [string]$_.region })
$list = @($all | Where-Object { -not $skipSet.Contains($_) })
if ($list.Count -eq $all.Count -and $skipSet.Count -gt 0) {
  throw "skip filter matched nothing (skip=$($skipSet -join '|')); refusing to run over every area"
}

Log ("===== realloc $Tag START ({0} of {1} areas; skipping {2}) =====" -f $list.Count, $all.Count, (($skipSet) -join ','))
$results = @()
$n = 0
foreach ($a in $list) {
  $n++
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $row = [ordered]@{ area = $a }
  foreach ($pair in @(@('ex', 'run_pharmacy_pipeline.bat'), @('nw', 'run_new_pharmacy_pipeline.bat'))) {
    $sideTag = $pair[0]; $bat = $pair[1]
    $env:STEPS = "alloc"
    & cmd /c "$bat $a 2>&1" | Out-Null
    $row["${sideTag}_exit"] = $LASTEXITCODE
  }
  $row["secs"] = [int]$sw.Elapsed.TotalSeconds
  $results += [pscustomobject]$row
  $results | Export-Csv -NoTypeInformation -Encoding UTF8 $csv
  Log ("[{0}/{1}] {2,-12} ex={3} nw={4} ({5}s)" -f $n, $list.Count, $a, $row.ex_exit, $row.nw_exit, $row.secs)
}
$bad = $results | Where-Object { $_.ex_exit -ne 0 -or $_.nw_exit -ne 0 }
Log "===== realloc $Tag FINISHED: $($results.Count - $bad.Count) ok, $($bad.Count) failed -> $csv ====="
if ($bad) { Log ("   failed: " + (($bad | ForEach-Object { $_.area }) -join ', ')) }
