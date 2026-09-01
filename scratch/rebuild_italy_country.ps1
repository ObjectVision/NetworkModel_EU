Set-Location 'E:\prj\JRC\NetworkModel_EU'
$env:NoDefaultCurrentDirectoryInExePath = $null
$env:STUDY_AREA = 'Italy'
$exe = 'C:\Program Files\ObjectVision\GeoDms20.19.1.m\GeoDmsRun.exe'
$cfg = 'E:\prj\JRC\NetworkModel_EU\cfg\main.dms'
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($step in @(
  @{n='network1'; i='/NetworkSetup/ExistingPharmacy_Analysis/NetwerkSpec/CreateInitialWorkingNetwork/LinkSet_Write'},
  @{n='network2'; i='/NetworkSetup/ExistingPharmacy_Analysis/NetwerkSpec/CreateMoreEfficientNetwork/Generate'}
)) {
  $t = [Diagnostics.Stopwatch]::StartNew()
  & $exe /L"E:\prj\JRC\NetworkModel_EU\logs\italy_country_$($step.n).log" $cfg $step.i *> $null
  "Italy $($step.n): exit=$LASTEXITCODE ($([int]$t.Elapsed.TotalSeconds)s)"
}
# now the descriptives for the country row
$t = [Diagnostics.Stopwatch]::StartNew()
& $exe /L"E:\prj\JRC\NetworkModel_EU\logs\descr_Italy.log" $cfg '/Analyses/Pharmacies/Descriptives/Table' *> $null
"Italy descriptives: exit=$LASTEXITCODE ($([int]$t.Elapsed.TotalSeconds)s)"
"TOTAL $([int]$sw.Elapsed.TotalSeconds)s"
