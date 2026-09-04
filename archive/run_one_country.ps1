# run_one_country.ps1 <country> [threads]
# Self-contained per-country pipeline for ONE study area, for running several
# countries concurrently (one detached window each). Idempotent / resumable:
#   1. Existing OD export   (skip if ExistingPharmacies\<c>_od.arrow exists)
#   2. New net + OD export   (skip if NewPharmacies\<c>_od.arrow exists)
#   3. sweep LINEAR + LOGISTIC -> logs\sweep_<c>_<FUNC>.log (UTF-8 via cmd redirect)
# Per-country progress -> logs\par_<c>.log.
param([Parameter(Mandatory=$true)][string]$c, [int]$Threads = 4)
$ErrorActionPreference = "Continue"
$env:NoDefaultCurrentDirectoryInExePath = $null
Set-Location 'E:\prj\JRC\NetworkModel_EU'
$EX = 'C:\LocalData\networkmodel_eu\ExistingPharmacies'
$NW = 'C:\LocalData\networkmodel_eu\NewPharmacies'
$prog = "logs\par_$c.log"
function Log($m) { "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m | Tee-Object -FilePath $prog -Append }

Log "===== $c START (threads=$Threads) ====="
if (Test-Path "$EX\${c}_od.arrow") { Log "existing OD present - skip" }
else { $env:STEPS = "alloc"; Log "> existing alloc"; & cmd /c "run_pharmacy_pipeline.bat $c" 2>&1 | Out-Null }

if (Test-Path "$NW\${c}_od.arrow") { Log "new OD present - skip" }
else { $env:STEPS = "network1 network2 alloc"; Log "> new network+alloc"; & cmd /c "run_new_pharmacy_pipeline.bat $c" 2>&1 | Out-Null }

if (-not (Test-Path "$EX\${c}_od.arrow") -or -not (Test-Path "$NW\${c}_od.arrow")) {
  Log "[FAIL] OD arrows missing after prep - aborting $c"; exit 1
}

$env:ROUNDING = "multistart"; $env:MAX_PARALLEL = "$Threads"; $env:COUNTRIES = "$c"
foreach ($fn in 'LINEAR','LOGISTIC') {
  $env:TRAVEL_FUNC = $fn
  $log = "logs\sweep_${c}_${fn}.log"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Log "> sweep $fn"
  & cmd /c "julia --startup-file=no --threads=$Threads lambda_sweep_simplex.jl > $log 2>&1"
  $ok = (Test-Path $log) -and (Select-String -Path $log -Pattern 'scenario summary' -Quiet)
  Log ("  sweep $fn {0} ({1}s)" -f ($(if ($ok) { 'OK' } else { 'NO-SUMMARY' }), [int]$sw.Elapsed.TotalSeconds))
}
Log "===== $c DONE ====="
