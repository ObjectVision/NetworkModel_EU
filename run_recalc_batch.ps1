# run_recalc_batch.ps1 -Areas <a,b,c> [-Threads 3] [-Tag q1]
# Recalculation worker (doc/todo.md #1 + #8): for each area in the list, sequentially
#   1. delete the stale NewPharmacies network (.mmd dirs + .xml) — belt-and-braces;
#      the candidate-set config change already invalidates GeoDMS's cache
#   2. run_new_pharmacy_pipeline.bat <area>   (network1 network2 alloc)
#   3. re-sweep LINEAR + LOGISTIC (adapted logit is the settings.jl default)
# Existing-pharmacy ODs are untouched (candidate change only affects the New side).
# Progress -> logs\recalc_<Tag>.log; sweep logs overwrite logs\sweep_<area>_<FUNC>.log.
param(
  [Parameter(Mandatory=$true)][string]$Areas,
  [int]$Threads = 3,
  [string]$Tag = "q"
)
$ErrorActionPreference = "Continue"
$env:NoDefaultCurrentDirectoryInExePath = $null
Set-Location 'E:\prj\JRC\NetworkModel_EU'
$NW = 'C:\LocalData\networkmodel_eu\NewPharmacies'
$prog = "logs\recalc_$Tag.log"
function Log($m) { "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m | Tee-Object -FilePath $prog -Append }

$list = $Areas -split ','
Log "===== recalc worker $Tag START ($($list.Count) areas, threads=$Threads) ====="
foreach ($a in $list) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Log "----- $a -----"

  # 1. purge stale network artefacts (mmd are DIRECTORIES -> -Recurse)
  if (Test-Path "$NW\$a") {
    Get-ChildItem "$NW\$a" -Filter "*set_O-1km*" | ForEach-Object {
      try { Remove-Item $_.FullName -Recurse -Force -Confirm:$false -ErrorAction Stop } catch { Log "  [warn] purge $($_.Name): $_" }
    }
    Log "  purged network artefacts"
  }

  # 2. rebuild network + OD export
  $env:STEPS = "network1 network2 alloc"
  & cmd /c "run_new_pharmacy_pipeline.bat $a" *> $null
  if (-not (Test-Path "$NW\${a}_od.arrow")) { Log "  [FAIL] no OD arrow after rebuild - skipping $a"; continue }
  Log ("  network+OD rebuilt ({0}s)" -f [int]$sw.Elapsed.TotalSeconds)

  # 3. sweeps
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
