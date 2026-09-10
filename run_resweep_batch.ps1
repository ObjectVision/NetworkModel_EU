# run_resweep_batch.ps1 -Areas <a,b,c> [-Threads 3] [-Tag q1]
#                       [-Funcs LINEAR,LOGISTIC] [-SkipComplete] [-RefineOnly]
# Sweep-only worker (todo #3+#4 resweep): networks/ODs are UNCHANGED — only the Julia
# sweep reruns per area (new coverage-consistent baseline + fixed common λ-grid
# 1e-4…5.0 with no early stop + S1 extension). Overwrites logs\sweep_<area>_<FUNC>.log.
# Progress -> logs\resweep_<Tag>.log.
#
# -Funcs        run only these travel-cost functions. A sweep is hours per area and the
#               two functions are independent, so when one half already completed there
#               is no reason to redo it: `-Funcs LOGISTIC` resumes just that half.
# -SkipComplete skip any (area, func) whose log already ends in a scenario summary.
#               Makes an interrupted batch resumable without working out by hand which
#               halves survived.
# -RefineOnly   (#52) pin S1/S2 by bisection without re-sweeping the frontier: the sweep
#               walks the coarse grid from 1e-4, bisects each scenario the moment its
#               bracket closes, and stops once both are pinned (SWEEP_STOP_AFTER_REFINE=1),
#               so the high-w tail that costs hours of time-outs is never entered. Writes
#               logs\refine_<area>_<FUNC>.log, which build_deck_data.py prefers for the
#               S1/S2 summary when it is newer than the sweep log; the frontier rows stay
#               those of the full sweep. The S1/S2 arrow folders are overwritten.
param(
  [Parameter(Mandatory=$true)][string]$Areas,
  [int]$Threads = 3,
  [string]$Tag = "q",
  [string]$Funcs = "LINEAR,LOGISTIC",
  [switch]$SkipComplete,
  [switch]$RefineOnly
)
$ErrorActionPreference = "Continue"
$env:NoDefaultCurrentDirectoryInExePath = $null
Set-Location 'E:\prj\JRC\NetworkModel_EU'
$prog = "logs\resweep_$Tag.log"
function Log($m) { "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m | Tee-Object -FilePath $prog -Append }

# True when this (area, func) log already ends in a completed sweep. The log is APPENDED
# to across runs, so only the LAST 'Country:' block counts -- an older successful run must
# not make a later failed one look complete.
function Test-SweepComplete([string]$path) {
  if (-not (Test-Path $path)) { return $false }
  $t = Get-Content $path -Raw -ErrorAction SilentlyContinue
  if (-not $t) { return $false }
  $i = $t.LastIndexOf('Country:')
  if ($i -lt 0) { return $false }
  return $t.Substring($i).Contains('scenario summary')
}

$list     = @($Areas -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$funcList = @($Funcs -split ',' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
foreach ($f in $funcList) {
  if ($f -notin @('LINEAR', 'LOGISTIC', 'QUADRATIC', 'PIECEWISE')) {
    throw "unknown travel-cost function '$f' (expected LINEAR, LOGISTIC, QUADRATIC or PIECEWISE)"
  }
}
$logKind = if ($RefineOnly) { 'refine' } else { 'sweep' }
if ($RefineOnly) { $env:SWEEP_STOP_AFTER_REFINE = '1' } else { Remove-Item Env:SWEEP_STOP_AFTER_REFINE -ErrorAction SilentlyContinue }
Log ("===== resweep worker $Tag START ({0} areas x {1}, threads={2}{3}{4}) =====" -f `
     $list.Count, ($funcList -join '+'), $Threads, $(if ($SkipComplete) { ', skip-complete' } else { '' }), $(if ($RefineOnly) { ', REFINE-ONLY' } else { '' }))
foreach ($a in $list) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Log "----- $a -----"
  $env:ROUNDING = "multistart"; $env:MAX_PARALLEL = "$Threads"; $env:COUNTRIES = "$a"
  foreach ($fn in $funcList) {
    $logPath = "logs\${logKind}_${a}_${fn}.log"
    if ($SkipComplete -and (Test-SweepComplete $logPath)) {
      Log "  sweep $fn SKIPPED (already complete)"
      continue
    }
    $env:TRAVEL_FUNC = $fn
    $ssw = [Diagnostics.Stopwatch]::StartNew()
    & cmd /c "julia --startup-file=no --threads=$Threads lambda_sweep_simplex.jl > $logPath 2>&1"
    $ok = Test-SweepComplete $logPath
    Log ("  $logKind $fn {0} ({1}s)" -f ($(if ($ok) { 'OK' } else { 'NO-SUMMARY' }), [int]$ssw.Elapsed.TotalSeconds))
  }
  Log ("  DONE $a ({0}s total)" -f [int]$sw.Elapsed.TotalSeconds)
}
Log "===== resweep worker $Tag FINISHED ====="
