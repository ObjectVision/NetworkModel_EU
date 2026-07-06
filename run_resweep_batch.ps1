# run_resweep_batch.ps1 -Areas <a,b,c> [-Threads 3] [-Tag q1]
# Sweep-only worker (todo #3+#4 resweep): networks/ODs are UNCHANGED — only the Julia
# sweep reruns per area (new coverage-consistent baseline + fixed common λ-grid
# 1e-4…5.0 with no early stop + S1 extension). Overwrites logs\sweep_<area>_<FUNC>.log.
# Progress -> logs\resweep_<Tag>.log.
param(
  [Parameter(Mandatory=$true)][string]$Areas,
  [int]$Threads = 3,
  [string]$Tag = "q"
)
$ErrorActionPreference = "Continue"
$env:NoDefaultCurrentDirectoryInExePath = $null
Set-Location 'E:\prj\JRC\NetworkModel_EU'
$prog = "logs\resweep_$Tag.log"
function Log($m) { "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m | Tee-Object -FilePath $prog -Append }

$list = $Areas -split ','
Log "===== resweep worker $Tag START ($($list.Count) areas, threads=$Threads) ====="
foreach ($a in $list) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Log "----- $a -----"
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
Log "===== resweep worker $Tag FINISHED ====="
