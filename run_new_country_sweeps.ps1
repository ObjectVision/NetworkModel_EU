# run_new_country_sweeps.ps1
# ----------------------------------------------------------------------------
# Sequentially prepares OD inputs and runs the lambda_sweep_simplex.jl sweep
# (LINEAR + LOGISTIC) for the newly-available countries, ordered SMALL -> LARGE
# by resident population. Per country:
#   1. Existing OD export   (run_pharmacy_pipeline.bat <c>      STEPS=alloc)
#   2. New candidate net+OD  (run_new_pharmacy_pipeline.bat <c>  STEPS=network1 network2 alloc)
#   3. sweep LINEAR   -> logs\sweep_<c>_LINEAR.log    (UTF-8, via cmd redirect)
#   4. sweep LOGISTIC -> logs\sweep_<c>_LOGISTIC.log
# Resumable: a step whose output already exists is skipped. Progress is appended
# to logs\orchestrator_progress.log AND echoed to this (visible) console so the
# work survives independently of the Claude session and the user can watch it.
# ----------------------------------------------------------------------------
$ErrorActionPreference = "Continue"
$env:NoDefaultCurrentDirectoryInExePath = $null
Set-Location 'E:\prj\JRC\NetworkModel_EU'

$EX  = 'C:\LocalData\networkmodel_eu\ExistingPharmacies'
$NW  = 'C:\LocalData\networkmodel_eu\NewPharmacies'
$prog = 'logs\orchestrator_progress.log'
$THREADS = 4   # MAX_PARALLEL LPs; 32 cores available, keep modest for big-country RAM

# small -> large by n_residents (from doc\pharmacy_descriptives.csv)
$countries = @(
  'Luxembourg','Estonia','Latvia','Slovenia','Lithuania','Ireland','Norway',
  'Denmark','Austria','Portugal','Czechia','Belgium','Poland'
)

function Log($m) {
  $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  $line | Tee-Object -FilePath $prog -Append
}

function RunCmd($title, $cmdline) {
  Log "  > $title"
  & cmd /c "$cmdline" 2>&1 | Out-Null
  return $LASTEXITCODE
}

Log "===== orchestrator START ($($countries.Count) countries, threads=$THREADS) ====="
foreach ($c in $countries) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Log "----- $c -----"

  # 1. Existing OD export (network .mmd already built; alloc only)
  if (Test-Path "$EX\${c}_od.arrow") {
    Log "  existing OD present - skip"
  } else {
    $env:STEPS = "alloc"
    $rc = RunCmd "existing alloc" "run_pharmacy_pipeline.bat $c"
    if (-not (Test-Path "$EX\${c}_od.arrow")) { Log "  [FAIL] existing OD not produced (rc=$rc) - skipping $c"; continue }
  }

  # 2. New candidate network + OD export
  if (Test-Path "$NW\${c}_od.arrow") {
    Log "  new OD present - skip"
  } else {
    $env:STEPS = "network1 network2 alloc"
    $rc = RunCmd "new network+alloc" "run_new_pharmacy_pipeline.bat $c"
    if (-not (Test-Path "$NW\${c}_od.arrow")) { Log "  [FAIL] new OD not produced (rc=$rc) - skipping $c"; continue }
  }

  # 3 + 4. sweeps (UTF-8 logs via cmd redirect)
  $env:ROUNDING = "multistart"; $env:MAX_PARALLEL = "$THREADS"; $env:COUNTRIES = "$c"
  foreach ($fn in 'LINEAR','LOGISTIC') {
    $log = "logs\sweep_${c}_${fn}.log"
    $env:TRAVEL_FUNC = $fn
    $ssw = [Diagnostics.Stopwatch]::StartNew()
    Log "  > sweep $fn"
    & cmd /c "julia --startup-file=no --threads=$THREADS lambda_sweep_simplex.jl > $log 2>&1"
    $ok = (Test-Path $log) -and (Select-String -Path $log -Pattern 'scenario summary' -Quiet)
    Log ("    sweep $fn {0} ({1}s)" -f ($(if($ok){'OK'}else{'NO-SUMMARY'}), [int]$ssw.Elapsed.TotalSeconds))
  }
  Log ("  DONE $c ({0}s total)" -f [int]$sw.Elapsed.TotalSeconds)
}
Log "===== orchestrator FINISHED ====="
