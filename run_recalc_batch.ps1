# run_recalc_batch.ps1 -Areas <a,b,c> [-Threads 3] [-Tag q1]
# Recalculation worker (doc/todo.md #1 + #2 + #8): for each area in the list, sequentially
#   1. purge stale network artefacts on BOTH sides (todo #2 changes the CLIENT set, and
#      the networks embed the client connections) — belt-and-braces; the config changes
#      already invalidate GeoDMS's cache
#   2. run_pharmacy_pipeline.bat <area>       (Existing: network1 network2 alloc)
#   3. run_new_pharmacy_pipeline.bat <area>   (New:      network1 network2 alloc)
#   4. re-sweep LINEAR + LOGISTIC (adapted logit is the settings.jl default)
# Progress -> logs\recalc_<Tag>.log; sweep logs overwrite logs\sweep_<area>_<FUNC>.log.
param(
  [Parameter(Mandatory=$true)][string]$Areas,
  [int]$Threads = 3,
  [string]$Tag = "q"
)
$ErrorActionPreference = "Continue"
$env:NoDefaultCurrentDirectoryInExePath = $null
Set-Location 'E:\prj\JRC\NetworkModel_EU'
$EX = 'C:\LocalData\networkmodel_eu\ExistingPharmacies'
$NW = 'C:\LocalData\networkmodel_eu\NewPharmacies'
$prog = "logs\recalc_$Tag.log"
function Log($m) { "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m | Tee-Object -FilePath $prog -Append }
function Purge($dir) {
  if (Test-Path $dir) {
    Get-ChildItem $dir -Filter "*set_O-1km*" | ForEach-Object {
      try { Remove-Item $_.FullName -Recurse -Force -Confirm:$false -ErrorAction Stop } catch { Log "  [warn] purge $($_.Name): $_" }
    }
  }
}

$list = $Areas -split ','
Log "===== recalc worker $Tag START ($($list.Count) areas, threads=$Threads) ====="
foreach ($a in $list) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Log "----- $a -----"

  # 1. purge stale network artefacts on both sides (mmd are DIRECTORIES -> -Recurse)
  Purge "$EX\$a"; Purge "$NW\$a"
  Log "  purged network artefacts (existing + new)"

  # 2. Existing side: clients changed (todo #2) -> rebuild network + OD
  $env:STEPS = "network1 network2 alloc"
  & cmd /c "run_pharmacy_pipeline.bat $a" *> $null
  if (-not (Test-Path "$EX\${a}_od.arrow")) { Log "  [FAIL] no Existing OD arrow - skipping $a"; continue }
  Log ("  existing network+OD rebuilt ({0}s)" -f [int]$sw.Elapsed.TotalSeconds)

  # 3. New side: candidate set (todo #1) + clients (todo #2) -> rebuild network + OD
  & cmd /c "run_new_pharmacy_pipeline.bat $a" *> $null
  if (-not (Test-Path "$NW\${a}_od.arrow")) { Log "  [FAIL] no New OD arrow - skipping $a"; continue }
  Log ("  new network+OD rebuilt ({0}s)" -f [int]$sw.Elapsed.TotalSeconds)

  # 4. sweeps
  $env:ROUNDING = "multistart"; $env:MAX_PARALLEL = "$Threads"; $env:COUNTRIES = "$a"
  foreach ($fn in 'LINEAR','LOGISTIC') {
    $env:TRAVEL_FUNC = $fn
    $ssw = [Diagnostics.Stopwatch]::StartNew()
    & cmd /c "julia --startup-file=no --threads=$Threads lambda_sweep_simplex.jl > logs\sweep_${a}_${fn}.log 2>&1"
    $ok = Select-String -Path "logs\sweep_${a}_${fn}.log" -Pattern 'scenario summary' -Quiet
    Log ("  sweep $fn {0} ({1}s)" -f ($(if ($ok) { 'OK' } else { 'NO-SUMMARY' }), [int]$ssw.Elapsed.TotalSeconds))
  }
  Log ("  DONE $a ({0}s total)" -f [int]$sw.Elapsed.TotalSeconds)
}
Log "===== recalc worker $Tag FINISHED ====="
