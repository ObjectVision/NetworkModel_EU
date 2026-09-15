# run_resweep_batch.ps1 -Areas <a,b,c> [-Threads 3] [-Tag q1]
#                       [-Funcs LINEAR,LOGISTIC] [-SkipComplete] [-RefineOnly]
#                       [-TailFrom <w> [-TailTo <w>] [-TailLimit <s>]]
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
# -TailFrom w   continue a finished sweep's grid beyond its tail stop (SWEEP_TAIL_ONLY=1):
#               grid points from w (a cold solve) up to -TailTo (default: the sweep's
#               w_max), each with -TailLimit seconds (default 14400), no bisection and no
#               scenario summary. Writes logs\tail_<area>_<FUNC>.log; build_deck_data.py
#               adds its rows to the frontier at the w's the sweep did not reach. Written
#               for FRI LOGISTIC, whose w=0.005 needed more than the sweep's hour and whose
#               stop at 0.002 capped the aggregate frontier below its own S2.
param(
  [Parameter(Mandatory=$true)][string]$Areas,
  [int]$Threads = 3,
  [string]$Tag = "q",
  [string]$Funcs = "LINEAR,LOGISTIC",
  [switch]$SkipComplete,
  [switch]$RefineOnly,
  [double]$TailFrom = 0,
  [double]$TailTo = 0,
  [int]$TailLimit = 14400
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
  # a tail-only run has no scenario summary; its Combined-sweep table is its result
  if ($TailFrom -gt 0) { return $t.Substring($i).Contains('Combined sweep') }
  return $t.Substring($i).Contains('scenario summary')
}

$list     = @($Areas -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$funcList = @($Funcs -split ',' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
foreach ($f in $funcList) {
  if ($f -notin @('LINEAR', 'LOGISTIC', 'QUADRATIC', 'PIECEWISE')) {
    throw "unknown travel-cost function '$f' (expected LINEAR, LOGISTIC, QUADRATIC or PIECEWISE)"
  }
}
if ($RefineOnly -and $TailFrom -gt 0) { throw "-RefineOnly and -TailFrom exclude each other" }
$logKind = if ($RefineOnly) { 'refine' } elseif ($TailFrom -gt 0) { 'tail' } else { 'sweep' }
if ($RefineOnly) { $env:SWEEP_STOP_AFTER_REFINE = '1' } else { Remove-Item Env:SWEEP_STOP_AFTER_REFINE -ErrorAction SilentlyContinue }
foreach ($v in 'SWEEP_TAIL_ONLY', 'SWEEP_WMIN', 'SWEEP_WMAX', 'LP_TIME_LIMIT') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
if ($TailFrom -gt 0) {
  $env:SWEEP_TAIL_ONLY = '1'
  $env:SWEEP_WMIN      = $TailFrom.ToString([Globalization.CultureInfo]::InvariantCulture)
  if ($TailTo -gt 0) { $env:SWEEP_WMAX = $TailTo.ToString([Globalization.CultureInfo]::InvariantCulture) }
  $env:LP_TIME_LIMIT   = "$TailLimit"
}
Log ("===== resweep worker $Tag START ({0} areas x {1}, threads={2}{3}{4}{5}) =====" -f `
     $list.Count, ($funcList -join '+'), $Threads, $(if ($SkipComplete) { ', skip-complete' } else { '' }), $(if ($RefineOnly) { ', REFINE-ONLY' } else { '' }), `
     $(if ($TailFrom -gt 0) { ", TAIL from w=$TailFrom" + $(if ($TailTo -gt 0) { " to $TailTo" } else { '' }) + " ($TailLimit s/solve)" } else { '' }))
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
